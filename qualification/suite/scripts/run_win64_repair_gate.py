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

from qualification_contracts import (
    ContractError,
    MANIFEST_PATH,
    LOCKS_PATH,
    canonical_sha256,
    load_json,
    planned_pairs,
    require_exact_actual,
    require_retirement_only,
    validate_focused_gate,
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


def verify_forstep_latch(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    body = assembly_procedure(
        text,
        "P$TFORSTEPLATCHASM1_$$_SUM$LONGINT$LONGINT$LONGINT$$LONGINT:",
    )
    if "fpc_rangeerror" not in body:
        raise RuntimeError("the runtime step<=0 gate is missing")
    # isolate the steady-state loop: the last backward conditional jump
    back_jumps = list(re.finditer(r"\tj([a-z]+)\t(\.Lj\d+)\n", body))
    loop = None
    for match in back_jumps:
        label = match.group(2) + ":"
        target = body.find(label)
        if 0 <= target < match.start():
            loop = body[target:match.end()]
            break
    if loop is None:
        raise RuntimeError("cannot isolate the for-step steady-state loop")
    if "fpc_rangeerror" in loop:
        raise RuntimeError("the step gate leaked into the steady state")
    conditional = re.findall(r"\tj(?!mp)[a-z]+\t", loop)
    if len(conditional) != 1:
        raise RuntimeError(
            f"for-step steady state must carry exactly one continuation "
            f"compare, found {len(conditional)}"
        )


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


ASM_VERIFIERS = {
    "unrolled-seh": verify_unrolled_seh,
    "loop-invariant-address": verify_loop_invariant_address,
    "inline-exception-registers": verify_inline_exception_registers,
    "inline-funcret-temp": verify_inline_funcret_temp,
    "forstep-latch": verify_forstep_latch,
}


def case_source(root: Path, compiler_root: Path, item: dict[str, object]) -> Path:
    base = compiler_root if item["source_root"] == "compiler" else root
    return base / str(item["source"])


def case_arguments(
    gate: dict[str, object], compiler_root: Path, item: dict[str, object]
) -> list[str]:
    result: list[str] = []
    argument_sets = gate["argument_sets"]
    assert isinstance(argument_sets, dict)
    for name in item["args"]:
        for value in argument_sets[name]:
            result.append(value.format(compiler_root=compiler_root))
    return result


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

    manifest = load_json(MANIFEST_PATH)
    locks = load_json(LOCKS_PATH)
    gate, inventory_digest = validate_focused_gate(
        manifest, locks, "win64-repairs"
    )
    require_retirement_only(manifest)
    cases = [case for case in gate["cases"] if case["state"] == "active"]
    planned = planned_pairs(gate)
    sources: dict[str, Path] = {}
    for item in cases:
        sources[f"{item['source_root']}:{item['source']}"] = case_source(
            root, compiler_root, item
        )
        setup = item.get("setup")
        if setup:
            sources[f"{setup['source_root']}:{setup['source']}"] = case_source(
                root, compiler_root, setup
            )
        for binding in item["asm"]:
            if binding["verifier"] not in ASM_VERIFIERS:
                raise ContractError(
                    f"unknown ASM verifier for {item['id']}: {binding['verifier']}"
                )
    missing = [str(source) for source in sources.values() if not source.is_file()]
    if missing:
        parser.error("missing regression sources: " + ", ".join(missing))

    result_root.mkdir(parents=True)
    rows: list[dict[str, object]] = []
    failures: list[str] = []
    for item in cases:
        case_id = item["id"]
        source = case_source(root, compiler_root, item)
        source_args = case_arguments(gate, compiler_root, item)
        expectation = item["expectation"]
        for profile in item["profiles"]:
            output = result_root / f"{case_id}-{profile.lower()}"
            output.mkdir()
            profile_args = gate["profiles"][profile]
            setup = item.get("setup")
            setup_result: subprocess.CompletedProcess[str] | None = None
            if setup:
                setup_source = case_source(root, compiler_root, setup)
                setup_result = run(
                    [
                        str(compiler),
                        "-n",
                        f"@{config}",
                        "-B",
                        *profile_args,
                        f"-FU{output}",
                        f"-FE{output}",
                        *source_args,
                        str(setup_source),
                    ],
                    cwd=output,
                )
            command = [
                str(compiler),
                "-n",
                f"@{config}",
                *([] if setup else ["-B"]),
                *profile_args,
                f"-FU{output}",
                f"-FE{output}",
                *([f"-Fu{output}"] if setup else []),
                *source_args,
            ]
            if any(binding["profile"] == profile for binding in item["asm"]):
                command.append("-al")
            command.append(str(source))
            compiled = (
                run(command, cwd=output)
                if setup_result is None or setup_result.returncode == 0
                else setup_result
            )
            if setup_result is None:
                log = compiled.stdout + compiled.stderr
            elif setup_result.returncode == 0:
                log = (
                    setup_result.stdout + setup_result.stderr
                    + compiled.stdout + compiled.stderr
                )
            else:
                log = setup_result.stdout + setup_result.stderr
            (output / "compile.log").write_text(log, encoding="utf-8")
            executable = output / f"{case_id}.exe"
            executed: subprocess.CompletedProcess[str] | None = None
            if (
                expectation["compile"] == "pass"
                and compiled.returncode == 0
                and executable.is_file()
            ):
                executed = run([str(executable)], cwd=output, timeout=30)
                (output / "run.log").write_text(
                    executed.stdout + executed.stderr, encoding="utf-8"
                )
            row = {
                "id": case_id,
                "profile": profile,
                "compile_exit": compiled.returncode,
                "run_exit": None if executed is None else executed.returncode,
            }
            if expectation["compile"] == "fail":
                row["diagnostic_matched"] = expectation["diagnostic"] in log
            rows.append(row)
            if expectation["compile"] == "pass":
                if row["compile_exit"] != 0 or row["run_exit"] != 0:
                    failures.append(f"{case_id}/{profile}")
            elif row["compile_exit"] == 0 or not row["diagnostic_matched"]:
                failures.append(f"{case_id}/{profile}")

    require_exact_actual(planned, ((row["id"], row["profile"]) for row in rows))
    expected_rows = len(planned)
    for item in cases:
        for binding in item["asm"]:
            assembly = (
                result_root
                / f"{item['id']}-{binding['profile'].lower()}"
                / f"{item['id']}.s"
            )
            try:
                ASM_VERIFIERS[binding["verifier"]](assembly)
            except (OSError, RuntimeError) as error:
                failures.append(
                    f"{item['id']}/{binding['profile']}/asm ({error})"
                )

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
        "manifest": str(MANIFEST_PATH),
        "manifest_sha256": sha256(MANIFEST_PATH),
        "inventory_sha256": inventory_digest,
        "planned_sha256": canonical_sha256(
            [{"id": case_id, "profile": profile} for case_id, profile in sorted(planned)]
        ),
        "rtl_units": {str(unit): sha256(unit) for unit in rtl_units},
        "sources": {name: sha256(source) for name, source in sorted(sources.items())},
        "rows": expected_rows,
    }
    (result_root / "provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if failures:
        raise RuntimeError("failed checks: " + ", ".join(failures))
    print(f"WIN64_REPAIR_GATE_OK rows={expected_rows} asm={sum(len(item['asm']) for item in cases)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ContractError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
