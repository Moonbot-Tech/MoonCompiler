#!/usr/bin/env python3
"""Fast Win64 semantic and assembly gate for SEH-aware regvars."""

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
    return ROOT / "compiler" / ("ppcx64.exe" if os.name == "nt" else "ppcx64")


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / "rtl" / "units" / target


def compile_one(compiler: Path, rtl: Path, source: Path, name: str,
                option: str, outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-O3", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}", str(source),
    ]
    if option:
        cmd.insert(4, option)
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


def scan_asm(asm: str) -> str:
    marker = re.search(
        r"(?mi)^P\$SEH_REGVAR_CODEGEN_\$\$_SCANWITHIRRELEVANTTRY.*:\s*$",
        asm)
    if not marker:
        raise RuntimeError("cannot find ScanWithIrrelevantTry assembly")
    tail = asm[marker.start():]
    end = re.search(r"(?mi)^\s*\.section\s+\.text", tail[1:])
    return tail if not end else tail[:end.start() + 1]


def main() -> int:
    if os.name != "nt":
        print("F4 SEH REGVAR: SKIP (Win64-only mechanism)")
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f4_"))
    failures: list[str] = []
    try:
        expected_semantic = (0, "SEHREGVAR:PASS\n", "")
        expected_codegen = (0, "SEHREGVAR-CODEGEN:522240\n", "")
        semantic_results = []
        codegen_builds = []
        for name, option in (
            ("off", "-OoNOSEHREGVAR"),
            ("on", "-OoSEHREGVAR"),
            ("default", ""),
        ):
            sem = compile_one(args.compiler, args.rtl, SEMANTIC,
                              "semantic-" + name, option, tmp)
            semantic_results.append(run(sem[0]))
            cg = compile_one(args.compiler, args.rtl, CODEGEN,
                             "codegen-" + name, option, tmp)
            codegen_builds.append(cg)
            if run(cg[0]) != expected_codegen:
                failures.append(f"codegen runtime differs for {name}")
        if any(result != expected_semantic for result in semantic_results):
            failures.append(f"semantic runtime differs: {semantic_results!r}")

        off = scan_asm(codegen_builds[0][1])
        on = scan_asm(codegen_builds[1][1])
        default = scan_asm(codegen_builds[2][1])
        off_stack = len(re.findall(r"-\d+\(%rbp\)", off))
        on_stack = len(re.findall(r"-\d+\(%rbp\)", on))
        default_stack = len(re.findall(r"-\d+\(%rbp\)", default))
        if off_stack < 10 or on_stack > 3 or on_stack >= off_stack:
            failures.append(
                f"hot-loop stack traffic not removed: {off_stack}->{on_stack}")
        if default_stack != on_stack:
            failures.append(
                f"O3 default differs from SEHREGVAR: {default_stack}!={on_stack}")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"F4 SEH REGVAR: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print(f"F4 SEH REGVAR: PASS (frame references {off_stack}->{on_stack})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
