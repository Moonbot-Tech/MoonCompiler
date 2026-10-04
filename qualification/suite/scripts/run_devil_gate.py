#!/usr/bin/env python3
"""Devil gate: generate, build everywhere, compare everything.

For each seed the gate

  1. generates a fresh program (new forms, not a new run of old ones);
  2. builds it with the compiler under test at every optimization level;
  3. optionally builds the identical source with Delphi 12.2 as an arbiter;
  4. runs all binaries and compares check by check.

A check is red when any two builds disagree, or when a build disagrees with
the generator's model.  Nothing here is a frozen expectation table, so adding
forms costs nothing.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import re
import hashlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc
import generate_devil

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
GENERATOR = Path(generate_devil.__file__).resolve()
sys.path.insert(0, str(ROOT.parent / "release"))
from inputs import digest_paths

FAILURE_RE = re.compile(
    r"^DEVIL_FAILURE (?P<name>[a-z0-9-]+) actual=(?P<actual>[0-9A-F]{16}) "
    r"expected=(?P<expected>[0-9A-F]{16})$")
CHECK_RE = re.compile(
    r"^DEVIL_CHECK (?P<name>[a-z0-9-]+) actual=(?P<actual>[0-9A-F]{16}) "
    r"expected=(?P<expected>[0-9A-F]{16})$")
PASS_SUMMARY_RE = re.compile(
    r"^DEVIL_PASS seed=(?P<seed>\d+) checks=(?P<checks>\d+) "
    r"digest=(?P<digest>[0-9A-F]{16})$")
FAIL_SUMMARY_RE = re.compile(
    r"^DEVIL_FAIL seed=(?P<seed>\d+) "
    r"failures=(?P<failures>[1-9][0-9]*) checks=(?P<checks>\d+) "
    r"digest=(?P<digest>[0-9A-F]{16})$")
NOTE_RE = re.compile(r"^DEVIL_NOTE (?P<name>[a-z0-9-]+)=(?P<value>[0-9A-F]{16})$")
LAYERS_RE = re.compile(r"^DEVIL_LAYERS (?P<layers>[a-z0-9,]+)$")
COUNTER_RE = re.compile(r"^DEVIL_(?P<what>FEEDS|STEPS) (?P<value>\d+)$")
LAYER_DIGEST_RE = re.compile(
    r"^DEVIL_LAYER (?P<layer>[a-z0-9]+)="
    r"(?P<digest>[0-9A-F]{16})$")
CHECK_LAYER_RE = re.compile(r"^dvl-([a-z0-9]+)-")
TRAIL_RE = re.compile(r"^DEVIL_TRAIL (?P<name>[a-z0-9-]+)=(?P<value>\S*)$")
FINALIZATION_RE = re.compile(r"^DEVIL_FINALIZATION checks=(?P<checks>\d+)$")
DEFAULT_GENERATED_PROGRAM_TIMEOUT = 120


def run(cmd: list[str], cwd: Path, timeout: int) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def generated_program_timeout(timeout: int, requested: int) -> int:
    """Keep runtime below both the outer command and explicit program bounds."""
    if requested <= 0:
        raise ValueError("generated program timeout must be positive")
    return min(timeout, requested)


class Build:
    def __init__(self, label: str) -> None:
        self.label = label
        self.compiled = False
        self.compile_log = ""
        self.output = ""
        self.failures: dict[str, tuple[str, str]] = {}
        self.failure_values: dict[str, set[tuple[str, str]]] = {}
        self.failure_events: dict[str, list[tuple[str, str]]] = {}
        self.failure_occurrences: dict[str, int] = {}
        self.check_events: dict[str, list[tuple[str, str]]] = {}
        self.check_event_order: list[tuple[str, str, str, int]] = []
        self.check_occurrences: dict[str, int] = {}
        self.notes: dict[str, str] = {}
        self.note_values: dict[str, set[str]] = {}
        self.note_events: dict[str, list[str]] = {}
        self.note_occurrences: dict[str, int] = {}
        self.digest = ""
        self.checks = 0
        self.reported_failures: int | None = None
        self.summary_seed: int | None = None
        self.expected_seed: int | None = None
        self.timed_out = False
        self.run_exit: int | None = None
        self.layers: set[str] = set()
        self.layer_inventory_valid = True
        # a subtotal per layer: what turns "something diverged" into "this
        # layer diverged" when the value that moved carries no check name
        self.layer_digests: dict[str, str] = {}
        # счётчики самого прибора: сборка, которая влила в поток меньше или
        # прошла меньше шагов, где-то перестала измерять
        self.counters: dict[str, int] = {}
        self.summary_occurrences = 0
        self.layers_occurrences = 0
        self.counter_occurrences: dict[str, int] = {}
        self.layer_digest_occurrences: dict[str, int] = {}
        self.finalization_occurrences = 0
        self.finalization_checks: int | None = None
        self.finalization_line = -1
        self.summary_line = -1
        self.layers_line = -1
        self.first_protocol_line = -1
        self.last_nonempty_line = -1
        self.protocol_errors: list[str] = []

    def parse(self, output: str) -> None:
        self.output = output
        for line_no, line in enumerate(output.splitlines()):
            stripped = line.strip()
            if stripped:
                self.last_nonempty_line = line_no
            if stripped.startswith("DEVIL_") and self.first_protocol_line < 0:
                self.first_protocol_line = line_no
            m = CHECK_RE.match(stripped)
            if m:
                name = m.group("name")
                value = (m.group("actual"), m.group("expected"))
                self.check_events.setdefault(name, []).append(value)
                self.check_event_order.append((name, *value, line_no))
                self.check_occurrences[name] = \
                    self.check_occurrences.get(name, 0) + 1
                continue
            m = FAILURE_RE.match(stripped)
            if m:
                name = m.group("name")
                value = (m.group("actual"), m.group("expected"))
                if (not self.check_event_order
                        or self.check_event_order[-1]
                           != (name, *value, line_no - 1)
                        or value[0] == value[1]):
                    self.protocol_errors.append(
                        f"line {line_no + 1}: failure is not paired with "
                        "the preceding failed check"
                    )
                self.failures[name] = value
                self.failure_values.setdefault(name, set()).add(value)
                self.failure_events.setdefault(name, []).append(value)
                self.failure_occurrences[name] = \
                    self.failure_occurrences.get(name, 0) + 1
                continue
            m = NOTE_RE.match(stripped)
            if m:
                name = m.group("name")
                value = m.group("value")
                self.notes[name] = value
                self.note_values.setdefault(name, set()).add(value)
                self.note_events.setdefault(name, []).append(value)
                self.note_occurrences[name] = \
                    self.note_occurrences.get(name, 0) + 1
                continue
            m = FINALIZATION_RE.match(stripped)
            if m:
                self.finalization_occurrences += 1
                self.finalization_checks = int(m.group("checks"))
                self.finalization_line = line_no
                continue
            m = TRAIL_RE.match(stripped)
            if m:
                name = m.group("name")
                value = m.group("value")
                self.notes[name] = value
                self.note_values.setdefault(name, set()).add(value)
                self.note_events.setdefault(name, []).append(value)
                self.note_occurrences[name] = \
                    self.note_occurrences.get(name, 0) + 1
                continue
            m = COUNTER_RE.match(stripped)
            if m:
                what = m.group("what")
                self.counters[what] = int(m.group("value"))
                self.counter_occurrences[what] = \
                    self.counter_occurrences.get(what, 0) + 1
                continue
            m = LAYER_DIGEST_RE.match(stripped)
            if m:
                layer = m.group("layer")
                self.layer_digests[layer] = m.group("digest")
                self.layer_digest_occurrences[layer] = \
                    self.layer_digest_occurrences.get(layer, 0) + 1
                continue
            m = LAYERS_RE.match(stripped)
            if m:
                self.layers_occurrences += 1
                self.layers_line = line_no
                layers = m.group("layers").split(",")
                self.layers = set(layers)
                self.layer_inventory_valid = len(layers) == len(self.layers)
                continue
            m = PASS_SUMMARY_RE.match(stripped)
            failures = 0
            if not m:
                m = FAIL_SUMMARY_RE.match(stripped)
                failures = int(m.group("failures")) if m else 0
            if m:
                self.summary_occurrences += 1
                self.summary_line = line_no
                self.digest = m.group("digest")
                self.checks = int(m.group("checks"))
                self.reported_failures = failures
                self.summary_seed = int(m.group("seed"))
                continue
            if stripped.startswith("DEVIL_"):
                self.protocol_errors.append(
                    f"line {line_no + 1}: malformed protocol record"
                )


def instrument_contract_errors(build: Build) -> list[str]:
    """Return every reason this run cannot be trusted as a complete sample."""
    invalid: list[str] = []
    if build.protocol_errors:
        invalid.extend(build.protocol_errors)
    if build.summary_occurrences != 1:
        invalid.append(f"terminal summaries={build.summary_occurrences}")
    if (build.expected_seed is not None
            and build.summary_seed != build.expected_seed):
        invalid.append(
            f"terminal seed={build.summary_seed}, expected={build.expected_seed}"
        )
    if (build.finalization_occurrences != 1
            or build.finalization_checks != build.checks
            or build.finalization_line < 0
            or build.summary_line != build.finalization_line + 1
            or build.summary_line != build.last_nonempty_line):
        invalid.append("terminal summary does not follow complete finalization")
    if (build.layers_occurrences != 1 or not build.layers
            or not build.layer_inventory_valid
            or build.layers_line != build.first_protocol_line):
        invalid.append(f"layer inventories={build.layers_occurrences}")
    if (set(build.counters) != {"FEEDS", "STEPS"}
            or any(build.counter_occurrences.get(name) != 1
                   for name in ("FEEDS", "STEPS"))):
        invalid.append("FEEDS/STEPS counters are missing or repeated")
    digest_layers = build.layers - generate_devil.FPC_ONLY_LAYERS
    if (set(build.layer_digests) != digest_layers
            or any(build.layer_digest_occurrences.get(layer) != 1
                   for layer in digest_layers)):
        invalid.append("layer digests do not match the layer inventory")
    failed_checks = sum(
        actual != expected
        for _, actual, expected, _ in build.check_event_order
    )
    printed_failures = sum(build.failure_occurrences.values())
    if (build.checks <= 0 or build.reported_failures is None
            or len(build.check_event_order) != build.checks
            or sum(build.check_occurrences.values()) != build.checks
            or build.reported_failures != failed_checks
            or printed_failures != failed_checks):
        invalid.append("terminal check/failure counts are incomplete")
    return invalid


def failure_sequence(build: Build, name: str) -> tuple[tuple[str, str], ...]:
    """All occurrences of a named check, without losing loop iterations."""
    events = build.failure_events.get(name)
    if events is not None:
        return tuple(events)
    value = build.failures.get(name)
    return (value,) if value is not None else ()


def check_sequence(build: Build, name: str) -> tuple[tuple[str, str], ...]:
    """Every invocation, including passes, in occurrence order for one name."""
    events = build.check_events.get(name)
    if events is not None:
        return tuple(events)
    # A few isolated unit fixtures predate the complete wire stream.  Runtime
    # samples without DEVIL_CHECK are rejected by instrument_contract_errors.
    return failure_sequence(build, name)


def note_sequence(build: Build, name: str) -> tuple[str, ...]:
    """All occurrences of a named observation in their execution order."""
    events = build.note_events.get(name)
    if events is not None:
        return tuple(events)
    value = build.notes.get(name)
    return (value,) if value is not None else ()


def sequence_value(values: tuple) -> object:
    """Keep the established wire shape for singleton findings."""
    if not values:
        return "<missing>"
    if len(values) == 1:
        return values[0]
    return list(values)


def build_fpc(work: Path, profile: str, defines: list[str], timeout: int,
              program_timeout: int, reuse: bool = False) -> Build:
    """Build the program the way the driver builds a real project."""
    build = Build(f"{profile}{'+reuse' if reuse else ''}")
    out = work / f"out-{profile}"
    if not reuse:
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
    cmd = tc.compile_command(work / "devil.dpr", out, profile, defines=defines)
    if reuse:
        cmd.remove("-B")
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = tc.executable(out, "devil")
    if code != 0 or not exe.exists():
        return build
    build.compiled = True
    code, output = run(
        [str(exe)], out, generated_program_timeout(timeout, program_timeout)
    )
    build.run_exit = code
    build.timed_out = code == 124
    build.parse(output)
    return build


def artefact_hashes(out: Path) -> dict[str, str]:
    """What the compiler produced, by content."""
    found: dict[str, str] = {}
    for path in sorted(out.iterdir()):
        if path.suffix.lower() in (".o", ".ppu", ".exe") or path.name == "devil":
            found[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return found


def source_fingerprint(work: Path) -> str:
    """Отпечаток того, что подано компилятору на вход."""
    digest = hashlib.sha256()
    for path in sorted(work.glob("devil*.dpr")) + sorted(work.glob("devil*.inc")) \
            + sorted(work.glob("devil*.pas")):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def keep_evidence(where: Path, label: str, out: Path) -> list[str]:
    """Сохранить артефакты сборки целиком: без них разбирать нечего."""
    room = where / label
    if room.exists():
        shutil.rmtree(room)
    room.mkdir(parents=True)
    kept = []
    for path in sorted(out.iterdir()):
        if path.suffix.lower() in (".o", ".ppu", ".exe") or path.name == "devil":
            shutil.copy(path, room / path.name)
            kept.append(path.name)
    return kept


def build_twice(work: Path, profile: str, defines: list[str],
                timeout: int, *, input_key: str) -> list[dict]:
    """Тот же исходник, тот же профиль, второй прогон: артефакты обязаны совпасть.

    Сверка идёт по двум осям: с повтором прямо сейчас и с тем, что видели
    прошлые прогоны на этом же входе.  Вторая ось важнее: режим держится
    сериями, поэтому внутри одного прогона расхождения может не быть, а между
    прогонами оно есть.
    """
    first = work / f"out-{profile}"
    if not first.is_dir():
        return []
    before = artefact_hashes(first)
    again = work / f"out-{profile}-again"
    if again.exists():
        shutil.rmtree(again)
    again.mkdir(parents=True)
    code, log = run(tc.compile_command(work / "devil.dpr", again, profile,
                                       defines=defines), work, timeout)
    findings: list[dict] = []
    evidence = work / "nondeterminism"
    fingerprint = source_fingerprint(work)

    if code != 0:
        findings.append({"kind": "rebuild-failed", "profile": profile,
                         "source": fingerprint[:16],
                         "detail": [l.strip() for l in log.splitlines()
                                    if "Error" in l or "Fatal" in l][:3],
                         "evidence": keep_evidence(evidence,
                                                   "rebuild-failed-first",
                                                   first)})
        return findings

    after = artefact_hashes(again)
    moved = sorted(name for name in set(before) & set(after)
                   if before[name] != after[name])
    missing = sorted(set(before) ^ set(after))
    if moved or missing:
        findings.append({
            "kind": "nondeterministic-build", "profile": profile,
            "source": fingerprint[:16], "artefacts": moved,
            "only-in-one": missing,
            "evidence": [keep_evidence(evidence, "pair-first", first),
                         keep_evidence(evidence, "pair-second", again)]})

    # вторая ось: сверка с тем, что этот же вход давал раньше
    ledger = work / "determinism-baseline.json"
    seen = {}
    if ledger.exists():
        try:
            seen = json.loads(ledger.read_text(encoding="utf-8"))
        except ValueError:
            seen = {}
    key = f"{input_key}:{profile}:{fingerprint}"
    known = seen.get(key)
    if known is None:
        seen[key] = after
        ledger.write_text(json.dumps(seen, indent=2, sort_keys=True),
                          encoding="utf-8")
    else:
        drifted = sorted(name for name in set(known) & set(after)
                         if known[name] != after[name])
        if drifted:
            findings.append({
                "kind": "nondeterministic-across-runs", "profile": profile,
                "source": fingerprint[:16], "artefacts": drifted,
                "evidence": keep_evidence(evidence, "drift-now", again),
                "note": "тот же вход давал другой машинный код в прошлом "
                        "прогоне: эталон в determinism-baseline.json"})
    return findings


def build_separate(work: Path, profile: str, defines: list[str],
                   timeout: int, program_timeout: int) -> Build:
    """Each unit in its own compiler process, then the program."""
    build = Build("separate")
    out = work / "out-separate"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    # units first, one invocation each: a consumer can only see what the
    # producer actually wrote into its PPU
    for unit in sorted(work.glob("devil_*.pas")):
        cmd = tc.compile_command(unit, out, profile, defines=defines)
        cmd.remove("-B")
        code, log = run(cmd, work, timeout)
        if code != 0:
            build.compile_log = log
            return build
    cmd = tc.compile_command(work / "devil.dpr", out, profile, defines=defines)
    cmd.remove("-B")
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = tc.executable(out, "devil")
    if code != 0 or not exe.exists():
        return build
    build.compiled = True
    code, output = run(
        [str(exe)], work, generated_program_timeout(timeout, program_timeout)
    )
    build.run_exit = code
    build.timed_out = code == 124
    build.parse(output)
    return build


def build_delphi(work: Path, dcc: Path, lib: Path, timeout: int) -> Build:
    build = Build("delphi")
    out = work / "out-delphi"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cmd = [str(dcc), "-B", "-CC", f"-U{lib}", "-NSSystem",
           f"-NU{out}", f"-E{out}", "devil.dpr"]
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = out / "devil.exe"
    if not exe.exists():
        return build
    build.compiled = True
    code, output = run([str(exe)], work, timeout)
    build.run_exit = code
    build.timed_out = code == 124
    build.parse(output)
    return build


def load_known(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8")).get("known", [])


def build_side(label: str) -> str:
    return "delphi" if label == "delphi" else "moon"


def known_runtime_semantics_match(rule: dict, finding: dict) -> bool:
    """A known name is not enough: pin which implementation may disagree."""
    kind = finding.get("kind")
    builds = finding.get("builds")
    if not isinstance(builds, dict) or not builds:
        return False
    if not all(isinstance(value, str) for value in builds.values()):
        return False
    if kind == "model-mismatch":
        failing_side = rule.get("failing_side")
        if failing_side not in ("moon", "delphi"):
            return False
        failing_values: list[str] = []
        side_seen = False
        for label, value in builds.items():
            on_failing_side = build_side(label) == failing_side
            side_seen |= on_failing_side
            if on_failing_side != (value != "ok"):
                return False
            if on_failing_side:
                failing_values.append(value)
        if not side_seen or len(set(failing_values)) != 1:
            return False
        actual = rule.get("actual")
        if actual and not re.fullmatch(actual, failing_values[0]):
            return False
        expected = rule.get("expected")
        if expected:
            finding_expected = finding.get("expected")
            if (not isinstance(finding_expected, str)
                    or not re.fullmatch(expected, finding_expected)):
                return False
        return True
    if kind == "observation-split":
        if rule.get("split") != "delphi-vs-moon":
            return False
        grouped = {
            side: [value for label, value in builds.items()
                   if build_side(label) == side]
            for side in ("moon", "delphi")
        }
        if (not grouped["moon"] or not grouped["delphi"]
                or len(set(grouped["moon"])) != 1
                or len(set(grouped["delphi"])) != 1
                or grouped["moon"][0] == grouped["delphi"][0]):
            return False
        moon_value = grouped["moon"][0]
        delphi_value = grouped["delphi"][0]
        for side in ("moon", "delphi"):
            pattern = rule.get(f"{side}_value")
            if pattern and not re.fullmatch(pattern, grouped[side][0]):
                return False
        if rule.get("moon_value") and rule.get("delphi_value"):
            return True
        if rule.get("relation") == "moon-unsigned-gt-delphi":
            try:
                return int(moon_value, 16) > int(delphi_value, 16)
            except ValueError:
                return False
        # An unconstrained split can turn any new wrong result with the same
        # generated name into a known difference.  Runtime exceptions therefore
        # need either exact values or an explicit relation.
        return False
    return True


def classify(findings: list[dict], known: list[dict]) -> tuple[list[dict], list[dict]]:
    """Split findings into new ones and ones already analysed in findings/."""
    fresh, old = [], []
    for f in findings:
        hit = None
        for rule in known:
            # rules keyed by case belong to the reject gate: without this they
            # match anything here, including a broken build
            if "case" in rule:
                continue
            if rule.get("kind") and rule["kind"] != f.get("kind"):
                continue
            if "check" in rule and not re.match(rule["check"], f.get("check", "")):
                continue
            if rule.get("kind") == "internal-error" and f.get("kind") == "internal-error":
                # an internal error is only the known one when its number
                # matches: a new ICE must not hide behind an old one
                wanted = rule.get("detail")
                if wanted and not any(wanted in line for line in f.get("detail", [])):
                    continue
                hit = rule
                break
            if "note_name" in rule and not re.match(rule["note_name"], f.get("note", "")):
                continue
            if not known_runtime_semantics_match(rule, f):
                continue
            hit = rule
            break
        if hit:
            old.append({**f, "known": hit["id"]})
        else:
            fresh.append(f)
    return fresh, old


def absorb_derived_known_effects(
        findings: list[dict], known_hits: list[dict],
        builds: list[Build]) -> tuple[list[dict], list[dict]]:
    """Do not report consequences of a known failed check as new failures.

    A count split for the same check is a direct consequence of its classified
    model mismatch.  Process exit is an independent runtime channel and is
    never derived from a known semantic disagreement: the instrumented program
    deliberately does not write ExitCode.
    """
    known_checks: set[str] = set()
    for hit in known_hits:
        if hit.get("kind") != "model-mismatch":
            continue
        check = hit.get("check")
        if not check:
            continue
        known_checks.add(check)
    fresh: list[dict] = []
    derived: list[dict] = []
    for finding in findings:
        if (finding.get("kind") == "failure-count-split"
                and finding.get("check") in known_checks):
            derived.append({**finding, "known": "derived"})
            continue
        fresh.append(finding)
    return fresh, known_hits + derived


def compare(builds: list[Build]) -> list[dict]:
    """Every disagreement, whether against the model or between builds."""
    findings: list[dict] = []
    alive = [b for b in builds if b.compiled and not b.timed_out]
    for b in builds:
        if not b.compiled:
            lines = [l.strip() for l in b.compile_log.splitlines()
                     if ("Error" in l or "Fatal" in l or "internal error" in l.lower())]
            findings.append({
                "kind": "internal-error" if any("nternal error" in l for l in lines)
                        else "compile-failed",
                "build": b.label,
                "detail": lines[:4] or b.compile_log.strip().splitlines()[-3:]})
        elif b.timed_out:
            findings.append({"kind": "timeout", "build": b.label})
        elif (b.run_exit not in (None, 0)) or not b.digest:
            findings.append({
                "kind": "runtime-failed",
                "build": b.label,
                "exit": b.run_exit,
                "detail": b.output.strip().splitlines()[-6:],
            })
        if b.compiled and not b.timed_out and b.digest:
            invalid = instrument_contract_errors(b)
            if invalid:
                findings.append({"kind": "instrument-invalid",
                                 "build": b.label, "detail": invalid})
    # a check whose prefix is not a layer would be silently excluded from
    # every comparison by the rule below, and the divergence would survive only
    # as a digest with no name attached: refuse to pretend that is a pass
    known: set[str] = set()
    for b in alive:
        known |= set(b.layers)
    if known:
        stray = sorted({CHECK_LAYER_RE.match(item).group(1)
                        for b in alive for item in
                        (set(b.check_events) | set(b.failures) | set(b.notes))
                        if CHECK_LAYER_RE.match(item)
                        and CHECK_LAYER_RE.match(item).group(1) not in known})
        if stray:
            findings.append({
                "kind": "instrument-blind",
                "detail": "check names carry unknown layers: %s"
                          % ", ".join(stray),
                "known": sorted(known)})

    def carries(build: Build, item: str) -> bool:
        """A build cannot disagree about a layer it was not built with."""
        m = CHECK_LAYER_RE.match(item)
        return not (m and build.layers) or m.group(1) in build.layers

    names: set[str] = set()
    for b in alive:
        names |= set(b.check_events) | set(b.failures)
    for name in sorted(names):
        sequences = {b.label: check_sequence(b, name) for b in alive
                     if carries(b, name)}
        for occurrence in range(max(map(len, sequences.values()))):
            rows = {
                label: (values[occurrence]
                        if occurrence < len(values) else None)
                for label, values in sequences.items()
            }
            expected = sorted({value[1] for value in rows.values() if value})
            if any(value is None for value in rows.values()):
                finding = {
                    "kind": "check-stream-split",
                    "check": name,
                    "builds": {
                        label: (list(value) if value else "<missing>")
                        for label, value in rows.items()
                    },
                }
                if occurrence:
                    finding["occurrence"] = occurrence + 1
                findings.append(finding)
                continue
            if all(value[0] == value[1] for value in rows.values()):
                if len(set(rows.values())) > 1:
                    finding = {
                        "kind": "check-stream-split",
                        "check": name,
                        "builds": {label: list(value)
                                   for label, value in rows.items()},
                    }
                    if occurrence:
                        finding["occurrence"] = occurrence + 1
                    findings.append(finding)
                continue
            finding = {
                "kind": "model-mismatch",
                "check": name,
                "builds": {k: (v[0] if v[0] != v[1] else "ok")
                           for k, v in rows.items()},
                "expected": expected[0] if len(expected) == 1 else expected,
            }
            if occurrence:
                finding["occurrence"] = occurrence + 1
            findings.append(finding)
        occurrences = {b.label: sum(
            actual != expected for actual, expected in check_sequence(b, name)
        )
                       for b in alive if carries(b, name)}
        if len(set(occurrences.values())) > 1:
            findings.append({"kind": "failure-count-split", "check": name,
                             "builds": occurrences})
    note_names: set[str] = set()
    for b in alive:
        note_names |= set(b.notes)
    for name in sorted(note_names):
        sequences = {b.label: note_sequence(b, name) for b in alive
                     if carries(b, name)}
        if len(set(sequences.values())) > 1:
            findings.append({"kind": "observation-split", "note": name,
                             "builds": {
                                 label: sequence_value(values)
                                 for label, values in sequences.items()
                             }})
        occurrences = {b.label: b.note_occurrences.get(name, 0) for b in alive
                       if carries(b, name)}
        if len(set(occurrences.values())) > 1:
            findings.append({"kind": "observation-count-split", "note": name,
                             "builds": occurrences})
    # a subtotal that moved names the layer even when no single check did
    for shared in {frozenset(b.layers) for b in alive}:
        group = [b for b in alive if frozenset(b.layers) == shared]
        if len(group) < 2:
            continue
        for layer in sorted(set().union(*(set(b.layer_digests)
                                          for b in group))):
            values = {b.label: b.layer_digests.get(layer, "<missing>")
                      for b in group}
            if len(set(values.values())) > 1:
                findings.append({"kind": "layer-digest-split",
                                 "layer": layer, "builds": values})

    # прибор обязан отработать одинаково: разное число вливаний или шагов
    # означает, что где-то перестали измерять, даже если дайджесты сошлись
    for shared in {frozenset(b.layers) for b in alive}:
        group = [b for b in alive if frozenset(b.layers) == shared]
        if len(group) < 2:
            continue
        for what in ("FEEDS", "STEPS"):
            values = {b.label: b.counters.get(what, -1) for b in group}
            if len(set(values.values())) > 1:
                findings.append({"kind": "instrument-count-split",
                                 "counter": what, "builds": values})

    # digest and check count only mean something between builds that
    # contain the same layers
    for shared in {frozenset(b.layers) for b in alive}:
        group = [b for b in alive if frozenset(b.layers) == shared]
        if len(group) < 2:
            continue
        digests = {b.label: b.digest for b in group}
        if len(set(digests.values())) > 1:
            findings.append({"kind": "digest-split", "digests": digests})
        counts = {b.label: b.checks for b in group}
        if len(set(counts.values())) > 1:
            findings.append({"kind": "check-count-split", "counts": counts})
    return findings


def compare_extended_program(reference: Build, extended: Build) -> list[dict]:
    """Extra declarations must not alter the execution prefix at all."""
    findings: list[dict] = []
    for what, first, second in (
        ("layers", reference.layers, extended.layers),
        ("checks", reference.checks, extended.checks),
        ("counters", reference.counters, extended.counters),
        ("layer-digests", reference.layer_digests, extended.layer_digests),
        ("digest", reference.digest, extended.digest),
    ):
        if first != second:
            first_out = sorted(first) if isinstance(first, set) else first
            second_out = sorted(second) if isinstance(second, set) else second
            findings.append({"kind": "cross-program-runtime",
                             "what": what,
                             "builds": {"first": first_out,
                                        "second": second_out}})
    for note in sorted(set(reference.notes) | set(extended.notes)):
        values = note_sequence(reference, note)
        other = note_sequence(extended, note)
        # The enlarged source may register more RTTI, but it executes the same
        # calls.  Thus every catalogue observation must still exist in the
        # same position and may only grow.
        if note.endswith("-gettypes"):
            try:
                grows = (len(values) == len(other)
                         and all(int(b, 16) >= int(a, 16)
                                 for a, b in zip(values, other)))
            except ValueError:
                grows = False
            if not grows:
                findings.append({"kind": "cross-program-note", "note": note,
                                 "builds": {
                                     "first": sequence_value(values),
                                     "second": sequence_value(other),
                                 }})
            continue
        if values != other:
            findings.append({"kind": "cross-program-note", "note": note,
                             "builds": {
                                 "first": sequence_value(values),
                                 "second": sequence_value(other),
                             }})
    check_names = (set(reference.check_events) | set(extended.check_events)
                   | set(reference.failures) | set(extended.failures))
    for name in sorted(check_names):
        values = check_sequence(reference, name)
        other = check_sequence(extended, name)
        if values != other:
            findings.append({
                "kind": "cross-program-check", "check": name,
                "builds": {
                    "first": sequence_value(values),
                    "second": sequence_value(other),
                },
            })
    return findings


def compare_shuffled_program(reference: Build, shuffled: Build) -> list[dict]:
    """Compare order-independent projections of two identical generated sets."""
    findings: list[dict] = []
    if reference.layers != shuffled.layers:
        findings.append({"kind": "order-dependent-layers",
                         "normal": sorted(reference.layers),
                         "shuffled": sorted(shuffled.layers)})
    if reference.checks != shuffled.checks:
        findings.append({"kind": "order-dependent-count",
                         "counts": {"normal": reference.checks,
                                    "shuffled": shuffled.checks}})
    for note in sorted(set(reference.notes) | set(shuffled.notes)):
        normal = note_sequence(reference, note)
        other = note_sequence(shuffled, note)
        if normal != other:
            findings.append({"kind": "order-dependent-note", "note": note,
                             "builds": {
                                 "normal": sequence_value(normal),
                                 "shuffled": sequence_value(other),
                             }})
        normal_count = reference.note_occurrences.get(note, 0)
        other_count = shuffled.note_occurrences.get(note, 0)
        if normal_count != other_count:
            findings.append({"kind": "order-dependent-note-count",
                             "note": note,
                             "counts": {"normal": normal_count,
                                        "shuffled": other_count}})
    check_names = (set(reference.check_events) | set(shuffled.check_events)
                   | set(reference.failures) | set(shuffled.failures))
    for name in sorted(check_names):
        normal = check_sequence(reference, name)
        other = check_sequence(shuffled, name)
        normal_count = reference.failure_occurrences.get(name, 0)
        other_count = shuffled.failure_occurrences.get(name, 0)
        if normal != other or normal_count != other_count:
            findings.append({
                "kind": "order-dependent-check", "check": name,
                "normal": sequence_value(normal),
                "shuffled": sequence_value(other),
                "counts": {"normal": normal_count, "shuffled": other_count},
            })
    for counter in ("FEEDS", "STEPS"):
        normal = reference.counters.get(counter, -1)
        other = shuffled.counters.get(counter, -1)
        if normal != other:
            findings.append({"kind": "order-dependent-instrument-count",
                             "counter": counter,
                             "counts": {"normal": normal,
                                        "shuffled": other}})
    for layer in sorted(set(reference.layer_digests)
                        | set(shuffled.layer_digests)):
        normal = reference.layer_digests.get(layer, "<missing>")
        other = shuffled.layer_digests.get(layer, "<missing>")
        if normal != other:
            findings.append({"kind": "order-dependent-layer-digest",
                             "layer": layer,
                             "digests": {"normal": normal,
                                         "shuffled": other}})
    return findings


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def checkpoint_key(args) -> str:
    product = Path(os.environ.get("MOONBOT_TOOLCHAIN", str(tc.ROOT / "toolchain")))
    paths = [product, tc.MM_SOURCE, ROOT / "scripts", DEVIL, ROOT.parent / "release/inputs.py"]
    if args.dcc:
        paths.extend([args.dcc, args.dcc_lib])
    options = {key: value for key, value in vars(args).items()
               if key not in {"work", "report", "jobs", "resume", "run_id"}}
    return hashlib.sha256((digest_paths(paths) + json.dumps(options, sort_keys=True, default=str)).encode()).hexdigest()


def cached_seed(args, seed: int) -> dict:
    path = args.work / f"seed-{seed}.json"
    if args.resume and path.exists():
        saved = json.loads(path.read_text(encoding="utf-8"))
        if saved["key"] == args.checkpoint_key and not saved["result"]["findings"]:
            print(f"DEVIL_RESUME seed={seed}", flush=True)
            return saved["result"]
    result = run_seed(args, seed)
    if args.resume:
        write_json(path, {"key": args.checkpoint_key, "result": result})
    return result


def run_seed(args, seed: int) -> dict:
    args = argparse.Namespace(**vars(args))
    args.work = args.work / f"seed-{seed}"
    args.work.mkdir(parents=True, exist_ok=True)
    profiles = args.profiles.split(",")
    defines = [d for d in args.defines.split(",") if d]
    gen = [sys.executable, str(GENERATOR), "--seed", str(seed),
           "--cases", str(args.cases), "--layers", args.layers,
           "--out", str(args.work)]
    code, log = run(gen, ROOT, args.timeout)
    if code != 0:
        print(f"seed {seed}: generator failed\n{log}")
        return {"seed": seed, "summary": {}, "findings": [{
            "kind": "generator-failed", "detail": log.splitlines()[-6:],
        }], "known_hits": []}

    generation_findings: list[dict] = []

    separate: Build | None = None
    if args.separate_units:
        separate = build_separate(args.work, profiles[-1], defines,
                                  args.timeout, args.program_timeout)

    second: Build | None = None
    if args.second_program:
        # Add declarations to every variable-sized layer, but execute the
        # exact original call prefix.  This perturbs whole-program compiler
        # context without letting a new invocation impersonate an old
        # observation in the comparison.
        prefix_manifest = args.work / "devil_runner_prefix.json"
        shutil.copy(args.work / "devil_manifest.json", prefix_manifest)
        code, log = run(gen + ["--extra-cases-per-layer", "1",
                               "--runner-prefix-manifest",
                               str(prefix_manifest)],
                        ROOT, args.timeout)
        if code == 0:
            second = build_fpc(args.work, profiles[-1], defines,
                               args.timeout, args.program_timeout)
            second.label = "second"
        else:
            generation_findings.append({
                "kind": "second-program-generator-failed",
                "detail": log.splitlines()[-6:],
            })
        restore_code, restore_log = run(gen, ROOT, args.timeout)
        if restore_code != 0:
            generation_findings.append({
                "kind": "base-program-restore-failed",
                "detail": restore_log.splitlines()[-6:],
            })

    shuffled: Build | None = None
    if args.shuffle_order:
        # build the same seed a second time with the layers emitted in
        # another order, then compare what the two programs computed
        code, log = run(gen + ["--shuffle-order"], ROOT, args.timeout)
        if code == 0:
            shuffled = build_fpc(args.work, profiles[-1], defines,
                                 args.timeout, args.program_timeout)
            shuffled.label = "shuffled"
        else:
            generation_findings.append({
                "kind": "shuffle-generator-failed",
                "detail": log.splitlines()[-6:],
            })
        restore_code, restore_log = run(gen, ROOT, args.timeout)
        if restore_code != 0:
            generation_findings.append({
                "kind": "base-program-restore-failed",
                "detail": restore_log.splitlines()[-6:],
            })

    builds = []
    if separate is not None:
        builds.append(separate)

    def build_profile(profile):
        pair = [build_fpc(args.work, profile, defines, args.timeout, args.program_timeout)]
        mirror = build_twice(args.work, profile, defines, args.timeout, input_key=args.checkpoint_key) \
            if args.determinism and profile == profiles[-1] else []
        if args.ppu_reuse:
            pair.append(build_fpc(args.work, profile, defines, args.timeout, args.program_timeout, reuse=True))
        return pair, mirror

    mirror_findings = []
    with ThreadPoolExecutor(max_workers=args.profile_jobs) as pool:
        for pair, mirror in pool.map(build_profile, profiles):
            builds.extend(pair)
            mirror_findings.extend(mirror)
    if args.dcc and args.dcc_lib:
        builds.append(build_delphi(args.work, args.dcc, args.dcc_lib,
                                   args.timeout))
    for build in builds:
        build.expected_seed = seed
    if second is not None:
        second.expected_seed = seed
    if shuffled is not None:
        shuffled.expected_seed = seed
    findings = generation_findings + compare(builds) + mirror_findings
    if second is not None:
        # Its source is larger, while its execution prefix is identical.
        findings += compare([second])
        reference = next((b for b in builds if b.label == profiles[-1]), None)
        if reference and reference.compiled and second.compiled:
            findings += compare_extended_program(reference, second)

    if shuffled is not None:
        findings += compare([shuffled])
        reference = next((b for b in builds if b.label == profiles[-1]), None)
        if reference and reference.compiled and shuffled.compiled:
            findings += compare_shuffled_program(reference, shuffled)
    findings, known_hits = classify(
        findings, load_known(DEVIL / "known_findings.json"))
    findings, known_hits = absorb_derived_known_effects(
        findings, known_hits, builds)
    summary = {b.label: (f"{b.checks} checks digest={b.digest}"
                         if b.compiled else "COMPILE FAILED")
               for b in builds}
    print(f"seed {seed}: " + ", ".join(f"{k}: {v}" for k, v in summary.items()))
    for f in findings:
        print("  NEW " + json.dumps(f, sort_keys=True))
    if known_hits:
        seen = sorted({h["known"] for h in known_hits})
        print("  known: %d hits (%s)" % (len(known_hits), ", ".join(seen)))
    return {"seed": seed, "summary": summary, "findings": findings, "known_hits": known_hits,
            "evidence": {build.label: {"compile_log": build.compile_log, "output": build.output,
                                       "run_exit": build.run_exit} for build in builds}}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seeds", default="1")
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--layers", default="all")
    p.add_argument("--profiles", default=tc.DEFAULT_PROFILES)
    p.add_argument("--defines", default="")
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--wall-budget", type=int, default=0,
                   help="stop between seeds if their measured rate cannot fit this many seconds")
    p.add_argument(
        "--program-timeout", type=int,
        default=DEFAULT_GENERATED_PROGRAM_TIMEOUT,
        help="finite runtime bound for each generated executable",
    )
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--work", type=Path,
                   default=ROOT / "results" / "runs" / "devil-main")
    p.add_argument("--report", type=Path)
    p.add_argument("--shuffle-order", action="store_true",
                   help="also build the same forms emitted in another order")
    p.add_argument("--separate-units", action="store_true",
                   help="also build with one compiler process per unit: a "
                        "consumer then sees only what reached the PPU")
    p.add_argument("--second-program", action="store_true",
                   help="also build a second program from the same seed with "
                        "one more case per layer: the digests of what both "
                        "computed must agree form by form")
    p.add_argument("--determinism", action="store_true",
                   help="build the same source twice and compare artefacts")
    p.add_argument("--ppu-reuse", action="store_true",
                   help="also rebuild reusing the PPUs of the first build")
    args = p.parse_args()
    if bool(args.dcc) != bool(args.dcc_lib):
        p.error("--dcc and --dcc-lib must be supplied together")
    if args.jobs < 1:
        p.error("--jobs must be positive")
    if args.cases <= 0:
        p.error("--cases must be positive")
    if args.timeout <= 0 or args.program_timeout <= 0 or args.wall_budget < 0:
        p.error("timeouts must be positive")
    try:
        seeds = [int(value.strip()) for value in args.seeds.split(",")
                 if value.strip()]
    except ValueError:
        p.error("--seeds must be a comma-separated list of integers")
    if not seeds or len(seeds) != len(set(seeds)):
        p.error("--seeds must be non-empty and unique")
    profiles = [value.strip() for value in args.profiles.split(",")
                if value.strip()]
    if (not profiles or len(profiles) != len(set(profiles))
            or any(profile not in tc.PROFILES for profile in profiles)):
        p.error("--profiles must contain unique known profiles")
    args.profiles = ",".join(profiles)

    tc.preflight()
    # every build runs inside the work directory, so tool paths must be
    # absolute before we change into it
    if args.dcc:
        args.dcc = args.dcc.resolve()
    if args.dcc_lib:
        args.dcc_lib = args.dcc_lib.resolve()
    args.work = args.work.resolve()
    args.work.mkdir(parents=True, exist_ok=True)
    if args.report:
        args.report = args.report.resolve()

    args.checkpoint_key = checkpoint_key(args) if args.resume or args.determinism else ""
    report: list[dict] = []
    total_findings = 0
    total_known = 0
    started = time.monotonic()
    budget_shortfall = False

    def budget_exhausted(completed: int) -> bool:
        elapsed = time.monotonic() - started
        estimate = elapsed * len(seeds) / completed
        budget = f"{args.wall_budget}s" if args.wall_budget else "none"
        print(f"DEVIL_PROGRESS completed={completed}/{len(seeds)} "
              f"elapsed={elapsed:.0f}s estimated_total={estimate:.0f}s "
              f"budget={budget}", flush=True)
        shortfall = bool(args.wall_budget and completed < len(seeds)
                         and estimate > args.wall_budget)
        if shortfall:
            print("DEVIL_BUDGET_INSUFFICIENT: remaining seeds cannot fit "
                  "the measured wall-clock budget", flush=True)
        return shortfall

    seed_jobs = min(len(seeds), max(1, args.jobs // len(profiles)))
    args.profile_jobs = max(1, args.jobs // seed_jobs)
    # Submit only one wave at a time: a measured timeout forecast can stop
    # before another wave starts, and completed seeds survive interruption.
    with ThreadPoolExecutor(max_workers=seed_jobs) as pool:
        for offset in range(0, len(seeds), seed_jobs):
            futures = {pool.submit(cached_seed, args, seed): seed for seed in seeds[offset:offset + seed_jobs]}
            for future in as_completed(futures):
                row = future.result()
                report.append(row)
                total_findings += len(row["findings"])
                total_known += len(row["known_hits"])
                if args.report:
                    write_json(args.report, sorted(report, key=lambda row: row["seed"]))
            if budget_exhausted(len(report)):
                budget_shortfall = True
                break
    report.sort(key=lambda row: row["seed"])

    if args.report:
        write_json(args.report, report)
    verdict = "BUDGET_INSUFFICIENT" if budget_shortfall else (
        "OK" if total_findings == 0 else "FINDINGS")
    print(f"DEVIL_GATE {verdict} seeds={len(report)}/{len(seeds)} "
          f"findings={total_findings} known={total_known}")
    sys.exit(2 if budget_shortfall else (1 if total_findings else 0))


if __name__ == "__main__":
    main()
