#!/usr/bin/env python3
"""Semantic and assembly gate for managed-load CSE profitability."""

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
SOURCE = ROOT / "tests/test/opt/tcsemanagedload1.pp"
EXPECTED = (0, "CSE-MANAGED-LOAD:PASS:2537984\n", "")


def default_compiler() -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    return ROOT / "compiler" / f"ppcx64{suffix}"


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / "rtl" / "units" / target


def compile_one(compiler: Path, rtl: Path, name: str, option: str,
                compiler_options: list[str], outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-O3", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}",
    ]
    if option:
        cmd.insert(4, option)
    cmd.extend(compiler_options)
    cmd.append(str(SOURCE))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    suffix = ".exe" if os.name == "nt" else ""
    exe = target / f"tcsemanagedload1{suffix}"
    asm = target / "tcsemanagedload1.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({name})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def routine_asm(asm: str, name: str) -> str:
    marker = re.search(
        rf"(?mi)^P\$TCSEMANAGEDLOAD1_\$\$_{name}[^:]*:\s*$", asm)
    if not marker:
        raise RuntimeError(f"cannot find {name} assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    if not end:
        raise RuntimeError(f"cannot find end of {name} assembly")
    return tail[:end.start() + 1]


def normalize(asm: str) -> str:
    asm = re.sub(r"\.L(?:eb|ee|c|j|e|d)\d+", ".L", asm)
    return re.sub(r"(?m)^# \[[^\n]*\n", "", asm)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    ap.add_argument("--compiler-option", action="append", default=[])
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_managed_cse_"))
    failures: list[str] = []
    try:
        builds = {
            name: compile_one(args.compiler, args.rtl, name, option,
                              args.compiler_option, tmp)
            for name, option in (
                ("off", "-OoNOCSE"),
                ("on", "-OoCSE"),
                ("default", ""),
            )
        }
        results = {name: run(build[0]) for name, build in builds.items()}
        if any(result != EXPECTED for result in results.values()):
            failures.append(f"runtime differs: {results!r}")

        for routine in (
            "ARRAYPRODUCT", "TEXTPRODUCT", "RECORDTEXTPRODUCT",
        ):
            bodies = {
                name: normalize(routine_asm(build[1], routine))
                for name, build in builds.items()
            }
            if bodies["on"] != bodies["off"]:
                failures.append(
                    f"{routine} gained a memory-backed managed CSE temp")
            if bodies["default"] != bodies["on"]:
                failures.append(f"default {routine} differs from explicit CSE")

        expensive = {
            name: normalize(routine_asm(build[1], "THREADTEXTPRODUCT"))
            for name, build in builds.items()
        }
        if expensive["on"] == expensive["off"]:
            failures.append("profitable threadvar managed CSE was rejected")
        if expensive["default"] != expensive["on"]:
            failures.append(
                "default THREADTEXTPRODUCT differs from explicit CSE")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"MANAGED LOAD CSE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("MANAGED LOAD CSE: PASS "
          "(cheap round-trips absent, expensive threadvar retained)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
