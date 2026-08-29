#!/usr/bin/env python3
"""Off/on identity gate of the effect-model observe mode (phase F1).

Observe mode has no right to change the generated code by a single byte.
Every identity workload is compiled twice with one toolchain - with and
without -OoEFFECTOBSERVE -vd - at -O-, -O2 and -O3; the gate then proves:

  1. the raw bytes of every PE section of the two executables are identical
     (post-assembler code and data, headers with their link timestamp are
     outside the comparison);
  2. both executables run and produce identical stdout and exit code
     (runtime semantic digest);
  3. the PPU of a generic-bearing UNIT is byte-identical off/on: a generic
     declaration serializes a settings snapshot into the PPU, and the
     diagnostic flag is masked out of it (review F-02).  An off/off repeat
     first proves the PPU is deterministic at all, so the off/on verdict
     cannot be noise;
  4. a consumer compiled with observe enabled keeps observing while it
     specializes a generic from a PPU produced with observe disabled.  The
     replayed source settings must not disable a process-local diagnostic.

Usage:
    run_effect_identity.py [--compiler PATH] [--rtl PATH]
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import subprocess
import sys
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
IDENTITY = HERE / "identity"
LEVELS = ("-O-", "-O2", "-O3")


def default_compiler() -> Path:
    return ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64" / "ppcx64.exe"


def default_rtl() -> Path:
    return ROOT / ".moonbot" / "toolchain" / "units" / "x86_64-win64" / "rtl"


def pe_sections(path: Path) -> list[tuple[str, bytes]]:
    """(name, raw data) of every section of a PE image."""
    data = path.read_bytes()
    (pe_off,) = struct.unpack_from("<I", data, 0x3C)
    if data[pe_off:pe_off + 4] != b"PE\0\0":
        raise SystemExit(f"{path}: not a PE image")
    (nsec,) = struct.unpack_from("<H", data, pe_off + 6)
    (opt_size,) = struct.unpack_from("<H", data, pe_off + 20)
    sec_off = pe_off + 24 + opt_size
    out = []
    for i in range(nsec):
        off = sec_off + i * 40
        name = data[off:off + 8].rstrip(b"\0").decode("ascii", "replace")
        raw_size, raw_ptr = struct.unpack_from("<II", data, off + 16)
        out.append((name, data[raw_ptr:raw_ptr + raw_size]))
    return out


def compile_program(compiler: Path, rtl: Path, src: Path, outdir: Path,
                    level: str, observe: bool) -> tuple[int, str, Path]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-Mdelphi", level, "-n",
           "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
           f"-FE{outdir}", f"-FU{outdir}"]
    if observe:
        cmd += ["-OoEFFECTOBSERVE", "-vd"]
    cmd.append(str(src))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or ""), \
        outdir / (src.stem + ".exe")


def run_exe(path: Path) -> tuple[int, str]:
    proc = subprocess.run([str(path)], capture_output=True, text=True,
                          timeout=60)
    return proc.returncode, proc.stdout


def compile_unit(compiler: Path, rtl: Path, src: Path, outdir: Path,
                 observe: bool) -> tuple[int, str, Path]:
    outdir.mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-Mdelphi", "-O2", "-n",
           "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
           f"-FE{outdir}", f"-FU{outdir}"]
    if observe:
        # deliberately WITHOUT -vd: the scanner has always serialized
        # `verbosity` into the generic settings token (an upstream fact
        # predating F1), so any -v* option changes the PPU of a
        # generic-bearing unit on its own.  This stand isolates the
        # effect-observe switch itself.
        cmd += ["-OoEFFECTOBSERVE"]
    cmd.append(str(src))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or ""), \
        outdir / (src.stem + ".ppu")


def check_ppu_identity(compiler: Path, rtl: Path, tmp: Path,
                       failures: list) -> int:
    """Compile the generic-bearing unit off/off/on; the off/off pair proves
    determinism, the off/on pair proves the flag leaves the PPU alone."""
    src = IDENTITY / "id_generic.pas"
    blobs = {}
    for label, observe in (("off1", False), ("off2", False), ("on", True)):
        code, out, ppu = compile_unit(compiler, rtl, src,
                                      tmp / f"ppu_{label}", observe)
        if code != 0 or not ppu.exists():
            failures.append(f"{src.name} [{label}]: compile failed\n{out[-1500:]}")
            return 0
        blobs[label] = ppu.read_bytes()
    if blobs["off1"] != blobs["off2"]:
        failures.append(f"{src.name}: PPU not deterministic between two "
                        f"identical off-compiles - the off/on verdict would be noise")
        return 0
    if blobs["off1"] != blobs["on"]:
        failures.append(f"{src.name}: PPU differs with the observe flag on "
                        f"({len(blobs['off1'])} vs {len(blobs['on'])} bytes)")
        return 0
    return 1


def check_ppu_replay_observe(compiler: Path, rtl: Path, tmp: Path,
                             failures: list) -> int:
    """Build the generic unit with observation OFF, then consume only its
    PPU with observation ON.  This is deliberately distinct from compiling
    the unit source and consumer together: ST_LOADSETTINGS used to replace
    the process flag and -vd with the recorded off-state, silently producing
    no summaries for either the specialization or the rest of the program."""
    unit_src = IDENTITY / "id_generic.pas"
    unit_dir = tmp / "replay_unit"
    code, out, ppu = compile_unit(compiler, rtl, unit_src, unit_dir, False)
    if code != 0 or not ppu.exists():
        failures.append(f"{unit_src.name} [replay source]: compile failed\n"
                        f"{out[-1500:]}")
        return 0

    source_dir = tmp / "replay_source"
    source_dir.mkdir(parents=True, exist_ok=True)
    source = source_dir / "id_generic_replay.pas"
    shutil.copyfile(IDENTITY / source.name, source)
    exes = {}
    observed_output = ""
    for observe in (False, True):
        outdir = tmp / f"replay_consumer_{int(observe)}"
        outdir.mkdir(parents=True, exist_ok=True)
        cmd = [str(compiler), "-Mdelphi", "-O2", "-n", "-Ur",
               "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{rtl}",
               f"-Fu{unit_dir}", f"-FE{outdir}", f"-FU{outdir}"]
        if observe:
            cmd += ["-OoEFFECTOBSERVE", "-vd"]
        cmd.append(str(source))
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        output = (proc.stdout or "") + (proc.stderr or "")
        exe = outdir / "id_generic_replay.exe"
        if proc.returncode != 0 or not exe.exists():
            failures.append("id_generic_replay.pas "
                            f"[observe={observe}]: compile failed\n{output[-1500:]}")
            return 0
        exes[observe] = exe
        if observe:
            observed_output = output

    summaries = observed_output.count("effect-observe-summary:")
    if summaries < 2:
        failures.append("id_generic_replay.pas: observe was lost while "
                        "replaying an off-built generic PPU "
                        f"({summaries} summaries, expected at least 2)")
        return 0

    off_secs = pe_sections(exes[False])
    on_secs = pe_sections(exes[True])
    if off_secs != on_secs:
        failures.append("id_generic_replay.pas: PE sections differ with "
                        "observe off/on across generic PPU replay")
        return 0
    off_run = run_exe(exes[False])
    on_run = run_exe(exes[True])
    if off_run != (0, "42\n") or on_run != off_run:
        failures.append("id_generic_replay.pas: runtime digest differs or "
                        f"is invalid: off={off_run!r} on={on_run!r}")
        return 0
    return len(off_secs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    args = ap.parse_args()

    if not args.compiler.exists():
        raise SystemExit(f"compiler not found: {args.compiler}")
    programs = sorted(IDENTITY.glob("*.dpr"))
    if not programs:
        raise SystemExit("no identity programs found")

    failures = []
    compared = 0
    ppu_checked = 0
    ppu_replay_checked = 0
    tmp = Path(tempfile.mkdtemp(prefix="effect_identity_"))
    try:
        ppu_checked = check_ppu_identity(args.compiler, args.rtl, tmp, failures)
        ppu_replay_checked = check_ppu_replay_observe(
            args.compiler, args.rtl, tmp, failures)
        compared += ppu_replay_checked
        for src in programs:
            for level in LEVELS:
                tag = f"{src.name} [{level}]"
                exes = {}
                for observe in (False, True):
                    sub = tmp / f"{src.stem}_{level.strip('-') or 'Om'}_{int(observe)}"
                    code, out, exe = compile_program(
                        args.compiler, args.rtl, src, sub, level, observe)
                    if code != 0 or not exe.exists():
                        failures.append(f"{tag} observe={observe}: compile failed\n{out[-1500:]}")
                        break
                    exes[observe] = exe
                if len(exes) != 2:
                    continue
                off_secs = pe_sections(exes[False])
                on_secs = pe_sections(exes[True])
                if [n for n, _ in off_secs] != [n for n, _ in on_secs]:
                    failures.append(f"{tag}: section lists differ: "
                                    f"{[n for n, _ in off_secs]} vs {[n for n, _ in on_secs]}")
                else:
                    for (name, off_data), (_, on_data) in zip(off_secs, on_secs):
                        compared += 1
                        if off_data != on_data:
                            failures.append(
                                f"{tag}: section {name} differs "
                                f"(off {hashlib.sha256(off_data).hexdigest()[:16]} "
                                f"vs on {hashlib.sha256(on_data).hexdigest()[:16]})")
                rc_off, out_off = run_exe(exes[False])
                rc_on, out_on = run_exe(exes[True])
                if (rc_off, out_off) != (rc_on, out_on):
                    failures.append(f"{tag}: runtime digest differs: "
                                    f"({rc_off!r},{out_off!r}) vs ({rc_on!r},{out_on!r})")
                elif not out_off.strip():
                    failures.append(f"{tag}: workload produced no output")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"EFFECT IDENTITY: FAIL ({len(failures)} problems)")
        for f in failures:
            print(" *", f)
        return 1
    print(f"EFFECT IDENTITY: PASS ({len(programs)} programs x {len(LEVELS)} levels, "
          f"{compared} sections byte-identical, runtime digests equal, "
          f"{ppu_checked} generic PPU byte-identical off/on, "
          f"generic replay observe preserved)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
