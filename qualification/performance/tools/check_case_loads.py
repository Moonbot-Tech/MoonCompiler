#!/usr/bin/env python3
"""No case loop of a Pulse image reloads a global.

Every case body the image registers (`list all`: body= and workbody=, found
through the one PulseRunCase anchor) is disassembled from its `.pdata`/ELF
range; each loop runs from its head to its back-edge.  A load there from the
image's `.data` or `.bss` whose address is the same on every pass of its
innermost loop is reported: a global sits at a page offset fixed by the link,
and when the case's own stores hit that offset the load waits on a false
dependency - `pulse_move` reloaded ActiveSize (page offset 0x050) right after
every copy to a page start, and Zen 3 slowed its small copies by the layout of
the code behind Move (audit WP3 r4).  A value the loop needs goes to a local
before the loop.

The address comes from RIP, from an absolute displacement the ELF linker
relocated, or from a register that holds a global's address (lea of it,
mov/movabs of its relocated address).  A register keeps its value when the
loop does not write it, computes it again on each pass from such registers
and immediates (GetterKeys[I and 15] inside the loop over J; lea, zeroing,
cdqe included) or loads it from a stack slot [rsp+n] the loop does not write,
with the address of no local at or below it taken (the counter of an outer
loop spilled to the frame) - before the load, or after it for the next pass of
a loop entered at its condition.  An address with a register the loop carries from pass to
pass, or loads from other memory, moves: that is the case walking its data,
an element or a pointer per pass, not a reload, and it is not judged.
Win64 reaches such an element through a register loaded by lea; an ELF image
without PIC writes the array's address into the instruction beside the index
register - the same walk.

Usage:
    check_case_loads.py EXE [EXE ...] [--allow FILE]

The allow list (default qualification/performance/case_loop_loads.txt) names
the loads the corpus keeps, one per line with the reason:
    <program> <body procedure> <global symbol>  # why
A load only one target's code has is named in that target's overlay,
case_loop_loads_win64.txt or case_loop_loads_linux.txt, read with the list for
images of that target.  Exit 1 on a load no line names, or on a line of a
checked program that names no load (stale).  It checks the corpus as the tree's
own toolchain builds it (test_check_case_loads.py), not a measured candidate: a
compiler that hoists such a load out of a loop is an improvement, not a reason
to refuse a run.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from bisect import bisect_right
from pathlib import Path

import code_placement as cp
import linked_image

ALLOW = Path(__file__).resolve().parents[1] / "case_loop_loads.txt"
RIP = re.compile(r"\[rip([+-])(0x[0-9a-f]+)\]", re.I)
MEMORY = re.compile(r"\[[^\]]*\]|\b[c-g]s:0x[0-9a-f]+", re.I)
DISPLACEMENT = re.compile(r"([+-])(0x[0-9a-f]+)\]", re.I)
# First operands a move-class instruction only writes; any other memory operand is read.
STORE_ONLY = ("mov", "vmov", "set", "stos", "fst", "fist", "fbstp", "fnst", "fxsave", "stmxcsr", "vstmxcsr",
              "pextr", "vpextr", "extractps", "vextract", "vmaskmov", "vpmaskmov", "maskmov")
NO_ACCESS = ("lea", "nop", "prefetch", "clflush", "clwb")
# Every general register name, to its 64-bit register.
FAMILY = {name: f"r{letter}x" for letter in "abcd"
          for name in (f"r{letter}x", f"e{letter}x", f"{letter}x", f"{letter}l", f"{letter}h")}
FAMILY.update({name: f"r{base}" for base in ("si", "di", "bp", "sp")
               for name in (f"r{base}", f"e{base}", base, f"{base}l")})
FAMILY.update({name: f"r{number}" for number in range(8, 16)
               for name in (f"r{number}", f"r{number}d", f"r{number}w", f"r{number}b")})
REGISTER = re.compile(r"\b(" + "|".join(sorted(FAMILY, key=len, reverse=True)) + r")\b")
# A first register operand these read, not write.
READS_FIRST = {"cmp", "test", "bt", "push", "ret", "ptest", "vptest", "mul", "div", "idiv", "imul"}
READS_FIRST_FAMILIES = ("j", "call", "loop", "nop", "prefetch", "ucomis", "comis", "vucomis", "vcomis")
# The registers an instruction writes without naming them.
IMPLICIT = {"mul": ("rax", "rdx"), "div": ("rax", "rdx"), "idiv": ("rax", "rdx"), "cqo": ("rdx",),
            "cdq": ("rdx",), "cwd": ("rdx",), "cdqe": ("rax",), "cwde": ("rax",), "cbw": ("rax",),
            "rdtsc": ("rax", "rdx"), "rdtscp": ("rax", "rcx", "rdx"), "cpuid": ("rax", "rbx", "rcx", "rdx"),
            "syscall": ("rax", "rcx", "r11"), "cmpxchg": ("rax",), "loop": ("rcx",), "loope": ("rcx",),
            "loopne": ("rcx",)}
CALLER_SAVED = {"rax", "rcx", "rdx", "r8", "r9", "r10", "r11"}
# A value these compute from their register and immediate operands alone is the same on every pass
# when those are; cdqe, cwde and cbw widen rax from itself.
RECOMPUTE = {"mov", "movsx", "movsxd", "movzx", "lea", "and", "or", "xor", "add", "sub", "shl", "shr", "sar",
             "imul", "neg", "not", "inc", "dec"}
WIDEN_RAX = {"cdqe", "cwde", "cbw"}
LOADS = {"mov", "movsx", "movsxd", "movzx"}
# A slot of the stack frame, [rsp+offset]: the compiler's own spill of a local.
FRAME_SLOT = re.compile(r"\[rsp(?:([+-])(0x[0-9a-f]+))?\]", re.I)
STRING = re.compile(r"(movs|stos|lods|scas|cmps)[bwdq]?$")


def reads_memory(mnemonic: str, operands: str) -> bool:
    op, rest = cp.effective_instruction(mnemonic, operands)
    if op.startswith(NO_ACCESS) or not MEMORY.search(rest):
        return False
    first, _, others = rest.partition(",")
    return bool(MEMORY.search(others)) or not MEMORY.search(first) or not op.startswith(STORE_ONLY)


def read_operands(mnemonic: str, operands: str) -> list[str]:
    """The memory operands a reading instruction reads: all but the first of a move-class store."""
    op, rest = cp.effective_instruction(mnemonic, operands)
    memories = MEMORY.findall(rest)
    if memories and op.startswith(STORE_ONLY) and MEMORY.search(rest.partition(",")[0]):
        return memories[1:]
    return memories


def written_registers(mnemonic: str, operands: str, elf: bool) -> set[str]:
    """The general registers an instruction writes: its first register operand, and the implicit ones."""
    op, rest = cp.effective_instruction(mnemonic, operands)
    if cp.is_padding(mnemonic, operands):
        return set()
    if op.startswith("call"):
        return CALLER_SAVED | {"rsi", "rdi"} if elf else set(CALLER_SAVED)
    written = set(IMPLICIT.get(op, ()))
    first, comma, _ = rest.partition(",")
    if first.strip() in FAMILY and not (op in READS_FIRST and not (op == "imul" and comma)) \
            and not op.startswith(READS_FIRST_FAMILIES):
        written.add(FAMILY[first.strip()])
    if op == "imul" and not comma:
        written.update(("rax", "rdx"))
    if op.startswith(("xchg", "xadd", "cmpxchg")):
        written.update(FAMILY[name] for name in REGISTER.findall(rest))
    if STRING.match(op) and "xmm" not in rest:
        written.update(("rax", "rcx", "rsi", "rdi"))
    return written


def displaced_global(memory: str, address: int, raw: bytes, relocations: dict[int, int]) -> int | None:
    """The address a memory operand names itself: RIP-relative, or a displacement the ELF linker relocated."""
    match = RIP.search(memory)
    if match:
        return address + len(raw) + int(match.group(2), 16) * (1 if match.group(1) == "+" else -1)
    for index in range(len(raw)):
        width = relocations.get(address + index)
        if width:
            value = int.from_bytes(raw[index:index + width], "little")
            if f"{value:#x}" in memory:
                return value
    return None


def global_address(instruction: tuple[str, str, bytes], address: int,
                   relocations: dict[int, int]) -> tuple[str, int] | None:
    """(register, address) when the instruction loads a global's address into a register."""
    mnemonic, operands, raw = instruction
    op, rest = cp.effective_instruction(mnemonic, operands)
    destination, _, source = rest.partition(",")
    register = FAMILY.get(destination.strip())
    if register is None or op not in ("lea", "mov", "movabs"):
        return None
    if op == "lea":
        if REGISTER.search(source):
            return None
        value = displaced_global(source, address, raw, relocations)
    elif MEMORY.search(source) or "PTR" in source:
        return None
    else:
        value = next((int.from_bytes(raw[index:index + relocations[address + index]], "little")
                      for index in range(len(raw)) if address + index in relocations), None)
    return None if value is None else (register, value)


def frame_slot(memory: str) -> int | None:
    """The offset of a stack-frame slot, [rsp+offset], or None for any other memory operand."""
    match = FRAME_SLOT.fullmatch(memory)
    if match is None:
        return None
    offset = int(match.group(2), 16) if match.group(2) else 0
    return -offset if match.group(1) == "-" else offset


def slot_kept(offset: int, body: list[int], instructions: dict[int, tuple[str, str, bytes]]) -> bool:
    """No instruction of the loop writes the frame near the slot, and the procedure takes the address of no
    local at or below it (a call could write the slot through it): the loop reads what was put there before
    it."""
    loop = set(body)
    for address, (mnemonic, operands, _) in instructions.items():
        op, rest = cp.effective_instruction(mnemonic, operands)
        first = rest.partition(",")[0]
        for memory in MEMORY.findall(rest):
            near = frame_slot(memory)
            if near is None:
                continue
            if op == "lea":
                if near <= offset:
                    return False
            elif address in loop and abs(near - offset) < 16 and (
                    op.startswith(("xchg", "xadd", "cmpxchg"))
                    or memory in first and op not in READS_FIRST and not op.startswith(READS_FIRST_FAMILIES)):
                return False
    return True


def pass_value(register: str, at: int, loop: tuple[list[int], list[int]],
               instructions: dict[int, tuple[str, str, bytes]], writes: dict[int, set[str]],
               homes: dict[int, tuple[str, int] | None], depth: int = 0) -> tuple[str, int | None] | None:
    """What the register holds at `at` on every pass of the loop: ("global", address) or ("same", None);
    None when it changes from pass to pass - the loop carries it, or computes it from something that
    changes, from memory other than a frame slot the loop keeps, or in a way this does not follow.  The
    value comes from the last write before `at`, or, when the loop writes the register only after `at`,
    from its last write on the pass before."""
    body, before = loop
    written = [address for address in body if register in writes[address]]
    if not written:
        prior = [address for address in before if register in writes[address]]
        home = homes[prior[-1]] if prior else None
        return ("global", home[1]) if home and home[0] == register else ("same", None)
    definition = ([address for address in written if address < at] or written)[-1]
    home = homes[definition]
    if home and home[0] == register:
        return ("global", home[1])
    mnemonic, operands, _ = instructions[definition]
    op, rest = cp.effective_instruction(mnemonic, operands)
    if depth > 8 or writes[definition] - {register}:
        return None
    target, _, source = rest.partition(",")
    if op in ("xor", "sub") and REGISTER.findall(target) == REGISTER.findall(source) == [target.strip()]:
        return ("same", None)  # zeroed on every pass
    memory = [] if op == "lea" else MEMORY.findall(rest)
    if memory:
        # a counter of the outer loop the compiler keeps in the frame
        offset = frame_slot(memory[0]) if op in LOADS and len(memory) == 1 else None
        return ("same", None) if offset is not None and slot_kept(offset, body, instructions) else None
    if op in WIDEN_RAX:
        sources = [register]
    elif op not in RECOMPUTE:
        return None
    else:
        sources = REGISTER.findall(source) if op in LOADS or op == "lea" else REGISTER.findall(rest)
    same = all(pass_value(FAMILY[name], definition, loop, instructions, writes, homes, depth + 1) is not None
               for name in sources)
    return ("same", None) if same else None


def data_sections(exe: Path) -> list[tuple[str, int, int]]:
    rows = []
    for line in cp.run([cp.tool("objdump"), "-h", str(exe)]).splitlines():
        fields = line.split()
        if len(fields) >= 4 and fields[0].isdigit() and fields[1] in (".data", ".bss"):
            begin = int(fields[3], 16)
            rows.append((fields[1], begin, begin + int(fields[2], 16)))
    return rows


def symbols(exe: Path) -> tuple[list[int], dict[int, str]]:
    table: dict[int, str] = {}
    for line in cp.run([cp.tool("nm"), str(exe)]).splitlines():
        match = cp.NM_LINE.match(line)
        if match and not match.group(3).startswith(("DEBUGSTART_", "DEBUGEND_", "$unwind$")):
            table.setdefault(int(match.group(1), 16), match.group(3))
    return sorted(table), table


def case_bodies(exe: Path) -> list[tuple[str, int]]:
    """(case, runtime address) of every body and work body the image registers."""
    done = subprocess.run([str(exe), "list", "all"], capture_output=True, text=True, timeout=300)
    if done.returncode:
        raise RuntimeError(f"{exe}: list all exited {done.returncode}")
    bodies = []
    for line in done.stdout.splitlines():
        if line.startswith("PULSE_CASEDEF "):
            row = dict(part.split("=", 1) for part in line.split()[1:] if "=" in part)
            for field in ("body", "workbody"):
                if int(row.get(field, "0"), 16):
                    bodies.append((row["case"], int(row[field], 16) - int(row["anchor"], 16)))
    if not bodies:
        raise RuntimeError(f"{exe}: no PULSE_CASEDEF")
    return bodies


def is_elf(exe: Path) -> bool:
    with exe.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def loop_loads(exe: Path) -> list[dict[str, object]]:
    """Every load of .data/.bss at an address its innermost loop of a case body does not move, once per
    instruction."""
    procedures = {begin: (name, begin, end) for name, begin, end in cp.procedures(exe)}
    starts = sorted(procedures)
    anchors = [begin for name, begin, _ in procedures.values()
               if "PULSE_HARNESS" in name.upper() and "_$$_PULSERUNCASE$" in name.upper()]
    if len(anchors) != 1:
        raise ValueError(f"{exe}: missing or ambiguous PulseRunCase anchor")
    sections = data_sections(exe)
    relocations = linked_image.absolute_relocations(exe)
    elf = is_elf(exe)
    symbol_starts, symbol_names = symbols(exe)
    found: dict[int, dict[str, object]] = {}
    seen_bodies: dict[int, list[str]] = {}
    for case, offset in case_bodies(exe):
        position = bisect_right(starts, anchors[0] + offset) - 1
        seen_bodies.setdefault(starts[position], []).append(case)
    for begin, cases in seen_bodies.items():
        name, begin, end = procedures[begin]
        instructions = cp.parse_instructions(cp.run([
            cp.tool("objdump"), "-d", "-M", "intel", "-w",
            f"--start-address={begin:#x}", f"--stop-address={end:#x}", str(exe)]))
        order = sorted(instructions)
        writes = {a: written_registers(*instructions[a][:2], elf) for a in order}
        homes = {a: global_address(instructions[a], a, relocations) for a in order}
        loops = {(loop.target, loop.at + len(instructions[loop.at][2])): None
                 for loop in cp.analyze(name, begin, end, instructions).loops}
        for loop in loops:
            loops[loop] = ([a for a in order if loop[0] <= a < loop[1]], [a for a in order if a < loop[0]])
        for address in order:
            inner = [loop for loop in loops if loop[0] <= address < loop[1]]
            mnemonic, operands, raw = instructions[address]
            if not inner or not reads_memory(mnemonic, operands):
                continue
            low, high = min(inner, key=lambda loop: loop[1] - loop[0])
            for memory in read_operands(mnemonic, operands):
                target = displaced_global(memory, address, raw, relocations)
                for register in REGISTER.findall(memory):
                    value = pass_value(FAMILY[register], address, loops[(low, high)], instructions, writes, homes)
                    if value is None:
                        target = None  # the loop walks its data through this register
                        break
                    if value[0] == "global" and target is None:
                        shift = DISPLACEMENT.search(memory)
                        target = value[1] + (int(shift.group(2), 16) * (1 if shift.group(1) == "+" else -1)
                                             if shift else 0)
                if target is None:
                    continue
                section = next((s for s, low_, high_ in sections if low_ <= target < high_), None)
                if section is None or address in found:
                    continue
                base = symbol_starts[bisect_right(symbol_starts, target) - 1]
                found[address] = {
                    "procedure": name, "cases": cases, "loop": low, "address": address,
                    "global": symbol_names[base], "offset": target - base, "section": section,
                    "page_offset": target % 4096, "instruction": f"{mnemonic} {operands}",
                }
    return sorted(found.values(), key=lambda item: item["address"])


def read_allowed(path: Path) -> dict[tuple[str, str, str], str]:
    allowed: dict[tuple[str, str, str], str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text, _, reason = line.partition("#")
        fields = text.split()
        if not fields:
            continue
        if len(fields) != 3 or not reason.strip():
            raise ValueError(f"{path}:{number}: <program> <procedure> <global>  # why")
        allowed[tuple(fields)] = reason.strip()
    return allowed


def overlay(executables: list[Path]) -> Path:
    """The allow overlay of the target the images are built for."""
    targets = {is_elf(exe) for exe in executables}
    if len(targets) != 1:
        raise ValueError("the images are not of one target")
    return ALLOW.with_name("case_loop_loads_linux.txt" if targets.pop() else "case_loop_loads_win64.txt")


def check(executables: list[Path], allow: Path = ALLOW, extra_allow: Path | None = None) -> list[str]:
    """A line per load no allow line names, and per allow line of a checked program no load matches."""
    allowed = read_allowed(allow)
    if extra_allow is not None:
        allowed.update(read_allowed(extra_allow))
    used: set[tuple[str, str, str]] = set()
    failures: list[str] = []
    programs = set()
    for exe in executables:
        program = exe.stem.removeprefix("pulse_").replace("_", "-")
        programs.add(program)
        for load in loop_loads(exe.resolve()):
            key = (program, str(load["procedure"]), str(load["global"]))
            if key in allowed:
                used.add(key)
                continue
            cases = load["cases"]
            failures.append(
                f"CASE_LOOP_LOAD {program} {load['procedure']} {load['global']}+{load['offset']:#x} "
                f"page_offset={load['page_offset']:#05x} at={load['address']:#x} loop={load['loop']:#x} "
                f"cases={len(cases)}:{cases[0]} | {load['instruction']}")
    for key in sorted(set(allowed) - used):
        if key[0] in programs:
            failures.append(f"CASE_LOOP_ALLOW_STALE {' '.join(key)}  # {allowed[key]}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("exe", type=Path, nargs="+")
    parser.add_argument("--allow", type=Path, default=ALLOW)
    args = parser.parse_args()
    failures = check(args.exe, args.allow, overlay(args.exe))
    for line in failures:
        print(line)
    print(f"CASE_LOOP_LOADS {'FAIL' if failures else 'PASS'} images={len(args.exe)} findings={len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
