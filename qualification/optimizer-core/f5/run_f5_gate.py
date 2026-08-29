#!/usr/bin/env python3
"""Fast semantic and assembly gate for x86-64 address reuse."""

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
SOURCE = HERE / "address_gvn_semantic.dpr"
EXPECTED = (0, "ADDRESSGVN:PASS:18446744073707293280\n", "")


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / "compiler/ppcx64.exe"
    return ROOT / "compiler/ppcx64"


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / f"rtl/units/{target}"


def compile_one(compiler: Path, rtl: Path, name: str,
                option: str, outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-O3", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}", str(SOURCE),
    ]
    if option:
        cmd.insert(4, option)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = target / ("address_gvn_semantic.exe" if os.name == "nt"
                    else "address_gvn_semantic")
    asm = target / "address_gvn_semantic.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({name})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def butterfly_asm(asm: str) -> str:
    marker = re.search(
        r"(?mi)^P\$ADDRESS_GVN_SEMANTIC_\$\$_BUTTERFLY\$LONGINT\$LONGINT:\s*$",
        asm)
    if not marker:
        raise RuntimeError("cannot find Butterfly assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    return tail if not end else tail[:end.start() + 1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f5_"))
    failures: list[str] = []
    try:
        off = compile_one(args.compiler, args.rtl, "off", "-OoNOADDRESSGVN", tmp)
        on = compile_one(args.compiler, args.rtl, "on", "-OoADDRESSGVN", tmp)
        default = compile_one(args.compiler, args.rtl, "default", "", tmp)
        off_result = run(off[0])
        on_result = run(on[0])
        default_result = run(default[0])
        if off_result != EXPECTED or on_result != EXPECTED or \
                default_result != EXPECTED:
            failures.append(f"runtime differs: off={off_result!r} on={on_result!r}")

        off_asm = butterfly_asm(off[1])
        on_asm = butterfly_asm(on[1])
        default_asm = butterfly_asm(default[1])
        off_shifts = len(re.findall(r"(?mi)^\s*shlq\s+\$4,", off_asm))
        on_shifts = len(re.findall(r"(?mi)^\s*shlq\s+\$4,", on_asm))
        off_bases = len(re.findall(r"(?mi)^\s*leaq\s+.*DATA.*\(%rip\)", off_asm))
        on_bases = len(re.findall(r"(?mi)^\s*leaq\s+.*DATA.*\(%rip\)", on_asm))
        default_shifts = len(re.findall(r"(?mi)^\s*shlq\s+\$4,", default_asm))
        default_bases = len(re.findall(
            r"(?mi)^\s*leaq\s+.*DATA.*\(%rip\)", default_asm))
        if off_shifts < 8 or on_shifts > 2:
            failures.append(
                f"index reuse missing: shifts off={off_shifts} on={on_shifts}")
        if off_bases < 8 or on_bases > 2:
            failures.append(
                f"base reuse missing: bases off={off_bases} on={on_bases}")
        if (default_shifts, default_bases) != (on_shifts, on_bases):
            failures.append(
                "O3 default differs from explicit ADDRESSGVN: "
                f"default={default_shifts}/{default_bases} "
                f"explicit={on_shifts}/{on_bases}")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"F5 ADDRESS GVN: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("F5 ADDRESS GVN: PASS "
          f"(shifts {off_shifts}->{on_shifts}, bases {off_bases}->{on_bases})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
