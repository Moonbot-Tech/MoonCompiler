#!/usr/bin/env python3
"""Run the exact regressions and adjacent forms for compiler repairs.

The inventory is `win64-repairs` of runner_manifest.json. The gate runs it
with the compiler it is given, x86_64-win64 or x86_64-linux, and the product
configuration: a case runs on the targets it names (on both when it names
none). The assembly bindings read Win64 listings and run on Win64.
"""

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
    TARGETS,
    canonical_sha256,
    case_targets,
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


def discover_loaded_rtl_units(
    compiler: Path, config: Path, result_root: Path
) -> tuple[Path, Path]:
    """Ask the compiler which PPUs the supplied config actually selects."""
    source = result_root / "rtl_provenance_probe.pas"
    unit_dir = result_root / "rtl-provenance-units"
    unit_dir.mkdir()
    source.write_text("program rtl_provenance_probe; uses SysUtils; begin end.\n")
    compiled = run(
        [
            str(compiler),
            "-n",
            f"@{config}",
            "-vu",
            f"-FU{unit_dir}",
            f"-FE{unit_dir}",
            str(source),
        ],
        cwd=result_root,
    )
    log = compiled.stdout + compiled.stderr
    (result_root / "rtl_provenance_probe.log").write_text(log, encoding="utf-8")
    if compiled.returncode != 0:
        raise RuntimeError("RTL provenance probe did not compile")
    loaded: dict[str, Path] = {}
    pattern = re.compile(r"^\((SYSTEM|SYSUTILS)\)\s+PPU Name:\s+(.+?)\s*$", re.MULTILINE)
    for unit, raw_path in pattern.findall(log):
        path = Path(raw_path)
        if not path.is_absolute():
            path = (result_root / path).resolve()
        loaded[unit.lower()] = path
    try:
        result = (loaded["system"], loaded["sysutils"])
    except KeyError as error:
        raise RuntimeError(f"RTL provenance probe did not report {error.args[0]}.ppu") from error
    missing = [str(path) for path in result if not path.is_file()]
    if missing:
        raise RuntimeError("loaded RTL units are missing: " + ", ".join(missing))
    return result


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


def verify_loop_counter_observability(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")

    def counter_values(body: str) -> set[str]:
        location = re.search(
            r"# Var Index located at (r(?:bp|sp|cx))([+-]\d+), size=OS_S32",
            body,
        )
        if not location:
            raise RuntimeError("cannot resolve the exact Index stack slot")
        operand = f"{int(location.group(2))}(%{location.group(1)})"
        stores = re.compile(rf"movl\s+\$([123]),{re.escape(operand)}")
        return set(stores.findall(body))

    for marker in (
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBE$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBECONTINUATION$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEELSEBRANCH$BOOLEAN$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEONHANDLER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEEXITTHROUGHFINALLY:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEBODYSTEPCHECKHANDLER$LONGINT$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEBODYSUBRANGESTEPCHECKHANDLER$TPOSITIVESTEP$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEBREAKTHROUGHFINALLY:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBECONTINUETHROUGHFINALLY:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBENESTEDEXITTHROUGHFINALLY$BOOLEAN:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEGOTOOUTOFLOOP$BOOLEAN:",
    ):
        body = assembly_procedure(text, marker)
        if counter_values(body) != {"1", "2", "3"}:
            raise RuntimeError(
                f"exception observer lost an exact unrolled counter state: {marker}"
            )
    for marker in (
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEWRITEBEFOREREAD$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEFINALLYKILLSCOUNTER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBECATCHALLKILLSCOUNTER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEGOTOKILLSCOUNTER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEGOTOLOOPKILLSCOUNTER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEBODYCONSTANTSTEPHANDLER$$LONGINT:",
        "P$TFORUNROLLEXCEPTIONCOUNTER1_$$_PROBEFINALIZERGOTOCONTEXTKILL:",
    ):
        body = assembly_procedure(text, marker)
        if counter_values(body):
            raise RuntimeError(
                f"a handler/finalizer kill retained dead counter stores: {marker}"
              )


def verify_loop_counter_nonlocal_goto(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")

    def counter_values(body: str) -> set[str]:
        location = re.search(
            r"# Var Index located at (r(?:bp|sp|cx))([+-]\d+), size=OS_S32",
            body,
        )
        if not location:
            return set()
        register, displacement = location.groups()
        displacement = str(int(displacement))
        stores = re.compile(
            rf"movl\s+\$([123]),{re.escape(displacement)}\(%{register}\)"
        )
        return set(stores.findall(body))

    for marker in (
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBELOOP:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBETRANSITIVELOOP:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEARRAYLABEL:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEIMPLICITSETLENGTH:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEDIRECTRANGEERROR:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBECALLEERANGEERROR:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBERECURSIVEACTIVATION$LONGINT:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBECONTINUATIONRANGEERROR:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBECONTINUATIONSTEPERROR:",
    ):
        body = assembly_procedure(text, marker)
        if counter_values(body) != {"1", "2", "3"}:
            raise RuntimeError(
                f"non-local goto lost an exact unrolled counter state: {marker}"
            )

    for marker in (
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEKILLEDTARGET:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEDISJOINTTARGETS:",
        "P$TFORUNROLLNONLOCALGOTO1_$$_PROBENOCALLINLOOP$BOOLEAN:",
    ):
        if counter_values(assembly_procedure(text, marker)):
            raise RuntimeError(
                f"dead non-local continuation retained counter stores: {marker}"
            )

    body = assembly_procedure(
        text, "P$TFORUNROLLNONLOCALGOTO1_$$_PROBECOUNTDOWN:"
    )
    location = re.search(
        r"# Var Index located at (r(?:bp|sp|cx))([+-]\d+), size=OS_S32",
        body,
    )
    if not location:
        raise RuntimeError("cannot resolve the non-local countdown counter slot")
    register, displacement = location.groups()
    operand = f"{int(displacement)}(%{register})"
    if not re.search(rf"movl\s+\$1,{re.escape(operand)}", body):
        raise RuntimeError("non-local countdown does not start with source value 1")
    if re.search(rf"movl\s+\$100,{re.escape(operand)}", body):
        raise RuntimeError("non-local countdown was reversed before an abrupt observer")

    body = assembly_procedure(
        text, "P$TFORUNROLLNONLOCALGOTO1_$$_PROBEORDINARYCOUNTDOWN:"
    )
    tick = "call\tP$TFORUNROLLNONLOCALGOTO1_$$_TICK"
    if body.count(tick) != 100 or re.search(r"\tj(?!mp)[a-z]+\t", body):
        raise RuntimeError("ordinary dead-counter loop lost its full optimization")


def verify_loop_counter_local_abrupt(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    got = "U_$P$TFORUNROLLLOCALABRUPT1_$$_GOT"

    for marker in (
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEGOTOREAD:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEGOTOBYPASSKILL:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEBREAKREAD:",
    ):
        body = assembly_procedure(text, marker)
        if not re.search(r"movl\s+\$1,", body):
            raise RuntimeError(
                f"local abrupt exit lost the source counter value: {marker}"
            )
        if re.search(r"movl\s+\$100,", body):
            raise RuntimeError(
                f"local abrupt exit exposed the reversed counter value: {marker}"
            )

    for marker in (
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEGOTOKILLED:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEBREAKKILLED:",
    ):
        body = assembly_procedure(text, marker)
        if not re.search(rf"movl\s+\$9,{re.escape(got)}", body):
            raise RuntimeError(f"local kill was not preserved: {marker}")
        if re.search(rf"movl\s+\$(?:1|100),{re.escape(got)}", body):
            raise RuntimeError(
                f"dead abrupt counter state reached the observable result: {marker}"
            )

    for marker in (
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBENESTEDBREAK:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBEINTERNALGOTO:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBENESTEDWHILEBREAKDEADNONLOCAL$BOOLEAN$BOOLEAN:",
        "P$TFORUNROLLLOCALABRUPT1_$$_PROBENESTEDREPEATBREAKDEADNONLOCAL$BOOLEAN$BOOLEAN:",
    ):
        body = assembly_procedure(text, marker)
        if not re.search(r"movl\s+\$100,", body):
            raise RuntimeError(
                f"an internal/nested transfer unnecessarily disabled loop reversal: {marker}"
            )

    body = assembly_procedure(
        text, "P$TFORUNROLLLOCALABRUPT1_$$_PROBEEXITFINALLY:"
    )
    location = re.search(
        r"# Var Index located at (r(?:bp|sp|cx))([+-]\d+), size=OS_S32", body
    )
    if not location:
        raise RuntimeError("cannot resolve the procedure-exit counter slot")
    register, displacement = location.groups()
    normalized_displacement = int(displacement)
    operand = (
        rf"(?:0)?\(%{register}\)"
        if normalized_displacement == 0
        else re.escape(f"{normalized_displacement}(%{register})")
    )
    if not re.search(rf"movl\s+\$1,{operand}", body):
        raise RuntimeError("procedure exit lost the counter observed by its finalizer")
    if re.search(rf"movl\s+\$100,{operand}", body):
        raise RuntimeError("procedure exit exposed a reversed counter to its finalizer")


def verify_late_phase_unrolling(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    sink = "call\tP$TFORUNROLLLATEPHASE1_$$_SINK$LONGINT"
    for marker, calls in (
        ("P$TFORUNROLLLATEPHASE1_$$_PLAIN:", 3),
        ("P$TFORUNROLLLATEPHASE1_$$_TRIPLENESTED:", 8),
        ("P$TFORUNROLLLATEPHASE1_$$_ARRAYITERATION:", 3),
        ("P$TFORUNROLLLATEPHASE1_$$_PACKARRAY:", 3),
        ("P$TFORUNROLLLATEPHASE1_$$_ENUMITERATION:", 3),
        ("P$TFORUNROLLLATEPHASE1_$$_LEXICALOPTIMIZERSTATE:", 3),
    ):
        body = assembly_procedure(text, marker)
        if body.count(sink) != calls:
            raise RuntimeError(
                f"late/generated loop was not fully unrolled ({calls} calls): {marker}"
            )
        if re.search(r"\tj(?!mp)[a-z]+\t", body):
            raise RuntimeError(f"late/generated loop retained a branch: {marker}")
    counter_store = re.compile(r"movl\s+\$[123],-?\d+\(%r(?:bp|sp|cx)\)")
    for marker in (
        "P$TFORUNROLLLATEPHASE1_$$_WRITEONLYFINALLY:",
        "P$TFORUNROLLLATEPHASE1_$$_WRITEBEFOREREADFINALLY:",
    ):
        if counter_store.search(assembly_procedure(text, marker)):
            raise RuntimeError(f"dead finalizer counter state was materialized: {marker}")


def verify_loop_invariant_address(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    start_marker = "P$TLOOPINVARIANTADDR1$_$TWORKER_$__$$_BUMP$LONGINT:"
    start = text.find(start_marker)
    end = text.find(".section", start + len(start_marker))
    if start < 0 or end < 0:
        raise RuntimeError("cannot isolate the invariant-address Bump procedure")
    body = text[start:end]
    loop_start = body.find("Inc(Counters[Index].Value);")
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

    local_exit = assembly_procedure(
        text,
        "P$TDELPHIINLINEEXCEPTREG1_$$_CALLERFINALLYAROUNDLOCALEXIT$LONGINT$$LONGINT:",
    )
    if "_FPC_local_unwind" in local_exit:
        raise RuntimeError(
            "an Exit local to an inlined block still unwinds the caller's finally"
        )
    if ".seh_handler __FPC_specific_handler,@unwind" not in local_exit:
        raise RuntimeError("the caller's real finally handler disappeared")

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
    for marker in (
        "P$TDELPHIINLINEFUNCRETTEMP1_$$_SUMSTRINGHIGHS$TSTRSTORE$$INT64:",
        "P$TDELPHIINLINEFUNCRETTEMP1_$$_SUMARRAYHIGHS$TARRSTORE$$INT64:",
    ):
        metadata = assembly_procedure(text, marker)
        if "fpc_unicodestr_assign" in metadata or "fpc_dynarray_assign" in metadata:
            raise RuntimeError(
                f"read-only High consumption still copies a managed result: {marker}"
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
    escaping = assembly_procedure(
        text,
        "P$TDELPHIINLINEFUNCRETTEMP1_$$_CHECKESCAPINGBORROWEDRESULTS:",
    )
    for requirement in ("fpc_unicodestr_assign", "fpc_dynarray_assign"):
        if requirement not in escaping:
            raise RuntimeError(
                f"an escaping borrowed result lost ownership: {requirement}"
            )


def verify_inline_out_registers(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker in (
        "P$TINLINEOUTREG1_$$_TESTOUT$LONGINT$$QWORD:",
        "P$TINLINEOUTREG1_$$_TESTVAR$LONGINT$$QWORD:",
    ):
        body = assembly_procedure(text, marker)
        loop_start = body.find("NextOut(I,A,B);")
        if loop_start < 0:
            loop_start = body.find("NextVar(I,A,B);")
        loop_end = body.find("Result:=Result+UInt32(A xor B);", loop_start)
        if loop_start < 0 or loop_end < 0:
            raise RuntimeError(f"cannot isolate inline out/var loop: {marker}")
        loop = body[loop_start:loop_end]
        if re.search(r"(?:mov|add|xor|lea)l\s+[^\n]*\d+\(%rsp\)", loop):
            raise RuntimeError(f"inline out/var local still uses a stack slot: {marker}")


def verify_generic_type_fork_inline(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    callers = re.findall(r"^(P\$TGENERICTYPEFORKINLINE1_\$\$_USE[A-Z]+\$\S*):$", text, re.MULTILINE)
    if len(callers) != 6:
        raise RuntimeError(f"expected six Use* callers of the type forks, found {len(callers)}")
    for caller in callers:
        body = assembly_procedure(text, f"{caller}:")
        if re.search(r"\tcall\t\S*_\$\$_(?:EQCASE|EQIF|EQMANAGED|CASE[123]|IF[123]|MANAGED[123])\$", body):
            raise RuntimeError(f"a type fork of the specialization stayed a call: {caller}")


def verify_checked_inline_constants(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    main = assembly_procedure(text, "PASCALMAIN:")
    start = main.find("If AddOne(40) <> 41 then")
    end = main.find("If Seen <> 4 then", start)
    if start < 0 or end < 0:
        raise RuntimeError("cannot isolate safe checked-inline constants")
    safe = main[start:end]
    if "FPC_OVERFLOW" in safe:
        raise RuntimeError("safe checked-inline constant still calls FPC_OVERFLOW")
    for value in (41, 42):
        if f"${value}" not in safe:
            raise RuntimeError(f"safe checked-inline result {value} was not folded")


def verify_inline_managed_forwarding(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace").lower()
    forwarding = assembly_procedure(
        text,
        "p$tinlinefallbackbyref1_$$_checkmanagedforwarding$unicodestring$ansistring$tintarray$iunknown$$int64:",
    )
    if "call\tp$tinlinefallbackbyref1_$$_forwardmanagedparameters" in forwarding:
        raise RuntimeError("non-owning managed parameter forwarding was not inlined")
    if "call\tp$tinlinefallbackbyref1_$$_consumemanagedparameters" not in forwarding:
        raise RuntimeError("inlined managed forwarding lost its destination call")

    refusal = assembly_procedure(
        text,
        "p$tinlinefallbackbyref1_$$_checkmanagedrefusal$$longint:",
    )
    if refusal.count(
        "call\tp$tinlinefallbackbyref1_$$_updatewithmanagedexpression$longint"
    ) != 4:
        raise RuntimeError("owned managed results no longer preserve the real call boundary")

    owned = assembly_procedure(
        text,
        "p$tinlinefallbackbyref1_$$_checkownedactuals$$longint:",
    )
    for marker in (
        "call\tp$tinlinefallbackbyref1_$$_forwardownedstring$longint",
        "call\tp$tinlinefallbackbyref1_$$_forwardownedarray",
        "call\tp$tinlinefallbackbyref1_$$_forwardownedinterface$boolean",
    ):
        if owned.count(marker) != 1:
            raise RuntimeError(
                "managed producer below a call parameter lost its real call boundary: "
                + marker
            )

    exceptional = assembly_procedure(
        text,
        "p$tinlinefallbackbyref1_$$_checkownedexception:",
    )
    if exceptional.count(
        "call\tp$tinlinefallbackbyref1_$$_forwardownedinterface$boolean"
    ) != 1:
        raise RuntimeError(
            "exceptional managed producer below a call parameter lost its call boundary"
        )


def verify_observable_intrinsics(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    atomic_discard = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_ATOMICDISCARD$$LONGINT:",
    )
    if atomic_discard.count("\tlock") != 1 or atomic_discard.count("\txadd") != 1:
        raise RuntimeError("discarded atomic expression lost or duplicated its update")
    atomic_pair = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_ATOMICPAIR$$LONGINT:",
    )
    if atomic_pair.count("\tlock") != 2 or atomic_pair.count("\txadd") != 2:
        raise RuntimeError("repeated atomic expression was folded or duplicated incorrectly")
    volatile_discard = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_VOLATILEDISCARD$$LONGINT:",
    )
    if not re.search(r"\tmov[a-z]*\t[^\n]*_\$\$_COUNTER", volatile_discard):
        raise RuntimeError("discarded volatile expression lost its memory read")
    # The root of an ordinary constant met after inlining is folded, exact or
    # not (its value in the product FP state is the run-time one); the root of
    # a negative constant stays a run-time sqrt with its invalid operation.
    for marker in (
        "P$TOBSERVABLEINTRINSICS1_$$_EXACTROOT$$DOUBLE:",
        "P$TOBSERVABLEINTRINSICS1_$$_EXACTSUBUNITROOT$$DOUBLE:",
        "P$TOBSERVABLEINTRINSICS1_$$_IRRATIONALROOT$$DOUBLE:",
    ):
        if "sqrt" in assembly_procedure(text, marker).lower():
            raise RuntimeError(f"root of an ordinary constant was not folded: {marker}")
    deferred = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_DEFERREDROOT$BOOLEAN:",
    )
    if "sqrt" not in deferred.lower():
        raise RuntimeError("root of a negative constant was folded")
    exact_single = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_EXACTSINGLE$$SINGLE:",
    )
    if "cvtsd2ss" in exact_single.lower():
        raise RuntimeError("exact quiet Double-to-Single conversion was not folded")
    rounding_sensitive_single = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_ROUNDINGSENSITIVESINGLE$$SINGLE:",
    )
    if "cvtsd2ss" in rounding_sensitive_single.lower():
        raise RuntimeError("inexact Double-to-Single conversion of an ordinary constant was not folded")
    exact_double = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_EXACTDOUBLE$$DOUBLE:",
    )
    if "cvtss2sd" in exact_double.lower():
        raise RuntimeError("exact quiet Single-to-Double conversion was not folded")
    subnormal_double = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_SUBNORMALSINGLETODOUBLE$$DOUBLE:",
    )
    if "cvtss2sd" not in subnormal_double.lower():
        raise RuntimeError("DAZ-sensitive Single-to-Double conversion was folded")
    for marker, required in (
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEMINDOUBLE$DOUBLE$DOUBLE$$DOUBLE:", "minsd"),
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEMAXDOUBLE$DOUBLE$DOUBLE$$DOUBLE:", "maxsd"),
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEMINSINGLE$SINGLE$SINGLE$$SINGLE:", "minss"),
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEMAXSINGLE$SINGLE$SINGLE$$SINGLE:", "maxss"),
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEFIELDMIN$PDOUBLEPAIR$DOUBLE$$DOUBLE:", "minsd"),
        ("P$TOBSERVABLEINTRINSICS1_$$_RUNTIMEFIELDMAX$PDOUBLEPAIR$DOUBLE$$DOUBLE:", "maxsd"),
    ):
        body = assembly_procedure(text, marker).lower()
        if required not in body:
            raise RuntimeError(f"pure floating Min/Max lost {required}: {marker}")
        if "call" in body:
            raise RuntimeError(f"pure floating Min/Max gained a helper call: {marker}")
    for marker, required in (
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATEOBJECTFIELDMIN$TDOUBLEHOLDER$DOUBLE:", "minsd"),
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATEOBJECTFIELDMAX$TDOUBLEHOLDER$DOUBLE:", "maxsd"),
    ):
        body = assembly_procedure(text, marker).lower()
        if required not in body or "comisd" in body:
            raise RuntimeError(f"stable floating field update lost {required}: {marker}")
        if "call" in body:
            raise RuntimeError(f"stable floating field update gained a helper call: {marker}")
    effectful = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_UPDATEOBJECTFIELDEFFECTFUL$TDOUBLEHOLDER:",
    ).lower()
    if effectful.count("call\tp$tobservableintrinsics1_$$_nextobserveddouble$$double") != 2:
        raise RuntimeError("effectful floating field update changed evaluation count")
    # Integer operands that can raise (array element, pointer target, class
    # field): the comparison evaluates them in both forms, so the update is a
    # min/max.  The exception has to stay: the range check of the element, the
    # load through the possibly nil pointer.
    for marker, checked in (
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATEELEMENTMIN$TDISTANCES$LONGINT$LONGWORD:", True),
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATEELEMENTMAX$TWIDEDISTANCES$LONGINT$INT64:", True),
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATETARGETMIN$PLONGINT$LONGINT:", False),
        ("P$TOBSERVABLEINTRINSICS1_$$_UPDATEINTEGERFIELDMAX$TINTEGERHOLDER$LONGINT:", False),
    ):
        body = assembly_procedure(text, marker).lower()
        if "\tcmov" not in body:
            raise RuntimeError(f"integer update through a raising operand lost cmov: {marker}")
        if checked:
            if "call\tfpc_rangeerror" not in body:
                raise RuntimeError(f"integer element update lost its range check: {marker}")
        elif re.search(r"\tj[a-z]+\t", body):
            raise RuntimeError(f"integer update through a raising operand branches: {marker}")
    effectful_integer = assembly_procedure(
        text,
        "P$TOBSERVABLEINTRINSICS1_$$_UPDATEELEMENTEFFECTFUL$TDISTANCES$LONGINT:",
    ).lower()
    if effectful_integer.count(
        "call\tp$tobservableintrinsics1_$$_nextobservedinteger$$longint"
    ) != 2:
        raise RuntimeError("effectful integer element update changed evaluation count")


def verify_dynarray_setlength_route(assembly: Path) -> None:
    """SetLength calls the transactional RTL routine exactly for record-like managed elements."""
    text = assembly.read_text(encoding="utf-8", errors="replace")
    expected = {
        "SETDOUBLES": "plain",
        "SETSTRINGS": "plain",
        "SETPLAINRECORDS": "plain",
        "SETMANAGEDRECORDS": "record",
        "SETSTRINGPAIRS": "record",
        "SETNESTEDRECORDS": "plain",
        "BUILDMANAGEDRECORDS": "record",
    }
    for routine, want in expected.items():
        match = re.search(
            r"^P\$TDYNARRAYSETLENGTHROUTE1_\$\$_" + routine + r"\$\S*:$", text, re.M
        )
        if not match:
            raise RuntimeError(f"cannot find {routine}")
        end = text.find(".section", match.end())
        if end < 0:
            raise RuntimeError(f"cannot isolate {routine}")
        calls = re.findall(
            r"call\s+(?:fpc_dynarray_setlength|FPC_DYNARR_SETLENGTH)(_record|_RECORD)?\b",
            text[match.end():end],
        )
        if len(calls) != 1:
            raise RuntimeError(f"{routine}: {len(calls)} SetLength calls")
        got = "record" if calls[0] else "plain"
        if got != want:
            raise RuntimeError(f"{routine} calls the {got} SetLength routine, expected {want}")


def verify_short_bool_prune(assembly: Path) -> None:
    """A constant-false left operand removes the arm, not only the jump into it."""
    text = assembly.read_text(encoding="utf-8", errors="replace")
    expected = {
        "LONGINT": {"ORDINALARM", "GENERICARM"},
        "UNICODESTRING": {"STRINGARM", "GENERICARM"},
        "DOUBLE": {"GENERICARM"},
    }
    seen = set()
    for match in re.finditer(
        r"^P\$TSHORTBOOLPRUNE1\$_\$TBOX\S*_PICK\$(\w+)\$\$LONGINT:$", text, re.M
    ):
        kind = match.group(1)
        end = text.find(".section", match.end())
        if end < 0:
            raise RuntimeError(f"cannot isolate TBox<{kind}>.Pick")
        arms = set(
            re.findall(
                r"(?:call|jmp)\s+P\$TSHORTBOOLPRUNE1_\$\$_(\w+ARM)\b",
                text[match.end():end],
            )
        )
        if kind in expected and arms != expected[kind]:
            raise RuntimeError(
                f"TBox<{kind}>.Pick keeps arms {sorted(arms)}, expected {sorted(expected[kind])}"
            )
        seen.add(kind)
    if seen != set(expected):
        raise RuntimeError(f"TBox.Pick specializations found: {sorted(seen)}")
    for marker in (
        "P$TSHORTBOOLPRUNE1_$$_SHORTANDCALL$$LONGINT:",
        "P$TSHORTBOOLPRUNE1_$$_SHORTORCALL$$LONGINT:",
    ):
        if "_$$_TOUCH$$BOOLEAN" in assembly_procedure(text, marker):
            raise RuntimeError(f"never evaluated call survived: {marker}")
    for marker in (
        "P$TSHORTBOOLPRUNE1_$$_COMPLETEANDCALL$$LONGINT:",
        "P$TSHORTBOOLPRUNE1_$$_COMPLETEORCALL$$LONGINT:",
    ):
        if assembly_procedure(text, marker).count("_$$_TOUCH$$BOOLEAN") != 1:
            raise RuntimeError(f"complete evaluation lost or repeated its call: {marker}")


def verify_string_cow_fastpath(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker, public_helper, slow_helper in (
        (
            "P$TSTRINGCOWFASTPATH1_$$_FILLUNICODE$LONGINT$$UNICODESTRING:",
            "FPC_UNICODESTR_UNIQUE",
            "FPC_TRUELY_UNICODESTR_UNIQUE",
        ),
        (
            "P$TSTRINGCOWFASTPATH1_$$_FILLANSI$LONGINT$$ANSISTRING:",
            "FPC_ANSISTR_UNIQUE",
            "FPC_TRUELY_ANSISTR_UNIQUE",
        ),
    ):
        body = assembly_procedure(text, marker)
        if f"call\t{public_helper}" in body:
            raise RuntimeError(f"string write still calls {public_helper} on its fast path")
        if "cmpl\t$1,-12(" not in body or slow_helper not in body:
            raise RuntimeError(f"string write lost its COW guard or slow path: {marker}")


def verify_unsigned_narrow_divmod(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker in (
        "P$TUNSIGNEDNARROWDIVMOD1_$$_NARROWDIV$LONGWORD$LONGWORD$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_NARROWMOD$LONGWORD$LONGWORD$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_DIRECTEFFECTDIV$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_DIRECTEFFECTMOD$$QWORD:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "divl" not in body or "divq" in body:
            raise RuntimeError(f"zero-extended Cardinal div/mod was not narrowed: {marker}")
    for marker in (
        "P$TUNSIGNEDNARROWDIVMOD1_$$_DIRECTEFFECTDIV$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_DIRECTEFFECTMOD$$QWORD:",
    ):
        body = assembly_procedure(text, marker).lower()
        if (
            body.count("call\tp$tunsignednarrowdivmod1_$$_leftvalue$longword$$longword") != 1
            or body.count("call\tp$tunsignednarrowdivmod1_$$_rightvalue$longword$$longword") != 1
        ):
            raise RuntimeError(f"effectful Cardinal div/mod duplicated an operand: {marker}")
    for marker in (
        "P$TUNSIGNEDNARROWDIVMOD1_$$_WIDEDIV$QWORD$QWORD$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_WIDEMOD$QWORD$QWORD$$QWORD:",
        "P$TUNSIGNEDNARROWDIVMOD1_$$_SIGNEDWIDE$LONGINT$LONGINT$$INT64:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "divq" not in body:
            raise RuntimeError(f"wide or signed control lost its 64-bit division: {marker}")


def verify_unicode_char_literal_compare(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker in (
        "P$TUNICODECHARLITERALCMP1_$$_EQX$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_NEX$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_XEQ$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_XNE$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_EQNUL$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_EQSURROGATE$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_EQHIGH$UNICODESTRING$$BOOLEAN:",
        "P$TUNICODECHARLITERALCMP1_$$_EQXZERO$UNICODESTRING$$BOOLEAN:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "fpc_unicodestr_compare" in body or "call" in body:
            raise RuntimeError(f"one-code-unit Unicode comparison still calls a helper: {marker}")
        if "cmpw" not in body:
            raise RuntimeError(f"one-code-unit Unicode comparison lost its scalar compare: {marker}")
    side_effect = assembly_procedure(
        text,
        "P$TUNICODECHARLITERALCMP1_$$_EQPRODUCED$UNICODESTRING$$BOOLEAN:",
    ).lower()
    if (
        side_effect.count("call\tp$tunicodecharliteralcmp1_$$_produce") != 1
        or side_effect.count("call\tfpc_unicodestr_compare") != 1
    ):
        raise RuntimeError("side-effectful Unicode operand no longer uses one producer and one helper call")
    ansi = assembly_procedure(
        text,
        "P$TUNICODECHARLITERALCMP1_$$_EQANSI$ANSISTRING$$BOOLEAN:",
    ).lower()
    if "fpc_ansistr_to_widestr" not in ansi or "fpc_widestr_compare" not in ansi:
        raise RuntimeError("AnsiString control was unexpectedly rewritten")


def verify_swapendian_intrinsic(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker, instruction in (
        ("P$TSWAPENDIANINTRINSIC1_$$_SWAP32$LONGWORD$$LONGWORD:", "bswapl"),
        ("P$TSWAPENDIANINTRINSIC1_$$_SWAP64$QWORD$$QWORD:", "bswapq"),
        ("P$TSWAPENDIANINTRINSIC1_$$_SWAPSIGNED32$LONGINT$$LONGINT:", "bswapl"),
        ("P$TSWAPENDIANINTRINSIC1_$$_SWAPSIGNED64$INT64$$INT64:", "bswapq"),
    ):
        body = assembly_procedure(text, marker).lower()
        if body.count(instruction) != 1 or "call" in body:
            raise RuntimeError(f"SwapEndian did not lower to one {instruction}: {marker}")
    for marker in (
        "P$TSWAPENDIANINTRINSIC1_$$_CONSTANT32$$LONGWORD:",
        "P$TSWAPENDIANINTRINSIC1_$$_CONSTANT64$$QWORD:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "bswap" in body or "call" in body:
            raise RuntimeError(f"constant SwapEndian was not folded: {marker}")
    effect = assembly_procedure(
        text,
        "P$TSWAPENDIANINTRINSIC1_$$_SWAPEFFECT$$QWORD:",
    ).lower()
    if effect.count("call\tp$tswapendianintrinsic1_$$_produce$$qword") != 1 or effect.count("bswapq") != 1:
        raise RuntimeError("side-effectful SwapEndian operand is not evaluated exactly once")
    user = assembly_procedure(
        text,
        "P$TSWAPENDIANINTRINSIC1_$$_SWAPUSER$QWORD$$QWORD:",
    ).lower()
    if "call\tuswapendianname1_$$_swapendian$qword$$qword" not in user:
        raise RuntimeError("same-name user function was treated as the System intrinsic")


def verify_ordinal_intervals(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker in (
        "P$TORDINALINTERVAL1_$$_MASKINDEX$QWORD$$BYTE:",
        "P$TORDINALINTERVAL1_$$_MODINDEX$QWORD$$BYTE:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "fpc_rangeerror" in body:
            raise RuntimeError(f"proven fixed-array interval still has a range check: {marker}")
    effect = assembly_procedure(
        text,
        "P$TORDINALINTERVAL1_$$_EFFECTINDEX$QWORD$$BYTE:",
    ).lower()
    if effect.count("call\tp$tordinalinterval1_$$_produce$qword$$qword") != 1:
        raise RuntimeError("effectful masked index is not evaluated exactly once")
    if "fpc_rangeerror" in effect:
        raise RuntimeError("effectful masked index retained a redundant range check")
    for marker in (
        "P$TORDINALINTERVAL1_$$_UNSAFEMASK$QWORD$$BYTE:",
        "P$TORDINALINTERVAL1_$$_STOREDNARROWINDEX$$BYTE:",
        "P$TORDINALINTERVAL1_$$_WIDEINDEX$UINT128$$BYTE:",
    ):
        if "fpc_rangeerror" not in assembly_procedure(text, marker).lower():
            raise RuntimeError(f"required fixed-array range check disappeared: {marker}")
    dynamic = assembly_procedure(
        text,
        "P$TORDINALINTERVAL1_$$_DYNAMICINDEX$QWORD$$BYTE:",
    ).lower()
    if "fpc_dynarray_rangecheck" not in dynamic:
        raise RuntimeError("dynamic-array length check disappeared")
    for marker, instruction in (
        ("P$TORDINALINTERVAL1_$$_MASKEDFLOAT32$QWORD$$DOUBLE:", "cvtsi2sdl"),
        ("P$TORDINALINTERVAL1_$$_MASKEDFLOAT64$QWORD$$DOUBLE:", "cvtsi2sdq"),
    ):
        body = assembly_procedure(text, marker).lower()
        if instruction not in body or "btq" in body:
            raise RuntimeError(f"bounded UInt64 conversion retained its wide branch: {marker}")
    wide = assembly_procedure(
        text,
        "P$TORDINALINTERVAL1_$$_WIDEFLOAT$QWORD$$DOUBLE:",
    ).lower()
    if "btq\t$63" not in wide:
        raise RuntimeError("full UInt64 conversion lost its required unsigned path")
    checked = assembly_procedure(
        text,
        "P$TORDINALINTERVAL1_$$_CHECKEDADD$QWORD$$QWORD:",
    ).lower()
    if "fpc_overflow" not in checked:
        raise RuntimeError("Q+ overflow helper disappeared from the negative control")


def verify_call_obligations(assembly: Path) -> None:
    text = assembly.read_text(encoding="utf-8", errors="replace")
    for marker in (
        "P$TCALLOBLIGATION1_$$_PURECHECKEDLEAF$QWORD$QWORD$$QWORD:",
        "P$TCALLOBLIGATION1_$$_PROVENNARROW$QWORD$$BYTE:",
        "P$TCALLOBLIGATION1_$$_PROVENINDEX$QWORD$$BYTE:",
        "P$TCALLOBLIGATION1_$$_PROVENWIDEINDEX$QWORD$$QWORD:",
        "P$TCALLOBLIGATION1_$$_FLOATINGADD$DOUBLE$DOUBLE$$DOUBLE:",
        "P$TCALLOBLIGATION1_$$_FLOATINGMULTIPLY$DOUBLE$DOUBLE$$DOUBLE:",
        "P$TCALLOBLIGATION1_$$_FULLBYTEINDEX$BYTE$$BYTE:",
        "P$TCALLOBLIGATION1_$$_FOLDEDCHECKEDCALL$$LONGINT:",
        "P$TCALLOBLIGATION1_$$_FOLDEDFIVEARGCALL$$LONGINT:",
        "P$TCALLOBLIGATION1_$$_STACKCHECKEDLEAF$QWORD$$QWORD:",
    ):
        body = assembly_procedure(text, marker).lower()
        if "\tcall\t" in body or ".seh_proc" in body or "%rsp" in body:
            raise RuntimeError(f"call-free checked leaf retained a call frame: {marker}")
    for marker, helper in (
        ("P$TCALLOBLIGATION1_$$_CHECKEDADD$QWORD$$QWORD:", "fpc_overflow"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDNARROW$QWORD$$BYTE:", "fpc_rangeerror"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDINDEX$QWORD$$BYTE:", "fpc_rangeerror"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDBYTEINDEX$BYTE$$BYTE:", "fpc_rangeerror"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDDYNAMICINDEX$QWORD$$BYTE:", "fpc_dynarray_rangecheck"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDSTRINGINDEX$QWORD$$WIDECHAR:", "fpc_unicodestr_rangecheck"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDSUBRANGE$BYTE$$TTENTOTWENTY:", "fpc_rangeerror"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDNEGATE$INT64$$INT64:", "fpc_overflow"),
        ("P$TCALLOBLIGATION1_$$_CHECKEDABS$INT64$$INT64:", "fpc_overflow"),
    ):
        body = assembly_procedure(text, marker).lower()
        if helper not in body or ".seh_stackalloc" not in body:
            raise RuntimeError(f"real check call lost its Win64 call frame: {marker}")
    called = assembly_procedure(
        text,
        "P$TCALLOBLIGATION1_$$_CALLEDLEAF$QWORD$$QWORD:",
    ).lower()
    if "call\tp$tcallobligation1_$$_purecheckedleaf" not in called or ".seh_stackalloc" not in called:
        raise RuntimeError("real source call lost its Win64 call frame")
    expanded = assembly_procedure(
        text,
        "P$TCALLOBLIGATION1_$$_EXPANDEDREALCALL$QWORD$$QWORD:",
    ).lower()
    if "call\tp$tcallobligation1_$$_purecheckedleaf" not in expanded or ".seh_stackalloc" not in expanded:
        raise RuntimeError("call surviving an inline expansion lost its Win64 call frame")
    conversion = assembly_procedure(
        text,
        "P$TCALLOBLIGATION1_$$_CONVERTSHORTSTRING$SHORTSTRING$$RAWBYTESTRING:",
    ).lower()
    if "fpc_shortstr_to_ansistr" not in conversion or ".seh_stackalloc" not in conversion:
        raise RuntimeError("compiler-proc call rejected from inlining lost its Win64 ABI frame")


ASM_VERIFIERS = {
    "unrolled-seh": verify_unrolled_seh,
    "loop-counter-observability": verify_loop_counter_observability,
    "loop-counter-nonlocal-goto": verify_loop_counter_nonlocal_goto,
    "loop-counter-local-abrupt": verify_loop_counter_local_abrupt,
    "late-phase-unrolling": verify_late_phase_unrolling,
    "loop-invariant-address": verify_loop_invariant_address,
    "inline-exception-registers": verify_inline_exception_registers,
    "inline-funcret-temp": verify_inline_funcret_temp,
    "inline-out-registers": verify_inline_out_registers,
    "generic-type-fork-inline": verify_generic_type_fork_inline,
    "inline-managed-forwarding": verify_inline_managed_forwarding,
    "checked-inline-constants": verify_checked_inline_constants,
    "observable-intrinsics": verify_observable_intrinsics,
    "short-bool-prune": verify_short_bool_prune,
    "dynarray-setlength-route": verify_dynarray_setlength_route,
    "string-cow-fastpath": verify_string_cow_fastpath,
    "unsigned-narrow-divmod": verify_unsigned_narrow_divmod,
    "unicode-char-literal-compare": verify_unicode_char_literal_compare,
    "swapendian-intrinsic": verify_swapendian_intrinsic,
    "ordinal-intervals": verify_ordinal_intervals,
    "call-obligations": verify_call_obligations,
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
    if not compiler.is_file() or not config.is_file() or not compiler_root.is_dir():
        parser.error("compiler, config and compiler_root must exist")
    target = compiler_info(compiler, "-iTO")
    if compiler_info(compiler, "-iTP") != "x86_64" or target not in TARGETS:
        parser.error("this gate requires an x86_64-win64 or x86_64-linux compiler")
    result_root = root / "results" / "runs" / args.run_id / f"{target}-repairs"
    if result_root.exists():
        parser.error(f"run already exists: {result_root}")

    manifest = load_json(MANIFEST_PATH)
    locks = load_json(LOCKS_PATH)
    gate, inventory_digest = validate_focused_gate(
        manifest, locks, "win64-repairs"
    )
    require_retirement_only(manifest)
    cases = [
        case for case in gate["cases"]
        if case["state"] == "active" and target in case_targets(case)
    ]
    planned = planned_pairs(gate, target)
    bindings = {case["id"]: case["asm"] if target == "win64" else [] for case in cases}
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
                    timeout=int(item.get("compile_timeout_seconds", 60)),
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
            if any(binding["profile"] == profile for binding in bindings[case_id]):
                command.append("-al")
            command.append(str(source))
            compiled = (
                run(
                    command,
                    cwd=output,
                    timeout=int(item.get("compile_timeout_seconds", 60)),
                )
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
            executable = output / (source.stem + (".exe" if target == "win64" else ""))
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
        for binding in bindings[item["id"]]:
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
    rtl_units = discover_loaded_rtl_units(compiler, config, result_root)
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
    print(
        f"{target.upper()}_REPAIR_GATE_OK rows={expected_rows} "
        f"asm={sum(len(value) for value in bindings.values())}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ContractError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
