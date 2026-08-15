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
import shutil
import subprocess
import sys
from pathlib import Path

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
            m = SUMMARY_RE.match(line.strip())
            if m:
                self.digest = m.group("digest")
                self.checks = int(m.group("checks"))


def build_fpc(work: Path, fpc: Path, cfg: Path, option: str,
              defines: list[str], timeout: int, reuse: bool = False) -> Build:
    build = Build(f"fpc{option}{'+reuse' if reuse else ''}")
    out = work / f"out-{option}"
    if not reuse:
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
    cmd = [str(fpc), "-n", f"@{cfg}", "-Mdelphi", f"-{option}"]
    cmd += [f"-d{d}" for d in defines]
    cmd += [f"-FU{out}", f"-FE{out}", "devil.dpr"]
    code, log = run(cmd, work, timeout)
    build.compile_log = log
    exe = out / "devil.exe"
    if not exe.exists():
        exe = out / "devil"
    if code != 0 or not exe.exists():
        return build
    build.compiled = True
    # a generated program must never run long; anything slower is a hang
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
            if rule.get("kind") and rule["kind"] != f.get("kind"):
                continue
            if "check" in rule and not re.match(rule["check"], f.get("check", "")):
                continue
            if rule.get("kind") == "internal-error" and f.get("kind") == "internal-error":
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
    names: set[str] = set()
    for b in alive:
        names |= set(b.failures)
    for name in sorted(names):
        rows = {b.label: b.failures.get(name) for b in alive}
        findings.append({
            "kind": "model-mismatch",
            "check": name,
            "builds": {k: (v[0] if v else "ok") for k, v in rows.items()},
        })
    note_names: set[str] = set()
    for b in alive:
        note_names |= set(b.notes)
    for name in sorted(note_names):
        values = {b.label: b.notes.get(name, "<missing>") for b in alive}
        if len(set(values.values())) > 1:
            findings.append({"kind": "observation-split", "note": name,
                             "builds": values})
    digests = {b.label: b.digest for b in alive}
    if len(set(digests.values())) > 1:
        findings.append({"kind": "digest-split", "digests": digests})
    counts = {b.label: b.checks for b in alive}
    if len(set(counts.values())) > 1:
        findings.append({"kind": "check-count-split", "counts": counts})
    return findings


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--fpc", type=Path, required=True)
    p.add_argument("--fpc-config", type=Path, required=True)
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seeds", default="1")
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--layers", default="all")
    p.add_argument("--options", default="O-,O1,O2,O3")
    p.add_argument("--defines", default="")
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--work", type=Path, default=DEVIL)
    p.add_argument("--report", type=Path)
    p.add_argument("--ppu-reuse", action="store_true",
                   help="also rebuild reusing the PPUs of the first build")
    args = p.parse_args()

    # every build runs inside the work directory, so tool paths must be
    # absolute before we change into it
    args.fpc = args.fpc.resolve()
    args.fpc_config = args.fpc_config.resolve()
    if args.dcc:
        args.dcc = args.dcc.resolve()
    if args.dcc_lib:
        args.dcc_lib = args.dcc_lib.resolve()
    args.work = args.work.resolve()

    seeds = [int(s) for s in args.seeds.split(",") if s]
    options = [o for o in args.options.split(",") if o]
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

        builds = []
        for opt in options:
            builds.append(build_fpc(args.work, args.fpc, args.fpc_config, opt,
                                    defines, args.timeout))
            if args.ppu_reuse:
                # second build over the units left behind by the first one:
                # this is the path where generic replay and alias identity break
                builds.append(build_fpc(args.work, args.fpc, args.fpc_config,
                                        opt, defines, args.timeout, reuse=True))
        if args.dcc and args.dcc_lib:
            builds.append(build_delphi(args.work, args.dcc, args.dcc_lib,
                                       args.timeout))
        findings = compare(builds)
        findings, known_hits = classify(findings, load_known(args.work / "known_findings.json"))
        # a digest split is a consequence, not a cause: when every underlying
        # disagreement is already analysed, the split carries no new information
        if known_hits and all(f["kind"] in ("digest-split", "check-count-split")
                              for f in findings):
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
