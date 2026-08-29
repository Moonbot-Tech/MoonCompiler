#!/usr/bin/env python3
"""Short ABBA performance proof for the minimal F2 LICM consumer."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import statistics
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "licm_perf.dpr"
COMMON = ROOT / "qualification/performance/common"
RESULT = re.compile(r"F2-PERF ticks=(\d+) iterations=(\d+) digest=(\d+)")


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


def compile_one(compiler: Path, rtl: Path, licm: bool, outdir: Path) -> Path:
    outdir.mkdir(parents=True)
    cmd = [
        str(compiler), "-Mdelphi", "-O2", "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}", f"-Fu{COMMON}",
        f"-FE{outdir}", f"-FU{outdir}",
    ]
    if licm:
        cmd.append("-OoLICM")
    cmd.append(str(SOURCE))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    exe = outdir / ("licm_perf" + (".exe" if os.name == "nt" else ""))
    if proc.returncode != 0 or not exe.exists():
        raise RuntimeError(proc.stdout + proc.stderr)
    return exe


def run_one(exe: Path) -> tuple[float, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    match = RESULT.fullmatch(proc.stdout.strip())
    if proc.returncode != 0 or not match:
        raise RuntimeError(
            f"bad benchmark run: rc={proc.returncode}, out={proc.stdout!r}, "
            f"err={proc.stderr!r}")
    ticks, iterations, digest = match.groups()
    return int(ticks) / int(iterations), digest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    ap.add_argument("--samples", type=int, default=9)
    args = ap.parse_args()
    if args.samples < 5:
        raise SystemExit("--samples must be at least 5")

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f2_perf_"))
    try:
        off = compile_one(args.compiler, args.rtl, False, tmp / "off")
        on = compile_one(args.compiler, args.rtl, True, tmp / "on")
        values = {"off": [], "on": []}
        digests: set[str] = set()
        order = ("off", "on", "on", "off")
        exes = {"off": off, "on": on}
        for index in range(args.samples * 2):
            key = order[index % len(order)]
            value, digest = run_one(exes[key])
            values[key].append(value)
            digests.add(digest)
        if len(digests) != 1:
            raise RuntimeError(f"semantic digest mismatch: {sorted(digests)}")
        off_med = statistics.median(values["off"])
        on_med = statistics.median(values["on"])
        ratio = on_med / off_med
        print(f"F2 PERF: off={off_med:.4f} on={on_med:.4f} "
              f"cycles/iteration ratio={ratio:.4f}x samples="
              f"{len(values['off'])}+{len(values['on'])}")
        if ratio >= 0.90:
            print("F2 PERF: FAIL (LICM did not remove the measured loop cost)")
            return 1
        print("F2 PERF: PASS")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
