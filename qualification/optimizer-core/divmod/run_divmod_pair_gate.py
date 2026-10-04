#!/usr/bin/env python3
"""Semantic and assembly gate for paired x86-64 DIV/MOD reuse."""

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
SOURCE = ROOT / "tests/test/cg/tdivmodpair1.pp"
EXPECTED = (0, "DIVMOD-PAIR:PASS\n", "")

OPTIMIZED_ROUTINES = (
    "SIGNED64DIVMOD",
    "SIGNED64MODDIV",
    "UNSIGNED64DIVMOD",
    "UNSIGNED64MODDIV",
    "SIGNED32DIVMOD",
    "SIGNED32MODDIV",
    "UNSIGNED32DIVMOD",
    "UNSIGNED32MODDIV",
)

NEGATIVE_CONTROLS = (
    "ALIASNUMERATOR",
    "ALIASDIVISOR",
    "SIDEEFFECTINGOPERANDS",
)


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
    exe = target / f"tdivmodpair1{suffix}"
    asm = target / "tdivmodpair1.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({opt})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def routine_asm(asm: str, name: str) -> str:
    marker = re.search(
        rf"(?mi)^P\$TDIVMODPAIR1_\$\$_{name}[^:]*:\s*$", asm)
    if not marker:
        raise RuntimeError(f"cannot find {name} assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    if not end:
        raise RuntimeError(f"cannot find end of {name} assembly")
    return tail[:end.start() + 1]


def division_count(asm: str) -> int:
    return len(re.findall(r"(?mi)^\s*(?:idiv|div)[lq]\s", asm))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--config", type=Path, default=default_config())
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_divmod_pair_"))
    failures: list[str] = []
    try:
        for opt in ("O2", "O3"):
            exe, asm = compile_one(args.compiler, args.config, opt, tmp)
            result = run(exe)
            if result != EXPECTED:
                failures.append(f"{opt} runtime differs: {result!r}")
            for routine in OPTIMIZED_ROUTINES:
                count = division_count(routine_asm(asm, routine))
                if count != 1:
                    failures.append(
                        f"{opt} {routine}: expected one division, got {count}")
            for routine in NEGATIVE_CONTROLS:
                count = division_count(routine_asm(asm, routine))
                if count != 2:
                    failures.append(
                        f"{opt} {routine}: unsafe merge, got {count} divisions")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"DIVMOD PAIR: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("DIVMOD PAIR: PASS (one division for exact pairs; aliases and effects kept)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
