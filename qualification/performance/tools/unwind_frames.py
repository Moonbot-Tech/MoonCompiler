#!/usr/bin/env python3
"""Does every routine tell the unwinder what it does to the stack?

An exception, the stack walk of the diagnostics and a debugger find the caller of a routine
from the routine's unwind information alone: where the return address lies relative to the
stack pointer at the instruction that faulted or was interrupted, and where the routine keeps
the registers it has to give back to its caller.  The compiler writes that information for
the frames it builds; a routine written in assembler has to write it itself
(doc/ASM_LAYOUT_RULES.md, "Unwinding hand-written frames").  A routine that moves rsp without
saying so sends the unwinder to a wrong return address - on Linux the program hangs or dies
past its try/except, the stack of a thread caught inside it is garbage - and one that saves a
callee-saved register without saying so hands its caller that register back wrong.

For every routine of the objects given - an FDE (ELF) or a .pdata entry (COFF), and every
function symbol of a code section that has neither - this walks the instructions from the
entry along the direct branches inside the routine and follows the stack depth (the bytes the
routine keeps below its return address) and the callee-saved registers it has pushed.  At
every instruction reached it compares them with the unwind information that holds there:

* ELF (Linux): the CFA rule and the register rules of the routine's FDE, interpreted here from
  .eh_frame: a CFA counted from rsp must be rsp + 8 + depth, every pushed callee-saved register
  must be recorded at its slot; a routine without an FDE may neither move rsp nor call;
* COFF (Win64): the UNWIND_INFO of the routine: inside the prologue the codes up to the
  instruction, behind it all of them (a frame register lets the body move rsp), an epilogue -
  add/lea rsp, pops, ret or a jump away - the unwinder simulates itself; a routine without
  unwind information is a leaf and may not move rsp.

Reported as well: two paths that reach one instruction with different depths, and a depth
that is no longer known (`and rsp`, `mov rsp, r`) while the unwind information counts from rsp.
A frame of a C compiler's Win64 prologue allocated behind its stack probe (`mov eax, N`,
`call ___chkstk_ms` - the probe keeps rax - `sub rsp, rax`) counts N.  An indirect jump ends
the walk of its path (its targets are not known here).  Saves by `mov` to the stack and the xmm
registers are not followed.  An epilogue - the frame given back, pops, ret or a jump away
(on Win64 an indirect one with REX.W, the unwinder's mark of a tail call) - that the CFI rows do
not follow is counted apart and not reported: the compiler writes no CFI for its epilogues on
Linux (a stack walk that samples a thread between the pops and the ret goes wrong there; an
exception cannot start there), and the Win64 unwinder recognizes the shape and simulates it.

Usage:
    unwind_frames.py [--allow REGEX ...] [--jobs N] OBJECT|DIRECTORY ...
Exit status 1 when a routine that no --allow names is reported.  OBJDUMP in the environment
names the objdump to use (default: objdump on PATH); it must read the objects' format.
"""

from __future__ import annotations

import argparse
from bisect import bisect_right
import os
import re
import struct
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

CALLEE_SAVED = {
    "elf": {"rbx", "rbp", "r12", "r13", "r14", "r15"},
    "coff": {"rbx", "rbp", "rdi", "rsi", "r12", "r13", "r14", "r15"},
}
DWARF_REGS = ["rax", "rdx", "rcx", "rbx", "rsi", "rdi", "rbp", "rsp",
              "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "ra"]
WIN_REGS = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
            "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
GPR = set(WIN_REGS)
ELF_MAGIC = bytes([0x7F]) + b"ELF"
COFF_AMD64 = bytes([0x64, 0x86])
CONDITIONAL = re.compile(r"^(j(?!mp)[a-z]+|loop[a-z]*)$")
INSN = re.compile(r"^\s*([0-9a-f]+):\t([0-9a-f ]+?)\s*\t(.*)$")
SECTION = re.compile(r"^Disassembly of section (\S+):")
SKIPPABLE = {0x9B, 0x2E, 0x3E, 0x26, 0x36, 0x64, 0x65, 0x66, 0x67, 0xF0, 0xF2, 0xF3}
PREFIXES = {"rex", "rex.w", "rex.b", "rex.r", "rex.x", "rex.wb", "rex.wr", "rex.wx", "rex.wrb", "rex.wrx",
            "rex.wxb", "rex.wrxb", "ds", "cs", "ss", "es", "fs", "gs", "data16", "addr32", "lock", "rep",
            "repz", "repe", "repnz", "repne", "bnd", "notrack"}
# Win64 stack probes that touch the pages of a frame of rax bytes and keep rax and rsp as they
# were (libgcc's ___chkstk_ms, the MSVC runtime's __chkstk); the prologue moves rsp itself
PROBES = {"___chkstk_ms", "__chkstk"}
RAX = {"rax", "eax", "ax", "al", "ah"}


def run(command: list[str]) -> str:
    return subprocess.run(command, check=True, text=True, encoding="utf-8", errors="replace",
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout


# ---------------------------------------------------------------- instructions

class Insn:
    __slots__ = ("offset", "size", "raw", "mnemonic", "args", "relocated", "target", "probe")

    def __init__(self, offset: int, raw: str, text: str):
        raw_bytes = raw.split()
        self.offset, self.size, self.raw = offset, len(raw_bytes), bytes(int(b, 16) for b in raw_bytes)
        self.relocated, self.target, self.probe = False, None, False
        words = text.split(None, 1)
        mnemonic, operands = (words[0], words[1] if len(words) > 1 else "") if words else ("", "")
        # objdump spells the REX ones with capitals: rex.W jmp rax
        while mnemonic.lower() in PREFIXES and operands:
            words = operands.split(None, 1)
            mnemonic, operands = words[0], (words[1] if len(words) > 1 else "")
        operands = re.sub(r"\s*<[^>]*>", "", operands.split("#", 1)[0]).strip()
        self.mnemonic = mnemonic
        self.args = [a.strip() for a in operands.split(",")] if operands else []


def without_symbols(data: bytes) -> bytes:
    """The object with its symbols and relocations hidden from objdump.  objdump looks for the
    symbol of every address it prints among all the symbols of an equal value, and in an object
    of a section a routine they all have the value 0: the 10678 code sections of odata's
    sharepoint.o took 1600 CPU-seconds so, 9 seconds without.  The relocations the walk needs
    are read from the object here (`relocation_offsets`)."""
    copy = bytearray(data)
    if copy[:4] == ELF_MAGIC:
        shoff, = struct.unpack_from("<Q", copy, 0x28)
        shentsize, shnum = struct.unpack_from("<HH", copy, 0x3A)
        for i in range(shnum):
            at = shoff + i * shentsize
            kind, = struct.unpack_from("<I", copy, at + 4)
            if kind in (2, 4, 9, 11, 17):  # symbols, relocations, a group: bytes nobody reads
                struct.pack_into("<I", copy, at + 4, 1)
            flags, = struct.unpack_from("<Q", copy, at + 8)
            struct.pack_into("<Q", copy, at + 8, flags & ~0x200)  # SHF_GROUP
        return bytes(copy)
    if is_bigobj(copy):
        count, pointer, symbols = struct.unpack_from("<III", copy, 44)
        struct.pack_into("<II", copy, 48, pointer + 20 * symbols, 0)
        header = 56
    else:
        count, = struct.unpack_from("<H", copy, 2)
        pointer, symbols = struct.unpack_from("<II", copy, 8)
        # the string table, which the long section names live in, stays where the symbols end
        struct.pack_into("<II", copy, 8, pointer + 18 * symbols, 0)
        header = 20 + struct.unpack_from("<H", copy, 16)[0]
    for i in range(count):
        at = header + 40 * i
        struct.pack_into("<I", copy, at + 24, 0)
        struct.pack_into("<H", copy, at + 32, 0)
        flags, = struct.unpack_from("<I", copy, at + 36)
        struct.pack_into("<I", copy, at + 36, flags & ~0x01000000)  # IMAGE_SCN_LNK_NRELOC_OVFL
    return bytes(copy)


def disassemble(data: bytes, relocations: dict[str, list[int]],
                probes: dict[str, set[int]] | None = None) -> dict[str, list[Insn]]:
    """section -> its instructions (offsets inside the section) of the object `data`;
    `relocations` holds the sorted offsets of every section's relocations, `probes` those of
    them that name a stack probe (PROBES)."""
    sections: dict[str, list[Insn]] = {}
    current: list[Insn] | None = None
    objdump = os.environ.get("OBJDUMP", "objdump")
    handle, name = tempfile.mkstemp(suffix=".o")
    try:
        with os.fdopen(handle, "wb") as copy:
            copy.write(without_symbols(data))
        text = run([objdump, "-d", "-w", "-M", "intel", name])
    finally:
        os.unlink(name)
    for line in text.splitlines():
        head = SECTION.match(line)
        if head:
            current = sections.setdefault(head.group(1), [])
            continue
        if current is None:
            continue
        insn_match = INSN.match(line)
        if insn_match:
            current.append(Insn(int(insn_match.group(1), 16), insn_match.group(2), insn_match.group(3).strip()))
    for section, insns in sections.items():
        offsets = relocations.get(section, [])
        probe_offsets = (probes or {}).get(section, set())
        k = 0
        for insn in insns:
            while k < len(offsets) and offsets[k] < insn.offset:
                k += 1
            insn.relocated = k < len(offsets) and offsets[k] < insn.offset + insn.size
            insn.probe = insn.relocated and insn.mnemonic == "call" and offsets[k] in probe_offsets
            if insn.mnemonic.startswith(("j", "loop")) and len(insn.args) == 1 and not insn.relocated:
                target = re.fullmatch(r"(?:0x)?([0-9a-f]+)", insn.args[0])
                if target:
                    insn.target = int(target.group(1), 16)
    return sections


def immediate(text: str) -> int | None:
    match = re.fullmatch(r"(-)?(0x[0-9a-f]+|\d+)", text)
    if not match:
        return None
    value = int(match.group(2), 0)
    if value >= 1 << 63:
        value -= 1 << 64
    return -value if match.group(1) else value


def displacement(operand: str, base: str) -> int | None:
    match = re.fullmatch(r"(?:QWORD PTR )?\[" + base + r"(?:([+-])(0x[0-9a-f]+|\d+))?\]", operand)
    if not match:
        return None
    value = int(match.group(2), 0) if match.group(2) else 0
    return -value if match.group(1) == "-" else value


class Walk:
    """Per instruction offset the state it is reached in: (depth or None, the pushed callee-saved
    registers as ((reg, depth after its push), ...), the depth rbp was set from rsp at or None,
    the constant in rax on the way to a probed frame's `sub rsp, rax` or None)."""

    def __init__(self, insns: list[Insn], begin: int, end: int, abi: str, depth: int = 0):
        """`depth`: what the routine keeps below its return address at its entry - 0, but a
        fragment entered with a frame already built (GCC's .text.unlikely part of a function)
        starts where its unwind information says."""
        self.start_depth = depth
        self.insns = [insn for insn in insns if begin <= insn.offset < end]
        self.index = {insn.offset: i for i, insn in enumerate(self.insns)}
        self.begin, self.end = begin, end
        self.callee = CALLEE_SAVED[abi]
        self.states: dict[int, tuple] = {}
        self.problems: list[str] = []
        self.exits: list[tuple[int, int | None]] = []
        self.calls = False

    def step(self, insn: Insn, state: tuple) -> tuple:
        depth, saved, rbp, rax = state
        saved = dict(saved)
        m, args = insn.mnemonic, insn.args
        # rax is followed only from `mov eax, N` over what a probed prologue puts before its
        # `sub rsp, rax`: pushes, stores and moves to other registers, the probe
        if m == "mov" and len(args) == 2 and args[0] in ("rax", "eax") and immediate(args[1]) is not None:
            after_rax = immediate(args[1]) & (0xFFFFFFFF if args[0] == "eax" else (1 << 64) - 1)
        elif insn.probe or (m in ("push", "pushq", "pop", "popq", "mov", "lea") and args and
                            args[0] not in RAX and not (m in ("pop", "popq") and args[0] == "rsp")):
            after_rax = rax
        else:
            after_rax = None
        if m in ("push", "pushq", "pushf", "pushfq"):
            if depth is not None:
                depth += 8
                if m in ("push", "pushq") and args and args[0] in self.callee:
                    saved.setdefault(args[0], depth)
        elif m in ("pop", "popq", "popf", "popfq"):
            if args and args[0] in saved and saved[args[0]] == depth:
                del saved[args[0]]
            if args and args[0] == "rbp":
                rbp = None
            if depth is not None:
                depth -= 8
        elif m == "leave":
            depth = None if rbp is None else rbp - 8
            saved.pop("rbp", None)
            rbp = None
        elif m == "enter":
            depth = None
        elif len(args) == 2 and args[0] == "rsp":
            value = rax if args[1] == "rax" else immediate(args[1])
            if m == "sub" and value is not None and depth is not None:
                depth += value
            elif m == "add" and value is not None and depth is not None:
                depth -= value
            elif m == "lea" and (disp := displacement(args[1], "rsp")) is not None and depth is not None:
                depth -= disp
            elif m == "lea" and (disp := displacement(args[1], "rbp")) is not None and rbp is not None:
                depth = rbp - disp
            elif m == "mov" and args[1] == "rbp" and rbp is not None:
                depth = rbp
            elif m in ("cmp", "test"):
                pass
            else:
                depth = None
        elif len(args) == 2 and args[0] == "rbp" and m == "mov" and args[1] == "rsp":
            rbp = depth
        elif args and args[0] == "rbp" and m not in ("cmp", "test"):
            rbp = None
        return (depth, tuple(sorted(saved.items())), rbp, after_rax)

    def run(self) -> None:
        if self.begin not in self.index:
            return
        work = [(self.begin, (self.start_depth, (), None, None))]
        while work:
            offset, state = work.pop()
            i = self.index.get(offset)
            if i is None:
                # a jump over bytes objdump printed as part of the next instruction: fwait in front
                # of an x87 one (9b db e2: fclex), or a prefix a hand layout left as padding in
                # front of a target (3e 4d 8d 14 08: the jump lands on the lea behind the ds);
                # the rest of that instruction does to rsp what all of it does
                i = next((k for k, insn in enumerate(self.insns)
                          if insn.offset < offset < insn.offset + insn.size and
                          all(byte in SKIPPABLE for byte in insn.raw[:offset - insn.offset])), None)
                if i is None:
                    self.problems.append(f"+{offset:#x}: a branch into the middle of an instruction")
                    continue
            while True:
                insn = self.insns[i]
                seen = self.states.get(insn.offset)
                if seen is not None:
                    if seen[:2] != state[:2]:
                        self.problems.append(f"+{insn.offset:#x}: reached with depth {seen[0]} {dict(seen[1])} "
                                             f"and with depth {state[0]} {dict(state[1])}")
                    break
                self.states[insn.offset] = state
                m = insn.mnemonic
                after = self.step(insn, state)
                if m == "call":
                    self.calls = True
                if m in ("ret", "retq", "iret", "iretq"):
                    self.exits.append((insn.offset, state[0]))
                    break
                if m in ("ud2", "hlt", "int3"):
                    break
                if m == "jmp":
                    if insn.target is not None and self.begin <= insn.target < self.end:
                        work.append((insn.target, after))
                    elif insn.relocated or insn.target is not None:
                        self.exits.append((insn.offset, state[0]))
                    break
                if CONDITIONAL.match(m):
                    if insn.target is not None and self.begin <= insn.target < self.end:
                        work.append((insn.target, after))
                    elif insn.relocated or insn.target is not None:
                        self.exits.append((insn.offset, state[0]))
                i += 1
                if i >= len(self.insns):
                    break
                state = after

    def common_problems(self) -> list[str]:
        # a ret behind a call that does not return (FPC keeps it after a noreturn callee) is
        # reached here with the depth of the call: whether a return leaves the stack right is
        # the routine's own test, not the unwinder's
        return list(self.problems)


def epilogue_at(insns: list[Insn], i: int, leave: bool = False) -> bool:
    """Is the code from insns[i] on an epilogue - the frame given back (add/lea rsp; with `leave`
    also leave and mov rsp, rbp), pops, then ret or a jump out of the routine (a tail call)?
    The Win64 unwinder takes that shape for an epilogue and simulates it; the DWARF unwinders
    only have the CFI rows.  `insns` are the routine's own."""
    insn = insns[i]
    frame_given_back = insn.mnemonic in ("add", "lea") and insn.args and insn.args[0] == "rsp"
    if leave and (insn.mnemonic == "leave" or (insn.mnemonic == "mov" and insn.args == ["rsp", "rbp"])):
        frame_given_back = True
    if frame_given_back:
        i += 1
    while i < len(insns) and insns[i].mnemonic == "pop" and insns[i].args and insns[i].args[0] in GPR:
        i += 1
    if i >= len(insns):
        return False
    last = insns[i]
    raw = last.raw
    # jmp [rip+X] (ff 25), and any indirect jmp with REX.W (48-4f ff /4): the REX.W is redundant
    # there, and the Win64 unwinder reads it as "a tail call out of the routine"; a jump to the
    # routine's own start is a recursive tail call to it
    away = raw[:2] == b"\xff\x25" or (len(raw) >= 3 and raw[0] & 0xF8 == 0x48 and raw[1] == 0xFF and
                                        raw[2] & 0x38 == 0x20)
    return last.mnemonic in ("ret", "retq") or (last.mnemonic == "jmp" and (
        away or last.relocated or last.target == insns[0].offset or
        (last.target is not None and not insns[0].offset <= last.target <= insns[-1].offset)))


def uncovered(covered: list[tuple[int, int]], starts: list[int], insns: list[Insn]) -> list[tuple]:
    """Routines (start, end, None) at the symbol addresses no unwind entry covers, each ending
    where the next routine or unwind entry begins."""
    end_of_code = insns[-1].offset + insns[-1].size
    bounds = sorted({s for s in starts} | {b for b, _ in covered} | {end_of_code})
    result = []
    for start in sorted(set(starts)):
        if any(b <= start < e for b, e in covered):
            continue
        following = [b for b in bounds if b > start]
        result.append((start, following[0] if following else end_of_code, None))
    return result


# ---------------------------------------------------------------- ELF

def uleb(data: bytes, at: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return value, at


def sleb(data: bytes, at: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            if byte & 0x40:
                value -= 1 << shift
            return value, at


def encoded_size(encoding: int) -> int:
    return {0x00: 8, 0x02: 2, 0x03: 4, 0x04: 8, 0x0A: 2, 0x0B: 4, 0x0C: 8}[encoding & 0x0F]


class Elf:
    def __init__(self, data: bytes):
        self.data = data
        shoff, = struct.unpack_from("<Q", data, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
        self.sections = []
        for i in range(shnum):
            fields = struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize)
            self.sections.append(fields)
        names = self.sections[shstrndx]
        self.names = [self.cstr(names[4] + s[0]) for s in self.sections]
        self.symbols = []
        for i, s in enumerate(self.sections):
            if s[1] == 2:  # SHT_SYMTAB
                strtab = self.sections[s[6]]
                for at in range(s[4], s[4] + s[5], 24):
                    name, info, _, shndx, value, size = struct.unpack_from("<IBBHQQ", data, at)
                    self.symbols.append((self.cstr(strtab[4] + name), info, shndx, value, size))

    def cstr(self, at: int) -> str:
        return self.data[at:self.data.index(b"\0", at)].decode("latin-1")

    def content(self, index: int) -> bytes:
        s = self.sections[index]
        return self.data[s[4]:s[4] + s[5]]

    def relocations(self, target: int) -> dict[int, tuple[int, int]]:
        """offset in section `target` -> (symbol index, addend)."""
        result = {}
        for s in self.sections:
            if s[1] == 4 and s[7] == target:  # SHT_RELA for that section
                for at in range(s[4], s[4] + s[5], 24):
                    offset, info, addend = struct.unpack_from("<QQq", self.data, at)
                    result[offset] = (info >> 32, addend)
        return result

    def relocation_offsets(self) -> dict[str, list[int]]:
        """section name -> the sorted offsets of its relocations."""
        result: dict[str, list[int]] = {}
        for s in self.sections:
            if s[1] == 4:
                result.setdefault(self.names[s[7]], []).extend(
                    struct.unpack_from("<Q", self.data, at)[0] for at in range(s[4], s[4] + s[5], 24))
        return {name: sorted(offsets) for name, offsets in result.items()}


def cfa_rows(cie: dict, program: bytes, pc_range: int) -> list[tuple[int, tuple, dict]]:
    """Interpret CIE initial instructions + FDE program: [(loc, (reg, offset) of CFA, {reg: rule})]."""
    rows: list[tuple[int, tuple, dict]] = []
    state = {"cfa": None, "rules": {}}
    initial = None
    stack = []

    def execute(code: bytes, loc: int, record: bool) -> int:
        nonlocal initial
        at = 0
        while at < len(code):
            op = code[at]
            at += 1
            high, low = op & 0xC0, op & 0x3F
            if high == 0x40:
                if record:
                    rows.append((loc, state["cfa"], dict(state["rules"])))
                loc += low * cie["code"]
                continue
            if high == 0x80:
                value, at = uleb(code, at)
                state["rules"][low] = ("c", value * cie["data"])
                continue
            if high == 0xC0:
                if initial is not None and low in initial["rules"]:
                    state["rules"][low] = initial["rules"][low]
                else:
                    state["rules"].pop(low, None)
                continue
            if op == 0x00:
                continue
            if op in (0x02, 0x03, 0x04):
                size = {0x02: 1, 0x03: 2, 0x04: 4}[op]
                delta = int.from_bytes(code[at:at + size], "little")
                at += size
                if record:
                    rows.append((loc, state["cfa"], dict(state["rules"])))
                loc += delta * cie["code"]
            elif op == 0x05:
                reg, at = uleb(code, at)
                value, at = uleb(code, at)
                state["rules"][reg] = ("c", value * cie["data"])
            elif op == 0x06:
                reg, at = uleb(code, at)
                if initial is not None and reg in initial["rules"]:
                    state["rules"][reg] = initial["rules"][reg]
                else:
                    state["rules"].pop(reg, None)
            elif op == 0x07:
                reg, at = uleb(code, at)
                state["rules"][reg] = ("undefined", 0)
            elif op == 0x08:
                reg, at = uleb(code, at)
                state["rules"].pop(reg, None)
            elif op == 0x09:
                reg, at = uleb(code, at)
                other, at = uleb(code, at)
                state["rules"][reg] = ("reg", other)
            elif op == 0x0A:
                stack.append((state["cfa"], dict(state["rules"])))
            elif op == 0x0B:
                state["cfa"], state["rules"] = stack.pop()
            elif op == 0x0C:
                reg, at = uleb(code, at)
                value, at = uleb(code, at)
                state["cfa"] = (reg, value)
            elif op == 0x0D:
                reg, at = uleb(code, at)
                state["cfa"] = (reg, state["cfa"][1])
            elif op == 0x0E:
                value, at = uleb(code, at)
                state["cfa"] = (state["cfa"][0], value)
            elif op == 0x11:
                reg, at = uleb(code, at)
                value, at = sleb(code, at)
                state["rules"][reg] = ("c", value * cie["data"])
            elif op == 0x12:
                reg, at = uleb(code, at)
                value, at = sleb(code, at)
                state["cfa"] = (reg, value * cie["data"])
            elif op == 0x13:
                value, at = sleb(code, at)
                state["cfa"] = (state["cfa"][0], value * cie["data"])
            elif op == 0x2E:
                _, at = uleb(code, at)
            else:
                raise ValueError(f"DW_CFA opcode {op:#x} not understood")
        return loc

    execute(cie["initial"], 0, False)
    initial = {"cfa": state["cfa"], "rules": dict(state["rules"])}
    end = execute(program, 0, True)
    rows.append((end, state["cfa"], dict(state["rules"])))
    # a row holds from its location up to the next one's
    merged = []
    for loc, cfa, rules in rows:
        if merged and merged[-1][0] == loc:
            merged[-1] = (loc, cfa, rules)
        else:
            merged.append((loc, cfa, rules))
    return [row for row in merged if row[0] <= pc_range]


def elf_fdes(elf: Elf) -> list[tuple[int, int, int, list]]:
    """[(code section index, start, length, rows)] of the .eh_frame."""
    index = next((i for i, name in enumerate(elf.names) if name == ".eh_frame"), None)
    if index is None:
        return []
    data = elf.content(index)
    relocs = elf.relocations(index)
    cies: dict[int, dict] = {}
    result = []
    at = 0
    while at + 4 <= len(data):
        length, = struct.unpack_from("<I", data, at)
        if length == 0:
            break
        start = at + 4
        end = start + length
        ident, = struct.unpack_from("<I", data, start)
        body = start + 4
        if ident == 0:
            version = data[body]
            p = body + 1
            augmentation = data[p:data.index(b"\0", p)].decode("latin-1")
            p += len(augmentation) + 1
            code, p = uleb(data, p)
            align, p = sleb(data, p)
            if version == 1:
                p += 1
            else:
                _, p = uleb(data, p)
            fde_encoding = 0
            if augmentation.startswith("z"):
                size, p = uleb(data, p)
                q = p
                for letter in augmentation[1:]:
                    if letter == "P":
                        q += 1 + encoded_size(data[q])
                    elif letter == "L":
                        q += 1
                    elif letter == "R":
                        fde_encoding = data[q]
                        q += 1
                p += size
            cies[at] = {"code": code, "data": align, "initial": data[p:end], "encoding": fde_encoding,
                        "augmented": augmentation.startswith("z")}
        else:
            cie = cies[start - ident]
            size = encoded_size(cie["encoding"])
            symbol, addend = relocs.get(body, (None, 0))
            pc_range = int.from_bytes(data[body + size:body + 2 * size], "little")
            p = body + 2 * size
            if cie["augmented"]:
                length_aug, p = uleb(data, p)
                p += length_aug
            if symbol is not None:
                name, info, shndx, value, _ = elf.symbols[symbol]
                result.append((shndx, value + addend, pc_range, cfa_rows(cie, data[p:end], pc_range)))
        at = end
    return result


def check_elf(data: bytes) -> tuple[list[tuple[str, str]], int]:
    elf = Elf(data)
    fdes = elf_fdes(elf)
    code = disassemble(data, elf.relocation_offsets())
    by_section: dict[int, list] = {}
    for fde in fdes:
        by_section.setdefault(fde[0], []).append(fde)
    symbols: dict[int, list] = {}
    for symbol in elf.symbols:
        if symbol[0] and (symbol[1] & 15) in (0, 2):
            symbols.setdefault(symbol[2], []).append(symbol)
    reports = []
    epilogues = 0
    for index, name in enumerate(elf.names):
        insns = code.get(name)
        if not insns:
            continue
        routines = [(start, start + length, rows) for _, start, length, rows in by_section.get(index, [])]
        covered = [(start, end) for start, end, _ in routines]
        # function symbols no FDE covers: leaves by that absence, each up to the next routine
        routines += uncovered(covered, [s[3] for s in symbols.get(index, [])], insns)
        if not routines:
            routines.append((0, insns[-1].offset + insns[-1].size, None))
        epilogue: set[int] = set()
        for begin, end, rows in routines:
            # an FDE whose first row already counts a frame: a fragment entered with it
            first = rows[0] if rows else None
            start = (first[1][1] - 8 if first and first[0] == 0 and first[1] and
                     DWARF_REGS[first[1][0]] == "rsp" and first[1][1] > 8 else 0)
            walk = Walk(insns, begin, end, "elf", start)
            walk.run()
            problems = walk.common_problems()
            if rows is None:
                if any(state[0] not in (0, None) for state in walk.states.values()):
                    problems.append("moves rsp and has no FDE")
                elif walk.calls:
                    problems.append("calls and has no FDE (an exception cannot leave the callee)")
            else:
                locations = [row[0] for row in rows]
                for i, insn in enumerate(walk.insns):
                    state = walk.states.get(insn.offset)
                    if state is None:
                        continue
                    offset, (depth, saved, _, _) = insn.offset, state
                    at = bisect_right(locations, offset - begin) - 1
                    row = rows[at] if at >= 0 else None
                    if row is None or row[1] is None:
                        continue
                    found = []
                    reg, value = row[1]
                    if DWARF_REGS[reg] == "rsp":
                        if depth is None:
                            found.append(f"+{offset:#x}: the stack depth is not known here, the CFA counts from rsp")
                        elif value != 8 + depth:
                            found.append(f"+{offset:#x}: CFA rsp+{value}, the routine is at rsp+{8 + depth}")
                    for register, at in saved:
                        rule = row[2].get(DWARF_REGS.index(register))
                        if rule != ("c", -(8 + at)):
                            found.append(f"+{offset:#x}: {register} pushed to CFA-{8 + at}, the FDE says {rule}")
                    if found and epilogue_at(walk.insns, i, leave=True):
                        epilogue.add(begin)
                    else:
                        problems += found
            if problems:
                label = next((s[0] for s in symbols.get(index, []) if s[3] == begin), name)
                reports.append((label, "; ".join(dict.fromkeys(problems))))
        epilogues += len(epilogue)
    return reports, epilogues


# ---------------------------------------------------------------- COFF

def is_bigobj(data: bytes) -> bool:
    """The COFF of more than 65535 sections (ANON_OBJECT_HEADER_BIGOBJ, x86-64)."""
    return data[:4] == bytes([0, 0, 0xFF, 0xFF]) and data[6:8] == COFF_AMD64


class Coff:
    def __init__(self, data: bytes):
        self.data = data
        if is_bigobj(data):
            # 56-byte header, 32-bit section numbers in 20-byte symbols
            count, pointer, symbol_count = struct.unpack_from("<III", data, 44)
            header, symbol_size, section_format = 56, 20, "<IihBB"
        else:
            count, = struct.unpack_from("<H", data, 2)
            pointer, symbol_count = struct.unpack_from("<II", data, 8)
            header = 20 + struct.unpack_from("<H", data, 16)[0]
            symbol_size, section_format = 18, "<IhHBB"
        self.strings = pointer + symbol_size * symbol_count
        self.sections = []
        for i in range(count):
            at = header + 40 * i
            name = data[at:at + 8].rstrip(b"\0")
            if name.startswith(b"/") and name[1:].isdigit():
                start = self.strings + int(name[1:])
                name = data[start:data.index(b"\0", start)]
            size, raw, relocs, _, nrelocs = struct.unpack_from("<IIIIH", data, at + 16)
            if struct.unpack_from("<I", data, at + 36)[0] & 0x01000000 and nrelocs == 0xFFFF:
                # IMAGE_SCN_LNK_NRELOC_OVFL: the first entry holds the count, itself included
                nrelocs = struct.unpack_from("<I", data, relocs)[0] - 1
                relocs += 10
            self.sections.append((name.decode("latin-1"), data[raw:raw + size] if raw else b"", relocs, nrelocs))
        self.symbols = []
        i = 0
        while i < symbol_count:
            at = pointer + symbol_size * i
            raw_name = data[at:at + 8]
            if raw_name[:4] == b"\0\0\0\0":
                offset, = struct.unpack_from("<I", raw_name, 4)
                name = data[self.strings + offset:data.index(b"\0", self.strings + offset)].decode("latin-1")
            else:
                name = raw_name.rstrip(b"\0").decode("latin-1")
            value, section, kind, storage, aux = struct.unpack_from(section_format, data, at + 8)
            self.symbols.append((name, value, section, kind, storage))
            self.symbols.extend([None] * aux)
            i += 1 + aux

    def relocations(self, index: int) -> dict[int, int]:
        _, _, pointer, count = self.sections[index]
        result = {}
        for i in range(count):
            offset, symbol, _ = struct.unpack_from("<IIH", self.data, pointer + 10 * i)
            result[offset] = symbol
        return result

    def relocation_offsets(self) -> dict[str, list[int]]:
        """section name -> the sorted offsets of its relocations."""
        return {name: sorted(self.relocations(index))
                for index, (name, _, _, count) in enumerate(self.sections) if count}

    def probe_relocations(self) -> dict[str, set[int]]:
        """section name -> the offsets of its relocations that name a stack probe."""
        result: dict[str, set[int]] = {}
        for index, (name, _, _, count) in enumerate(self.sections):
            for offset, symbol in (self.relocations(index).items() if count else ()):
                if symbol < len(self.symbols) and self.symbols[symbol] and self.symbols[symbol][0] in PROBES:
                    result.setdefault(name, set()).add(offset)
        return result


def unwind_codes(info: bytes) -> tuple[int, bool, list[tuple[int, str, object]]]:
    """(prologue size, frame register set, [(code offset, op, operand)]) of an UNWIND_INFO."""
    version, flags = info[0] & 7, info[0] >> 3
    if version not in (1, 2) or flags & 4:
        raise ValueError(f"UNWIND_INFO version {version} flags {flags} (chained info) not understood")
    prologue, count = info[1], info[2]
    codes = []
    i = 0
    while i < count:
        at, op, arg = info[4 + 2 * i], info[5 + 2 * i] & 15, info[5 + 2 * i] >> 4
        if op == 0:
            codes.append((at, "push", WIN_REGS[arg]))
            i += 1
        elif op == 1:
            size = struct.unpack_from("<H", info, 6 + 2 * i)[0] * 8 if arg == 0 else \
                struct.unpack_from("<I", info, 6 + 2 * i)[0]
            codes.append((at, "alloc", size))
            i += 2 if arg == 0 else 3
        elif op == 2:
            codes.append((at, "alloc", arg * 8 + 8))
            i += 1
        elif op == 3:
            codes.append((at, "frame", None))
            i += 1
        elif op in (4, 5):
            codes.append((at, "save", WIN_REGS[arg]))
            i += 2 if op == 4 else 3
        elif op in (8, 9):
            i += 2 if op == 8 else 3
        elif op == 10:
            codes.append((at, "machframe", arg))
            i += 1
        else:
            raise ValueError(f"UWOP {op} not understood")
    return prologue, (info[3] & 15) != 0, codes




def check_coff(data: bytes) -> tuple[list[tuple[str, str]], int]:
    coff = Coff(data)
    code = disassemble(data, coff.relocation_offsets(), coff.probe_relocations())
    # every .pdata entry: (code section, start, end, unwind info bytes)
    entries: dict[int, list] = {}
    for index, (name, content, _, _) in enumerate(coff.sections):
        if not name.startswith(".pdata"):
            continue
        relocs = coff.relocations(index)
        for at in range(0, len(content) - 11, 12):
            begin, end, unwind = struct.unpack_from("<III", content, at)
            targets = [coff.symbols[relocs[at + k]] if at + k in relocs else None for k in (0, 4, 8)]
            if None in targets:
                continue
            section = targets[0][2] - 1
            base = targets[0][1]
            info_section = targets[2][2] - 1
            info = coff.sections[info_section][1][targets[2][1] + unwind:]
            entries.setdefault(section, []).append((base + begin, targets[1][1] + end, info))
    symbols: dict[int, list] = {}
    for symbol in coff.symbols:
        if symbol and symbol[4] in (2, 3) and symbol[0] and not symbol[0].startswith("."):
            symbols.setdefault(symbol[2] - 1, []).append(symbol)
    reports = []
    for index, (name, _, _, _) in enumerate(coff.sections):
        insns = code.get(name)
        if not insns:
            continue
        routines = [(begin, end, info) for begin, end, info in entries.get(index, [])]
        covered = [(begin, end) for begin, end, _ in routines]
        routines += uncovered(covered, [s[1] for s in symbols.get(index, [])], insns)
        if not routines:
            routines.append((0, insns[-1].offset + insns[-1].size, None))
        for begin, end, info in routines:
            codes = None
            parse_error = None
            if info is not None:
                try:
                    prologue, framed, codes = unwind_codes(info)
                except (ValueError, IndexError, struct.error) as error:
                    parse_error = str(error)
            # no prologue but codes: a fragment entered with the frame they describe (GCC's
            # .text.unlikely part of a function carries its parent's codes that way)
            start = (sum(8 if op == "push" else arg for _, op, arg in codes if op in ("push", "alloc"))
                     if codes and prologue == 0 else 0)
            walk = Walk(insns, begin, end, "coff", start)
            walk.run()
            problems = walk.common_problems()
            if info is None:
                for offset, (depth, _, _, _) in sorted(walk.states.items()):
                    if depth != 0:
                        problems.append(f"+{offset:#x}: rsp moved by {depth} and the routine has no unwind information")
                        break
            else:
                if parse_error:
                    problems.append(parse_error)
                for i, insn in enumerate(walk.insns if codes is not None else []):
                    state = walk.states.get(insn.offset)
                    if state is None:
                        continue
                    depth, saved, _, _ = state
                    at = insn.offset - begin
                    live = [c for c in codes if c[0] <= at] if at < prologue else codes
                    described = sum(8 if op == "push" else arg for _, op, arg in live if op in ("push", "alloc"))
                    kept = {arg for _, op, arg in live if op in ("push", "save")}
                    if at >= prologue and epilogue_at(walk.insns, i):
                        continue
                    if not (framed and at >= prologue):
                        if depth is None:
                            problems.append(f"+{insn.offset:#x}: the stack depth is not known here and no frame register is set")
                        elif depth != described:
                            problems.append(f"+{insn.offset:#x}: rsp moved by {depth}, the unwind codes say {described}")
                    for register, _ in saved:
                        if register not in kept:
                            problems.append(f"+{insn.offset:#x}: {register} pushed and not in the unwind codes")
            if problems:
                label = next((s[0] for s in symbols.get(index, []) if s[1] == begin), name)
                reports.append((label, "; ".join(dict.fromkeys(problems))))
    return reports, 0


def check(path: Path) -> tuple[Path, list[tuple[str, str]], str | None, int]:
    """(object, reports, error, routines whose only gap is an undescribed epilogue) of an object."""
    try:
        data = path.read_bytes()
        if data[:4] == ELF_MAGIC:
            reports, epilogues = check_elf(data)
        elif data[:2] == COFF_AMD64 or is_bigobj(data):
            reports, epilogues = check_coff(data)
        else:
            return path, [], f"{path}: neither ELF nor x86-64 COFF, not checked", 0
        return path, reports, None, epilogues
    except (subprocess.CalledProcessError, ValueError, KeyError, IndexError, struct.error, OSError) as error:
        return path, [], f"{path}: {type(error).__name__}: {error}", 0


def scan(paths: list[str], allow: list[str], jobs: int) -> tuple[list[str], list[str], int, int]:
    """(reports that fail, reports that --allow excuses, objects, routines with an undescribed
    epilogue only) for the gates that import this."""
    allowed = [re.compile(pattern) for pattern in allow]
    failing: list[str] = []
    excused: list[str] = []
    epilogues = 0
    objects = [item for name in paths
               for item in (sorted(Path(name).rglob("*.o")) if Path(name).is_dir() else [Path(name)])]
    # the biggest first, so that none of them is left alone at the end of the pool's work
    work = sorted(objects, key=lambda item: item.stat().st_size, reverse=True)
    with ProcessPoolExecutor(max_workers=max(1, jobs)) as pool:
        results = sorted(pool.map(check, work, chunksize=1), key=lambda result: str(result[0]))
    for path, reports, error, gaps in results:
        epilogues += gaps
        if error:
            failing.append(f"ERROR {error}")
        for routine, text in reports:
            line = f"{path.name}: {routine}: {text}"
            (excused if any(p.search(routine) for p in allowed) else failing).append(line)
    return failing, excused, len(objects), epilogues


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--allow", action="append", default=[],
                    help="REGEX of a routine that is reported but does not fail")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    args = ap.parse_args()
    failing, excused, count, epilogues = scan(args.paths, args.allow, args.jobs)
    for line in excused:
        print("ALLOWED " + line)
    for line in failing:
        print("UNDESCRIBED " + line)
    print(f"UNWIND_FRAMES objects={count} reported={len(failing)} allowed={len(excused)} "
          f"epilogue-only={epilogues}")
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
