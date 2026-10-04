#!/usr/bin/env python3
"""Semantic gate for the x86-64 shl/lea and shl/add peephole merge.

`shl $y,%r` followed by `lea (%r,%r,s),%r` or `add %r,%r` must not be merged
into one lea: the lea's base is the shifted value, the merged lea would read
the unshifted register.  shl_lea_scale.dpr computes x*2*3 and x*2*2 with the
value kept out of constant folding and compares them with an oracle that
multiplies by a runtime factor; -O2, -O3 and -O3 -OoNOCODEALIGN must all
print the same success line.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "shl_lea_scale.dpr"
EXPECTED_PREFIX = "SHL_LEA_SCALE_OK "


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / "toolchain/bin/ppcx64"


def default_rtl() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/units/x86_64-win64/rtl"
    roots = sorted((ROOT / "toolchain/lib/fpc").glob("*/units/x86_64-linux/rtl"))
    if len(roots) != 1:
        raise SystemExit("cannot uniquely locate Linux RTL; pass --rtl")
    return roots[0]


def link_args() -> list[str]:
    if os.name == "nt":
        return []
    probe = subprocess.run(["gcc", "-print-file-name=libgcc_s.so"], capture_output=True, text=True, timeout=30)
    libgcc = Path(probe.stdout.strip())
    if probe.returncode != 0 or not libgcc.is_absolute() or not libgcc.exists():
        raise SystemExit("cannot locate libgcc_s")
    return [f"-Fl{libgcc.parent}"]


def compile_and_run(compiler: Path, rtl: Path, name: str, options: list[str], outdir: Path) -> tuple[int, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-Mdelphi", "-n", "-dMOONCOMPILER_VANILLA_RUNTIME",
           f"-Fu{rtl}", f"-FE{target}", f"-FU{target}", f"-o{name}"] + link_args() + options + [str(SOURCE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    exe = target / name
    if not exe.is_file():
        exe = target / (name + ".exe")
    if proc.returncode != 0 or not exe.is_file():
        output = (proc.stdout or "") + (proc.stderr or "")
        raise RuntimeError(f"compile failed ({name})\n{output[-2000:]}")
    run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    return run.returncode, run.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path)
    args = ap.parse_args()
    args.rtl = args.rtl or default_rtl()
    builds = {"o2": ["-O2"], "o3": ["-O3"], "o3_off": ["-O3", "-OoNOCODEALIGN"]}
    failures: list[str] = []
    outputs: dict[str, str] = {}
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_shl_lea_"))
    try:
        for name, options in builds.items():
            try:
                code, out = compile_and_run(args.compiler, args.rtl, name, options, tmp)
            except Exception as exc:
                failures.append(f"{name}: {exc}")
                continue
            outputs[name] = out
            if code != 0 or not out.startswith(EXPECTED_PREFIX):
                failures.append(f"{name}: exit {code}, output {out!r}")
        if len(set(outputs.values())) > 1:
            failures.append(f"outputs differ: {outputs!r}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print(f"SHL LEA GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print(f"SHL LEA GATE: PASS ({outputs['o3']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
