#!/usr/bin/env python3
"""Pascal codegen against independent handwritten x86-64 oracles."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / "tests" / "devil" / "asm-oracle"
CHIMERA_SUPPORT = ROOT / "tests" / "chimera"
COVER = re.compile(r"^CHI_COVER\s+(\S+)(.*)$")


def parse_coverage(text: str) -> dict[str, dict[str, int]]:
    seen: dict[str, dict[str, int]] = {}
    for line in text.splitlines():
        found = COVER.match(line.strip())
        if not found:
            continue
        branches: dict[str, int] = {}
        for part in found.group(2).split():
            if "=" in part:
                name, _, count = part.partition("=")
                branches[name] = int(count)
        seen[found.group(1)] = branches
    return seen


def check_coverage(expected: list[dict], seen: dict[str, dict[str, int]],
                   profile: str) -> list[dict]:
    findings: list[dict] = []
    known = {row["id"] for row in expected}
    for row in expected:
        rid = row["id"]
        if rid not in seen:
            findings.append({"kind": "coverage-missing", "case": profile,
                             "detail": rid})
            continue
        for branch in row["branches"]:
            if seen[rid].get(branch, 0) <= 0:
                findings.append({"kind": "branch-dead", "case": profile,
                                 "detail": f"{rid}/{branch}"})
    for rid in sorted(set(seen) - known):
        findings.append({"kind": "coverage-unknown", "case": profile,
                         "detail": rid})
    return findings


def build_and_run(work: Path, profile: str, timeout: int) -> dict:
    out = work / profile
    out.mkdir(parents=True, exist_ok=True)
    source = TEST / "asm_oracle.dpr"
    build = subprocess.run(
        tc.compile_command(source, out, profile,
                           search=[TEST, CHIMERA_SUPPORT]),
        cwd=TEST, capture_output=True, text=True, errors="replace",
        timeout=timeout)
    compile_text = (build.stdout or "") + (build.stderr or "")
    (out / "compile.log").write_text(compile_text, encoding="utf-8")
    if build.returncode != 0:
        return {"built": False, "exit": build.returncode,
                "terminal": "", "coverage": {}}

    run = subprocess.run([str(tc.executable(out, "asm_oracle"))], cwd=TEST,
                         capture_output=True, text=True, errors="replace",
                         timeout=timeout)
    run_text = (run.stdout or "") + (run.stderr or "")
    (out / "run.log").write_text(run_text, encoding="utf-8")
    terminal = next((line.strip() for line in run_text.splitlines()
                     if line.startswith("ASM_ORACLE_")), "")
    return {"built": True, "exit": run.returncode, "terminal": terminal,
            "coverage": parse_coverage(run_text)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profiles", action="store_true",
                        help="Debug/O1/O2/O3 instead of O2/O3")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "asm-oracle")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    tc.preflight()
    args.work = args.work.resolve()
    if args.report:
        args.report = args.report.resolve()
    expected = json.loads(
        (TEST / "inventory.json").read_text(encoding="utf-8"))["rows"]
    profiles = ["debug", "o1", "o2", "release"] if args.profiles else [
        "o2", "release"]

    started = time.time()
    findings: list[dict] = []
    results: list[dict] = []
    digest: str | None = None
    for profile in profiles:
        result = build_and_run(args.work, profile, args.timeout)
        results.append({k: v for k, v in result.items() if k != "coverage"}
                       | {"profile": profile})
        if not result["built"]:
            findings.append({"kind": "build-failed", "case": profile,
                             "detail": f"exit {result['exit']}"})
            continue
        if result["exit"] != 0 or not result["terminal"].startswith(
                "ASM_ORACLE_OK"):
            findings.append({"kind": "run-failed", "case": profile,
                             "detail": result["terminal"] or
                                       f"exit {result['exit']}"})
            continue
        findings += check_coverage(expected, result["coverage"], profile)
        if digest is None:
            digest = result["terminal"]
        elif result["terminal"] != digest:
            findings.append({"kind": "digest-differs", "case": profile,
                             "detail": result["terminal"]})
        print(f"PASS {profile} {result['terminal']}")

    report = {"profiles": results, "findings": findings,
              "seconds": round(time.time() - started, 1)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2,
                                          ensure_ascii=False),
                               encoding="utf-8")
    if findings:
        for finding in findings[:12]:
            print(f"FAIL {finding['case']} {finding['kind']}: "
                  f"{finding['detail']}")
        print(f"ASM_ORACLE_GATE FINDINGS findings={len(findings)}")
        return 1
    print(f"ASM_ORACLE_GATE OK profiles={len(profiles)} "
          f"seconds={report['seconds']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
