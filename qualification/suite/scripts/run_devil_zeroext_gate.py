#!/usr/bin/env python3
"""Focused regression for narrow integer extension through O3 peepholes."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = Path(__file__).with_name("run_devil_gate.py")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" /
                        "devil-zeroext-focused")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    work = args.work.resolve()
    report = work / "report.json"
    command = [
        sys.executable, str(MAIN),
        "--seeds", "1,24",
        "--cases", "200",
        "--layers", "expr,unary,fold,unit,gen",
        "--profiles", "debug,o1,o2,release",
        "--timeout", str(args.timeout),
        "--work", str(work),
        "--report", str(report),
    ]
    result = subprocess.run(command, cwd=ROOT.parent.parent,
                            timeout=args.timeout, text=True)
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    rows = json.loads(report.read_text(encoding="utf-8"))
    findings = [finding for row in rows for finding in row["findings"]]
    known = [finding for row in rows for finding in row["known_hits"]]
    if findings or known:
        print(f"DEVIL_ZEROEXT FINDINGS new={len(findings)} known={len(known)}")
        raise SystemExit(1)
    print("DEVIL_ZEROEXT OK seeds=2 profiles=4 layers=5")


if __name__ == "__main__":
    main()
