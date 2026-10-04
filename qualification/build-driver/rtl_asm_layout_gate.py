#!/usr/bin/env python3
"""Gate for the hand-laid assembler routines of the x86-64 RTL.

The compiler places nothing of a hand-written assembler block, not even its
entry, so the routines below are laid out in their source by hand under
doc/ASM_LAYOUT_RULES.md: the entry and blocks on 64-byte lines, short forms of
forward jumps written out where one assembler pass would take the long one,
loops inside a line, DS prefixes or parked blocks where a branch or a
compare/jump pair would sit on a 32-byte boundary.  A later edit of such a
routine, or a change of the assembler's encodings or jump sizes, moves every
byte behind it; nothing else would notice.

The gate builds RTL-test/semantic/asm_block_routines_semantic.dpr (it calls
every routine of the table and checks them against Pascal references) with
the toolchain under test, runs it, and checks per routine on the linked
executable:

* the entry is on a 64-byte line (rule 1);
* the number of branches and macro-fused pairs that cross or end on a 32-byte
  boundary (rule 4) does not exceed the documented ceiling; Move's two
  once-per-copy NT preparation sites are named by offset and branch below;
* the number of short loops that do not lie inside one 64-byte line (rule 2)
  does not exceed its ceiling (Move: the NT/ERMS check chain, which the loop
  finder takes for a loop and which runs once).

A jump written out as bytes (`.byte 0x77,0x72 { ja .LWordwise_Prepare }`) keeps
the displacement its author counted, whatever lands between it and its label
later.  Such jumps are found by their bytes (code_placement.written_jumps: a
.byte/db line whose first opcode is a jump; the comment has to name the
mnemonic and label), and the units holding them are compiled twice with the
recorded profile and the RTL make's own command line (as rtl_profile_gate.py
rebuilds its witnesses) - from the sources and from a copy with the mnemonics,
placed by the assembler.  Every direct jump of the two objects has to reach
the same instruction; the compiler says which written-out jumps it compiled
for this target, and they have to be the compared ones behind the marks of the
copy, one for one - a listing that leaves any code of the unit out fails naming
them, and so does a marked jump the compiler did not name
(code_placement.same_jumps; what this does not guard:
qualification/memory-manager/README.md).  Needs GNU make (rtl_profile_gate.py
finds it).

A hand-written routine has a second contract besides its layout: whatever it
does to rsp and to the callee-saved registers it pushes, it tells the unwinder
(doc/ASM_LAYOUT_RULES.md, "Unwinding hand-written frames"), or an exception
inside it hangs the program or reaches the caller with the caller's registers
wrong.  The gate checks that contract on every routine of every object the
toolchain installs and of the probe's own build (the bundled memory manager):
qualification/performance/tools/unwind_frames.py walks each routine and compares
the stack depth at every instruction with its FDE (Linux) or UNWIND_INFO (Win64).
Only the routines of UNWIND_ALLOWED are let through, each for its own reason.
Before that it compiles qualification/performance/tools/unwind_fixture.pas and
requires the check to report every Bad* routine of the fixture and no Good* one
- a check that stops seeing a silent push fails here, not in a program.

Usage:
    python3 rtl_asm_layout_gate.py [--compiler PPCX64 --config FPC.CFG] [--keep] [--list]
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "qualification" / "performance" / "tools"
PROBE = ROOT / "RTL-test" / "semantic" / "asm_block_routines_semantic.dpr"
UNWIND_FIXTURE = TOOLS / "unwind_fixture.pas"
sys.path.insert(0, str(TOOLS))
import code_placement  # noqa: E402
import rtl_profile_gate  # noqa: E402
import unwind_frames  # noqa: E402

# routines the unwind check lets through, each named with its reason
UNWIND_ALLOWED = {
    # longjmp gives up its own frame on purpose: it loads rsp from the jump buffer and jumps
    r"^fpc_longjmp$": "loads rsp from the jump buffer and jumps; nothing unwinds from inside it",
    # the Linux process entry and exit stubs lie below PASCALMAIN, whose FDE marks the return
    # address undefined, so no unwind passes them; a walk starts inside them only while the
    # process starts or exits (_start has no return address at all)
    r"^SI_(C|G|PRC)_\$\$_": "process entry and exit stubs under the outermost frame",
    # MoonORMot's memory manager: runtime/mm is its byte copy, and the repair belongs to MoonORMot.
    # Its Linux paths push without CFI: LockMediumBlocks around OsAllocMedium, FreeMediumBlock
    # (rbx and the block size), _FreeMem around its call of FreeMediumBlock.  Named one by one:
    # a new silent frame of the manager fails the gate.
    r"^MORMOT\.CORE\.FPCX64MM_\$\$_(LOCKMEDIUMBLOCKS\$LONGWORD|FREEMEDIUMBLOCK\$POINTER\$POINTER"
    r"\$\$QWORD|_FREEMEM\$POINTER\$\$QWORD)$": "MoonORMot's manager, pending its repair there",
}

# routine pattern -> (rule-4 ceiling Win64, Linux, short loops off a line Win64, Linux)
ROUTINES = {
    r"^FPC_MOVE$": (0, 0, 1, 1),
    r"^SYSTEM_\$\$_COMPAREBYTE\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_COMPAREWORD\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_INDEXBYTE\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_INDEXWORD\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_FILLCHAR\$formal\$INT64\$BYTE$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_FILLWORD\$": (0, 0, 0, 0),
    r"^fpc_ansistr_assign$": (0, 0, 0, 0),
    r"^fpc_unicodestr_assign$": (0, 0, 0, 0),
    r"^fpc_ansistr_compare$": (0, 0, 0, 0),
    r"^fpc_ansistr_compare_equal$": (0, 0, 0, 0),
    r"^fpc_unicodestr_compare_equal$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_COMPAREDWORD\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_FILLDWORD\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_FILLQWORD\$": (0, 0, 0, 0),
    # the jump that reuses the loop body for the last three vectors is a second back-edge: the
    # loop finder sees a 64-byte loop across the line; the 54-byte main loop lies inside one
    r"^SYSTEM_\$\$_INDEXQWORD_SSE41\$": (0, 0, 1, 1),
    r"^STRINGS_\$\$_STRCOMP\$": (0, 0, 0, 0),
    r"^MATH_\$\$_ROUNDTO\$DOUBLE\$": (0, 0, 0, 0),
    r"^MATH_\$\$_ROUNDTO\$SINGLE\$": (0, 0, 0, 0),
    r"^MATH_\$\$_ROUNDTO\$EXTENDED\$": (0, 0, 0, 0),
    r"^SYSTEM_\$\$_SYSRELOCATETHREADVAR\$": (0, 0, 0, 0),
    r"^GENERICS\.HASHES_\$\$_CRC32CSSE42\$": (0, 0, 0, 0),
    r"^GENERICS\.HASHES_\$\$_XXHASH32\$LONGWORD": (0, 0, 0, 0),
    r"^fpc_varset_add_sets$": (0, 0, 0, 0),
    r"^fpc_varset_mul_sets$": (0, 0, 0, 0),
    r"^fpc_varset_sub_sets$": (0, 0, 0, 0),
    r"^fpc_varset_symdif_sets$": (0, 0, 0, 0),
    r"^fpc_varset_contains_sets$": (0, 0, 0, 0),
}
# the compiler answers `=` on UnicodeString with its own length check and the _content helper,
# so the probe does not always link this one; it is checked when it is there
# ... and these exist on one of the two systems only: the 80-bit Extended on Linux, the TEB walk
# of SysRelocateThreadvar on Win64.  The two hashers of Generics.Hashes are required on both: while
# FPC_PIC took out all of its assembler, the PIC-built Linux packages had neither, and the optional
# rows passed without them (crc32c skipped, xxHash32 an 8-byte jump to the Pascal routine)
OPTIONAL = {r"^fpc_unicodestr_compare_equal$", r"^MATH_\$\$_ROUNDTO\$EXTENDED\$",
            r"^SYSTEM_\$\$_SYSRELOCATETHREADVAR\$"}

ASM_SOURCES = {
    "rtl_asm_x86_64_sha256": ROOT / "rtl" / "x86_64" / "x86_64.inc",
    "rtl_asm_strings_sha256": ROOT / "rtl" / "x86_64" / "strings.inc",
    "rtl_asm_sets_sha256": ROOT / "rtl" / "x86_64" / "set.inc",
    "rtl_asm_threadvar_sha256": ROOT / "rtl" / "win" / "systhrd.inc",
    "rtl_asm_math_sha256": ROOT / "rtl" / "objpas" / "math.pp",
    "rtl_asm_sysstrings_sha256": ROOT / "rtl" / "objpas" / "sysutils" / "sysstr.inc",
    "rtl_asm_hashes_sha256": ROOT / "packages" / "rtl-generics" / "src" / "generics.hashes.pas",
    "rtl_asm_astrings_sha256": ROOT / "rtl" / "inc" / "astrings.inc",
    "rtl_asm_ustrings_sha256": ROOT / "rtl" / "inc" / "ustrings.inc",
}
# the unit a source with written-out jumps is compiled into (the main source of its RTL make line)
JUMP_UNITS = {"x86_64.inc": "system", "astrings.inc": "system", "math.pp": "math"}


def default_toolchain() -> tuple[Path | None, Path]:
    stand = os.environ.get("MOONBOT_TOOLCHAIN")
    base = Path(stand) if stand else ROOT / "toolchain"
    if os.name == "nt":
        return base / "bin" / "x86_64-win64" / "ppcx64.exe", base / "bin" / "x86_64-win64" / "moon-base.cfg"
    versions = sorted((base / "lib" / "fpc").glob("*/ppcx64"))
    return (versions[0] if len(versions) == 1 else None), base / "etc" / "moon-base.cfg"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def toolchain_profile(compiler: Path) -> Path:
    profile = next((parent / "profile.txt" for parent in compiler.parents
                    if (parent / "profile.txt").is_file()), None)
    if profile is None:
        raise RuntimeError(f"toolchain profile.txt not found above {compiler}")
    return profile


def verify_source_provenance(compiler: Path) -> None:
    profile = toolchain_profile(compiler)
    record = {}
    for raw in profile.read_text(encoding="ascii").splitlines():
        if "=" in raw:
            key, value = raw.split("=", 1)
            record[key] = value
    missing = sorted(ASM_SOURCES.keys() - record.keys())
    if missing:
        raise RuntimeError(
            f"{profile} lacks RTL ASM source provenance ({', '.join(missing)}); rebuild the toolchain")
    stale = [str(path.relative_to(ROOT)) for key, path in ASM_SOURCES.items()
             if sha256(path) != record[key]]
    if stale:
        raise RuntimeError(
            "installed RTL was built from different hand-written ASM sources: "
            + ", ".join(stale) + "; rebuild the toolchain before running the layout gate")


def build(compiler: Path, config: Path, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-n", f"@{config}", "-O3", "-gw3", f"-FE{out}", f"-FU{out}", str(PROBE)]
    # never from a directory that holds RTL sources: the compiler would try to recompile System
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600, cwd=out)
    exe = out / (PROBE.stem + (".exe" if os.name == "nt" else ""))
    if proc.returncode != 0 or not exe.is_file():
        tail = [line for line in ((proc.stdout or "") + (proc.stderr or "")).splitlines()
                if re.search(r"Error|Fatal", line)]
        raise RuntimeError("probe build failed\n" + "\n".join(tail[-20:]))
    run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=300)
    if run.returncode != 0 or "ASM_BLOCK_ROUTINES_OK" not in run.stdout:
        raise RuntimeError(f"probe run failed: exit {run.returncode}\n{run.stdout[-2000:]}{run.stderr[-500:]}")
    return exe


def compile_unit(compiler: Path, arguments: list[str], cwd: Path, units: Path, out: Path,
                 extra: list[str]) -> str:
    """One RTL make line into `out`; a unit other than System finds the installed units in a copy
    there, as the witnesses of rtl_profile_gate.py do (nothing else is recompiled)."""
    out.mkdir(parents=True)
    if "-Us" not in arguments:
        for unit in units.iterdir():
            if unit.suffix in (".ppu", ".o"):
                shutil.copy2(unit, out / unit.name)
    arguments = [f"-FE{out}" if a == "-FE." else (f"-FU{out}" if a.startswith("-FU") else a) for a in arguments]
    result = subprocess.run([str(compiler), *arguments[:-1], *extra, arguments[-1]], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8",
                            errors="replace", timeout=900)
    if result.returncode != 0:
        raise RuntimeError(f"{arguments[-1]} does not build from {cwd}:\n{result.stdout[-2000:]}")
    return result.stdout


def check_written_jumps(compiler: Path, work: Path) -> list[str]:
    """The failures of the written-out jumps against their mnemonics (module docstring); prints
    what was compared."""
    failures: list[str] = []
    try:
        profile = toolchain_profile(compiler)
        opt = rtl_profile_gate.read_record(profile)["rtl_packages_opt"][len("OPT="):].strip()
        units = rtl_profile_gate.toolchain_layout(profile.parent)[1]
        lines = rtl_profile_gate.make_lines(rtl_profile_gate.find_make(None), compiler, opt)
        cwd = ROOT / "rtl" / rtl_profile_gate.OS_DIR
        texts: dict[str, dict[Path, str]] = {}
        found: list[str] = []
        unnamed = 0
        for path in ASM_SOURCES.values():
            text, written, problems = code_placement.written_jumps(
                path.read_bytes().decode("utf-8", "surrogateescape"), path.name)
            failures += problems
            unnamed += len(problems)
            if written and path.name not in JUMP_UNITS:
                failures.append(f"{path.relative_to(ROOT)}: written-out jumps, and no unit is rebuilt for them "
                                "(JUMP_UNITS)")
            elif written:
                texts.setdefault(JUMP_UNITS[path.name], {})[path] = text
                found += written
        print(f"written-out jumps: {len(found) + unnamed} found by their bytes, "
              f"{len(found)}/{len(found) + unnamed} with the mnemonic and label of their comment")
        compiled: set[str] = set()
        unbuilt: set[str] = set()
        for unit, symbolic in sorted(texts.items()):
            line = next((line for line in lines if re.search(rf"[/ ]{unit}\.pp$", line)), None)
            if line is None:
                failures.append(f"the RTL make compiles no {unit}.pp")
                continue
            arguments = line.split()[1:]
            # every unit on its own: a unit over System does not build when System's sources are newer
            # than the installed units, and that must not hide a moved jump of System itself
            try:
                # the copy: every directory the line reads, the sources of this unit as mnemonics
                tree = work / unit / "tree"
                for directory in {cwd, (cwd / arguments[-1]).parent,
                                  *(cwd / a[3:] for a in arguments if a.startswith(("-Fi", "-Fu")))}:
                    if not directory.is_dir():
                        continue
                    copy = tree / directory.resolve().relative_to(ROOT)
                    copy.mkdir(parents=True, exist_ok=True)
                    for source in directory.iterdir():
                        if source.is_file():
                            shutil.copy2(source, copy / source.name)
                for path, text in symbolic.items():
                    (tree / path.relative_to(ROOT)).write_bytes(text.encode("utf-8", "surrogateescape"))
                compile_unit(compiler, arguments, cwd, units, work / unit / "written", [])
                output = compile_unit(compiler, arguments, tree / cwd.relative_to(ROOT), units,
                                      work / unit / "symbolic", ["-vi"])
                here = code_placement.compiled_written_jumps(output)
                compiled |= here
                count, wrong = code_placement.same_jumps(work / unit / "written" / f"{unit}.o",
                                                         work / unit / "symbolic" / f"{unit}.o", here)
            except (RuntimeError, OSError, ValueError) as error:
                failures.append(f"{unit}: {error}")
                unbuilt |= {path.name for path in symbolic}
                continue
            print(f"  {unit}.o: {count} jumps compared, {len(here)} of them written out")
            failures += [f"{unit}: written-out jump off its label: {one}" for one in wrong]
        rest = [where for where in found if where not in compiled and where.split(":")[0] not in unbuilt]
        if rest:
            print(f"  not compiled for this target: {', '.join(rest)}")
    except (RuntimeError, OSError, ValueError, rtl_profile_gate.GateError) as error:
        failures.append(f"written-out jumps: {error}")
    return failures


def unwind_tools(compiler: Path) -> tuple[Path, str]:
    """(the toolchain's unit directory, the objdump that reads its objects).  On Win64 the
    toolchain's own binutils: newer ones refuse FPC's COFF relocations of type 0."""
    profile = toolchain_profile(compiler)
    units = rtl_profile_gate.toolchain_layout(profile.parent)[1].parent
    if os.environ.get("MOON_OBJDUMP"):
        return units, os.environ["MOON_OBJDUMP"]
    if os.name == "nt":
        return units, str(compiler.parent / "objdump.exe")
    return units, "objdump"


def check_unwind(compiler: Path, config: Path, probe_dir: Path, work: Path) -> list[str]:
    """The unwind contract of every routine of the toolchain and of the probe's build, after the
    fixture shows the check sees what it has to (module docstring)."""
    failures: list[str] = []
    try:
        units, objdump = unwind_tools(compiler)
        os.environ["OBJDUMP"] = objdump
        fixture = work / "unwind-fixture"
        fixture.mkdir(parents=True)
        result = subprocess.run([str(compiler), "-n", f"@{config}", "-O3", f"-FE{fixture}", f"-FU{fixture}",
                                 str(UNWIND_FIXTURE)], capture_output=True, text=True, timeout=300, cwd=fixture)
        objects = sorted(fixture.glob("unwind_fixture.o"))
        if result.returncode != 0 or not objects:
            return [f"the unwind fixture does not build:\n{(result.stdout + result.stderr)[-2000:]}"]
        reported, _, _, _ = unwind_frames.scan([str(o) for o in objects], [], 1)
        named = {line.split(": ", 2)[1].rsplit("_$$_", 1)[-1] for line in reported if not line.startswith("ERROR")}
        bad = {"BADPUSHSILENT", "BADALLOCSILENT", "BADPUSHEARLY"} | ({"BADPUSHUNTOLD"} if os.name != "nt" else set())
        good = {"GOODLEAF", "GOODPUSH", "GOODALLOC", "GOODPUSHATT"}
        missed, wrong = sorted(bad - named), sorted(good & named)
        print(f"unwind fixture: {len(bad) - len(missed)}/{len(bad)} silent frames reported, "
              f"{len(wrong)} of {len(good)} described ones taken for silent")
        if missed or wrong or any(line.startswith("ERROR") for line in reported):
            failures.append(f"the unwind check is blind on its fixture: missed {missed}, wrong {wrong}; "
                            + "; ".join(reported))
            return failures
        # the probe's own objects only: the unit rebuilds and the fixture lie in directories below
        probe_objects = [str(o) for o in sorted(probe_dir.glob("*.o"))]
        failing, excused, count, epilogues = unwind_frames.scan([str(units), *probe_objects],
                                                                 list(UNWIND_ALLOWED), os.cpu_count() or 1)
        print(f"unwind: {count} objects, {len(excused)} routines let through by name, {epilogues} with only "
              f"an epilogue the CFI does not follow (the compiler's own, Linux), {len(failing)} reported")
        for line in excused:
            print(f"  let through: {line[:150]}")
        failures += [f"unwind: {line}" for line in failing]
    except (RuntimeError, OSError, ValueError, rtl_profile_gate.GateError) as error:
        failures.append(f"unwind: {error}")
    return failures


# The accepted 60-byte NT loop is wholly inside its aligned line. Its one-time
# alignment test/pad jump cross/end on 32 bytes after the count-bias instruction.
# These are not loop branches. Keep their exact identities instead of allowing
# two arbitrary new rule-4 violations anywhere in Move.
RULE4_SITES = {"FPC_MOVE": {(2145, "je"), (2174, "jmp")}}


def documented_rule4_site(name: str, begin: int, line: str) -> bool:
    if not line.startswith("R4: "):
        return False
    routine, address, _, _, branch = ast.literal_eval(line[4:])
    return routine == name and (address - begin, branch) in RULE4_SITES.get(name, set())


def check(exe: Path, pattern: str) -> tuple[int, int, int, list[str]]:
    """(branches, rule-4 sites, short loops off a line, listed violations) of the routines matching."""
    result = subprocess.run([sys.executable, str(TOOLS / "check_placement_rules.py"), str(exe),
                             "--match", pattern, "--list-violations"],
                            capture_output=True, text=True, timeout=300)
    out = result.stdout
    if result.returncode:
        raise RuntimeError(f"placement checker failed for {pattern}: exit={result.returncode}\n"
                           + result.stderr[-1500:])
    r4 = re.search(r"R4 branches: (\d+), crossing/ending on 32B: (\d+)", out)
    r2 = re.search(r"R2 short loops \(<=64B\): (\d+), not inside one 64B line: (\d+)", out)
    if not r4 or not r2:
        raise RuntimeError(f"cannot read the checker's report for {pattern}:\n{out[-1500:]}")
    listed = [line.strip() for line in out.splitlines() if re.match(r"\s+(R4|R2):", line)]
    return int(r4.group(1)), int(r4.group(2)), int(r2.group(2)), listed


def main() -> int:
    compiler, config = default_toolchain()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", type=Path, default=compiler)
    ap.add_argument("--config", type=Path, default=config)
    ap.add_argument("--keep", action="store_true", help="keep the build directory")
    ap.add_argument("--list", action="store_true", help="print every violation")
    args = ap.parse_args()
    if args.compiler is None:
        raise SystemExit("cannot uniquely locate ppcx64 in the toolchain; pass --compiler")

    column = 0 if os.name == "nt" else 1
    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="rtl_asm_layout_gate_"))
    try:
        # judged from the sources: a moved jump is named on an older toolchain too
        failures += check_written_jumps(args.compiler.resolve(), tmp / "written-jumps")
        verify_source_provenance(args.compiler.resolve())
        exe = build(args.compiler.resolve(), args.config.resolve(), tmp)
        failures += check_unwind(args.compiler.resolve(), args.config.resolve(), tmp, tmp / "unwind")
        procedures = code_placement.procedures(exe)
        print(f"# {exe}")
        print("routine                              entry  size  branches  rule4/max  loops-off-line/max")
        for pattern, ceilings in ROUTINES.items():
            r4_max, r2_max = ceilings[column], ceilings[2 + column]
            found = [(n, b, e) for n, b, e in procedures if re.search(pattern, n)]
            if not found and pattern in OPTIONAL:
                print(f"{pattern:36s} not linked into the probe, skipped")
                continue
            if len(found) != 1:
                failures.append(f"{pattern}: {len(found)} procedures match (the probe must link exactly one)")
                continue
            name, begin, end = found[0]
            short = name.split("$$_")[-1].split("$")[0]
            branches, r4, r2, listed = check(exe, pattern)
            named_r4 = sum(documented_rule4_site(name, begin, line) for line in listed)
            print(f"{short:36s} @{begin % 64:2d} {end - begin:6d} {branches:9d} {r4:6d}/{r4_max + named_r4:<3d} {r2:12d}/{r2_max}")
            if begin % 64 != 0:
                failures.append(f"{short}: entry on byte {begin % 64} of a 64-byte line (rule 1)")
            if r4 - named_r4 > r4_max:
                failures.append(f"{short}: {r4} branches on a 32-byte boundary, {r4_max + named_r4} documented (rule 4)")
            if r2 > r2_max:
                failures.append(f"{short}: {r2} short loops not inside one 64-byte line, {r2_max} documented (rule 2)")
            if args.list or r4 > r4_max or r2 > r2_max:
                for line in listed:
                    print("    " + line)
    except Exception as exc:  # noqa: BLE001 - reported as a gate failure
        failures.append(str(exc))
    finally:
        if args.keep:
            print(f"build directory kept: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print(f"RTL ASM LAYOUT GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("RTL ASM LAYOUT GATE: PASS (entries on 64-byte lines, rule-4 sites and loops within the documented ceilings, "
          "written-out jumps on their labels)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
