#!/usr/bin/env python3
"""Compile and run the deterministic mORMot TFTP ownership regression."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SUITE = Path(__file__).resolve().parents[1]
REPO = SUITE.parents[1]
SOURCE = SUITE / "tests" / "mormot" / "tftp_shutdown_lifetime_semantic.dpr"
MM = REPO / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
MODES = {
    "debug": ["-O-", "-gl", "-gw3", "-Ci", "-Co-", "-Cr-", "-Ct-", "-Sa"],
    "o2": ["-O2", "-gl", "-gw3", "-Ci", "-Co-", "-Cr-", "-Ct-", "-Sa-"],
    "o3": ["-O3", "-gl", "-gw3", "-Ci", "-Co-", "-Cr-", "-Ct-", "-Sa-"],
}
LANGUAGE = [
    "-dMOONCOMPILER_UNICODE_DEFAULT",
    "-Mdelphi",
    "-Municodestrings",
    "-MduplicateLocals",
    "-Madvancedrecords",
    "-Marrayoperators",
    "-Munderscoreisseparator",
    "-Mfunctionreferences",
    "-Manonymousfunctions",
    "-Minlinevars",
    "-Mimplicitgenerics",
    "-Mautoderef",
]


def toolchain() -> tuple[Path, Path, list[str], str]:
    if os.name == "nt":
        base = REPO / ".moonbot" / "toolchain" / "bin" / "x86_64-win64"
        return base / "fpc.exe", base / "fpc.cfg", ["-Px86_64", "-Twin64"], ".exe"
    if sys.platform == "linux" and os.uname().machine == "x86_64":
        base = REPO / ".moonbot" / "toolchain"
        return (
            base / "bin" / "fpc",
            base / "etc" / "fpc.cfg",
            ["-Px86_64", "-Tlinux", "-dPOSIX"],
            "",
        )
    raise RuntimeError("TFTP qualification supports only Win64 and Linux x86-64")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mormot",
        type=Path,
        default=REPO / "qualification" / "vendor" / "mormot-product",
    )
    parser.add_argument("--modes", nargs="+", choices=tuple(MODES), default=list(MODES))
    args = parser.parse_args()

    mormot = args.mormot.resolve()
    src = mormot / "src"
    static = mormot / "static" / (
        "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    )
    compiler, config, target, suffix = toolchain()
    for required in (compiler, config, MM, SOURCE, src, static):
        if not required.exists():
            raise RuntimeError(f"required input is missing: {required}")

    unit_dirs = sorted({path.parent for path in src.rglob("*.pas")})
    state = REPO / ".moonbot"
    state.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="tftp-shutdown-", dir=state))
    try:
        for mode in args.modes:
            output = work / mode
            output.mkdir()
            command = [
                str(compiler),
                "-n",
                f"@{config}",
                *LANGUAGE,
                *target,
                "-B",
                "-dMOONBOT_MM_PROFILE_REQUIRED",
                "-dFPCMM_BOOSTER",
                "-dFPCMM_MOONSHARD",
                f"--pinned-unit=mormot.core.fpcx64mm={MM}",
                "--required-first-unit=mormot.core.fpcx64mm,cthreads"
                if os.name != "nt"
                else "--required-first-unit=mormot.core.fpcx64mm",
                f"-Fi{src}",
                *(f"-Fu{path}" for path in unit_dirs),
                f"-Fl{static}",
                f"-FU{output}",
                f"-FE{output}",
                *MODES[mode],
                str(SOURCE),
            ]
            compiled = subprocess.run(
                command,
                # mORMot's {$L ../static/...} directives are resolved from the
                # compiler working directory, not from the including unit.
                cwd=src,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=180,
                check=False,
            )
            if compiled.returncode != 0:
                print(compiled.stdout, file=sys.stderr)
                raise RuntimeError(f"TFTP compile failed in {mode}")
            executable = output / f"{SOURCE.stem}{suffix}"
            run = subprocess.run(
                [str(executable)],
                cwd=output,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=30,
                check=False,
            )
            if run.returncode != 0 or "TFTP_SHUTDOWN_LIFETIME_OK" not in run.stdout:
                print(f"runtime exit code: {run.returncode}", file=sys.stderr)
                print(run.stdout, file=sys.stderr)
                raise RuntimeError(f"TFTP runtime oracle failed in {mode}")
            print(f"PASS tftp_shutdown_lifetime_semantic {mode}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
