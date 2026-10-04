#!/usr/bin/env python3
"""Fast native x86-64 gate for spilled values kept in registers across the
outermost call-free loop and the orientation of memory compares inside
loops."""

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
TESTS = ROOT / "tests" / "test" / "cg"
PROMOTE = TESTS / "tloopregvarpromote1.pp"
ORIENT = TESTS / "tloopcompareorient1.pp"

# (routine, source text inside a call-free loop which accesses no frame slot)
REGISTER_LOOPS = (
    ("HASHREQUESTS", "Hash := (Hash xor Payload^) * Prime;"),
    ("BREAKANDCONTINUE", "Inc(S, I);"),
    ("NESTEDINNER", "Inc(I);"),
    ("REPEATNARROW", "W := W xor (B shl 3);"),
    ("PARAMWRITTEN", "Dec(I, 2);"),
    ("DEADAFTER", "Dec(I);"),
    ("LASTINBODY", "Inc(S, I);"),
    ("LASTINBODY", "S := S + I * 3;"),
    ("REPEATFALSE", "Dec(I);"),
    ("FORSTEP", "Inc(S, K);"),
    ("FORSTEPCONTINUE", "Inc(S, K * J);"),
    ("INREGISTERALREADY", "T := T xor (S shl 1);"),
    ("SPILLEDINVARIANT", "S := S * 31 + UInt64(K);"),
    ("WRITEEVERYITERATION", "Last := K * 3 + Records[K];"),
)
# (routine, statistic, least, most) of its line LOOPSPILL (WP4_LOOPSPILL_STATS)
LOOP_STATS = (
    ("HASHREQUESTS", "helpers", 2, None),
    ("SPILLEDINVARIANT", "helpers", 1, None),
    ("INREGISTERALREADY", "helpers", 0, 0),
    ("TOPLEVEL", "helpers", 0, 0),
    ("MANAGEDINNER", "regions", 0, 0),
    ("EXITINNER", "regions", 0, 0),
    ("WRITETHENBREAK", "helpers", 0, 0),
    ("WRITETHENBREAK", "exitonly", 1, 1),
    ("WRITEEVERYITERATION", "helpers", 1, 1),
)
# routine: source text inside a loop region without spilled values, whose
# entry must stay as it was
UNCHANGED = {
    "INREGISTERALREADY": "T := T xor (S shl 1);",
    "TOPLEVEL": "Inc(S, I * I);",
}
# routines whose loop compare must load the loop-invariant operand
ORIENTED = (
    "COUNTSIGNEDLT", "COUNTSIGNEDLE", "COUNTSIGNEDGT", "COUNTSIGNEDGE",
    "COUNTUNSIGNEDLT", "COUNTUNSIGNEDLE", "COUNTUNSIGNEDGT",
    "COUNTUNSIGNEDGE", "COUNTEQUAL", "COUNTNOTEQUAL", "COUNTBYTEGT",
    "COUNTSHORTINTLT", "COUNTWORDGE", "COUNTSMALLINTLE", "COUNTINT64LT",
    "COUNTUINT64GT", "COUNTINVARIANTLEFT", "INSERTPOSITION",
)

STACK = re.compile(r"(-?\d*)\(%(?:rbp|rsp)\)")
FRAME = re.compile(r"\(%(?:rbp|rsp)[,)]")
LOOPSPILL = re.compile(r"^LOOPSPILL proc=(\S+) regions=(\d+) helpers=(\d+) "
                       r"refused=(\d+) nobudget=(\d+)(?: exitonly=(\d+))?", re.M)
MEMORY = re.compile(r"-?\w*\(%(\w+)(?:,%\w+(?:,\d)?)?\)")
READ_ONLY = ("cmp", "test", "bt", "ucomis", "comis")
PURE_WRITE = ("mov", "lea", "set", "pop")


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / "toolchain/bin/x86_64-win64/ppcx64.exe"
    return ROOT / "toolchain/bin/ppcx64"


def default_rtl() -> Path:
    target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
    return ROOT / "rtl" / "units" / target


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


def build_and_run(compiler: Path, rtl: Path, source: Path, level: str,
                  compiler_options: list[str],
                  outdir: Path) -> tuple[str, str]:
    target = outdir / f"{source.stem}-{level}"
    target.mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-Mdelphi", "-n", f"-{level}", "-al", "-Aas",
           "-dMOONCOMPILER_VANILLA_RUNTIME", "-dWP4_LOOPSPILL_STATS",
           f"-Fu{rtl}", f"-FE{target}", f"-FU{target}", *link_args(),
           *compiler_options, str(source)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    exe = target / (source.stem + (".exe" if os.name == "nt" else ""))
    asm = target / (source.stem + ".s")
    if proc.returncode != 0 or not exe.is_file() or not asm.is_file():
        raise RuntimeError(f"{source.name} -{level}: compile failed\n"
                           f"{(proc.stdout + proc.stderr)[-3000:]}")
    run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    if run.returncode != 0:
        raise RuntimeError(f"{source.name} -{level}: exit code {run.returncode}")
    return (asm.read_text(encoding="utf-8", errors="replace"),
            proc.stdout + proc.stderr)


def routine(asm: str, name: str) -> list[str]:
    lines = asm.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if re.match(rf"^P\$\w+_\$\$_{name}(\$|:)", line)), None)
    if start is None:
        raise RuntimeError(f"cannot find routine {name}")
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith(".section")), len(lines))
    return lines[start:end]


def instruction(line: str) -> tuple[str, list[str]] | None:
    match = re.match(r"^\t([a-z][a-z0-9]*)\s*(.*)$", line)
    if not match:
        return None
    operands, depth, part = [], 0, ""
    for ch in match[2]:
        if ch == "," and depth == 0:
            operands.append(part.strip())
            part = ""
            continue
        depth += (ch == "(") - (ch == ")")
        part += ch
    if part.strip():
        operands.append(part.strip())
    return match[1], operands


def label_at(line: str) -> str | None:
    match = re.match(r"^(\.L\w+):", line)
    return match[1] if match else None


def jump_target(line: str) -> str | None:
    ins = instruction(line)
    if ins and ins[0].startswith("j") and ins[1] and ins[1][0].startswith(".L"):
        return ins[1][0]
    return None


def loops(lines: list[str]) -> list[tuple[int, int]]:
    labels = {label_at(line): i for i, line in enumerate(lines) if label_at(line)}
    found = []
    for i, line in enumerate(lines):
        target = jump_target(line)
        if target in labels and labels[target] < i:
            found.append((labels[target], i))
    return found


def loop_containing(lines: list[str], text: str) -> tuple[int, int]:
    marks = [i for i, line in enumerate(lines)
             if re.match(r"^# \[\d+\] ", line) and line.split("] ", 1)[1].strip() == text]
    if len(marks) != 1:
        raise RuntimeError(f"source line {text!r} found {len(marks)} times")
    inside = [loop for loop in loops(lines) if loop[0] < marks[0] < loop[1]]
    if not inside:
        raise RuntimeError(f"no loop around {text!r}")
    return min(inside, key=lambda loop: loop[1] - loop[0])


def frame_operands(lines: list[str], loop: tuple[int, int]) -> list[str]:
    return [line.strip() for line in lines[loop[0]:loop[1] + 1]
            if instruction(line) and FRAME.search(line)]


def loop_stats(output: str) -> dict[str, dict[str, int]]:
    """The line LOOPSPILL of every routine of the program, by routine name."""
    stats = {}
    for match in LOOPSPILL.finditer(output):
        name = re.match(r"^P\$\w+?_\$\$_(\w+?)(?:\$|$)", match[1])
        if name:
            stats[name[1]] = {
                key: int(value) for key, value in zip(
                    ("regions", "helpers", "refused", "nobudget", "exitonly"),
                    match.groups()[1:]) if value is not None}
    return stats


def entry_variables(lines: list[str], loop: tuple[int, int]) -> set[str]:
    """Variables whose location changes in the straight code which enters the
    loop: after its guard branch, before the head (skipping the jump to a
    bottom-tested condition inside the loop)."""
    names, skipped_jump = set(), False
    for i in range(loop[0] - 1, -1, -1):
        line = lines[i]
        var = re.match(r"^# Var (\S+) located in register ", line)
        if var:
            names.add(var[1])
            continue
        if line.startswith("#") or re.match(r"^\t\.", line) or not line.strip():
            continue
        if label_at(line):
            break
        ins = instruction(line)
        if ins is None:
            break
        target = jump_target(line)
        if ins[0] == "jmp" and not skipped_jump and target in {
                label_at(lines[j]) for j in range(loop[0], loop[1])}:
            skipped_jump = True
            continue
        if ins[0].startswith("j") or ins[0].startswith("call") or ins[0] == "ret":
            break
    return names


def stack_recurrence(lines: list[str], loop: tuple[int, int]) -> set[str]:
    written, read = set(), set()
    for line in lines[loop[0]:loop[1] + 1]:
        ins = instruction(line)
        if not ins or not ins[1]:
            continue
        mnemonic, operands = ins
        if mnemonic.startswith("lea"):
            continue
        for k, operand in enumerate(operands):
            slot = STACK.search(operand)
            if not slot:
                continue
            offset = slot[1] or "0"
            last = k == len(operands) - 1
            if not last or mnemonic.startswith(READ_ONLY):
                read.add(offset)
            else:
                written.add(offset)
                if not mnemonic.startswith(PURE_WRITE):
                    read.add(offset)
    return written & read


FAMILIES = {}
for n in ("ax", "bx", "cx", "dx", "si", "di", "bp", "sp"):
    FAMILIES.update({f"r{n}": f"r{n}", f"e{n}": f"r{n}", n: f"r{n}"})
for n in ("al", "bl", "cl", "dl"):
    FAMILIES[n] = f"r{n[0]}x"
FAMILIES.update({"sil": "rsi", "dil": "rdi", "bpl": "rbp", "spl": "rsp"})
for n in range(8, 16):
    for suffix in ("", "d", "w", "b"):
        FAMILIES[f"r{n}{suffix}"] = f"r{n}"


def family(register: str) -> str:
    return FAMILIES.get(register.lstrip("%"), register.lstrip("%"))


def compare_orientation(lines: list[str]) -> str | None:
    """None when every memory compare of the routine's loop loads the operand
    which the loop does not change and keeps the changing one in memory."""
    inner = min(loops(lines), key=lambda loop: loop[1] - loop[0])
    body = [instruction(line) for line in lines[inner[0]:inner[1] + 1]]
    body = [ins for ins in body if ins]
    written = {family(ins[1][-1]) for ins in body
               if ins[1] and ins[1][-1].startswith("%")
               and not ins[0].startswith(READ_ONLY)}
    compares = [k for k, ins in enumerate(body) if ins[0].startswith("cmp")
                and len(ins[1]) == 2 and MEMORY.fullmatch(ins[1][0])
                and ins[1][1].startswith("%")]
    if not compares:
        return "no memory compare in the loop"
    for k in compares:
        base = family(MEMORY.fullmatch(body[k][1][0])[1])
        register = family(body[k][1][1])
        load = next((ins for ins in reversed(body[:k])
                     if ins[1] and not ins[0].startswith(READ_ONLY)
                     and family(ins[1][-1]) == register), None)
        if base not in written:
            return f"cmp reads the loop-invariant operand from memory: {body[k]}"
        if (load is None or not load[0].startswith("mov")
                or not MEMORY.fullmatch(load[1][0])
                or family(MEMORY.fullmatch(load[1][0])[1]) in written):
            return f"compared register is not a loop-invariant load: {load}"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path)
    ap.add_argument(
        "--compiler-option", action="append", default=[],
        help="extra compiler option; repeat for multiple options")
    args = ap.parse_args()
    args.rtl = args.rtl or default_rtl()

    tmp = Path(tempfile.mkdtemp(prefix="optimizer_loop_regvar_"))
    failures: list[str] = []
    try:
        listings, outputs = {}, {}
        for source in (PROMOTE, ORIENT):
            for level in ("O-", "O2", "O3"):
                listing, output = build_and_run(
                    args.compiler, args.rtl, source, level,
                    args.compiler_option, tmp)
                listings[source.stem, level] = listing
                outputs[source.stem, level] = output
        promote = listings[PROMOTE.stem, "O3"]
        for name, text in REGISTER_LOOPS:
            lines = routine(promote, name)
            loop = loop_containing(lines, text)
            slots = stack_recurrence(lines, loop)
            if slots:
                failures.append(f"{name}: frame slots stored and loaded in "
                                f"the loop: {sorted(slots)}")
            frame = frame_operands(lines, loop)
            if frame:
                failures.append(f"{name}: frame operands in the call-free "
                                f"loop: {frame}")
        stats = loop_stats(outputs[PROMOTE.stem, "O3"])
        for name, key, least, most in LOOP_STATS:
            if key not in stats.get(name, {}):
                failures.append(f"{name}: no loop region statistics "
                                f"(LOOPSPILL {key}) from the compiler")
                continue
            value = stats[name][key]
            if value < least or (most is not None and value > most):
                expected = (f"{least}" if most == least else
                            f">= {least}" if most is None else
                            f"{least}..{most}")
                failures.append(f"{name}: {key}={value}, expected {expected}")
        for name, text in UNCHANGED.items():
            lines = routine(promote, name)
            if stats.get(name, {}).get("regions", 0) < 1:
                failures.append(f"{name}: the call-free loop is no loop region")
            moved = entry_variables(lines, loop_containing(lines, text))
            if moved:
                failures.append(f"{name}: copies at the loop entry {sorted(moved)}")
        orient = listings[ORIENT.stem, "O3"]
        for name in ORIENTED:
            problem = compare_orientation(routine(orient, name))
            if problem:
                failures.append(f"{name}: {problem}")
    except Exception as exc:
        failures.append(str(exc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"LOOP REGVAR: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print(f"LOOP REGVAR: PASS ({len(REGISTER_LOOPS)} loops without frame "
          f"operands, {len(LOOP_STATS)} region statistics, "
          f"{len(ORIENTED)} oriented compares)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
