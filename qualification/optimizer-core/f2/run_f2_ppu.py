#!/usr/bin/env python3
"""Prove F2 LICM settings and decisions survive generic PPU replay."""

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
UNIT = HERE / "licm_ppu_source.pas"
CONSUMER = HERE / "licm_ppu_consumer.dpr"
SUMMARY = re.compile(
    r"effect-observe-summary: proc=(\S+) mid=\S+ nodes=\d+ r=\S+ w=\S+"
    r" ie=\S+ temps=(\d+) reasons=\S+"
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


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=180)


def compile_unit(compiler: Path, rtl: Path, outdir: Path,
                 licm: bool) -> bytes:
    outdir.mkdir(parents=True)
    cmd = [
        str(compiler), "-Mdelphi", "-O2", "-n", "-B", "-Cn",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}", f"-FU{outdir}",
    ]
    if licm:
        cmd.append("-OoLICM")
    cmd.append(str(UNIT))
    proc = run(cmd, ROOT)
    ppu = outdir / "licm_ppu_source.ppu"
    if proc.returncode != 0 or not ppu.is_file():
        raise RuntimeError(
            f"unit compile failed (licm={licm})\n"
            f"{((proc.stdout or '') + (proc.stderr or ''))[-3000:]}")
    return ppu.read_bytes()


def compile_consumer(compiler: Path, rtl: Path, unitdir: Path,
                     outdir: Path, consumer_licm: bool) -> tuple[str, Path]:
    outdir.mkdir(parents=True)
    source_dir = outdir / "source"
    source_dir.mkdir()
    source = source_dir / CONSUMER.name
    shutil.copyfile(CONSUMER, source)
    cmd = [
        str(compiler), "-Mdelphi", "-O2", "-n", "-Ur",
        "-dMOONCOMPILER_VANILLA_RUNTIME", "-OoEFFECTOBSERVE", "-vd",
        f"-Fu{rtl}", f"-Fu{unitdir}", f"-FE{outdir}", f"-FU{outdir}",
    ] + link_args()
    if consumer_licm:
        cmd.append("-OoLICM")
    cmd.append(str(source))
    proc = run(cmd, source_dir)
    output = (proc.stdout or "") + (proc.stderr or "")
    exe = outdir / ("licm_ppu_consumer" + (".exe" if os.name == "nt" else ""))
    if proc.returncode != 0 or not exe.is_file():
        raise RuntimeError(
            f"consumer compile failed (licm={consumer_licm})\n{output[-3000:]}")
    return output, exe


def run_consumer(exe: Path) -> None:
    proc = subprocess.run(
        [str(exe)], capture_output=True, text=True, timeout=60)
    if (proc.returncode, proc.stdout, proc.stderr) != (
            0, "F2-PPU:117152\n", ""):
        raise RuntimeError(
            "consumer semantic digest differs: "
            f"{(proc.returncode, proc.stdout, proc.stderr)!r}")


def run_temps(output: str) -> list[int]:
    return [int(temps) for proc, temps in SUMMARY.findall(output)
            if proc.casefold() == "run"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()
    compiler = args.compiler.resolve()
    rtl = args.rtl.resolve()
    tmp = Path(tempfile.mkdtemp(prefix="optimizer_f2_ppu_"))
    try:
        blobs: dict[str, bytes] = {}
        unit_dirs: dict[bool, Path] = {}
        for licm in (False, True):
            for repeat in (1, 2):
                label = f"{'on' if licm else 'off'}{repeat}"
                unitdir = tmp / f"unit_{label}"
                blobs[label] = compile_unit(
                    compiler, rtl, unitdir, licm)
                if repeat == 1:
                    unit_dirs[licm] = unitdir
        if blobs["off1"] != blobs["off2"] or blobs["on1"] != blobs["on2"]:
            raise RuntimeError("identical cold generic PPU builds differ")
        # Generic code generation belongs to the current consumer build.  A
        # PPU recorded with LICM off must not suppress an enabled consumer,
        # and a PPU recorded with LICM on must not force a disabled consumer.
        # Exercise all four combinations so producer provenance cannot be
        # confused with the process-local codegen decision.
        for producer_licm in (False, True):
            for consumer_licm in (False, True):
                text, exe = compile_consumer(
                    compiler, rtl, unit_dirs[producer_licm],
                    tmp / (f"producer_{int(producer_licm)}_"
                           f"consumer_{int(consumer_licm)}"),
                    consumer_licm)
                run_consumer(exe)
                temps = run_temps(text)
                if len(temps) != 1:
                    raise RuntimeError(
                        "generic Run specialization summary is missing or "
                        f"ambiguous: producer={producer_licm}, "
                        f"consumer={consumer_licm}, temps={temps!r}")
                if consumer_licm and temps[0] <= 0:
                    raise RuntimeError(
                        "consumer LICM was suppressed by generic PPU: "
                        f"producer={producer_licm}, temps={temps[0]}")
                if not consumer_licm and temps[0] != 0:
                    raise RuntimeError(
                        "generic PPU forced LICM into a disabled consumer: "
                        f"producer={producer_licm}, temps={temps[0]}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("F2 PPU: PASS (cold deterministic, consumer owns LICM, runtime equal)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
