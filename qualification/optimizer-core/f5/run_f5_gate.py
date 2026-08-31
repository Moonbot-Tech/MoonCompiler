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
        return ROOT / ".moonbot/toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / ".moonbot/toolchain/bin/ppcx64"


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / f"rtl/units/{target}"


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


def compile_one(compiler: Path, rtl: Path, name: str,
                option: str, compiler_options: list[str],
                outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-O3", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}",
    ] + link_args()
    if option:
        cmd.insert(4, option)
    cmd.extend(compiler_options)
    cmd.append(str(SOURCE))
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


def routine_asm(asm: str, name: str) -> str:
    marker = re.search(
        rf"(?mi)^P\$ADDRESS_GVN_SEMANTIC_\$\$_{name}[^:]*:\s*$",
        asm)
    if not marker:
        raise RuntimeError(f"cannot find {name} assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    return tail if not end else tail[:end.start() + 1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    ap.add_argument(
        "--compiler-option", action="append", default=[],
        help="extra compiler option; repeat for multiple options",
    )
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f5_"))
    failures: list[str] = []
    try:
        off = compile_one(
            args.compiler, args.rtl, "off", "-OoNOADDRESSGVN",
            args.compiler_option, tmp)
        on = compile_one(
            args.compiler, args.rtl, "on", "-OoADDRESSGVN",
            args.compiler_option, tmp)
        default = compile_one(
            args.compiler, args.rtl, "default", "",
            args.compiler_option, tmp)
        off_result = run(off[0])
        on_result = run(on[0])
        default_result = run(default[0])
        if off_result != EXPECTED or on_result != EXPECTED or \
                default_result != EXPECTED:
            failures.append(f"runtime differs: off={off_result!r} on={on_result!r}")

        off_asm = routine_asm(off[1], "BUTTERFLY\\$")
        on_asm = routine_asm(on[1], "BUTTERFLY\\$")
        default_asm = routine_asm(default[1], "BUTTERFLY\\$")
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
        if off_bases and (off_bases < 8 or on_bases > 2):
            failures.append(
                f"base reuse missing: bases off={off_bases} on={on_bases}")
        if not off_bases and on_bases:
            failures.append(
                f"unexpected base materialization: bases off=0 on={on_bases}")
        if (default_shifts, default_bases) != (on_shifts, on_bases):
            failures.append(
                "O3 default differs from explicit ADDRESSGVN: "
                f"default={default_shifts}/{default_bases} "
                f"explicit={on_shifts}/{on_bases}")
        off_open = routine_asm(off[1], "BUTTERFLYOPEN")
        on_open = routine_asm(on[1], "BUTTERFLYOPEN")
        default_open = routine_asm(default[1], "BUTTERFLYOPEN")
        off_open_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", off_open))
        on_open_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", on_open))
        default_open_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", default_open))
        if off_open_shifts < 8 or on_open_shifts > 2:
            failures.append(
                "open-array index reuse missing: "
                f"shifts off={off_open_shifts} on={on_open_shifts}")
        if default_open_shifts != on_open_shifts:
            failures.append(
                "O3 default open-array differs from explicit ADDRESSGVN: "
                f"default={default_open_shifts} explicit={on_open_shifts}")
        off_float = routine_asm(off[1], "BUTTERFLYFLOATOPEN")
        on_float = routine_asm(on[1], "BUTTERFLYFLOATOPEN")
        default_float = routine_asm(default[1], "BUTTERFLYFLOATOPEN")
        off_float_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", off_float))
        on_float_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", on_float))
        default_float_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", default_float))
        if off_float_shifts < 8 or on_float_shifts > 2:
            failures.append(
                "floating open-array index reuse missing: "
                f"shifts off={off_float_shifts} on={on_float_shifts}")
        if default_float_shifts != on_float_shifts:
            failures.append(
                "O3 default floating open-array differs from explicit "
                f"ADDRESSGVN: default={default_float_shifts} "
                f"explicit={on_float_shifts}")
        off_pair = routine_asm(off[1], "READPAIR\\$")
        on_pair = routine_asm(on[1], "READPAIR\\$")
        default_pair = routine_asm(default[1], "READPAIR\\$")
        off_pair_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", off_pair))
        on_pair_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", on_pair))
        default_pair_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", default_pair))
        off_pair_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", off_pair))
        on_pair_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", on_pair))
        default_pair_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", default_pair))
        if off_pair_shifts < 2 or on_pair_shifts > 1 or \
                off_pair_extends < 2 or on_pair_extends > 1:
            failures.append(
                "two-use record reuse missing: "
                f"shifts {off_pair_shifts}->{on_pair_shifts}, "
                f"extends {off_pair_extends}->{on_pair_extends}")
        if (default_pair_shifts, default_pair_extends) != \
                (on_pair_shifts, on_pair_extends):
            failures.append(
                "O3 default two-use pair differs from explicit ADDRESSGVN: "
                f"default={default_pair_shifts}/{default_pair_extends} "
                f"explicit={on_pair_shifts}/{on_pair_extends}")
        for routine in (
            "READPAIRREDEFINED", "READPAIRACROSSCALL",
            "READPAIRACROSSINDIRECTCALL", "READPAIRACROSSMEMORY",
        ):
            off_barrier = routine_asm(off[1], routine)
            on_barrier = routine_asm(on[1], routine)
            off_barrier_shifts = len(re.findall(
                r"(?mi)^\s*shlq\s+\$4,", off_barrier))
            on_barrier_shifts = len(re.findall(
                r"(?mi)^\s*shlq\s+\$4,", on_barrier))
            if off_barrier_shifts < 2 or \
                    on_barrier_shifts != off_barrier_shifts:
                failures.append(
                    f"{routine} barrier crossed: "
                    f"shifts {off_barrier_shifts}->{on_barrier_shifts}")
        off_market = routine_asm(off[1], "READMARKETPOINT")
        on_market = routine_asm(on[1], "READMARKETPOINT")
        default_market = routine_asm(default[1], "READMARKETPOINT")
        off_market_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", off_market))
        on_market_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", on_market))
        default_market_shifts = len(re.findall(
            r"(?mi)^\s*shlq\s+\$4,", default_market))
        off_market_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", off_market))
        on_market_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", on_market))
        default_market_extends = len(re.findall(
            r"(?mi)^\s*movslq\s+", default_market))
        if off_market_shifts < 2 or off_market_extends < 2 or \
                (on_market_shifts, on_market_extends) != \
                (off_market_shifts, off_market_extends):
            failures.append(
                "mixed-field memory barrier crossed: "
                f"shifts {off_market_shifts}->{on_market_shifts}, "
                f"extends {off_market_extends}->{on_market_extends}")
        if (default_market_shifts, default_market_extends) != \
                (on_market_shifts, on_market_extends):
            failures.append(
                "O3 default mixed-field differs from explicit ADDRESSGVN: "
                f"default={default_market_shifts}/{default_market_extends} "
                f"explicit={on_market_shifts}/{on_market_extends}")
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
          f"(static shifts {off_shifts}->{on_shifts}, "
          f"open shifts {off_open_shifts}->{on_open_shifts}, "
          f"float-open shifts {off_float_shifts}->{on_float_shifts}, "
          f"two-use shifts {off_pair_shifts}->{on_pair_shifts}, "
          f"extends {off_pair_extends}->{on_pair_extends}, "
          f"mixed-field {off_market_shifts}/{off_market_extends}->"
          f"{on_market_shifts}/{on_market_extends}, "
          f"bases {off_bases}->{on_bases})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
