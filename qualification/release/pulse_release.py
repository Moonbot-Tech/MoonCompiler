#!/usr/bin/env python3
"""Collect the release performance report; a measured loss is not a broken run."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification/performance/tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pulse_assessment
import pulse
import pulse_completion
import pulse_roundto_oracle


def validate_report(path: Path) -> None:
    result = json.loads(path.read_text(encoding="utf-8"))
    raw_path = path.parent / "result.raw.json.gz"
    if result.get("raw_sha256"):
        if not raw_path.is_file() or hashlib.sha256(raw_path.read_bytes()).hexdigest() != result["raw_sha256"]:
            raise ValueError("Pulse compact report has no matching full raw evidence")
        raw = json.loads(gzip.decompress(raw_path.read_bytes()))
        if raw.get("release_validation") != result.get("release_validation"):
            raise ValueError("Pulse compact and raw release validation differ")
        result = raw
    proof = pulse_roundto_oracle.prove(result)
    if (result.get("release_validation") or {}).get("proved_noncomparable") != proof:
        raise ValueError("Pulse noncomparable case lacks its exact independent oracle")
    comparable = {name: row for name, row in result["cases"].items()
                  if proof is None or name != pulse_roundto_oracle.CASE}
    if not pulse_assessment.measurement_completed({**result, "cases": comparable}):
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
    if not pulse_completion.shortlist(result) <= {
        name for name, row in result["cases"].items() if row.get("confirmation")
    }:
        raise ValueError("release Pulse shortlist lacks an independent confirmation")
    if not (path.parent / "REPORT.md").is_file():
        raise ValueError("Pulse report is missing")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-toolchain", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline-mm-source", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--single-cpus", default="", help="physical CPU pairs for single-CPU Pulse cases")
    parser.add_argument("--complete-from", type=Path,
                        help="original full Pulse output whose rejected pairs are to be completed")
    parser.add_argument("--complete-sha256", default="", help="expected SHA-256 of original raw gzip")
    parser.add_argument("--complete-logs-sha256", default="", help="expected SHA-256 of original log manifest")
    args = parser.parse_args()
    completion = (args.complete_from, args.complete_sha256, args.complete_logs_sha256)
    if any(completion) != all(completion):
        parser.error("completion requires source directory, raw SHA-256, and log-manifest SHA-256 together")
    baseline = args.baseline_toolchain.resolve()
    baseline_mm = (args.baseline_mm_source or baseline / "runtime/mm/mormot.core.fpcx64mm.pas").resolve()
    if args.complete_from:
        pulse_completion.complete(args.complete_from.resolve(), args.complete_sha256,
                                  args.complete_logs_sha256, args.output.resolve(), baseline,
                                  ROOT / "toolchain", baseline_mm,
                                  ROOT / "runtime/mm/mormot.core.fpcx64mm.pas", args.single_cpus)
        validate_report(args.output / "result.json")
        print(f"PULSE_RELEASE_REPORT_READY {args.output / 'REPORT.md'}; completion evidence retained")
        return 0
    # The release baseline is an installed archive, including its own bundled MM.
    command = [sys.executable, str(ROOT / "qualification/performance/tools/pulse_full.py"),
               "--baseline-toolchain", str(baseline), "--candidate-toolchain", str(ROOT / "toolchain"),
               "--baseline-mm-source", str(baseline_mm),
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
