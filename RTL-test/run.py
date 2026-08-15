#!/usr/bin/env python3
"""Compile and execute the self-contained RTL semantic matrix."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEMANTIC = ROOT / "RTL-test" / "semantic"
MM = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
MARKER = re.compile(r"WriteLn\(\s*'([A-Z0-9_]*(?:PASS|OK))'")
FORBIDDEN_O3_ASM = {
    "collections_codegen": ("MOVENEXT", "GETCURRENT"),
}
MODES = {
    "debug": ["-O-", "-gl", "-gw3", "-Criot", "-Sa"],
    "o2": ["-O2", "-gl", "-gw3"],
    "o3": ["-O3", "-gl", "-gw3"],
}
LANGUAGE = [
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
NAMESPACES = [
    "-FNSystem",
    "-UaSystem.SysUtils=SysUtils",
    "-UaSystem.Variants=Variants",
    "-UaSystem.Classes=Classes",
    "-UaSystem.DateUtils=DateUtils",
    "-UaSystem.Math=Math",
    "-UaSystem.Types=Types",
    "-UaSystem.TypInfo=TypInfo",
    "-UaSystem.Rtti=Rtti",
    "-UaSystem.StrUtils=StrUtils",
    "-UaSystem.Character=Character",
    "-UaSystem.SyncObjs=SyncObjs",
    "-UaSystem.Generics.Defaults=Generics.Defaults",
    "-UaSystem.Generics.Collections=Generics.Collections",
    "-UaSystem.IniFiles=IniFiles",
    "-UaSystem.SysConst=SysConst",
    "-UaSystem.RTLConsts=RTLConsts",
]


def toolchain() -> tuple[Path, Path, list[str], str]:
    if os.name == "nt":
        base = ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64"
        return base / "fpc.exe", base / "fpc.cfg", ["-Px86_64", "-Twin64"], ".exe"
    if sys.platform == "linux" and os.uname().machine == "x86_64":
        base = ROOT / ".moonbot" / "toolchain"
        return (
            base / "bin" / "fpc",
            base / "etc" / "fpc.cfg",
            ["-Px86_64", "-Tlinux", "-dPOSIX"],
            "",
        )
    raise RuntimeError("RTL qualification supports only Win64 and Linux x86-64")


def execute(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--modes",
        nargs="+",
        choices=tuple(MODES),
        default=list(MODES),
    )
    parser.add_argument("--only", help="regular expression for source stem")
    args = parser.parse_args()

    compiler, config, target, executable_suffix = toolchain()
    for required in (compiler, config, MM):
        if not required.is_file():
            raise RuntimeError(f"required product file is missing: {required}")

    sources = sorted(SEMANTIC.glob("*.dpr"))
    if args.only:
        selected = re.compile(args.only)
        sources = [source for source in sources if selected.search(source.stem)]
    if not sources:
        raise RuntimeError("no RTL semantic sources selected")

    state = ROOT / ".moonbot"
    state.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="rtl-test-", dir=state))
    passed = 0
    try:
        for source in sources:
            markers = MARKER.findall(source.read_text(encoding="utf-8"))
            if len(markers) != 1:
                raise RuntimeError(
                    f"{source.name}: expected one unique PASS/OK marker, got {markers}"
                )
            marker = markers[0]
            for mode in args.modes:
                output = work / source.stem / mode
                output.mkdir(parents=True)
                command = [
                    str(compiler),
                    "-n",
                    f"@{config}",
                    *LANGUAGE,
                    *target,
                    "-Rintel",
                    "-B",
                    "-dMOONBOT_MM_PROFILE_REQUIRED",
                    "-dFPCMM_BOOSTER",
                    "-dFPCMM_MOONSHARD",
                    f"--pinned-unit=mormot.core.fpcx64mm={MM}",
                    "--required-first-unit=mormot.core.fpcx64mm,cthreads"
                    if os.name != "nt"
                    else "--required-first-unit=mormot.core.fpcx64mm",
                    *NAMESPACES,
                    f"-Fu{SEMANTIC}",
                    f"-Fi{SEMANTIC}",
                    f"-Fu{SEMANTIC / 'support'}",
                    f"-Fi{SEMANTIC / 'support'}",
                    f"-FU{output}",
                    f"-FE{output}",
                    *MODES[mode],
                    *(["-al"] if mode == "o3" and source.stem in FORBIDDEN_O3_ASM else []),
                    str(source),
                ]
                compiled = execute(command)
                if compiled.returncode != 0:
                    print(compiled.stdout, file=sys.stderr)
                    raise RuntimeError(f"compile failed: {source.name} {mode}")
                executable = output / f"{source.stem}{executable_suffix}"
                run = execute([str(executable)])
                if run.returncode != 0 or marker not in run.stdout:
                    print(run.stdout, file=sys.stderr)
                    raise RuntimeError(f"runtime oracle failed: {source.name} {mode}")
                if mode == "o3" and source.stem in FORBIDDEN_O3_ASM:
                    assembly = output / f"{source.stem}.s"
                    if not assembly.is_file():
                        raise RuntimeError(f"assembly output is missing: {assembly}")
                    asm_text = assembly.read_text(encoding="utf-8", errors="replace")
                    leftovers = [
                        name for name in FORBIDDEN_O3_ASM[source.stem]
                        if re.search(
                            rf"^\s*call[^\r\n]*{name}",
                            asm_text,
                            re.IGNORECASE | re.MULTILINE,
                        )
                    ]
                    if leftovers:
                        raise RuntimeError(
                            f"O3 hot loop retains enumerator calls: {source.name} {leftovers}"
                        )
                passed += 1
                print(f"PASS {source.name} {mode} {marker}", flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    expected = len(sources) * len(args.modes)
    print(f"RTL_TEST_PASS rows={passed}/{expected} sources={len(sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
