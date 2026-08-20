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
import json
import re
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
GENERATOR = ROOT / "scripts" / "generate_devil.py"

FAILURE_RE = re.compile(
    r"^DEVIL_FAILURE (?P<name>[a-z0-9-]+) actual=(?P<actual>[0-9A-F]{16}) "
    r"expected=(?P<expected>[0-9A-F]{16})$")
SUMMARY_RE = re.compile(
    r"^DEVIL_(?P<verdict>PASS|FAIL) seed=(?P<seed>\d+) .*?"
    r"checks=(?P<checks>\d+) digest=(?P<digest>[0-9A-F]{16})$")
NOTE_RE = re.compile(r"^DEVIL_NOTE (?P<name>[a-z0-9-]+)=(?P<value>[0-9A-F]{16})$")
LAYERS_RE = re.compile(r"^DEVIL_LAYERS (?P<layers>[a-z0-9,]+)$")
COUNTER_RE = re.compile(r"^DEVIL_(?P<what>FEEDS|STEPS) (?P<value>\d+)$")
LAYER_DIGEST_RE = re.compile(
    r"^DEVIL_LAYER (?P<layer>[a-z0-9]+)=(?P<digest>[0-9A-F]+)"
    r"(?: checks=(?P<checks>\d+))?$")
CHECK_LAYER_RE = re.compile(r"^dvl-([a-z0-9]+)-")
TRAIL_RE = re.compile(r"^DEVIL_TRAIL (?P<name>[a-z0-9-]+)=(?P<value>\S*)$")


def run(cmd: list[str], cwd: Path, timeout: int) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


class Build:
    def __init__(self, label: str) -> None:
        self.label = label
        self.compiled = False
        self.compile_log = ""
        self.output = ""
        self.failures: dict[str, tuple[str, str]] = {}
        self.notes: dict[str, str] = {}
        self.digest = ""
        self.checks = 0
        self.timed_out = False
        self.layers: set[str] = set()
        # a subtotal per layer: what turns "something diverged" into "this
        # layer diverged" when the value that moved carries no check name
        self.layer_digests: dict[str, str] = {}
        # счётчики самого прибора: сборка, которая влила в поток меньше или
        # прошла меньше шагов, где-то перестала измерять
        self.counters: dict[str, int] = {}

    def parse(self, output: str) -> None:
        self.output = output
        for line in output.splitlines():
            m = FAILURE_RE.match(line.strip())
            if m:
                self.failures[m.group("name")] = (m.group("actual"),
                                                  m.group("expected"))
                continue
            m = NOTE_RE.match(line.strip())
            if m:
                self.notes[m.group("name")] = m.group("value")
                continue
            m = TRAIL_RE.match(line.strip())
            if m:
                self.notes[m.group("name")] = m.group("value")
                continue
            m = COUNTER_RE.match(line.strip())
            if m:
                self.counters[m.group("what")] = int(m.group("value"))
                continue
            m = LAYER_DIGEST_RE.match(line.strip())
            if m:
                self.layer_digests[m.group("layer")] = m.group("digest")
                continue
            m = LAYERS_RE.match(line.strip())
            if m:
                self.layers = set(m.group("layers").split(","))
                continue
            m = SUMMARY_RE.match(line.strip())
            if m:
                self.digest = m.group("digest")
                self.checks = int(m.group("checks"))


def build_fpc(work: Path, profile: str, defines: list[str], timeout: int,
              reuse: bool = False) -> Build:
    """Build the program the way the driver builds a real project."""
    build = Build(f"{profile}{'+reuse' if reuse else ''}")
    out = work / f"out-{profile}"
    if not reuse:
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
    cmd = tc.compile_command(work / "devil.dpr", out, profile, defines=defines)
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = tc.executable(out, "devil")
    if code != 0 or not exe.exists():
        return build
    build.compiled = True
    # a generated program must never run long; anything slower is a hang
    code, output = run([str(exe)], work, min(timeout, 120))
    build.timed_out = code == 124
    build.parse(output)
    return build


def artefact_hashes(out: Path) -> dict[str, str]:
    """What the compiler produced, by content."""
    found: dict[str, str] = {}
    for path in sorted(out.iterdir()):
        if path.suffix.lower() in (".o", ".ppu", ".exe"):
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
        if path.suffix.lower() in (".o", ".ppu", ".exe"):
            shutil.copy(path, room / path.name)
            kept.append(path.name)
    return kept


def build_twice(work: Path, profile: str, defines: list[str],
                timeout: int) -> list[dict]:
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
    key = f"{profile}:{fingerprint}"
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
                   timeout: int) -> Build:
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
        code, log = run(cmd, work, timeout)
        if code != 0:
            build.compile_log = log
            return build
    cmd = tc.compile_command(work / "devil.dpr", out, profile, defines=defines)
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = tc.executable(out, "devil")
    if code != 0 or not exe.exists():
        return build
    build.compiled = True
    code, output = run([str(exe)], work, min(timeout, 120))
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
    build.timed_out = code == 124
    build.parse(output)
    return build


def load_known(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8")).get("known", [])


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
            hit = rule
            break
        if hit:
            old.append({**f, "known": hit["id"]})
        else:
            fresh.append(f)
    return fresh, old


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
    # a check whose prefix is not a layer would be silently excluded from
    # every comparison by the rule below, and the divergence would survive only
    # as a digest with no name attached: refuse to pretend that is a pass
    known: set[str] = set()
    for b in alive:
        known |= set(b.layers)
    if known:
        stray = sorted({CHECK_LAYER_RE.match(item).group(1)
                        for b in alive for item in
                        (set(b.failures) | set(b.notes))
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
        names |= set(b.failures)
    for name in sorted(names):
        rows = {b.label: b.failures.get(name) for b in alive
                if carries(b, name)}
        findings.append({
            "kind": "model-mismatch",
            "check": name,
            "builds": {k: (v[0] if v else "ok") for k, v in rows.items()},
        })
    note_names: set[str] = set()
    for b in alive:
        note_names |= set(b.notes)
    for name in sorted(note_names):
        values = {b.label: b.notes.get(name, "<missing>") for b in alive
                  if carries(b, name)}
        if len(set(values.values())) > 1:
            findings.append({"kind": "observation-split", "note": name,
                             "builds": values})
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
    p.add_argument("--work", type=Path, default=DEVIL)
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

    tc.preflight()
    # every build runs inside the work directory, so tool paths must be
    # absolute before we change into it
    if args.dcc:
        args.dcc = args.dcc.resolve()
    if args.dcc_lib:
        args.dcc_lib = args.dcc_lib.resolve()
    args.work = args.work.resolve()

    seeds = [int(s) for s in args.seeds.split(",") if s]
    profiles = [p for p in args.profiles.split(",") if p]
    defines = [d for d in args.defines.split(",") if d]
    report: list[dict] = []
    total_findings = 0

    for seed in seeds:
        gen = [sys.executable, str(GENERATOR), "--seed", str(seed),
               "--cases", str(args.cases), "--layers", args.layers,
               "--out", str(args.work)]
        code, log = run(gen, ROOT, args.timeout)
        if code != 0:
            print(f"seed {seed}: generator failed\n{log}")
            total_findings += 1
            continue

        separate: Build | None = None
        if args.separate_units:
            separate = build_separate(args.work, profiles[-1], defines,
                                      args.timeout)

        second: Build | None = None
        if args.second_program:
            # the same seed, one more case per layer: every form the first
            # program contains is also in this one, and must behave the same
            code, log = run(gen[:-4] + ["--cases", str(args.cases + 1),
                                        "--layers", args.layers,
                                        "--out", str(args.work)],
                            ROOT, args.timeout)
            if code == 0:
                second = build_fpc(args.work, profiles[-1], defines,
                                   args.timeout)
                second.label = "second"
            run(gen, ROOT, args.timeout)

        shuffled: Build | None = None
        if args.shuffle_order:
            # build the same seed a second time with the layers emitted in
            # another order, then compare what the two programs computed
            code, log = run(gen + ["--shuffle-order"], ROOT, args.timeout)
            if code == 0:
                shuffled = build_fpc(args.work, profiles[-1], defines,
                                     args.timeout)
                shuffled.label = "shuffled"
            run(gen, ROOT, args.timeout)

        builds = []
        if separate is not None:
            builds.append(separate)
        for profile in profiles:
            builds.append(build_fpc(args.work, profile, defines, args.timeout))
            if args.ppu_reuse:
                # second build over the units left behind by the first one:
                # this is the path where generic replay and alias identity break
                builds.append(build_fpc(args.work, profile, defines,
                                        args.timeout, reuse=True))
        if args.dcc and args.dcc_lib:
            builds.append(build_delphi(args.work, args.dcc, args.dcc_lib,
                                       args.timeout))
        # the mirror runs after the profiles, so it compares this build with
        # a repeat of itself and not with whatever the previous seed left
        mirror_findings: list[dict] = []
        if args.determinism:
            mirror_findings = build_twice(args.work, profiles[-1], defines,
                                          args.timeout)

        findings = compare(builds) + mirror_findings
        if second is not None:
            reference = next((b for b in builds if b.label == profiles[-1]), None)
            if reference and reference.compiled and second.compiled:
                # forms present in both programs must have produced the same
                # observations; the extra case only adds new names
                for note, value in sorted(reference.notes.items()):
                    # some observations describe the program as a whole (how
                    # many types its RTTI catalogue holds); a program with one
                    # more case legitimately differs there
                    if note.endswith("-gettypes"):
                        continue
                    other = second.notes.get(note)
                    if other is not None and other != value:
                        findings.append({"kind": "cross-program-note",
                                         "note": note,
                                         "builds": {"first": value,
                                                    "second": other}})
                for name in sorted(set(reference.failures)
                                   - set(second.failures)):
                    findings.append({"kind": "cross-program-check",
                                     "check": name,
                                     "detail": "red in the first program only"})

        if shuffled is not None:
            reference = next((b for b in builds if b.label == profiles[-1]), None)
            if reference and reference.compiled and shuffled.compiled:
                if shuffled.checks != reference.checks:
                    findings.append({"kind": "order-dependent-count",
                                     "counts": {"normal": reference.checks,
                                                "shuffled": shuffled.checks}})
                for note, value in sorted(reference.notes.items()):
                    other = shuffled.notes.get(note)
                    if other is not None and other != value:
                        findings.append({"kind": "order-dependent-note",
                                         "note": note,
                                         "builds": {"normal": value,
                                                    "shuffled": other}})
                for name in sorted(set(reference.failures) ^ set(shuffled.failures)):
                    findings.append({"kind": "order-dependent-check",
                                     "check": name})
        findings, known_hits = classify(findings, load_known(args.work / "known_findings.json"))
        # a digest split is a consequence, not a cause: when every underlying
        # disagreement is already analysed, the split carries no new
        # information.  But it is only a consequence of *those* findings if the
        # layers that moved are the layers they live in - otherwise something
        # else moved too, and absorbing it would hide it.
        moved = {f.get("layer") for f in findings
                 if f["kind"] == "layer-digest-split"}
        analysed = {CHECK_LAYER_RE.match(h.get("check") or h.get("note") or "")
                    for h in known_hits}
        analysed = {m.group(1) for m in analysed if m}
        if (known_hits and not moved - analysed
                and all(f["kind"] in ("digest-split", "check-count-split",
                                      "layer-digest-split")
                        for f in findings)):
            known_hits += [{**f, "known": "derived"} for f in findings]
            findings = []
        total_findings += len(findings)
        summary = {b.label: (f"{b.checks} checks digest={b.digest}"
                             if b.compiled else "COMPILE FAILED")
                   for b in builds}
        print(f"seed {seed}: " + ", ".join(f"{k}: {v}" for k, v in summary.items()))
        for f in findings:
            print("  NEW " + json.dumps(f, sort_keys=True))
        if known_hits:
            seen = sorted({h["known"] for h in known_hits})
            print("  known: %d hits (%s)" % (len(known_hits), ", ".join(seen)))
        report.append({"seed": seed, "summary": summary, "findings": findings})

    if args.report:
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print(f"DEVIL_GATE {'OK' if total_findings == 0 else 'FINDINGS'} "
          f"seeds={len(seeds)} findings={total_findings}")
    sys.exit(1 if total_findings else 0)


if __name__ == "__main__":
    main()
