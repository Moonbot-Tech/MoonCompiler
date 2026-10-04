#!/usr/bin/env python3
"""Where did the code land: procedure entries, loop heads and code hashes.

Reads a linked Win64 PE (or Linux ELF) and reports, per procedure:

* entry address and its remainder modulo 32 and 64 (cache-line placement);
* every backward-branch target inside the procedure (natural loop heads)
  with the same remainders;
* the procedure size, the number of padding (nop-family) instructions and
  the raw SHA-256 of its bytes;
* a normalized SHA-256 of its instruction stream where immediates,
  RIP-relative displacements and branch targets are masked and nop padding is
  dropped, so two copies of the same code linked at different addresses or
  with different alignment padding hash identically.

Procedure ranges come from the Win64 `.pdata` function table (via
`objdump -p`); names come from the `T` symbols / `$unwind$<name>` symbols
the internal linker keeps when the program carries debug information
(`-gw3`).  Code symbols without a `.pdata` entry (hand-written assembler
objects) get the range up to the next symbol.  On Linux the ELF symbol table
supplies names and sizes.  A Pulse binary built without debug information has
no names at all: build it with `-gw3` first.

Usage:
    code_placement.py scan  EXE [--match REGEX ...] [--all] [--json OUT]
    code_placement.py compare LEFT.json RIGHT.json [--match REGEX]
"""

from __future__ import annotations

import argparse
from bisect import bisect_left, bisect_right
from collections import Counter
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path


def tool(name: str) -> str:
    override = os.environ.get("MOON_" + name.upper())
    if override:
        return override
    candidates = [name]
    if os.name == "nt":
        candidates = [
            rf"C:\Files\utils\mingw64\bin\{name}.exe",
            f"x86_64-win64-{name}",
            name,
        ]
    for candidate in candidates:
        found = shutil.which(candidate) or (candidate if Path(candidate).is_file() else None)
        if found:
            return found
    raise RuntimeError(f"{name} not found; set MOON_{name.upper()}")


def run(command: list[str]) -> str:
    return subprocess.run(
        command, check=True, text=True, encoding="utf-8", errors="replace",
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    ).stdout


@dataclass
class Branch:
    at: int
    target: int
    mnemonic: str
    target_mod32: int
    target_mod64: int
    body_bytes: int
    lines64: int


@dataclass
class Procedure:
    name: str
    begin: int
    end: int
    size: int
    entry_mod32: int
    entry_mod64: int
    raw_sha256: str
    normalized_sha256: str
    instructions: int
    nops: int
    loops: list[Branch] = field(default_factory=list)


NM_LINE = re.compile(r"^([0-9a-fA-F]+)\s+(\S)\s+(.+)$")
PDATA_LINE = re.compile(
    r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s*$"
)
INSN_LINE = re.compile(r"^\s*([0-9a-fA-F]+):\t([0-9a-f ]+?)\t(\S+)\s*(.*)$")
HEX_TOKEN = re.compile(r"0x[0-9a-fA-F]+|\b[0-9a-fA-F]{6,}\b")
ANNOTATION = re.compile(r"\s*(#.*|<[^>]*>)")
BRANCH_TARGET = re.compile(r"^([0-9a-fA-F]+)\b")
JUMPS = {"jmp", "loop", "loope", "loopne", "loopz", "loopnz"}
NOPS = {"nop", "nopw", "nopl", "xchg", "data16", "cs", "lea"}
DUMMY_PREFIXES = {"cs", "ds", "es", "ss"}
SEMANTIC_PREFIXES = {"fs", "gs", "lock", "rep", "repe", "repz", "repne", "repnz",
                     "data16", "addr16", "bnd", "notrack", "xacquire", "xrelease", "rex"}
REPEAT_OR_LOCK = {"lock", "rep", "repe", "repz", "repne", "repnz", "xacquire", "xrelease"}
LEGACY_PREFIX_BYTES = {0xF0, 0xF2, 0xF3, 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65, 0x66, 0x67}


def leading_prefixes(raw: bytes) -> bytes:
    end = 0
    while end < len(raw) - 1 and raw[end] in LEGACY_PREFIX_BYTES:
        end += 1
    return raw[:end]


def effective_instruction(mnemonic: str, operands: str) -> tuple[str, str]:
    """Return the opcode for control-flow checks without erasing semantic prefixes."""
    while (mnemonic in SEMANTIC_PREFIXES or mnemonic.startswith("rex.")) and operands:
        parts = operands.split(None, 1)
        mnemonic = parts[0]
        operands = parts[1] if len(parts) > 1 else ""
    return mnemonic, operands


def is_padding(mnemonic: str, operands: str) -> bool:
    if mnemonic in DUMMY_PREFIXES and operands:
        parts = operands.split(None, 1)
        return is_padding(parts[0], parts[1] if len(parts) > 1 else "")
    if mnemonic in REPEAT_OR_LOCK:
        return False
    mnemonic, operands = effective_instruction(mnemonic, operands)
    if mnemonic in ("nop", "nopw", "nopl"):
        return True
    if mnemonic == "xchg" and operands.replace(" ", "") == "ax,ax":
        return True
    if mnemonic == "lea":
        # Only a full-width self-LEA is inert; lea esi,[esi] clears the upper half of RSI.
        parts = operands.replace(" ", "").split(",")
        return (len(parts) == 2 and parts[0] in ("rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp",
                                                "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15")
                and parts[1] in (f"[{parts[0]}+0x0]", f"[{parts[0]}]"))
    return False


def read_symbols(exe: Path) -> tuple[dict[int, str], dict[int, str]]:
    """(unwind-info address -> name, code address -> name)."""
    unwind: dict[int, str] = {}
    code: dict[int, str] = {}
    for line in run([tool("nm"), str(exe)]).splitlines():
        match = NM_LINE.match(line)
        if not match:
            continue
        address = int(match.group(1), 16)
        kind = match.group(2)
        name = match.group(3).strip()
        if name.startswith("$unwind$"):
            unwind[address] = name[len("$unwind$"):]
        elif kind in "TtWw":
            # the DEBUGEND_ marker of one unit and the first routine of the next share an
            # address (STRINGS_$$_STRCOMP sat under DEBUGEND_$OBJPAS and no gate saw it)
            if address not in code or code[address].startswith(("DEBUGSTART_", "DEBUGEND_")):
                code[address] = name
    return unwind, code


def read_pdata(exe: Path) -> list[tuple[int, int, int]]:
    rows: list[tuple[int, int, int]] = []
    inside = False
    for line in run([tool("objdump"), "-p", str(exe)]).splitlines():
        if "Function Table" in line:
            inside = True
            continue
        if not inside:
            continue
        match = PDATA_LINE.match(line)
        if match:
            rows.append((int(match.group(2), 16), int(match.group(3), 16), int(match.group(4), 16)))
        elif rows and not line.strip():
            break
    return rows


def read_elf_functions(exe: Path) -> list[tuple[str, int, int]]:
    """ELF: FUNC symbols with sizes from `nm -S`, sizeless ones up to the next symbol."""
    sized: list[tuple[str, int, int]] = []
    unsized: list[tuple[str, int]] = []
    for line in run([tool("nm"), "-S", "--defined-only", str(exe)]).splitlines():
        parts = line.split()
        if len(parts) == 4 and parts[2] in "TtWw":
            begin = int(parts[0], 16)
            size = int(parts[1], 16)
            sized.append((parts[3], begin, begin + size))
        elif len(parts) == 3 and parts[1] in "TtWw":
            unsized.append((parts[2], int(parts[0], 16)))
    starts = sorted({begin for _, begin, _ in sized} | {begin for _, begin in unsized})
    result = list(sized)
    for name, begin in unsized:
        later = [start for start in starts if start > begin]
        if later:
            result.append((name, begin, later[0]))
    return result


# The symbol objdump prints behind a call target (`<_Unwind_Resume@plt>`),
# by instruction address, from the last disassemble() call.  The operands in
# the instruction table are stripped of it so that the normalized code hash
# does not depend on symbol names; the placement checker needs it to tell an
# exception-cleanup re-entry (a block ending in a call to _Unwind_Resume or
# fpc_reraise, then a backward jmp into the function body) from a loop.
CALL_SYMBOLS: dict[int, str] = {}
CALL_SYMBOL = re.compile(r"<([^>]*)>")


def parse_instructions(text: str) -> dict[int, tuple[str, str, bytes]]:
    insns: dict[int, tuple[str, str, bytes]] = {}
    for line in text.splitlines():
        match = INSN_LINE.match(line)
        if not match:
            continue
        address = int(match.group(1), 16)
        raw = bytes.fromhex(match.group(2).replace(" ", ""))
        mnemonic = match.group(3)
        operands = match.group(4).strip()
        while mnemonic in DUMMY_PREFIXES and operands:
            parts = operands.split(None, 1)
            mnemonic = parts[0]
            operands = parts[1] if len(parts) > 1 else ""
        operands = ANNOTATION.sub("", operands).strip()
        if mnemonic.startswith("(bad)"):
            continue
        if effective_instruction(mnemonic, operands)[0] == "call":
            symbol = CALL_SYMBOL.search(match.group(4))
            if symbol:
                CALL_SYMBOLS[address] = symbol.group(1)
        insns[address] = (mnemonic, operands, raw)
    return insns


def linear_disassembly(exe: Path) -> dict[int, tuple[str, str, bytes]]:
    """Read the linear listing; embedded data is not a control-flow root."""
    CALL_SYMBOLS.clear()
    insns = parse_instructions(run([tool("objdump"), "-d", "-M", "intel", "-w", str(exe)]))
    if not insns:
        raise RuntimeError(f"no instructions decoded from {exe}")
    return insns


def repair_overlaps(exe: Path, insns: dict[int, tuple[str, str, bytes]],
                    scope: tuple[int, int] | None = None) -> dict[int, tuple[str, str, bytes]]:
    """Recover alternate entries reached by branches from the requested procedure."""
    if scope is not None and (scope[0] >= scope[1] or scope[0] not in insns):
        raise RuntimeError(f"missing instruction at procedure entry: {scope[0]:x}")
    while True:
        addresses = sorted(insns)
        overlap = None
        origins = addresses if scope is None else addresses[bisect_left(addresses, scope[0]):bisect_left(addresses, scope[1])]
        for address in origins:
            mnemonic, operands, _ = insns[address]
            mnemonic, operands = effective_instruction(mnemonic, operands)
            if not (mnemonic.startswith("j") or mnemonic in JUMPS or mnemonic == "call"):
                continue
            match = BRANCH_TARGET.match(operands)
            if not match:
                continue
            target = int(match.group(1), 16)
            if target in insns:
                continue
            index = bisect_right(addresses, target) - 1
            if index < 0:
                continue
            start = addresses[index]
            end = start + len(insns[start][2])
            if target < end:
                overlap = (index, start, target, end)
                break
        if overlap is None:
            break
        index, start, target, end = overlap
        previous = addresses[index - 1] if index else None
        corrected = parse_instructions(run([tool("objdump"), "-d", "-M", "intel", "-w",
                                            f"--start-address=0x{target:x}",
                                            f"--stop-address=0x{end:x}", str(exe)]))
        cursor = target
        for address in sorted(corrected):
            if address != cursor:
                break
            cursor += len(corrected[address][2])
        if target not in corrected or cursor != end:
            raise RuntimeError(f"cannot decode branch target {target:x} inside {start:x}")
        if (previous is not None and previous + len(insns[previous][2]) == start
                and insns[previous][0] in ("jmp", "ret", "retq")):
            del insns[start]
        insns.update(corrected)
    return insns


def disassemble(exe: Path) -> dict[int, tuple[str, str, bytes]]:
    """Decode alternate entries for the full-image placement tools."""
    return repair_overlaps(exe, linear_disassembly(exe))


# A hand layout writes a short forward jump out as its bytes where one assembler pass would take
# the long form (doc/ASM_LAYOUT_RULES.md, "Short jumps forward are decided once"): a db/.byte
# line (a label may stand in front) whose first opcode behind legacy prefixes is a jump, the
# comment naming it (`db $75, $76 // jne @Pending`, `.byte 0x77,0x72 { ja .LWordwise_Prepare }`).
# The line is one by its start, whatever follows the directive: its bytes, then a // or { }
# comment at its end, or the finder has not read it (written_jumps).
BYTES_LINE = re.compile(r"^(\s*(?:[\w@.$]+:\s*)*)(db|\.byte)\b(.*?)(\s*(?://.*|\{[^}]*\}\s*))?$", re.IGNORECASE)
# a decimal has no leading zero: the AT&T reader takes one for octal (raatt.pas; `.byte 017` is 0x4F)
BYTE_VALUE = re.compile(r"\$([0-9a-fA-F]{1,2})|0x([0-9a-fA-F]{1,2})|(0|[1-9]\d{0,2})")
NAMED_JUMP = re.compile(r"\b(j[a-z]+|loop[a-z]*)\s+(@@?\w+|\.L\w+)", re.IGNORECASE)
ROUTINE_HEAD = re.compile(r"\s*(?:procedure|function)\s+([\w.]+)", re.IGNORECASE)
WRITTEN_JUMP_INFO = "MOON_WRITTEN_JUMP"
# nop dword ptr [rax+disp32] in front of a mnemonic of the copy, the displacement its line: the
# listing of the copy names the jump behind it (jumps)
MARK = bytes((0x0F, 0x1F, 0x80))
# objdump -h -d -z -M intel -w: a row of the section table, an instruction, a routine, a direct jump's text
LISTING_SECTION = re.compile(r"\s*\d+ (\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+[0-9a-f]+\s+2\*\*\d+\s+(.+)$")
LISTING_INSN = re.compile(r"\s*([0-9a-f]+):\t([0-9a-f ]+)\t(.*)$")
LISTING_HEAD = re.compile(r"[0-9a-f]+ <(\S+)>:$")
LISTING_JUMP = re.compile(r"\b(j\w+|loop\w*)\S*\s+([0-9a-f]+) <([^>]*)>")


def jump_size(code) -> int:
    """The size of the direct jump whose opcode starts `code` (byte values): rel8, jmp rel32 or jcc
    rel32; 0 for any other opcode."""
    first, second = (list(code[:2]) + [0, 0])[:2]
    if 0x70 <= first <= 0x7F or 0xE0 <= first <= 0xE3 or first == 0xEB:
        return 2
    if first == 0xE9:
        return 5
    return 6 if first == 0x0F and 0x80 <= second <= 0x8F else 0


def jump_target(address: int, raw: bytes) -> int | None:
    """Where the bytes of one instruction at `address` jump to if they are a direct jump, behind
    legacy prefixes and a REX; None if they are none."""
    at = len(leading_prefixes(raw))
    if at < len(raw) - 1 and 0x40 <= raw[at] <= 0x4F:
        at += 1
    size = jump_size(raw[at:])
    if size != len(raw) - at:
        return None
    return address + len(raw) + int.from_bytes(raw[-1 if size == 2 else -4:], "little", signed=True)


def written_jumps(source: str, name: str) -> tuple[str, list[str], list[str]]:
    """The jumps `source` writes out as bytes, found by the bytes (the comment only names them):
    the source with each such line's bytes replaced by the jump its comment names, as a mnemonic
    the assembler places, behind a MARK carrying the line and with an {$info} naming the jump, so
    that a compile with -vi reports the ones it compiled (compiled_written_jumps) and the listing
    of its object shows where they are (jumps); the jumps found (`name:line (routine)`); and the
    problems (a db/.byte line the finder does not read whole - its bytes written otherwise than
    $XX, 0xXX or decimal, an expression among them, or anything but a // or { } comment behind
    them -, a written-out jump whose comment names no mnemonic and label, or that shares its line
    with other bytes)."""
    lines = source.split("\n")
    found: list[str] = []
    problems: list[str] = []
    routine = "no routine"
    for number, line in enumerate(lines, 1):
        head = ROUTINE_HEAD.match(line)
        if head:
            routine = head.group(1)
        match = BYTES_LINE.match(line)
        if not match:
            continue
        where = f"{name}:{number} ({routine})"
        values = [BYTE_VALUE.fullmatch(token.strip()) for token in match.group(3).split(",")]
        if not all(values):
            problems.append(f"{where}: `{match.group(3).strip()}` - bytes the gate cannot read ($XX, 0xXX or decimal, "
                            "then only a // or { } comment)")
            continue
        data = [int(v.group(1) or v.group(2), 16) if v.group(3) is None else int(v.group(3)) for v in values]
        at = 0
        while at < len(data) and data[at] in LEGACY_PREFIX_BYTES:
            at += 1
        size = jump_size(data[at:])
        if not size:
            continue
        jump = NAMED_JUMP.search(match.group(4) or "")
        if at or len(data) != size:
            problems.append(f"{where}: `{match.group(3).strip()}` is a written-out jump with other bytes on its line")
        elif not jump:
            problems.append(f"{where}: `{match.group(3).strip()}` is a written-out jump whose comment names "
                            "no mnemonic and label")
        else:
            found.append(where)
            mark = ",".join(str(byte) for byte in MARK + number.to_bytes(4, "little"))
            lines[number - 1] = (f"{match.group(1)}{match.group(2)} {mark}; {jump.group(1)} {jump.group(2)} "
                                 f"{{$info {WRITTEN_JUMP_INFO} {where}}}{match.group(4) or ''}")
    return "\n".join(lines), found, problems


def compiled_written_jumps(output: str) -> set[str]:
    """The written-out jumps (`name:line (routine)`) a compile of a written_jumps() copy with -vi
    compiled."""
    return set(re.findall(rf"{WRITTEN_JUMP_INFO} (\S+ \([^)]*\))", output))


def jumps(binary: Path) -> tuple[list[tuple[str, int, str, str]], list[int]]:
    """(routine, index, mnemonic, target) of every direct jump in `binary` (an object: every
    routine of its unit), and the lines of the jumps behind a MARK (written_jumps).  Alignment
    fill is not counted, so an index does not depend on the encodings in front of it; a target
    inside the routine is the index of its instruction (on fill: of the one behind it), any other
    stays as objdump names it.  The listing has to account for all the code, or this raises: every
    line of it understood, every code section of the section table listed byte after byte from
    its start to its end (-z: zeros too, objdump prints no `...`), and an instruction whose bytes
    are a direct jump read as one, to the target its bytes reach - an empty or a partial listing
    is no object without jumps."""
    try:
        listing = run([tool("objdump"), "-h", "-d", "-z", "-M", "intel", "-w", str(binary)])
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{binary}: objdump exited {error.returncode}") from None
    code: dict[str, tuple[int, int]] = {}
    routines: dict[tuple[str, str], list[tuple[int, bytes, str]]] = {}
    section, body, at, end = None, [], 0, 0
    for line in listing.splitlines() + ["Disassembly of section :"]:
        insn = LISTING_INSN.match(line)
        row = LISTING_SECTION.match(line)
        head = LISTING_HEAD.match(line)
        if insn and section is not None:
            address, raw = int(insn.group(1), 16), bytes.fromhex(insn.group(2).replace(" ", ""))
            if address != at:
                raise RuntimeError(f"{binary}: {section} is listed on at 0x{address:x}, its code at 0x{at:x}")
            body.append((address, raw, insn.group(3)))
            at = address + len(raw)
        elif line.startswith("Disassembly of section ") and line.endswith(":"):
            if section is not None and at != end:
                raise RuntimeError(f"{binary}: {section} is listed up to 0x{at:x} of 0x{end:x}")
            section = line[len("Disassembly of section "):-1]
            if not section:
                break
            if section not in code or (section, section) in routines:
                raise RuntimeError(f"{binary}: {section} is listed and is no code section of the table, or twice")
            (at, end), body = code[section], routines.setdefault((section, section), [])
        elif head and section is not None:
            body = routines.setdefault((section, head.group(1)), [])
        elif row and section is None:
            name, size, start, flags = row.group(1), int(row.group(2), 16), int(row.group(3), 16), row.group(4)
            if size and {"CODE", "CONTENTS"} <= set(flags.split(", ")):
                code[name] = (start, start + size)
        elif line.strip() and not (section is None and (line == "Sections:" or line.startswith("Idx Name")
                                                        or re.search(r":\s+file format ", line))):
            raise RuntimeError(f"{binary}: a line of the objdump listing not understood: {line.strip()[:120]}")
    if not code:
        raise RuntimeError(f"{binary}: objdump listed no code section of it")
    unlisted = sorted(name for name in code if (name, name) not in routines)
    if unlisted:
        raise RuntimeError(f"{binary}: {len(unlisted)} of its {len(code)} code sections not listed: "
                           + ", ".join(unlisted[:5]))
    found: list[tuple[str, int, str, str]] = []
    marked: list[int] = []
    for (_, routine), listed in sorted(routines.items()):
        index, k = {}, 0
        for address, _, text in listed:
            index[address] = k
            mnemonic, _, operands = text.partition(" ")
            k += not is_padding(mnemonic, operands.strip())
        mark = None
        for address, raw, text in listed:
            jump = LISTING_JUMP.search(text)
            target = int(jump.group(2), 16) if jump else None
            if target != jump_target(address, raw):
                raise RuntimeError(f"{binary}: {routine}+0x{address:x} `{text.strip()}` ({raw.hex(' ')}): its bytes "
                                   "and the text of objdump disagree on a direct jump")
            if jump:
                found.append((routine.split("$$_")[-1], index[address], jump.group(1),
                              f"#{index[target]}" if target in index else jump.group(3)))
                if mark:
                    marked.append(mark)
            mark = int.from_bytes(raw[3:], "little") if len(raw) == 7 and raw[:3] == MARK else None
    return found, marked


def same_jumps(written: Path, placed: Path, compiled: set[str]) -> tuple[int, list[str]]:
    """(jumps compared, differences) of two builds of one unit: with the written-out jumps and with
    their mnemonics (written_jumps).  Raises unless both listings are whole (jumps), the unit has
    jumps at all and the written-out jumps the build of the copy compiled (`compiled`,
    compiled_written_jumps) are the jumps behind the MARKs of its listing, one for one by line:
    naming a compiled one that is not among the compared jumps, and a marked one the compiler did
    not name (its messages lost)."""
    try:
        (left, _), (right, marked) = jumps(written), jumps(placed)
        problems = [] if left else [f"{written}: not a single direct jump listed"]
    except RuntimeError as error:
        left, right, marked, problems = [], [], [], [str(error)]
    lines = Counter(marked)
    unchecked = []
    for where in sorted(compiled):
        line = int(where.split(" ")[0].rpartition(":")[2])
        if lines[line]:
            lines[line] -= 1
        else:
            unchecked.append(where)
    if unchecked:
        problems.append(f"{len(unchecked)} of the {len(compiled)} written-out jumps compiled not compared: "
                        + ", ".join(unchecked))
    unnamed = sorted(lines.elements())
    if unnamed:
        problems.append(f"{placed}: {len(unnamed)} marked written-out jumps the compiler did not name as compiled, "
                        "lines " + ", ".join(map(str, unnamed)))
    if problems:
        raise RuntimeError("; ".join(problems))
    wrong = [f"{x[0]} {x[2]} #{x[1]} goes to {x[3]}, as a mnemonic to {y[3]}"
             for x, y in zip(left, right) if x != y]
    if len(left) != len(right):
        wrong.append(f"{len(left)} jumps as written, {len(right)} with mnemonics")
    return len(left), wrong


def normalize(mnemonic: str, operands: str) -> str:
    return mnemonic + " " + HEX_TOKEN.sub("IMM", operands)


def analyze(name: str, begin: int, end: int, insns: dict[int, tuple[str, str, bytes]]) -> Procedure:
    raw = hashlib.sha256()
    normalized = hashlib.sha256()
    count = 0
    nops = 0
    loops: dict[int, Branch] = {}
    addresses = [address for address in range(begin, end) if address in insns]
    for address in addresses:
        mnemonic, operands, raw_bytes = insns[address]
        opcode, branch_operands = effective_instruction(mnemonic, operands)
        raw.update(raw_bytes)
        count += 1
        if is_padding(mnemonic, operands):
            nops += 1
        else:
            normalized.update(leading_prefixes(raw_bytes).hex().encode())
            normalized.update(normalize(mnemonic, operands).encode())
            normalized.update(b"\n")
        if opcode.startswith("j") or opcode in JUMPS:
            match = BRANCH_TARGET.match(branch_operands)
            if match:
                target = int(match.group(1), 16)
                if begin <= target < address:
                    body_end = address + len(raw_bytes)
                    branch = Branch(
                        at=address,
                        target=target,
                        mnemonic=opcode,
                        target_mod32=target % 32,
                        target_mod64=target % 64,
                        body_bytes=body_end - target,
                        lines64=(body_end - 1) // 64 - target // 64 + 1,
                    )
                    existing = loops.get(target)
                    if existing is None or branch.body_bytes > existing.body_bytes:
                        loops[target] = branch
    return Procedure(
        name=name,
        begin=begin,
        end=end,
        size=end - begin,
        entry_mod32=begin % 32,
        entry_mod64=begin % 64,
        raw_sha256=raw.hexdigest(),
        normalized_sha256=normalized.hexdigest(),
        instructions=count,
        nops=nops,
        loops=sorted(loops.values(), key=lambda item: item.target),
    )


def procedures(exe: Path) -> list[tuple[str, int, int]]:
    header = exe.read_bytes()[:4]
    if header[:2] == b"MZ":
        unwind, code = read_symbols(exe)
        result = []
        covered: list[tuple[int, int]] = []
        seen: set[tuple[int, int]] = set()
        for begin, end, unwind_address in read_pdata(exe):
            if (begin, end) in seen:
                continue
            seen.add((begin, end))
            covered.append((begin, end))
            name = unwind.get(unwind_address) or code.get(begin) or f"sub_{begin:x}"
            result.append((name, begin, end))
        if not result:
            raise RuntimeError(f"{exe}: no .pdata function table; is this a Win64 PE?")
        if not unwind and not code:
            raise RuntimeError(
                f"{exe}: no symbols at all; build with -gw3 so the linker keeps names"
            )
        # code symbols without unwind information (assembler objects): range up
        # to the next code symbol or pdata function start
        starts = sorted({begin for begin, _ in covered} | set(code))
        for address, name in code.items():
            if any(begin <= address < end for begin, end in covered):
                continue
            later = [start for start in starts if start > address]
            if later:
                result.append((name, address, later[0]))
        return result
    if header == b"\x7fELF":
        return read_elf_functions(exe)
    raise RuntimeError(f"{exe}: unknown executable format")


def scan(exe: Path, patterns: list[str], everything: bool) -> dict[str, object]:
    selected = procedures(exe)
    if not everything:
        regexes = [re.compile(pattern, re.IGNORECASE) for pattern in patterns]
        if not regexes:
            raise ValueError("pass --match REGEX or --all")
        selected = [item for item in selected if any(regex.search(item[0]) for regex in regexes)]
    insns = disassemble(exe)
    report = [analyze(name, begin, end, insns) for name, begin, end in selected]
    report.sort(key=lambda item: item.begin)
    return {
        "executable": str(exe),
        "executable_sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
        "procedures": [asdict(item) for item in report],
    }


def print_scan(report: dict[str, object]) -> None:
    print(f"# {report['executable']}")
    print("| procedure | entry | mod32 | mod64 | size | insns | nops | loops (target:mod64/body bytes/64B lines) | normalized sha256 |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |")
    for item in report["procedures"]:
        loops = "; ".join(
            f"{loop['target']:x}:{loop['target_mod64']}/{loop['body_bytes']}/{loop['lines64']}"
            for loop in item["loops"]
        ) or "-"
        print(
            f"| `{item['name']}` | {item['begin']:x} | {item['entry_mod32']} | {item['entry_mod64']} | "
            f"{item['size']} | {item['instructions']} | {item['nops']} | {loops} | `{item['normalized_sha256'][:16]}` |"
        )


def compare(left: dict[str, object], right: dict[str, object], pattern: str | None) -> int:
    regex = re.compile(pattern, re.IGNORECASE) if pattern else None
    left_map = {item["name"]: item for item in left["procedures"]}
    right_map = {item["name"]: item for item in right["procedures"]}
    names = sorted(set(left_map) & set(right_map))
    if regex:
        names = [name for name in names if regex.search(name)]
    print("| procedure | code | size L/R | nops L/R | entry mod64 L/R | loop heads mod64 L -> R |")
    print("| --- | --- | ---: | ---: | ---: | --- |")
    changed = 0
    for name in names:
        a, b = left_map[name], right_map[name]
        same = a["normalized_sha256"] == b["normalized_sha256"]
        changed += 0 if same else 1
        left_loops = ",".join(str(loop["target_mod64"]) for loop in a["loops"]) or "-"
        right_loops = ",".join(str(loop["target_mod64"]) for loop in b["loops"]) or "-"
        print(
            f"| `{name}` | {'same' if same else 'DIFFERENT'} | {a['size']}/{b['size']} | {a['nops']}/{b['nops']} | "
            f"{a['entry_mod64']}/{b['entry_mod64']} | {left_loops} -> {right_loops} |"
        )
    missing_left = sorted(set(right_map) - set(left_map))
    missing_right = sorted(set(left_map) - set(right_map))
    if regex:
        missing_left = [name for name in missing_left if regex.search(name)]
        missing_right = [name for name in missing_right if regex.search(name)]
    if missing_left:
        print(f"\nonly in right: {missing_left}")
    if missing_right:
        print(f"\nonly in left: {missing_right}")
    print(f"\n{len(names)} compared, {changed} with different code")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan")
    scan_parser.add_argument("exe", type=Path)
    scan_parser.add_argument("--match", action="append", default=[])
    scan_parser.add_argument("--all", action="store_true")
    scan_parser.add_argument("--json", type=Path)
    scan_parser.add_argument("--quiet", action="store_true")
    compare_parser = sub.add_parser("compare")
    compare_parser.add_argument("left", type=Path)
    compare_parser.add_argument("right", type=Path)
    compare_parser.add_argument("--match")
    args = parser.parse_args()
    if args.command == "scan":
        report = scan(args.exe.resolve(), args.match, args.all)
        if args.json:
            args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        if not args.quiet:
            print_scan(report)
        return 0
    left = json.loads(args.left.read_text(encoding="utf-8"))
    right = json.loads(args.right.read_text(encoding="utf-8"))
    compare(left, right, args.match)
    return 0


if __name__ == "__main__":
    sys.exit(main())
