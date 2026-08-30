#!/usr/bin/env python3
"""Compile-time scaling and code-identity gate for ADDRESSGVN facts."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


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


def write_source(path: Path, count: int) -> None:
    body = "\n".join(
        f"  Sum := Sum + Data[(Seed + {i}) and 1023].A + "
        f"Data[(Seed + {i}) and 1023].B;"
        for i in range(count)
    )
    path.write_text(
        "program addressgvn_scale;\n"
        "{$mode delphi}\n{$R-}{$Q-}\n"
        "type TItem = record A, B: QWord; end;\n"
        "type TItems = array[0..1023] of TItem;\n"
        "var Data: TItems;\n"
        "function Work(Seed: LongInt): QWord; noinline;\n"
        "var Sum: QWord;\n"
        "begin\n  Sum := 0;\n" + body +
        "\n  Result := Sum;\nend;\n"
        "begin\n  if Work(1) <> 0 then Halt(1);\nend.\n",
        encoding="utf-8",
    )


def compile_one(compiler: Path, rtl: Path, source: Path, mode: str,
                outdir: Path) -> tuple[float, str]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(compiler), "-Mdelphi", "-O3", f"-Oo{mode}", "-n",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-al", "-Aas",
        f"-Fu{rtl}", f"-FE{outdir}", f"-FU{outdir}",
    ] + link_args() + [str(source)]
    started = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    elapsed = time.perf_counter() - started
    asm = outdir / "addressgvn_scale.s"
    if proc.returncode != 0 or not asm.is_file():
        output = (proc.stdout or "") + (proc.stderr or "")
        raise RuntimeError(f"compile failed ({mode})\n{output[-3000:]}")
    digest = hashlib.sha256(asm.read_bytes()).hexdigest()
    return elapsed, digest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    failures: list[str] = []
    timings: dict[tuple[int, str], float] = {}
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f3_scale_"))
    try:
        for count in (1000, 2000):
            source = tmp / f"source-{count}" / "addressgvn_scale.pas"
            source.parent.mkdir(parents=True)
            write_source(source, count)
            digests: dict[str, str] = {}
            for mode in ("NOADDRESSGVN", "ADDRESSGVN"):
                elapsed, digest = compile_one(
                    args.compiler, args.rtl, source, mode,
                    tmp / f"out-{count}-{mode}")
                timings[count, mode] = elapsed
                digests[mode] = digest
            if digests["NOADDRESSGVN"] != digests["ADDRESSGVN"]:
                failures.append(f"{count}: ADDRESSGVN changed generated assembly")

        for count in (1000, 2000):
            plain = timings[count, "NOADDRESSGVN"]
            address = timings[count, "ADDRESSGVN"]
            if address > plain * 3.0 + 0.5:
                failures.append(
                    f"{count}: ADDRESSGVN compile time {address:.3f}s vs "
                    f"plain {plain:.3f}s")
        growth = (timings[2000, "ADDRESSGVN"] /
                  timings[1000, "ADDRESSGVN"])
        if growth > 3.5:
            failures.append(f"ADDRESSGVN 1000->2000 growth is {growth:.2f}x")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for count in (1000, 2000):
        if (count, "NOADDRESSGVN") in timings:
            print(f"{count}: no={timings[count, 'NOADDRESSGVN']:.3f}s "
                  f"address={timings[count, 'ADDRESSGVN']:.3f}s")
    if failures:
        print(f"F3a SCALING: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("F3a SCALING: PASS (linear machine facts, code identity)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
