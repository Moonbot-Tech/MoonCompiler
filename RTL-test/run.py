#!/usr/bin/env python3
"""Compile and execute the self-contained RTL semantic matrix."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEMANTIC = ROOT / "RTL-test" / "semantic"
SURFACE_GATE = ROOT / "RTL-test" / "surface" / "check_surface.py"
PROFILE_GATE = ROOT / "qualification" / "build-driver" / "rtl_profile_gate.py"
# The byte side of a runtime oracle: the linked executable of the source
# must also pass the gate (every return address as the Win64 unwinder reads it).
EXECUTABLE_GATES = {
    "win64_trailing_call_semantic": ROOT / "qualification" / "build-driver" / "pdata_tail_gate.py",
}
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
    "unicode_equality_codegen": (
        r"^\s*call[^\r\n]*FPC_UNICODESTR_COMPARE_EQUAL_CONTENT",
    ),
    # The unconditional post-call checker also passes the semantic oracle;
    # require the buffered entries so qualification covers the accepted path.
    "text_io_predicate_equivalence_semantic": (
        r"^\s*call[^\r\n]*fpc_text_eof_checked\b",
        r"^\s*call[^\r\n]*fpc_text_eoln_checked\b",
        r"^\s*call[^\r\n]*fpc_text_seekeof_checked\b",
        r"^\s*call[^\r\n]*fpc_text_seekeoln_checked\b",
    ),
}
FORBIDDEN_O3_CALL_PATTERNS.update({
    # Forwarding a fresh managed function result transfers an existing owner;
    # the borrowed-source safety gate must not restore a redundant assignment.
    "inline_fresh_managed_result_codegen": (
        r"^\s*call[^\r\n]*FPC_DYNARRAY_ASSIGN",
    ),
    # x86-64 lowers the pointer and length fast paths into the caller; only
    # equal-length, distinct payloads reach the content-only helper.
    "unicode_equality_codegen": (
        r"^\s*call[^\r\n]*FPC_UNICODESTR_COMPARE_EQUAL(?:\s|$)",
    ),
    # Comparing an Ansi/UTF-8/Short/Wide string with an empty literal only
    # needs its length.  Promoting the non-empty operand to UnicodeString is
    # both unnecessary and, for a large RawByteString, an O(n) temporary.
    "string_empty_compare_semantic": (
        r"^\s*call[^\r\n]*FPC_ANSISTR_TO_UNICODESTR",
        r"^\s*call[^\r\n]*FPC_SHORTSTR_TO_UNICODESTR",
        r"^\s*call[^\r\n]*FPC_WIDESTR_TO_UNICODESTR",
    ),
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
    "dictionary_factory_cache_semantic": ("-dENABLE_METHODS_WITH_TEnumerableWithPointers",),
    "variant_cardinal_semantic": (
        f"-Fi{ROOT / 'packages' / 'rtl-objpas' / 'src' / 'win'}",
    ),
    "mm_finalization_lifetime_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
    "mm_finalization_leak_report_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
    "openarray_finalize_throw_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
    "mm_hotpath_stress_semantic": ("-dFPCMM_REPORTMEMORYLEAKS",),
}
CURRENT_TREE_UNIT_DIRS = {
    "conversion_api_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc",
        ROOT / "packages" / "rtl-objpas" / "src" / ("win" if os.name == "nt" else "unix"),
        ROOT / "packages" / "rtl-objpas" / "src" / "x86_64",
    ),
    "variant_unicode_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc",
        ROOT / "packages" / "rtl-objpas" / "src" / ("win" if os.name == "nt" else "unix"),
        ROOT / "packages" / "rtl-objpas" / "src" / "x86_64",
    ),
    # Cardinal conversion spans the System operator and the rtl-objpas
    # Variant manager.  Compile the latter from the current tree so a stale
    # installed Variants PPU cannot hide half of the repair.
    "variant_cardinal_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc",
        ROOT / "packages" / "rtl-objpas" / "src" / "win",
    ),
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
    "task_running_cancel_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "parallel_contracts_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "aggregate_exception_enumerator_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "ioutils_api_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "rtl_api_product_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "rtti_invoke_product_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "thread_pool_lifecycle_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "thread_pool_idle_worker_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "thread_pool_delivery_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "sync_handle_lifetime_semantic": (
        ROOT / "packages" / "fcl-base" / "src",
        ROOT / "packages" / "vcl-compat" / "src",
    ),
    "thread_pool_limits_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "thread_pool_blocked_growth_semantic": ROOT / "packages" / "vcl-compat" / "src",
    # TJSONByteReader lives in packages/vcl-compat System.JSON; without this
    # the pin would silently reuse the installed PPU.
    "json_byte_reader_semantic": ROOT / "packages" / "vcl-compat" / "src",
    # TNetEncoding stream/byte repairs live in packages/vcl-compat.
    "net_encoding_streams_semantic": ROOT / "packages" / "vcl-compat" / "src",
    # The flat TDictionary path and the notification flag live in
    # packages/rtl-generics; compile Generics.Collections from the tree so
    # an installed PPU of an older dictionary cannot pass for it.
    "dictionary_flat_semantic": ROOT / "packages" / "rtl-generics" / "src",
    "dictionary_sparse_ordinal_semantic": ROOT / "packages" / "rtl-generics" / "src",
    "dictionary_rehash_ownership_semantic": ROOT / "packages" / "rtl-generics" / "src",
    "list_insert_reserved_semantic": ROOT / "packages" / "rtl-generics" / "src",
    "dictionary_factory_cache_semantic": ROOT / "packages" / "rtl-generics" / "src",
    "html_encoding_spans_semantic": ROOT / "packages" / "vcl-compat" / "src",
    "text_stream_encoding_semantic": (
        ROOT / "packages" / "fcl-base" / "src",
        ROOT / "packages" / "vcl-compat" / "src",
    ),
}
CURRENT_TREE_UNIT_FILES = {
    "monitor_wait_contract_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc" / "fpmonitor.pp",
        ROOT / "packages" / "rtl-objpas" / "src" / "win" / "fpwinmonitor.pp",
    ),
    "monitor_data_publication_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc" / "fpmonitor.pp",
        ROOT / "packages" / "rtl-objpas" / "src" / "win" / "fpwinmonitor.pp",
    ),
    # The zero-timeout overloads live in SyncObjs itself.  Test that source
    # without shadowing the rest of fcl-base with unbuilt units.
    "lightweight_mrew_semantic": (
        ROOT / "packages" / "fcl-base" / "src" / "syncobjs.pp",
        ROOT / "packages" / "fcl-base" / "src" / "countdown.inc",
        ROOT / "packages" / "fcl-base" / "src" / "lightweight.inc",
    ),
    "spin_overloads_semantic": (
        ROOT / "packages" / "fcl-base" / "src" / "syncobjs.pp",
        ROOT / "packages" / "fcl-base" / "src" / "countdown.inc",
        ROOT / "packages" / "fcl-base" / "src" / "lightweight.inc",
    ),
    # Stage only StrUtils itself.  Exposing its whole source directory would
    # also shadow unrelated installed units such as Variants.
    "strutils_surface_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc" / "strutils.pp",
    ),
    # StartsText / EndsText / ContainsText / ReplaceText of the product
    # String live in StrUtils; the SysUtils and Classes parts of the same
    # test come from the installed toolchain.
    "text_search_locale_semantic": (
        ROOT / "packages" / "rtl-objpas" / "src" / "inc" / "strutils.pp",
    ),
}
PPU_ONLY_UNITS = {
    "managed_result_ppu_semantic": ("semtrack", "semmopreload"),
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
    "mm_hotpath_stress_semantic": (
        r"^FPCMM_REPORTMEMORYLEAKS_BEGIN$",
        r"^FPCMM_REPORTMEMORYLEAKS_DONE$",
    ),
}
FORBIDDEN_RUNTIME_PATTERNS = {
    "mm_finalization_lifetime_semantic": (
        r"small block leak|medium block leak|large block leak",
    ),
    "openarray_finalize_throw_semantic": (
        r"small block leak|medium block leak|large block leak",
    ),
    # the cross-thread stress hands every block to another thread for the
    # free: a block lost on a foreign-thread path shows up in the census
    "mm_hotpath_stress_semantic": (
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
SOURCE_UNIT_ABI = [
    "-dUNICODERTL",
    "-dENABLE_DELPHI_RTTI",
]
NAMESPACES = [
    "-FNSystem",
    "-UaWinapi.Windows=Windows",
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
    "-UaZLib=System.ZLib",
    "-UaZip=System.Zip",
]


def toolchain() -> tuple[Path, Path, list[str], str]:
    # RTL profile stand: MOONBOT_TOOLCHAIN selects an alternative installed
    # toolchain directory (same layout as toolchain).
    stand = Path(os.environ["MOONBOT_TOOLCHAIN"]) if os.environ.get("MOONBOT_TOOLCHAIN") else None
    if os.name == "nt":
        base = (stand or ROOT / "toolchain") / "bin" / "x86_64-win64"
        return base / "fpc.exe", base / "moon-base.cfg", ["-Px86_64", "-Twin64"], ".exe"
    if sys.platform == "linux" and os.uname().machine == "x86_64":
        base = stand or ROOT / "toolchain"
        return (
            base / "bin" / "fpc",
            base / "etc" / "moon-base.cfg",
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
    parser.add_argument("--jobs", type=int, default=1)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")

    surface = execute([sys.executable, str(SURFACE_GATE)])
    if surface.returncode != 0:
        print(surface.stdout, file=sys.stderr)
        raise RuntimeError("RTL source surface gate failed")
    print(surface.stdout, end="")

    compiler, config, target, executable_suffix = toolchain()
    for required in (compiler, config, MM):
        if not required.is_file():
            raise RuntimeError(f"required product file is missing: {required}")
    if os.name != "nt":
        # RTTI Invoke links libffi on Linux (System.JSON.Serializers uses
        # ffi.manager); ld needs the unversioned libffi.so of libffi-dev.
        libffi = execute(["gcc", "-print-file-name=libffi.so"]).stdout.strip()
        if not Path(libffi).is_file():
            raise RuntimeError(
                "libffi development linker input is missing "
                "(Debian/Ubuntu: apt-get install libffi-dev)"
            )

    profile_command = [sys.executable, str(PROFILE_GATE)]
    if selected_toolchain := os.environ.get("MOONBOT_TOOLCHAIN"):
        profile_command += ["--toolchain", selected_toolchain]
    profile = execute(profile_command)
    if profile.returncode != 0:
        print(profile.stdout, file=sys.stderr)
        raise RuntimeError("RTL profile gate failed")
    print(profile.stdout, end="")

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

    work = Path(tempfile.mkdtemp(prefix="rtl-test-"))
    def run_source(source):
        completed = 0
        markers = MARKER.findall(source.read_text(encoding="utf-8"))
        if len(markers) != 1:
            raise RuntimeError(
                f"{source.name}: expected one unique PASS/OK marker, got {markers}"
            )
        marker = markers[0]
        for mode in args.modes:
            output = work / source.stem / mode
            output.mkdir(parents=True)
            unit_dirs = CURRENT_TREE_UNIT_DIRS.get(source.stem, ())
            if isinstance(unit_dirs, Path):
                unit_dirs = (unit_dirs,)
            unit_files = CURRENT_TREE_UNIT_FILES.get(source.stem, ())
            if unit_files:
                unit_stage = output / "current-units"
                unit_stage.mkdir()
                for unit_file in unit_files:
                    shutil.copy2(unit_file, unit_stage / unit_file.name)
                unit_dirs = (*unit_dirs, unit_stage)
            source_unit_abi = bool(unit_dirs)
            ppu_units = PPU_ONLY_UNITS.get(source.stem, ())
            if ppu_units:
                unit_stage = output / "ppu-only"
                unit_stage.mkdir()
                for name in ppu_units:
                    shutil.copy2(SEMANTIC / "support" / (name + ".pas"), unit_stage)
                producer = execute([
                    str(compiler), "-n", f"@{config}", *LANGUAGE, *target, *NAMESPACES,
                    *MODES[mode], "-B", f"-Fu{unit_stage}", f"-FU{unit_stage}",
                    str(unit_stage / (ppu_units[-1] + ".pas")),
                ], unit_stage)
                if producer.returncode != 0:
                    print(producer.stdout, file=sys.stderr)
                    raise RuntimeError(f"PPU producer failed: {source.name} {mode}")
                for name in ppu_units:
                    (unit_stage / (name + ".pas")).rename(unit_stage / (name + ".hidden"))
                unit_dirs = (*unit_dirs, unit_stage)
            rebuild = [] if unit_dirs else ["-B"]
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
                *(
                    []
                    if source.stem.startswith("runtime_prefix_")
                    else [
                        "--required-first-unit=mormot.core.fpcx64mm,cthreads"
                        if os.name != "nt"
                        else "--required-first-unit=mormot.core.fpcx64mm"
                    ]
                ),
                *NAMESPACES,
                f"-Fu{SEMANTIC}",
                f"-Fi{SEMANTIC}",
                *([] if ppu_units else [f"-Fu{SEMANTIC / 'support'}", f"-Fi{SEMANTIC / 'support'}"]),
                *(option for unit_dir in unit_dirs for option in (f"-Fu{unit_dir}", f"-Fi{unit_dir}")),
                *(SOURCE_UNIT_ABI if source_unit_abi else ()),
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
            compiled = execute(command, unit_dirs[0] if unit_dirs else ROOT)
            if compiled.returncode != 0:
                print(compiled.stdout, file=sys.stderr)
                raise RuntimeError(f"compile failed: {source.name} {mode}")
            executable = output / f"{source.stem}{executable_suffix}"
            run = execute([str(executable)], output)
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
            if gate := EXECUTABLE_GATES.get(source.stem):
                checked = execute([sys.executable, str(gate), str(executable)])
                if checked.returncode != 0:
                    print(checked.stdout, file=sys.stderr)
                    raise RuntimeError(f"executable gate failed: {source.name} {mode}")
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
            completed += 1
            print(f"PASS {source.name} {mode} {marker}", flush=True)
            # nothing reads a passed row's build again: the free space
            # a run needs is one row, not the whole matrix
            shutil.rmtree(output, ignore_errors=True)
        return completed

    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            passed = sum(pool.map(run_source, sources))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    expected = len(sources) * len(args.modes)
    print(f"RTL_TEST_PASS rows={passed}/{expected} sources={len(sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
