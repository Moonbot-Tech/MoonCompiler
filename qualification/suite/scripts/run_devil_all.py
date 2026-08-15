#!/usr/bin/env python3
"""Run every Devil gate in one go and report a single verdict.

Order matters: the cheap gates run first so an obvious break is reported in
seconds, and the expensive sweep runs last.

    run_devil_all.py --fpc ... --fpc-config ... [--dcc ... --dcc-lib ...]
                     [--seeds 1,2,3] [--cases 200] [--with-mutation]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(cmd: list[str], timeout: int) -> tuple[int, str, float]:
    started = time.time()
    try:
        p = subprocess.run(cmd, cwd=ROOT.parent.parent, capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>", time.time() - started
    return p.returncode, (p.stdout or "") + (p.stderr or ""), time.time() - started


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--fpc", type=Path, required=True)
    p.add_argument("--fpc-config", type=Path, required=True)
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seeds", default="1,2,3")
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--stress-cases", type=int, default=30)
    p.add_argument("--with-mutation", action="store_true")
    p.add_argument("--timeout", type=int, default=7200)
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    common = ["--fpc", str(args.fpc), "--fpc-config", str(args.fpc_config)]
    delphi = []
    if args.dcc and args.dcc_lib:
        delphi = ["--dcc", str(args.dcc), "--dcc-lib", str(args.dcc_lib)]

    stages = [
        ("codegen", [sys.executable, str(SCRIPTS / "run_devil_codegen_gate.py")]
         + common),
        ("reject", [sys.executable, str(SCRIPTS / "run_devil_reject_gate.py")]
         + common + delphi),
        ("stress", [sys.executable, str(SCRIPTS / "run_devil_stress_gate.py")]
         + common + ["--cases", str(args.stress_cases)]),
        ("main", [sys.executable, str(SCRIPTS / "run_devil_gate.py")]
         + common + delphi + ["--seeds", args.seeds, "--cases", str(args.cases),
                              "--ppu-reuse"]),
    ]
    if args.with_mutation:
        stages.append(("mutation",
                       [sys.executable, str(SCRIPTS / "run_devil_mutation.py"),
                        "--seeds", args.seeds, "--cases", "60"]))

    results = []
    failed = []
    for name, cmd in stages:
        code, log, seconds = run(cmd, args.timeout)
        verdict = [l for l in log.splitlines()
                   if l.startswith(("DEVIL_", "  NEW"))][-8:]
        results.append({"stage": name, "code": code,
                        "seconds": round(seconds, 1), "tail": verdict})
        print(f"=== {name}: exit {code} in {seconds:.0f}s")
        for line in verdict:
            print("   " + line)
        if code != 0:
            failed.append(name)

    if args.report:
        args.report.write_text(json.dumps(results, indent=2, ensure_ascii=False)
                               + "\n", encoding="utf-8")
    print(f"DEVIL_ALL {'OK' if not failed else 'FINDINGS in ' + ','.join(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
