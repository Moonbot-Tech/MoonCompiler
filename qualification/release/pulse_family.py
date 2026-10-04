#!/usr/bin/env python3
"""Run and judge a four-placement Pulse family on an idle qualification host."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "qualification/performance/tools"


def pinned_mm(toolchain: Path) -> Path:
    config = (toolchain / "bin/x86_64-win64/moon-base.cfg" if sys.platform == "win32"
              else toolchain / "etc/moon-base.cfg")
    for line in config.read_text(encoding="utf-8").splitlines():
        prefix = "--pinned-unit=mormot.core.fpcx64mm="
        if line.startswith(prefix):
            raw = line[len(prefix):].strip().replace("$FPCBINDIR", str(config.parent))
            path = Path(raw).resolve()
            if not path.is_file():
                raise ValueError(f"pinned MM is absent: {path}")
            return path
    raise ValueError(f"pinned MM is absent from {config}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=("bc", "aa"), required=True)
    parser.add_argument("--baseline-toolchain", type=Path)
    parser.add_argument("--candidate-toolchain", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("medium", "long"), default="long")
    parser.add_argument("--case", help="one program/case for a focused family probe")
    args = parser.parse_args()
    if args.case and "/" not in args.case:
        parser.error("--case requires a program/case name")
    candidate = args.candidate_toolchain.resolve(strict=True)
    baseline = ((args.baseline_toolchain or candidate).resolve(strict=True)
                if args.kind == "bc" else candidate)
    if args.kind == "bc" and args.baseline_toolchain is None:
        parser.error("--baseline-toolchain is required for B/C")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = output / "pulse-family"
    if result.exists():
        raise ValueError(f"Pulse result already exists: {result}")
    if args.case:
        programs = args.case.split("/", 1)[0]
    else:
        programs = subprocess.check_output(
            [sys.executable, str(TOOLS / "pulse.py"), "programs", "--all"],
            cwd=ROOT, text=True).strip()
    left, right = ("B", "C") if args.kind == "bc" else ("A", "Acheck")
    systems = [name + suffix for name in (left, right)
               for suffix in ("", "1", "2", "3")]
    command = [sys.executable, str(TOOLS / "pulse.py"), "run", "--mode", args.mode,
               "--systems", ",".join(systems), "--programs", programs,
               "--build-jobs", "4", "--moon-extra-option=-gw3",
               "--tag", "pulse-family", "--result-root", str(output)]
    if args.case:
        command.extend(("--cases", args.case))
    for family, toolchain in ((left, baseline), (right, candidate)):
        mm = pinned_mm(toolchain)
        for suffix in ("", "1", "2", "3"):
            name = family + suffix
            command.extend(("--moon-system", f"{name}={toolchain}",
                            "--moon-system-mm-source", f"{name}={mm}"))
            if suffix:
                command.extend(("--moon-system-option",
                                f"{name}=-dPULSE_FILLER_{suffix}"))
    print(f"PULSE_START kind={args.kind} mode={args.mode} programs={len(programs.split(','))} "
          f"placements=4 result={result}", flush=True)
    pulse_code = subprocess.call(command, cwd=ROOT)
    if pulse_code:
        print(f"PULSE_FAIL exit={pulse_code} result={result}", flush=True)
        return pulse_code
    verdict = subprocess.call([sys.executable, str(TOOLS / "stand_ab_gate.py"),
                               str(result), "--baseline", left, "--candidate", right,
                               "--programs", programs], cwd=ROOT)
    if verdict:
        print(f"PULSE_GATE_FAIL exit={verdict} result={result}", flush=True)
        return verdict
    print(f"PULSE_FAMILY_PASS kind={args.kind} result={result}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"PULSE_FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
