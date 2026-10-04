#!/usr/bin/env python3
"""Semantic and assembly gate for proven full-range array loops."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / "tests/test/cg/trangeprovenloop1.pp"
EXPECTED = (0, "RANGE-PROVEN-LOOP:PASS\n", "")

PROVEN_ROUTINES = (
    "DYNAMICUP",
    "DYNAMICDOWN",
    "DYNAMICIDENTITYBOUND",
    "OPENUP",
    "OPENDOWN",
    "STATICUP",
    "STATICDOWN",
)

NEGATIVE_CONTROLS = (
    "DYNAMICPASTEND",
    "OPENPASTEND",
    "DYNAMICOFFSETPASTEND",
    "DYNAMICNARROWEDINDEX",
    "DYNAMICNARROWEDBOUND",
    "DYNAMICNARROWEDBOUNDDOWN",
    "OPENNARROWEDBOUND",
    "MUTABLEDESCRIPTOR",
)

CHECK_HELPER = re.compile(
    r"(?mi)^\s*call\s+fpc_(?:rangeerror|dynarray_rangecheck)\s*$")


def default_bin_dir() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/bin/x86_64-win64"
    return ROOT / "toolchain/bin"


def default_compiler() -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    return default_bin_dir() / f"ppcx64{suffix}"


def default_config() -> Path:
    return default_bin_dir() / "moon-base.cfg"


def compile_one(compiler: Path, config: Path, opt: str,
                outdir: Path) -> tuple[Path, str]:
    target = outdir / opt.lower()
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-n", f"@{config}", "-B", f"-{opt}", "-al", "-Aas",
        f"-FU{target}", f"-FE{target}", str(SOURCE),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    suffix = ".exe" if os.name == "nt" else ""
    exe = target / f"trangeprovenloop1{suffix}"
    asm = target / "trangeprovenloop1.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({opt})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def routine_asm(asm: str, name: str) -> str:
    marker = re.search(
        rf"(?mi)^P\$TRANGEPROVENLOOP1_\$\$_{name}[^:]*:\s*$", asm)
    if not marker:
        raise RuntimeError(f"cannot find {name} assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    if not end:
        raise RuntimeError(f"cannot find end of {name} assembly")
    return tail[:end.start() + 1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--config", type=Path, default=default_config())
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_range_loop_"))
    failures: list[str] = []
    try:
        for opt in ("O-", "O2", "O3"):
            exe, asm = compile_one(args.compiler, args.config, opt, tmp)
            result = run(exe)
            if result != EXPECTED:
                failures.append(f"{opt} runtime differs: {result!r}")
            if opt == "O3":
                for routine in PROVEN_ROUTINES:
                    if CHECK_HELPER.search(routine_asm(asm, routine)):
                        failures.append(
                            f"{opt} {routine}: redundant range helper remains")
                for routine in NEGATIVE_CONTROLS:
                    if not CHECK_HELPER.search(routine_asm(asm, routine)):
                        failures.append(
                            f"{opt} {routine}: required range helper disappeared")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"RANGE LOOP: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("RANGE LOOP: PASS (O3 full ranges optimized; unsafe forms still checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
