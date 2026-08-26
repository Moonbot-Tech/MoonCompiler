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
TARGET = re.compile(r"\{\s*%TARGET=(win64|linux)\s*\}", re.IGNORECASE)
FORBIDDEN_O3_ASM = {
    "collections_codegen": ("MOVENEXT", "GETCURRENT"),
}
# Custom-Initialize locals no longer block inlining (dvl-0057): the
# tracked-record routines must now expand like any ordinary managed-local
# routine, with the operator lifecycle preserved at the call site.
FORBIDDEN_O3_CALL_PATTERNS = {
    "inline_managed_locals_semantic": (
        r"^\s*call[^\r\n]*_\$\$_USETAG\$ANSICHAR\s*$",
        r"^\s*call[^\r\n]*_\$\$_USETRACKEDRECORD\s*$",
        r"^\s*call[^\r\n]*_\$\$_USETRACKEDAGGREGATE\s*$",
    ),
}
REQUIRED_O3_CALL_PATTERNS = {
    "inline_managed_locals_semantic": (
        r"^\s*call[^\r\n]*_\$\$_APPENDGLOBAL\$ANSICHAR\s*$",
    ),
}
FORBIDDEN_O3_CALL_PATTERNS.update({
    # managed by-value parameters must not block inlining: the copy is
    # materialized with the callee's lifetime (journal 6, deep layer).
    # The negative lookahead admits the finally funclet call
    # (..._$$_fin$NNNNNNNN) that buries the materialized copy - that
    # call is the contour working, not the inline failing
    "inline_managed_value_copy_semantic": (
        r"^\s*call(?![^\r\n]*_fin\$)[^\r\n]*MODIFYRECBYVALUE",
        r"^\s*call(?![^\r\n]*_fin\$)[^\r\n]*MODIFYSTRBYVALUE",
    ),
    # A read-only const-reference helper over non-local storage is safe to
    # inline; the alias gate must not block it merely because the argument is
    # global.  A mutating helper with a value-ABI const scalar must likewise
    # stay inline after the caller snapshot has been materialized.
    "inline_const_alias_semantic": (
        r"^\s*call[^\r\n]*SUMBIG",
        r"^\s*call[^\r\n]*READSCALARAFTERWRITE",
    ),
})
SOURCE_OPTIONS = {
    "mm_finalization_lifetime_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
    "mm_finalization_leak_report_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
}
CURRENT_TREE_UNIT_DIRS = {
    # This repair lives in packages/vcl-compat.  An ordinary program build
    # would otherwise silently reuse the already installed PPU and leave the
    # edited System.NetEncoding source untested.
    "url_encoding_utf8_codepage_semantic": ROOT / "packages" / "vcl-compat" / "src",
    # Linux forward DNS must exercise the edited fcl-net NetDB source rather
    # than an older PPU already installed in the product toolchain.
    "netdb_linux_resolver_semantic": ROOT / "packages" / "fcl-net" / "src",
    # WaitForAll/WaitForAny and the completion callback race live in the
    # imported Delphi-compatible threading unit, not in an installed RTL PPU.
    "task_wait_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "ioutils_api_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "rtl_api_product_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "rtti_invoke_product_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "thread_pool_lifecycle_semantic": ROOT / "packages" / "vcl-compat" / "src",
}
REQUIRED_RUNTIME_PATTERNS = {
    "mm_finalization_lifetime_semantic": (
        r"^FPCMM_REPORTMEMORYLEAKS_BEGIN$",
        r"^FPCMM_REPORTMEMORYLEAKS_DONE$",
    ),
    "mm_finalization_leak_report_semantic": (
        r"^FPCMM_REPORTMEMORYLEAKS_BEGIN$",
        r"^ small block leak x1 of size=",
        r"^FPCMM_REPORTMEMORYLEAKS_DONE$",
    ),
}
FORBIDDEN_RUNTIME_PATTERNS = {
    "mm_finalization_lifetime_semantic": (
        r"small block leak|medium block leak|large block leak",
    ),
}
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


def execute(command: list[str], cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
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
    host_target = "win64" if os.name == "nt" else "linux"
    sources = [
        source
        for source in sources
        if (
            (match := TARGET.search(source.read_text(encoding="utf-8"))) is None
            or match.group(1).lower() == host_target
        )
    ]
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
                unit_dir = CURRENT_TREE_UNIT_DIRS.get(source.stem)
                rebuild = [] if unit_dir else ["-B"]
                command = [
                    str(compiler),
                    "-n",
                    f"@{config}",
                    *LANGUAGE,
                    *target,
                    "-Rintel",
                    *rebuild,
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
                    *([f"-Fu{unit_dir}"] if unit_dir else []),
                    f"-FU{output}",
                    f"-FE{output}",
                    *MODES[mode],
                    *SOURCE_OPTIONS.get(source.stem, ()),
                    *(
                        ["-al"]
                        if mode == "o3"
                        and source.stem
                        in (
                            FORBIDDEN_O3_ASM.keys()
                            | FORBIDDEN_O3_CALL_PATTERNS.keys()
                            | REQUIRED_O3_CALL_PATTERNS.keys()
                        )
                        else []
                    ),
                    str(source),
                ]
                compiled = execute(command, unit_dir or ROOT)
                if compiled.returncode != 0:
                    print(compiled.stdout, file=sys.stderr)
                    raise RuntimeError(f"compile failed: {source.name} {mode}")
                executable = output / f"{source.stem}{executable_suffix}"
                run = execute([str(executable)])
                if run.returncode != 0 or marker not in run.stdout:
                    print(run.stdout, file=sys.stderr)
                    raise RuntimeError(f"runtime oracle failed: {source.name} {mode}")
                missing_runtime = [
                    pattern
                    for pattern in REQUIRED_RUNTIME_PATTERNS.get(source.stem, ())
                    if not re.search(pattern, run.stdout, re.MULTILINE)
                ]
                forbidden_runtime = [
                    pattern
                    for pattern in FORBIDDEN_RUNTIME_PATTERNS.get(source.stem, ())
                    if re.search(pattern, run.stdout, re.MULTILINE)
                ]
                if missing_runtime or forbidden_runtime:
                    print(run.stdout, file=sys.stderr)
                    raise RuntimeError(
                        f"runtime lifecycle oracle failed: {source.name} {mode} "
                        f"missing={missing_runtime} forbidden={forbidden_runtime}"
                    )
                if mode == "o3" and source.stem in (
                    FORBIDDEN_O3_ASM.keys()
                    | FORBIDDEN_O3_CALL_PATTERNS.keys()
                    | REQUIRED_O3_CALL_PATTERNS.keys()
                ):
                    assembly = output / f"{source.stem}.s"
                    if not assembly.is_file():
                        raise RuntimeError(f"assembly output is missing: {assembly}")
                    asm_text = assembly.read_text(encoding="utf-8", errors="replace")
                    leftovers = [
                        name for name in FORBIDDEN_O3_ASM.get(source.stem, ())
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
                    forbidden_calls = [
                        pattern
                        for pattern in FORBIDDEN_O3_CALL_PATTERNS.get(source.stem, ())
                        if re.search(pattern, asm_text, re.IGNORECASE | re.MULTILINE)
                    ]
                    if forbidden_calls:
                        raise RuntimeError(
                            f"O3 retains calls that must inline: {source.name} {forbidden_calls}"
                        )
                    missing_calls = [
                        pattern
                        for pattern in REQUIRED_O3_CALL_PATTERNS.get(source.stem, ())
                        if not re.search(pattern, asm_text, re.IGNORECASE | re.MULTILINE)
                    ]
                    if missing_calls:
                        raise RuntimeError(
                            f"O3 lost required call boundaries: {source.name} {missing_calls}"
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
