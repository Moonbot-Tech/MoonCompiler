#!/usr/bin/env python3
"""The zlib objects System.ZLib links unwind, and copy more than a byte a step.

System.ZLib links zlib 1.3.1 compiled to freestanding objects
(packages/vcl-compat/native/zlib/<target>, build.py), installed next to
system.zlib.ppu - on Win64 and on Linux, and MoonORMot's mormot.lib.z
compresses through the same unit.  Two defects of the first Win64 build went
unnoticed, because nothing looked at the objects:

* they were built with -fno-asynchronous-unwind-tables: no .pdata/.xdata, and
  every zlib routine that moves rsp looked like a leaf to the Win64 unwinder -
  an EOutOfMemory of the unit's allocator inside deflateInit/inflateInit, or a
  fault on a buffer, ended the program past its except, and at -O3 let it go on
  with registers zlib had not given back (on Linux the same objects without
  .eh_frame leave the table-driven unwinder no way through a zlib frame);
* -DZ_SOLO implies NO_MEMCPY (zutil.h): zlib copies through its own zmemcpy,
  which GCC's -O2 left a loop over single bytes - the window after every
  inflate call, deflate's input; an exchange websocket message cost 27 % more
  than on Delphi;
* -DZ_SOLO also leaves zutil.h without the 8-byte integer type, and crc32.c
  without it computes the CRC a byte a step instead of its braided five words
  - every ZIP entry mORMot writes was 3.7 % dearer on Win64;
* without the two-byte candidate check, deflate.c's longest_match costs a ZIP
  entry 3.9-5.3 % on Linux; on Win64 the two-byte match extension made a short
  trade packet dearer, so that target keeps the candidate check and byte scan.

The gate reads the eight objects the toolchain installed for the target it
runs on (--objects DIR: any other set, e.g. the objects of an older commit):
1. each object has its unwind tables - .pdata and .xdata (COFF), .eh_frame
   (ELF) - and qualification/performance/tools/unwind_frames.py finds every
   routine of it described;
2. zmemcpy and zmemzero of moonzlib_zutil.o each have a loop that stores 8
   bytes or more a step (a copy or clear whose loops all store single bytes is
   the defect; rep movs/stos count as wide) - or, where zlib is built with the
   C library (Linux: no Z_SOLO), zutil.o has neither and the objects copy and
   clear through the C library's memcpy and memset;
3. moonzlib_crc32.o carries crc_braid_table, the table of crc32.c's braided
   CRC, which exists only when crc32.c has its word type;
4. longest_match of moonzlib_deflate.o has two 16-bit candidate compares on
   both targets, then eight byte compares on Win64 or four 16-bit compares on
   Linux in the unrolled match extension.
Before that it checks itself: the loop of the first objects' zmemcpy (their
bytes are below) must be taken for a byte copy, a 16-byte loop must not.

Usage: python3 zlib_objects_gate.py [--toolchain DIR | --objects DIR] [--objdump PATH]
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification" / "performance" / "tools"))
import unwind_frames  # noqa: E402

NAMES = ("adler32", "crc32", "deflate", "inffast", "inflate", "inftrees", "trees", "zutil")
ROUTINES = ("moon_zlib_zmemcpy", "moon_zlib_zmemzero")
# what zlib calls in their place when it is built with the C library (zutil.h without NO_MEMCPY)
LIBRARY = {"moon_zlib_zmemcpy": "memcpy", "moon_zlib_zmemzero": "memset"}
INSN = re.compile(r"^\s*([0-9a-f]+):\t[0-9a-f ]+\t(.*)$")
HEAD = re.compile(r"^([0-9a-f]+) <([^>]+)>:$")
WIDTH = {"BYTE": 1, "WORD": 2, "DWORD": 4, "QWORD": 8, "TBYTE": 10, "XMMWORD": 16, "YMMWORD": 32, "ZMMWORD": 64}
# zmemcpy of the objects of 9f9ffd0cd..70a8ad900 (GCC -O2): test; je; the byte loop; ret
BYTE_LOOP = bytes.fromhex("4585c0741d4589c031c0660f1f440000440fb60c02"
                          "44880c014883c0014c39c075eec3")
# the 16-byte loop of the same routine at -O3: movdqu; movups; add; cmp; jne; ret
WIDE_LOOP = bytes.fromhex("f30f6f04020f1104014883c0104c39c875eec3")


class GateError(Exception):
    pass


def installed(toolchain: Path) -> Path:
    """The vcl-compat unit directory of the toolchain for this platform: system.zlib.ppu and its objects."""
    if os.name == "nt":
        return toolchain / "units" / "x86_64-win64" / "vcl-compat"
    found = sorted(toolchain.glob("lib/fpc/*/units/x86_64-linux/vcl-compat"))
    return found[0] if found else toolchain / "lib" / "fpc" / "units" / "x86_64-linux" / "vcl-compat"


def parse(text: str) -> dict[str, list[tuple[int, str, str, bool]]]:
    """routine (or the section of a raw dump) -> [(address, mnemonic, operands, rep)]."""
    routines: dict[str, list[tuple[int, str, str, bool]]] = {}
    current: list | None = None
    for line in text.splitlines():
        head = HEAD.match(line)
        if head:
            current = routines.setdefault(head.group(2), [])
            continue
        insn = INSN.match(line)
        if current is None or not insn:
            continue
        words = insn.group(2).split("#", 1)[0].split()
        rep = False
        while words and words[0].lower() in unwind_frames.PREFIXES:
            rep = rep or words[0].startswith("rep")
            words = words[1:]
        if words:
            current.append((int(insn.group(1), 16), words[0], " ".join(words[1:]), rep))
    return routines


def store_width(mnemonic: str, operands: str, rep: bool) -> int:
    """Bytes a step of a store (0: not a store to memory)."""
    destination = operands.split(",", 1)[0]
    if "[" not in destination or not mnemonic.startswith(("mov", "vmov", "stos")):
        return 0
    if rep and mnemonic.startswith(("movs", "stos")):
        return 64  # the processor's own block copy or fill
    size = re.match(r"([A-Z]+) PTR", destination)
    return WIDTH.get(size.group(1), 0) if size else 0


def loops(insns: list[tuple[int, str, str, bool]]) -> list[tuple[int, int, int]]:
    """(start, end, widest store) of every loop: a jump back to an address of the routine."""
    found = []
    start = insns[0][0] if insns else 0
    for address, mnemonic, operands, _ in insns:
        target = re.match(r"(?:0x)?([0-9a-f]+)\b", operands)
        if not (mnemonic.startswith(("j", "loop")) and target):
            continue
        back = int(target.group(1), 16)
        if start <= back <= address:
            width = max((store_width(m, o, r) for a, m, o, r in insns if back <= a <= address), default=0)
            found.append((back, address, width))
    return found


def verdict(insns: list[tuple[int, str, str, bool]]) -> str | None:
    """None when a loop stores 8 bytes or more a step, else what the routine does."""
    found = loops(insns)
    if any(width >= 8 for _, _, width in found):
        return None
    if not found:
        return "has no loop"
    return "has no loop that stores 8 bytes or more a step: " + ", ".join(
        f"+{start:#x}..+{end:#x} {width or 'no'} byte{'s' if width != 1 else ''} a step"
        for start, end, width in found)


def objdump_text(objdump: str, arguments: list[str]) -> str:
    result = subprocess.run([objdump, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise GateError(f"{objdump} {' '.join(arguments)}: {result.stderr.strip()[-500:]}")
    return result.stdout


def self_check(objdump: str) -> None:
    with tempfile.TemporaryDirectory(prefix="zlib-gate-") as temporary:
        verdicts = []
        for name, code in (("byte", BYTE_LOOP), ("wide", WIDE_LOOP)):
            raw = Path(temporary) / f"{name}.bin"
            raw.write_bytes(code)
            routines = parse(objdump_text(objdump, ["-D", "-w", "-b", "binary", "-m", "i386:x86-64",
                                                    "-M", "intel", str(raw)]))
            verdicts.append(verdict(next(iter(routines.values()), [])))
    if verdicts[0] is None or verdicts[1] is not None:
        raise GateError(f"the byte-copy check does not see what it must: byte loop -> {verdicts[0]}, "
                        f"16-byte loop -> {verdicts[1]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--toolchain", type=Path, default=ROOT / "toolchain")
    parser.add_argument("--objects", type=Path, help="the directory of the moonzlib_*.o to check")
    parser.add_argument("--objdump", default=None,
                        help="an objdump that reads the objects (default: MOON_OBJDUMP, else the toolchain's "
                             "on Windows, objdump on Linux)")
    args = parser.parse_args()
    objects = (args.objects or installed(args.toolchain)).resolve()
    objdump = args.objdump or os.environ.get("MOON_OBJDUMP") or (
        str(args.toolchain / "bin" / "x86_64-win64" / "objdump.exe") if os.name == "nt" else "objdump")
    os.environ["OBJDUMP"] = objdump
    failures: list[str] = []
    described = 0
    steps: dict[str, int] = {}
    try:
        self_check(objdump)
        for name in NAMES:
            path = objects / f"moonzlib_{name}.o"
            if not path.is_file():
                failures.append(f"{path.name}: missing from {objects}")
                continue
            data = path.read_bytes()
            if data[:4] == unwind_frames.ELF_MAGIC:
                elf = unwind_frames.Elf(data)
                absent = [kind for kind in (".eh_frame",) if kind not in elf.names]
                described += len(unwind_frames.elf_fdes(elf))
            else:
                coff = unwind_frames.Coff(data)
                sections = {section[0] for section in coff.sections}
                absent = [kind for kind in (".pdata", ".xdata") if kind not in sections]
                described += sum(len(content) // 12 for kind, content, _, _ in coff.sections if kind == ".pdata")
            if absent:
                failures.append(f"{path.name}: no {' and no '.join(absent)} - built without unwind tables")
            _, reports, error, _ = unwind_frames.check(path)
            if error:
                failures.append(f"{path.name}: {error}")
            failures += [f"{path.name}: {routine}: {text[:300]}" for routine, text in reports]
        zutil = objects / "moonzlib_zutil.o"
        if zutil.is_file():
            routines = parse(objdump_text(objdump, ["-d", "-w", "-M", "intel", str(zutil)]))
            called = set()
            for name in NAMES:
                path = objects / f"moonzlib_{name}.o"
                if path.is_file():
                    called |= {line.split()[-1] for line in objdump_text(objdump, ["-t", str(path)]).splitlines()
                               if "*UND*" in line}
            for routine in ROUTINES:
                if routine not in routines:
                    if LIBRARY[routine] in called:
                        steps[routine] = f"the C library's {LIBRARY[routine]}"
                        continue
                    failures.append(f"{zutil.name}: no {routine} - zlib copies through something this gate "
                                    f"does not look at")
                    continue
                problem = verdict(routines[routine])
                if problem:
                    failures.append(f"{zutil.name}: {routine} {problem} - zlib copies by byte")
                else:
                    steps[routine] = max(width for _, _, width in loops(routines[routine]))
        crc = objects / "moonzlib_crc32.o"
        if crc.is_file() and not re.search(r"\bcrc_braid_table\b", objdump_text(objdump, ["-t", str(crc)])):
            failures.append(f"{crc.name}: no crc_braid_table - crc32.c was built without its 8-byte word type "
                            f"(Z_SOLO leaves Z_U8 undefined) and computes the CRC a byte a step")
        deflate = objects / "moonzlib_deflate.o"
        if deflate.is_file():
            match = parse(objdump_text(objdump, ["-d", "-w", "-M", "intel", str(deflate)])).get("longest_match")
            if match is None:
                failures.append(f"{deflate.name}: no longest_match - the match search is not where this gate "
                                f"looks")
            else:
                word_compares = sum(mnemonic == "cmp" and bool(re.search(r"\bWORD PTR", operands))
                                    for _, mnemonic, operands, _ in match)
                byte_compares = sum(mnemonic == "cmp" and bool(re.search(r"\bBYTE PTR", operands))
                                    for _, mnemonic, operands, _ in match)
                is_linux = deflate.read_bytes()[:4] == unwind_frames.ELF_MAGIC
                if word_compares < (6 if is_linux else 2) or (not is_linux and byte_compares < 8):
                    failures.append(f"{deflate.name}: longest_match candidate check or match extension differs "
                                    f"(16-bit compares={word_compares}, byte compares={byte_compares})")
    except (GateError, OSError, ValueError, subprocess.SubprocessError) as error:
        failures.append(str(error))
    if failures:
        print("ZLIB OBJECTS GATE: FAIL")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"ZLIB OBJECTS GATE: PASS ({len(NAMES)} objects of {objects} with unwind tables, {described} routines "
          f"described; " + ", ".join(f"{name.removeprefix('moon_zlib_')} {width} bytes a step"
                                     if isinstance(width, int) else f"{name.removeprefix('moon_zlib_')}: {width}"
                                     for name, width in steps.items()) + "; crc32 braided; longest_match checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
