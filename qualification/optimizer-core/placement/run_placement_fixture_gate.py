#!/usr/bin/env python3
"""Placement gate on the product toolchain: the code placement draft holds its rules in compiled code.

The draft is off by default (doc/OPTIMIZER.md, "Code placement"); the gate
switches it on for its build (MOONCOMPILER_PLACEMENT=1).  Builds
qualification/performance/tools/placement_fixture.dpr with the product
compiler and configuration at -O3 (tiny leaves, short and long loops, a loop
over a line, call loops, branch-dense code, sixteen set tests with the jump
target between the compare and the jump, a hand-written block), runs it and
asserts with check_placement_rules.py that no rule of the list is violated
in the fixture's own code:

  R4   no jmp/jcc/call/ret or fused ALU+jcc pair crosses or ends on a
       32-byte boundary
  R2E  a loop of at most 64 bytes lies inside one 64-byte line, its back-edge
       not ending on byte 29-31 or 62-63
  R2X  no prefix inside a one-line loop or procedure that no rule needs
  R3H  a longer loop starts on byte 0, 16 or 32 of a line
  R3L  ... and touches no more lines than its length needs
  RT   no taken-branch target inside a long loop in the last 12 bytes of a line
  R1   every procedure starts on a 64-byte line

The stand chains (scripts/Stand-F-Chain.ps1, scripts/stand-chain.sh) run the
same check on every stand variant; this is the form for CI and for a product
toolchain.  Needs objdump (code_placement.py; MOON_OBJDUMP overrides).

  python qualification/optimizer-core/placement/run_placement_fixture_gate.py
  python ... --compiler <ppcx64> --config <moon-base.cfg> [--assert R4,R1] [--keep]
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TOOLS = ROOT / "qualification" / "performance" / "tools"
FIXTURE = TOOLS / "placement_fixture.dpr"
MM = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
RULES = "R4,R2E,R2X,R3H,R3L,RT,R1"


def default_toolchain() -> tuple[Path | None, Path]:
    stand = os.environ.get("MOONBOT_TOOLCHAIN")
    base = Path(stand) if stand else ROOT / "toolchain"
    if os.name == "nt":
        return base / "bin" / "x86_64-win64" / "ppcx64.exe", base / "bin" / "x86_64-win64" / "moon-base.cfg"
    versions = sorted((base / "lib" / "fpc").glob("*/ppcx64"))
    return (versions[0] if len(versions) == 1 else None), base / "etc" / "moon-base.cfg"


def build(compiler: Path, config: Path, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    first = "mormot.core.fpcx64mm" if os.name == "nt" else "mormot.core.fpcx64mm,cthreads"
    cmd = [str(compiler), "-n", f"@{config}", "-Mdelphi", "-O3", "-B", "-gw3",
           "-uMOONCOMPILER_VANILLA_RUNTIME", "-dMOONBOT_MM_PROFILE_REQUIRED",
           "-dFPCMM_BOOSTER", "-dFPCMM_MOONSHARD", "-dNOPATCHRTL",
           f"--pinned-unit=mormot.core.fpcx64mm={MM}", f"--required-first-unit={first}",
           f"-Fu{MM.parent}", f"-FE{out}", f"-FU{out}", str(FIXTURE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600,
                          env={**os.environ, "MOONCOMPILER_PLACEMENT": "1"})  # the draft is off by default
    (out / "build.log").write_text((proc.stdout or "") + (proc.stderr or ""), encoding="utf-8")
    exe = out / ("placement_fixture.exe" if os.name == "nt" else "placement_fixture")
    if proc.returncode != 0 or not exe.is_file():
        tail = [line for line in ((proc.stdout or "") + (proc.stderr or "")).splitlines()
                if re.search(r"Error|Fatal", line)]
        raise RuntimeError("fixture build failed\n" + "\n".join(tail[-20:]))
    run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
    if run.returncode != 0 or "PLACEMENT_FIXTURE_OK" not in run.stdout:
        raise RuntimeError(f"fixture run failed: exit {run.returncode}\n{run.stdout}{run.stderr}")
    return exe


def main() -> int:
    compiler, config = default_toolchain()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", type=Path, default=compiler)
    ap.add_argument("--config", type=Path, default=config)
    ap.add_argument("--assert", dest="rules", default=RULES)
    ap.add_argument("--keep", action="store_true", help="keep the build directory")
    args = ap.parse_args()
    if args.compiler is None or not Path(args.compiler).is_file() or not Path(args.config).is_file():
        print("PLACEMENT FIXTURE GATE: FAIL (no toolchain: pass --compiler and --config)")
        return 2
    out = Path(tempfile.mkdtemp(prefix="placement_fixture_gate_"))
    try:
        try:
            exe = build(Path(args.compiler), Path(args.config), out)
        except RuntimeError as error:
            print(f"PLACEMENT FIXTURE GATE: FAIL ({error})")
            return 1
        # the fixture's own code: 'P$PLACEMENT_FIXTURE...' ('$' is '.' for the ELF spelling too)
        check = subprocess.run(
            [sys.executable, str(TOOLS / "check_placement_rules.py"), str(exe),
             "--match", r"P.PLACEMENT_FIXTURE", "--assert", args.rules, "--list-violations"],
            capture_output=True, text=True, timeout=600)
        print(check.stdout, end="")
        if check.returncode != 0 or "PLACEMENT_GATE_PASS" not in check.stdout:
            print(check.stderr, end="")
            print(f"PLACEMENT FIXTURE GATE: FAIL (rules {args.rules})")
            return 1
        print(f"PLACEMENT FIXTURE GATE: PASS (rules {args.rules})")
        return 0
    finally:
        if args.keep:
            print(f"kept: {out}")
        else:
            shutil.rmtree(out, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
