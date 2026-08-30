#!/usr/bin/env python3
"""Semantic and x86-64 assembly gate for stable dynamic-array base reuse."""

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
SOURCE = ROOT / "tests/test/cg/tloopdynarraybase1.pp"
EXPECTED = (0, "LOOP-BASE:PASS\n", "")

POSITIVE = (
    "ScalarRead", "RecordRead", "ManagedRead", "PointerRead",
    "LocalRead", "ValueParamRead",
)
PRESSURE_CAP = "PressureCap"
NEGATIVE = (
    "SingleRead", "WrittenArray", "ReassignedArray", "CallClobber",
    "ByRefClobber", "NestedSplit", "ConstRefRead", "GlobalRead",
    "ThreadRead",
)
CHECKED_NEGATIVE = "CheckedRead"


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
        raise RuntimeError("cannot locate libgcc_s")
    return [f"-Fl{libgcc.parent}"]


def compile_one(compiler: Path, rtl: Path, level: str,
                strength: bool | None, outdir: Path) -> tuple[Path, str]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", level, "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-al", "-Aas",
        f"-Fu{rtl}", f"-FE{outdir}", f"-FU{outdir}",
    ] + link_args()
    if strength is not None:
        cmd.append("-OoSTRENGTH" if strength else "-OoNOSTRENGTH")
    cmd.append(str(SOURCE))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    suffix = ".exe" if os.name == "nt" else ""
    exe = outdir / ("tloopdynarraybase1" + suffix)
    asm = outdir / "tloopdynarraybase1.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(
            f"compile failed ({level}, strength={strength})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr


def routine(asm: str, name: str) -> str:
    needle = "_$$_" + name.upper()
    symbol = None
    for line in asm.splitlines():
        if line.startswith(".globl") and needle in line:
            symbol = line.split()[1]
            break
    if symbol is None:
        raise RuntimeError(f"assembly routine not found: {name}")
    start = asm.find("\n" + symbol + ":")
    end = asm.find("\n\t.size\t" + symbol, start)
    if start < 0 or end < 0:
        raise RuntimeError(f"assembly routine is incomplete: {name}")
    return asm[start:end]


def stack_descriptor_loads(body: str) -> int:
    return sum(bool(re.search(r"\bmovq\s+[-+]?\d*\(%rsp\)", line))
               for line in body.splitlines())


def normalized_routine(body: str) -> str:
    return re.sub(r"\.L([A-Za-z]+)\d+", r".L\1#", body)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_loop_base_"))
    try:
        builds: dict[str, tuple[Path, str]] = {}
        for tag, level, strength in (
            ("O0", "-O-", None),
            ("O2", "-O2", None),
            ("off", "-O3", False),
            ("on", "-O3", True),
            ("default", "-O3", None),
        ):
            try:
                builds[tag] = compile_one(
                    args.compiler, args.rtl, level, strength, tmp / tag)
                actual = run(builds[tag][0])
                if actual != EXPECTED:
                    failures.append(f"{tag}: runtime={actual!r}")
            except Exception as exc:
                failures.append(f"{tag}: {exc}")

        if all(tag in builds for tag in ("off", "on", "default")):
            off_asm = builds["off"][1]
            on_asm = builds["on"][1]
            default_asm = builds["default"][1]
            for proc_name in POSITIVE:
                try:
                    off_body = routine(off_asm, proc_name)
                    on_body = routine(on_asm, proc_name)
                    default_body = routine(default_asm, proc_name)
                    off_count = stack_descriptor_loads(off_body)
                    on_count = stack_descriptor_loads(on_body)
                    default_count = stack_descriptor_loads(default_body)
                    if off_count < 2 or on_count != off_count - 1:
                        failures.append(
                            f"{proc_name}: stack descriptor loads "
                            f"off={off_count}, on={on_count}, expected one "
                            f"retired load")
                    if default_count != on_count:
                        failures.append(
                            f"{proc_name}: default/on descriptor mismatch "
                            f"{default_count}/{on_count}")
                except Exception as exc:
                    failures.append(f"{proc_name}: {exc}")

            for proc_name in NEGATIVE:
                try:
                    off_body = normalized_routine(routine(off_asm, proc_name))
                    on_body = normalized_routine(routine(on_asm, proc_name))
                    default_body = normalized_routine(
                        routine(default_asm, proc_name))
                    if on_body != off_body:
                        failures.append(
                            f"{proc_name}: forbidden normalized ASM delta")
                    if default_body != on_body:
                        failures.append(
                            f"{proc_name}: default/on normalized ASM mismatch")
                except Exception as exc:
                    failures.append(f"{proc_name}: {exc}")

            try:
                proc_name = CHECKED_NEGATIVE
                off_count = stack_descriptor_loads(
                    routine(off_asm, proc_name))
                on_count = stack_descriptor_loads(
                    routine(on_asm, proc_name))
                default_count = stack_descriptor_loads(
                    routine(default_asm, proc_name))
                if off_count < 2 or on_count < off_count:
                    failures.append(
                        f"{proc_name}: checked descriptor loads unexpectedly "
                        f"reduced off={off_count}, on={on_count}")
                if default_count != on_count:
                    failures.append(
                        f"{proc_name}: default/on descriptor mismatch "
                        f"{default_count}/{on_count}")
            except Exception as exc:
                failures.append(f"{CHECKED_NEGATIVE}: {exc}")

            try:
                proc_name = PRESSURE_CAP
                off_body = routine(off_asm, proc_name)
                on_body = routine(on_asm, proc_name)
                default_body = routine(default_asm, proc_name)
                off_count = stack_descriptor_loads(off_body)
                on_count = stack_descriptor_loads(on_body)
                default_count = stack_descriptor_loads(default_body)
                if off_count < 6 or on_count != off_count - 2:
                    failures.append(
                        f"{proc_name}: descriptor mentions off={off_count}, "
                        f"on={on_count}, expected exactly two retired loads")
                if default_count != on_count:
                    failures.append(
                        f"{proc_name}: default/on descriptor mismatch "
                        f"{default_count}/{on_count}")
            except Exception as exc:
                failures.append(f"{PRESSURE_CAP}: {exc}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"LOOP BASE GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("LOOP BASE GATE: PASS (5 semantic builds, 7 positive and "
          "10 negative structural witnesses)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
