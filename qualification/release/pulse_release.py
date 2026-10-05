#!/usr/bin/env python3
"""Collect the release performance report; a measured loss is not a broken run."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/performance/tools"))
import pulse_assessment
import pulse


def validate_report(path: Path) -> None:
    result = json.loads(path.read_text(encoding="utf-8"))
    if not pulse_assessment.measurement_completed(result):
        raise ValueError("Pulse measurement is incomplete or its semantic/A/A checks failed")
    scope = result.get("scope", {})
    # A program the released toolchain cannot build (no System.ZLib before it) is named, not measured;
    # the candidate builds every program.
    left_out = scope.get("left_out") or {}
    if any(systems != ["moon-baseline"] for systems in left_out.values()):
        raise ValueError(f"the candidate toolchain does not build every Pulse program: {left_out}")
    if (scope.get("cases") != "all" or result.get("pairs", 0) < 12
            or set(scope.get("programs", [])) | set(left_out) != set(pulse.stand_programs(True))
            or not result.get("confirmation_required")
            or not result.get("confirmation_preflight", {}).get("passed")):
        raise ValueError("release Pulse requires full coverage and independent confirmation")
    if any(row["final"]["valid_pairs"] < 12 for row in result["cases"].values()):
        raise ValueError("release Pulse requires 12 valid pairs for every case")
    confirmations = [row["confirmation"] for row in result["cases"].values() if row.get("confirmation")]
    if not confirmations or any(row["final"]["valid_pairs"] < 12 for row in confirmations):
        raise ValueError("release Pulse confirmation is missing or incomplete")
    if not (path.parent / "REPORT.md").is_file():
        raise ValueError("Pulse report is missing")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-toolchain", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline-mm-source", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--single-cpus", default="", help="physical CPU pairs for single-CPU Pulse cases")
    args = parser.parse_args()
    baseline = args.baseline_toolchain.resolve()
    # The release baseline is an installed archive, including its own bundled MM.
    command = [sys.executable, str(ROOT / "qualification/performance/tools/pulse_full.py"),
               "--baseline-toolchain", str(baseline), "--candidate-toolchain", str(ROOT / "toolchain"),
               "--baseline-mm-source", str(args.baseline_mm_source or baseline / "runtime/mm/mormot.core.fpcx64mm.pas"),
               "--candidate-mm-source", str(ROOT / "runtime/mm/mormot.core.fpcx64mm.pas"),
               "--output", str(args.output), "--pairs", "12", "--build-jobs", str(args.jobs)]
    if args.single_cpus:
        command += ["--single-cpus", args.single_cpus]
    code = subprocess.call(command, cwd=ROOT)
    if code:
        return code
    validate_report(args.output / "result.json")
    print(f"PULSE_RELEASE_REPORT_READY {args.output / 'REPORT.md'}; performance acceptance requires review")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"PULSE_RELEASE_FAILED {error}", file=sys.stderr)
        raise SystemExit(2)
