#!/usr/bin/env python3
"""Run the exact Win64 regressions and adjacent forms for compiler repairs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


CORE_TESTS = (
    "tdelphimixeduint641",
    "tu64modpow2mask1",
    "tdelphicurrencymul1",
    "tdelphirawbyteconcat1",
    "tdelphirawbyteconst1",
    "tunsignednarrowarith1",
    "tdelphix86shiftfold1",
    "tcapturedinlineinterface1",
    "tcapturedinlineinterface2",
    "tdelphilocalfinalize1",
    "tdelphilocalfinalizedefer1",
    "tdelphimaininlinefinalize1",
    "tpeepequalregloop1",
    "tforunrollfinally1",
    "tforunrollfinally2",
    "tdelphisparseenumtypeinfo1",
    "tdelphiinlineconstruntime1",
    "tdelphianonymousnew1",
    "tdelphinilvaroverload1",
    "tdelphithreadcreate1",
    "tdelphifilegetsize1",
    "tdelphimemorystreamcapacity1",
    "tdelphitextpos1",
    "tdelphiforvarexplicit1",
    "tmoonnamespacequalified1",
    "tdelphiconstref1",
    "tarrayconstafterinline1",
    "tdelphiunicodeliteral1",
    "tdelphibyteconstppu1",
    "tdelphibytestringcast1",
    "tdelphibytestringconcatdomain1",
    "tdelphicharcast1",
    "tdelphiintpair1",
    "tobjfpcliteralcastoverload1",
    "tsetconstbase1",
    "tx86boolconstmovwidth1",
    "tunicodeguidparse1",
    "tdelphiqualifiedinteger1",
    "tdelphisplitempty1",
    "tdelphistringlistbom1",
    "tdelphivariantstring1",
    "tdelphivariantrawbytestring1",
    "tdelphinegativezero1",
    "tmoonoddconstu641",
    "tmoonconstpropglobalcalls1",
    "tmooninlinemanagedexprfinally1",
    "tmoondelphicallbacktypes1",
    "tmoonattributemarker1",
    "tloopinvariantaddr1",
    "tloopinvariantarraywrite1",
    "tloopmutablestringbase1",
    "tlooplocaldynarraycall1",
    "twidecharsetmembership1",
    "tstrengthenumguard1",
    "tstrengthresultcounter1",
    "tstrengthresultcountertrace1",
    "tarrayindexoffsetconv1",
    "tarraypointerindexoffset1",
    "tdelphiinlineexceptreg1",
    "tdelphiinlinefuncrettemp1",
    "tdelphidefaultarray1",
)
CORE_SOURCE_ARGS = {
    "tstrengthresultcountertrace1": ["-gt"],
    "tmoonnamespacequalified1": [
        "-FNSystem",
        "-UaSystem.SysUtils=SysUtils",
    ],
}
GENERIC_TESTS = (
    "tinlinegenericcomparer1",
    "tnestedgenericarray1",
    "tqualifiedintegercomparer1",
    "tdelphitarraycopy1",
    "tdelphidictionaryisempty1",
)
OPTIONS = ("O2", "O3")
NEGATIVE_TESTS = (
    ("delphi_mixed_uint64_pair_ambiguous", "Can't determine which overloaded function to call"),
    ("inline_const_reassign_fail", "Can't assign values to const variable"),
    ("inline_const_typed_reassign_fail", "Can't assign values to const variable"),
    ("inline_const_record_field_reassign_fail", "Can't assign values to const variable"),
    ("inline_const_string_char_reassign_fail", "Can't assign values to const variable"),
    ("inline_const_var_parameter_rejected", "Can't assign values to const variable"),
    ("dead_try_handler_still_checked", 'Identifier not found "MissingInDeadHandler"'),
    ("array_const_index_out_of_range", "Range check error while evaluating constants"),
    ("delphi_constref_write_rejected", "Can't assign values to const variable"),
    ("objfpc_delphi_constref_rejected", "Syntax error"),
)


def run(command: list[str], *, cwd: Path, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compiler_info(compiler: Path, switch: str) -> str:
    result = run([str(compiler), switch], cwd=compiler.parent)
    if result.returncode != 0:
        raise RuntimeError(f"compiler {switch} failed: {result.stderr.strip()}")
    return result.stdout.strip().lower()


def generic_source_args(compiler_root: Path) -> list[str]:
    package = compiler_root / "packages" / "rtl-generics"
    return [
        f"-Fu{package / 'namespaced'}",
        f"-Fi{package / 'src'}",
        f"-Fi{package / 'src' / 'inc'}",
        "-UaSystem.Classes=Classes",
        "-UaSystem.SysUtils=SysUtils",
        "-UaSystem.TypInfo=TypInfo",
        "-UaSystem.Variants=Variants",
        "-UaSystem.Math=Math",
        "-UaSystem.CPU=CPU",
    ]


def verify_unrolled_seh(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    start_marker = "P$TFORUNROLLFINALLY2_$$_EXERCISE$ANSISTRING:"
    end_marker = ".seh_handler __FPC_specific_handler,@unwind"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise RuntimeError("cannot isolate the Win64 SEH Exercise procedure")
    body = text[start:end]
    for value in range(48, 52):
        if f"movl\t${value},%edx" not in body:
            raise RuntimeError(f"Win64 SEH loop was not unrolled: missing constant {value}")
    if "cmpl\t$3" in body or "jng\t" in body:
        raise RuntimeError("Win64 SEH loop still contains its runtime loop branch")


def verify_loop_invariant_address(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    start_marker = "P$TLOOPINVARIANTADDR1$_$TWORKER_$__$$_BUMP$LONGINT:"
    start = text.find(start_marker)
    end = text.find(".section", start + len(start_marker))
    if start < 0 or end < 0:
        raise RuntimeError("cannot isolate the invariant-address Bump procedure")
    body = text[start:end]
    loop_start = body.find("Inc(Counters[FIndex].Value);")
    loop_end = body.find("jne\t", loop_start)
    if loop_start < 0 or loop_end < 0:
        raise RuntimeError("cannot isolate the invariant-address loop")
    prefix = body[:loop_start]
    loop = body[loop_start:loop_end]
    if "COUNTERS" not in prefix or not re.search(r"addq\s+\$1,\(%[a-z0-9]+\)", loop):
        raise RuntimeError("static array element address was not materialized before the loop")
    if "COUNTERS" in loop or re.search(r"\d+\(%[a-z0-9]+\)", loop):
        raise RuntimeError("loop-invariant array address is still recalculated in the loop")


def assembly_procedure(text: str, marker: str) -> str:
    start = text.find(marker)
    end = text.find(".section", start + len(marker))
    if start < 0 or end < 0:
        raise RuntimeError(f"cannot isolate assembly procedure {marker}")
    return text[start:end]


def verify_inline_exception_registers(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    pure = assembly_procedure(
        text,
        "P$TDELPHIINLINEEXCEPTREG1_$$_PUREINCALLEREXCEPT$LONGINT$$QWORD:",
    )
    if ".seh_handler" in pure:
        raise RuntimeError("proven non-throwing inline body still has a Win64 handler")
    loop_start = pure.find("Result := Mix(Result + UInt64(J));")
    loop_end = pure.find("jng\t", loop_start)
    if loop_start < 0 or loop_end < 0:
        raise RuntimeError("cannot isolate the pure inline exception loop")
    loop = pure[loop_start:loop_end]
    if re.search(r"movq\s+%r[a-z0-9]+,\d+\(%rsp\)", loop):
        raise RuntimeError("scalar inline parameter still spills into the exception frame")

    for marker in (
        "P$TDELPHIINLINEEXCEPTREG1_$$_THROWTOCALLER$QWORD$$QWORD:",
        "P$TDELPHIINLINEEXCEPTREG1_$$_CHECKEDOVERFLOWCAUGHT$LONGINT$$LONGINT:",
        "P$TDELPHIINLINEEXCEPTREG1_$$_DIVIDEBYZEROCAUGHT$LONGINT$$LONGINT:",
        "P$TDELPHIINLINEEXCEPTREG1_$$_RANGECHECKCAUGHT$LONGINT$$LONGINT:",
        "P$TDELPHIINLINEEXCEPTREG1_$$_INDEXEDINCREMENTCAUGHT$$LONGINT:",
        "P$TDELPHIINLINEEXCEPTREG1_$$_NILVARCAUGHT$$LONGINT:",
    ):
        if ".seh_handler __FPC_specific_handler,@except" not in assembly_procedure(text, marker):
            raise RuntimeError(f"real exception path lost its Win64 handler: {marker}")


def verify_inline_funcret_temp(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    consume = assembly_procedure(
        text,
        "P$TDELPHIINLINEFUNCRETTEMP1_$$_SUMLENGTHS$TSTRSTORE$LONGINT$$QWORD:",
    )
    if "fpc_unicodestr_assign" in consume:
        raise RuntimeError(
            "read-only consumption of an inlined managed getter still copies "
            "the result through a temp"
        )
    arrays = assembly_procedure(
        text,
        "P$TDELPHIINLINEFUNCRETTEMP1_$$_SUMARRAYLENGTHS$TARRSTORE$$QWORD:",
    )
    if "fpc_dynarray_assign" in arrays or "fpc_dynarray_incr_ref" in arrays:
        raise RuntimeError(
            "read-only consumption of an inlined dynamic-array getter still "
            "copies the result through a temp"
        )
    for marker, requirement in (
        (
            "P$TDELPHIINLINEFUNCRETTEMP1_$$_COPYOUTLIVESSTORE$TSTRSTORE$$UNICODESTRING:",
            "fpc_unicodestr_assign",
        ),
        (
            "P$TDELPHIINLINEFUNCRETTEMP1_$$_DOUBLEDAT$TSTRSTORE$NATIVEINT$$UNICODESTRING:",
            "fpc_unicodestr_assign",
        ),
    ):
        if requirement not in assembly_procedure(text, marker):
            raise RuntimeError(f"a required managed copy disappeared: {marker}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("run_id")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    config = args.config.resolve()
    compiler_root = args.compiler_root.resolve()
    result_root = root / "results" / "runs" / args.run_id / "win64-repairs"
    if not compiler.is_file() or not config.is_file() or not compiler_root.is_dir():
        parser.error("compiler, config and compiler_root must exist")
    if result_root.exists():
        parser.error(f"run already exists: {result_root}")
    if compiler_info(compiler, "-iTP") != "x86_64" or compiler_info(compiler, "-iTO") != "win64":
        parser.error("this gate requires an x86_64-win64 compiler")

    cases: list[tuple[str, Path, list[str]]] = []
    for name in CORE_TESTS:
        cases.append((
            name,
            compiler_root / "tests" / "test" / "cg" / f"{name}.pp",
            CORE_SOURCE_ARGS.get(name, []),
        ))
    generic_args = generic_source_args(compiler_root)
    for name in GENERIC_TESTS:
        cases.append(
            (name, compiler_root / "packages" / "rtl-generics" / "tests" / f"{name}.pp", generic_args)
        )
    missing = [str(source) for _, source, _ in cases if not source.is_file()]
    if missing:
        parser.error("missing regression sources: " + ", ".join(missing))

    result_root.mkdir(parents=True)
    rows: list[dict[str, object]] = []
    failures: list[str] = []
    for name, source, source_args in cases:
        for option in OPTIONS:
            output = result_root / f"{name}-{option.lower()}"
            output.mkdir()
            command = [
                str(compiler),
                "-n",
                f"@{config}",
                "-B",
                f"-{option}",
                f"-FU{output}",
                f"-FE{output}",
                *source_args,
            ]
            if name in (
                "tforunrollfinally2",
                "tloopinvariantaddr1",
                "tdelphiinlineexceptreg1",
                "tdelphiinlinefuncrettemp1",
            ) and option == "O3":
                command.append("-al")
            command.append(str(source))
            compiled = run(command, cwd=output)
            (output / "compile.log").write_text(
                compiled.stdout + compiled.stderr, encoding="utf-8"
            )
            executable = output / f"{name}.exe"
            executed: subprocess.CompletedProcess[str] | None = None
            if compiled.returncode == 0 and executable.is_file():
                executed = run([str(executable)], cwd=output, timeout=30)
                (output / "run.log").write_text(
                    executed.stdout + executed.stderr, encoding="utf-8"
                )
            row = {
                "test": name,
                "option": option,
                "compile_exit": compiled.returncode,
                "run_exit": None if executed is None else executed.returncode,
            }
            rows.append(row)
            if row["compile_exit"] != 0 or row["run_exit"] != 0:
                failures.append(f"{name}/{option}")

    for name, expected_error in NEGATIVE_TESTS:
        source = root / "tests" / "smoke" / f"{name}.pas"
        if not source.is_file():
            raise RuntimeError(f"missing negative regression source: {source}")
        for option in OPTIONS:
            output = result_root / f"{name}-{option.lower()}"
            output.mkdir()
            compiled = run(
                [
                    str(compiler),
                    "-n",
                    f"@{config}",
                    "-B",
                    f"-{option}",
                    f"-FU{output}",
                    f"-FE{output}",
                    str(source),
                ],
                cwd=output,
            )
            log = compiled.stdout + compiled.stderr
            (output / "compile.log").write_text(log, encoding="utf-8")
            rows.append(
                {
                    "test": name,
                    "option": option,
                    "compile_exit": compiled.returncode,
                    "expected_error": expected_error in log,
                }
            )
            if compiled.returncode == 0 or expected_error not in log:
                failures.append(f"{name}/{option}")

    expected_rows = (
        len(CORE_TESTS) + len(GENERIC_TESTS) + len(NEGATIVE_TESTS)
    ) * len(OPTIONS)
    if len(rows) != expected_rows:
        raise RuntimeError(f"incomplete matrix: {len(rows)}/{expected_rows}")
    try:
        verify_unrolled_seh(result_root / "tforunrollfinally2-o3" / "tforunrollfinally2.s")
    except (OSError, RuntimeError) as error:
        failures.append(f"seh-assembly ({error})")
    try:
        verify_loop_invariant_address(
            result_root / "tloopinvariantaddr1-o3" / "tloopinvariantaddr1.s"
        )
    except (OSError, RuntimeError) as error:
        failures.append(f"loop-invariant-address-assembly ({error})")
    try:
        verify_inline_exception_registers(
            result_root / "tdelphiinlineexceptreg1-o3" / "tdelphiinlineexceptreg1.s"
        )
    except (OSError, RuntimeError) as error:
        failures.append(f"inline-exception-registers-assembly ({error})")
    try:
        verify_inline_funcret_temp(
            result_root / "tdelphiinlinefuncrettemp1-o3" / "tdelphiinlinefuncrettemp1.s"
        )
    except (OSError, RuntimeError) as error:
        failures.append(f"inline-funcret-temp-assembly ({error})")

    (result_root / "results.json").write_text(
        json.dumps(rows, indent=2) + "\n", encoding="utf-8"
    )
    rtl_dir = compiler.parents[2] / "units" / "x86_64-win64" / "rtl"
    rtl_units = (rtl_dir / "system.ppu", rtl_dir / "sysutils.ppu")
    missing_rtl_units = [str(unit) for unit in rtl_units if not unit.is_file()]
    if missing_rtl_units:
        raise RuntimeError(
            "missing installed RTL units: " + ", ".join(missing_rtl_units)
        )
    provenance = {
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "rtl_units": {str(unit): sha256(unit) for unit in rtl_units},
        "sources": {
            **{str(source.relative_to(compiler_root)): sha256(source) for _, source, _ in cases},
            **{
                str((root / "tests" / "smoke" / f"{name}.pas").relative_to(root)):
                    sha256(root / "tests" / "smoke" / f"{name}.pas")
                for name, _ in NEGATIVE_TESTS
            },
        },
        "rows": expected_rows,
    }
    (result_root / "provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if failures:
        raise RuntimeError("failed checks: " + ", ".join(failures))
    print(f"WIN64_REPAIR_GATE_OK rows={expected_rows} seh_unrolled=1 invariant_address=1")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
