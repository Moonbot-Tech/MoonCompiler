#!/usr/bin/env python3
"""Fast native x86-64 semantic and assembly gate for EH-aware regvars."""

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
SEMANTIC = HERE / "seh_regvar_semantic.dpr"
CODEGEN = HERE / "seh_regvar_codegen.dpr"


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / ".moonbot/toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / ".moonbot/toolchain/bin/ppcx64"


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / "rtl" / "units" / target


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


def compile_one(compiler: Path, rtl: Path, source: Path, name: str,
                option: str, compiler_options: list[str],
                outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-O3", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}",
    ]
    if option:
        cmd.insert(4, option)
    cmd.extend(link_args())
    cmd.extend(compiler_options)
    cmd.append(str(source))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = target / (source.stem + (".exe" if os.name == "nt" else ""))
    asm = target / (source.stem + ".s")
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({name})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def routine_asm(asm: str, name: str) -> str:
    marker = re.search(
        rf"(?mi)^P\$SEH_REGVAR_CODEGEN_\$\$_{name}.*:\s*$",
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

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f4_"))
    failures: list[str] = []
    try:
        expected_semantic = (0, "SEHREGVAR:PASS\n", "")
        expected_codegen = (0, "SEHREGVAR-CODEGEN:537407\n", "")
        semantic_results = []
        codegen_builds = []
        for name, option in (
            ("off", "-OoNOSEHREGVAR"),
            ("on", "-OoSEHREGVAR"),
            ("default", ""),
        ):
            sem = compile_one(args.compiler, args.rtl, SEMANTIC,
                              "semantic-" + name, option,
                              args.compiler_option, tmp)
            semantic_results.append(run(sem[0]))
            cg = compile_one(args.compiler, args.rtl, CODEGEN,
                             "codegen-" + name, option,
                             args.compiler_option, tmp)
            codegen_builds.append(cg)
            if run(cg[0]) != expected_codegen:
                failures.append(f"codegen runtime differs for {name}")
        if any(result != expected_semantic for result in semantic_results):
            failures.append(f"semantic runtime differs: {semantic_results!r}")

        stack_ref = re.compile(r"(?:-\d+\(%rbp\)|-?\d*\(%rsp\))")
        off = routine_asm(codegen_builds[0][1], "SCANWITHIRRELEVANTTRY")
        on = routine_asm(codegen_builds[1][1], "SCANWITHIRRELEVANTTRY")
        default = routine_asm(
            codegen_builds[2][1], "SCANWITHIRRELEVANTTRY")
        off_stack = len(stack_ref.findall(off))
        on_stack = len(stack_ref.findall(on))
        default_stack = len(stack_ref.findall(default))
        if off_stack < 8 or on_stack > 4 or on_stack >= off_stack:
            failures.append(
                f"hot-loop stack traffic not removed: {off_stack}->{on_stack}")
        if default_stack != on_stack:
            failures.append(
                f"O3 default differs from SEHREGVAR: {default_stack}!={on_stack}")
        off_cleanup = routine_asm(
            codegen_builds[0][1], "SCANGENERATEDCLEANUP")
        on_cleanup = routine_asm(
            codegen_builds[1][1], "SCANGENERATEDCLEANUP")
        default_cleanup = routine_asm(
            codegen_builds[2][1], "SCANGENERATEDCLEANUP")
        off_cleanup_stack = len(stack_ref.findall(off_cleanup))
        on_cleanup_stack = len(stack_ref.findall(on_cleanup))
        default_cleanup_stack = len(stack_ref.findall(default_cleanup))
        cleanup_vars = ("Value", "Sum")
        off_cleanup_registers = {
            name for name in cleanup_vars
            if re.search(rf"(?m)^# Var {name} located in register ",
                         off_cleanup)
        }
        on_cleanup_registers = {
            name for name in cleanup_vars
            if re.search(rf"(?m)^# Var {name} located in register ",
                         on_cleanup)
        }
        default_cleanup_registers = {
            name for name in cleanup_vars
            if re.search(rf"(?m)^# Var {name} located in register ",
                         default_cleanup)
        }
        if off_cleanup_stack < 8 or \
                on_cleanup_stack > off_cleanup_stack:
            failures.append(
                "generated-cleanup loop stack traffic grew: "
                f"{off_cleanup_stack}->{on_cleanup_stack}")
        if off_cleanup_registers or \
                on_cleanup_registers != set(cleanup_vars):
            failures.append(
                "generated-cleanup induction/reduction allocation differs: "
                f"off={sorted(off_cleanup_registers)!r} "
                f"on={sorted(on_cleanup_registers)!r}")
        if default_cleanup_stack != on_cleanup_stack:
            failures.append(
                "O3 default generated cleanup differs from SEHREGVAR: "
                f"{default_cleanup_stack}!={on_cleanup_stack}")
        if default_cleanup_registers != on_cleanup_registers:
            failures.append(
                "O3 default generated-cleanup registers differ from "
                f"SEHREGVAR: {sorted(default_cleanup_registers)!r}!="
                f"{sorted(on_cleanup_registers)!r}")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"F4 SEH REGVAR: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("F4 SEH REGVAR: PASS "
          f"(explicit frame references {off_stack}->{on_stack}, "
          f"generated cleanup {off_cleanup_stack}->{on_cleanup_stack})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
