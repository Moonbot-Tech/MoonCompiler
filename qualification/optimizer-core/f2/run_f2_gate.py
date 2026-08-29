#!/usr/bin/env python3
"""Focused semantic and structural gate for optimizer phase F2."""

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
SOURCE = HERE / "licm_semantic.dpr"
LEVELS = ("-O-", "-O2", "-O3")
SUMMARY = re.compile(
    r"effect-observe-summary: proc=(\S+) mid=\S+ nodes=\d+ r=\S+ w=\S+"
    r" ie=\S+ temps=(\d+) reasons=\S+"
)

POSITIVE = ("HoistProbe", "NestedProbe", "BreakContinue")
NEGATIVE = (
    "MutatedLocal", "CallClobber", "GlobalClobber", "ThreadClobber",
    "PointerClobber", "CheckedZero", "DivZero", "StepLatch",
    "ManagedFuncret", "ManagedFetchInLoop", "GrowingLength",
    "RealExcluded", "LabelBarrier",
)


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / ".moonbot/toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / ".moonbot/toolchain/bin/ppcx64"


def default_rtl() -> Path:
    if os.name == "nt":
        return ROOT / ".moonbot/toolchain/units/x86_64-win64/rtl"
    roots = sorted((ROOT / ".moonbot/toolchain/lib/fpc").glob(
        "*/units/x86_64-linux/rtl"))
    if len(roots) != 1:
        raise SystemExit("cannot uniquely locate Linux RTL; pass --rtl")
    return roots[0]


def link_args() -> list[str]:
    if os.name == "nt":
        return []
    probe = subprocess.run(
        ["gcc", "-print-file-name=libgcc_s.so"], capture_output=True,
        text=True, timeout=30)
    libgcc = Path(probe.stdout.strip())
    if probe.returncode != 0 or not libgcc.is_absolute() or not libgcc.exists():
        raise SystemExit("cannot locate libgcc_s")
    return [f"-Fl{libgcc.parent}"]


def compile_one(compiler: Path, rtl: Path, level: str, licm: bool,
                verify: bool, outdir: Path) -> tuple[str, Path, str]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", level, "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-OoEFFECTOBSERVE", "-vd",
        "-al", "-Aas", f"-Fu{rtl}", f"-FE{outdir}", f"-FU{outdir}",
    ] + link_args()
    if licm:
        cmd.append("-OoLICM")
    if verify:
        cmd.append("-dOPTCORE_VERIFY")
    cmd.append(str(SOURCE))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = outdir / ("licm_semantic" + (".exe" if os.name == "nt" else ""))
    if proc.returncode != 0 or not exe.exists():
        raise RuntimeError(
            f"compile failed ({level}, licm={licm}, verify={verify})\n"
            f"{output[-3000:]}")
    asm = outdir / "licm_semantic.s"
    if not asm.is_file():
        raise RuntimeError(f"assembly listing missing ({level}, verify={verify})")
    return output, exe, asm.read_text(encoding="utf-8", errors="replace")


def summaries(output: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for proc, temps in SUMMARY.findall(output):
        if proc in result:
            raise RuntimeError(f"duplicate short routine name in observe output: {proc}")
        result[proc] = int(temps)
    return result


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f2_"))
    try:
        for level in LEVELS:
            try:
                off_text, off_exe, _ = compile_one(
                    args.compiler, args.rtl, level, False, False,
                    tmp / f"{level}_off")
                on_text, on_exe, on_asm = compile_one(
                    args.compiler, args.rtl, level, True, False,
                    tmp / f"{level}_on")
                _, verify_exe, verify_asm = compile_one(
                    args.compiler, args.rtl, level, True, True,
                    tmp / f"{level}_verify")
                off_run = run(off_exe)
                on_run = run(on_exe)
                verify_run = run(verify_exe)
                expected = (0, "F2-LICM:PASS\n", "")
                if (off_run != expected or on_run != expected or
                        verify_run != expected):
                    failures.append(
                        f"{level}: runtime off={off_run!r}, on={on_run!r}, "
                        f"verify={verify_run!r}")
                if (verify_asm.count("fpc_rangeerror") <=
                        on_asm.count("fpc_rangeerror")):
                    failures.append(
                        f"{level}: OPTCORE_VERIFY injected no executable "
                        "range-error checks")
                off_sum = summaries(off_text)
                on_sum = summaries(on_text)
                for proc in POSITIVE:
                    if proc not in off_sum or proc not in on_sum:
                        failures.append(f"{level} {proc}: missing observe summary")
                    elif on_sum[proc] <= off_sum[proc]:
                        failures.append(
                            f"{level} {proc}: LICM created no temp "
                            f"(off={off_sum[proc]}, on={on_sum[proc]})")
                for proc in NEGATIVE:
                    if proc not in off_sum or proc not in on_sum:
                        failures.append(f"{level} {proc}: missing observe summary")
                    elif on_sum[proc] != off_sum[proc]:
                        failures.append(
                            f"{level} {proc}: forbidden hoist/temp delta "
                            f"(off={off_sum[proc]}, on={on_sum[proc]})")
            except Exception as exc:
                failures.append(f"{level}: {exc}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"F2 GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print(f"F2 GATE: PASS ({len(LEVELS)} levels, "
          f"{len(POSITIVE)} positive and {len(NEGATIVE)} negative routines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
