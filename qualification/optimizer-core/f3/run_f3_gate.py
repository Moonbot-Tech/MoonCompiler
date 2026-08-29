#!/usr/bin/env python3
"""Read-only USE/DEF and EBB reaching-definition gate for phase F3a."""

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
SOURCE = HERE / "flow_semantic.dpr"
SUMMARY = re.compile(
    r"m-facts-summary: proc=(\S+) blocks=(\d+) insns=(\d+) use=(\d+) "
    r"def=(\d+) usedef=(\d+) reaching=(\d+)"
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


def compile_one(compiler: Path, rtl: Path, diagnostic: bool,
                outdir: Path) -> tuple[str, Path, str]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-O3", "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-al", "-Aas",
        f"-Fu{rtl}", f"-FE{outdir}", f"-FU{outdir}",
    ] + link_args()
    if diagnostic:
        cmd.append("-dOPTCORE_MFACTS")
    cmd.append(str(SOURCE))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = outdir / ("flow_semantic" + (".exe" if os.name == "nt" else ""))
    asm = outdir / "flow_semantic.s"
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"compile failed (diagnostic={diagnostic})\n"
                           f"{output[-3000:]}")
    return output, exe, asm.read_text(encoding="utf-8", errors="replace")


def compile_stale(compiler: Path, rtl: Path, outdir: Path) -> str:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-O3", "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-dOPTCORE_MFACTS",
        "-dOPTCORE_MFACTS_STALE", f"-Fu{rtl}", f"-FE{outdir}",
        f"-FU{outdir}",
    ] + link_args() + [str(SOURCE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode == 0:
        raise RuntimeError("stale-generation sabotage unexpectedly compiled")
    return output


def run(exe: Path) -> tuple[int, str, str]:
    proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout, proc.stderr


def parse(output: str) -> dict[str, tuple[int, ...]]:
    result: dict[str, tuple[int, ...]] = {}
    for name, *values in SUMMARY.findall(output):
        result[name] = tuple(int(value) for value in values)
    return result


def find_routine(rows: dict[str, tuple[int, ...]], short: str) -> tuple[int, ...]:
    matches = [value for name, value in rows.items()
               if f"_$$_{short.upper()}" in name]
    if len(matches) != 1:
        raise RuntimeError(f"expected one {short} summary, got {len(matches)}")
    return matches[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f3_"))
    try:
        plain_text, plain_exe, plain_asm = compile_one(
            args.compiler, args.rtl, False, tmp / "plain")
        diag1_text, diag1_exe, diag1_asm = compile_one(
            args.compiler, args.rtl, True, tmp / "diag1")
        diag2_text, diag2_exe, diag2_asm = compile_one(
            args.compiler, args.rtl, True, tmp / "diag2")
        expected = (0, "F3-MFACTS:PASS\n", "")
        for label, exe in (("plain", plain_exe), ("diag1", diag1_exe),
                           ("diag2", diag2_exe)):
            actual = run(exe)
            if actual != expected:
                failures.append(f"{label}: runtime={actual!r}")
        if plain_text.find("m-facts-summary:") >= 0:
            failures.append("plain compile unexpectedly emitted M facts")
        if plain_asm != diag1_asm or diag1_asm != diag2_asm:
            failures.append("read-only diagnostics changed generated assembly")
        rows1 = parse(diag1_text)
        rows2 = parse(diag2_text)
        if rows1 != rows2:
            failures.append("M facts are not deterministic")
        for name in ("Mix", "DividePair", "AcrossCall"):
            blocks, insns, uses, defs, usedefs, reaching = find_routine(
                rows1, name)
            if min(blocks, insns, uses, defs) <= 0:
                failures.append(f"{name}: incomplete facts "
                                f"{(blocks, insns, uses, defs)!r}")
            if reaching <= 0:
                failures.append(f"{name}: no EBB-local reaching use")
        _, _, _, _, div_usedefs, _ = find_routine(rows1, "DividePair")
        if div_usedefs <= 0:
            failures.append("DividePair: implicit/two-address operands not decoded")
        stale_text = compile_stale(args.compiler, args.rtl, tmp / "stale")
        if ("stale x86 machine facts" not in stale_text or
                "2026082901" not in stale_text):
            failures.append("stale-generation sabotage missed the guard")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"F3a GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("F3a GATE: PASS (read-only code identity, deterministic x86-64 "
          "USE/DEF and EBB reaching definitions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
