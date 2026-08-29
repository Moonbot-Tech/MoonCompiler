#!/usr/bin/env python3
"""Focused semantic and assembly gate for x86-64 hot-code alignment."""

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
SOURCE = HERE / "code_alignment_semantic.dpr"
EXPECTED = (0, "CODEALIGN:PASS:677800\n", "")


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


def compile_one(compiler: Path, rtl: Path, name: str,
                options: list[str], outdir: Path) -> tuple[Path, str]:
    target = outdir / name
    target.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-n", "-al", "-Aas",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
        f"-FE{target}", f"-FU{target}", f"-o{name}",
    ] + link_args() + options + [str(SOURCE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = target / name
    if not exe.is_file():
        exe = target / (name + ".exe")
    asm = target / "code_alignment_semantic.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed ({name})\n{output[-3000:]}")
    return exe, asm.read_text(encoding="utf-8", errors="replace")


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout, proc.stderr


def text_alignment_counts(asm: str, alignment: int) -> dict[str, int]:
    result: dict[str, int] = {}
    section = ""
    align = re.compile(
        rf"^\s*(?:\.balign\s+{alignment}(?:\s*,.*)?|"
        rf"\.p2align\s+{alignment.bit_length() - 1}(?:\s*,.*)?)\s*$",
        re.IGNORECASE,
    )
    for line in asm.splitlines():
        match = re.match(r"^\s*\.section\s+([^,\s]+)", line,
                         re.IGNORECASE)
        if match:
            section = match.group(1).lower()
            if section.startswith(".text"):
                result.setdefault(section, 0)
            continue
        if section.startswith(".text") and align.match(line):
            result[section] += 1
    return result


def routine_alignment_count(counts: dict[str, int], marker: str) -> int:
    matches = [count for section, count in counts.items() if marker in section]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one text section containing {marker!r}, got {len(matches)}")
    return matches[0]


def contract_failures(name: str, counts: dict[str, int]) -> list[str]:
    result: list[str] = []
    if routine_alignment_count(counts, "hotleaf") < 1:
        result.append(f"{name}: hot leaf procedure entry is not aligned")
    if routine_alignment_count(counts, "naturalloop") < 2:
        result.append(f"{name}: natural loop header is not aligned")
    if routine_alignment_count(counts, "explicitlabelloop") < 2:
        result.append(f"{name}: explicit Pascal label is not aligned")
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_code_alignment_"))
    try:
        builds = {
            "o2": ["-O2"],
            "o2_on": ["-O2", "-OoCODEALIGN"],
            "o3": ["-O3"],
            "o3_off": ["-O3", "-OoNOCODEALIGN"],
            "o3_wide": ["-O3", "-dCODEALIGN_64"],
            "size": ["-O3", "-Os", "-OoCODEALIGN"],
        }
        results: dict[str, tuple[Path, str]] = {}
        for name, options in builds.items():
            try:
                results[name] = compile_one(
                    args.compiler, args.rtl, name, options, tmp)
                actual = run(results[name][0])
                if actual != EXPECTED:
                    failures.append(f"{name}: runtime {actual!r}")
            except Exception as exc:
                failures.append(f"{name}: {exc}")

        if len(results) == len(builds):
            counts = {name: text_alignment_counts(asm, 32)
                      for name, (_, asm) in results.items()}
            for name in ("o2_on", "o3"):
                try:
                    failures.extend(contract_failures(name, counts[name]))
                except Exception as exc:
                    failures.append(f"{name}: {exc}")
            wide = text_alignment_counts(results["o3_wide"][1], 64)
            try:
                for failure in contract_failures("o3_wide", wide):
                    failures.append(failure.replace(
                        "is not aligned", "lost the 64-byte override"))
            except Exception as exc:
                failures.append(f"o3_wide: {exc}")
            for name in ("o2", "o3_off", "size"):
                leaked = sum(counts[name].values())
                if leaked != 0:
                    failures.append(
                        f"{name}: CODEALIGN leaked into disabled/size build "
                        f"({leaked} text directives)")
            baseline_size = results["o3_off"][0].stat().st_size
            aligned_size = results["o3"][0].stat().st_size
            if aligned_size > baseline_size * 1.10:
                failures.append(
                    "o3: focused executable grew by more than 10% "
                    f"({baseline_size} -> {aligned_size})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"CODE ALIGNMENT GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("CODE ALIGNMENT GATE: PASS "
          "(procedure entries, natural loops, explicit labels, opt-out, size)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
