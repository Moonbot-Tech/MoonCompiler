#!/usr/bin/env python3
"""Gate for what the Win64 unwinder finds at the return address of a call.

RtlLookupFunctionEntry finds the function of a return address in .pdata only
below the function's end, and RtlVirtualUnwind takes a ret found at the return
address for the end of an epilogue and emulates just that ret.  A noreturn
procedure never removes its frame, so the byte behind its last call must lie
inside the function and must not be a return: the compiler puts int3 there
(doc/COMPILER_FIXES.md, "Win64: trailing call in noreturn procedures").
Checked on every .pdata function of the executables:

* TAIL - a call ends the function: its return address is the .pdata end;
* RET - a ret follows a call while the unwind codes of the function move rsp
  (push, stack allocation): the unwinder pops the frame as the caller's address.

RTL-test/run.py runs it on RTL-test/semantic/win64_trailing_call_semantic.dpr,
whose run is the runtime side of the same rule.

Usage:
    python3 pdata_tail_gate.py EXE [EXE ...]
"""

from __future__ import annotations

import struct
import sys
from bisect import bisect_left
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "qualification" / "performance" / "tools"))
import code_placement  # noqa: E402

RSP_OPS = {0, 1, 2, 10}             # UWOP_PUSH_NONVOL, UWOP_ALLOC_LARGE/SMALL, UWOP_PUSH_MACHFRAME
SLOTS = {4: 2, 5: 3, 8: 2, 9: 3}    # UWOP_SAVE_NONVOL(_FAR), UWOP_SAVE_XMM128(_FAR)
RETURNS = (b"\xc3", b"\xc2", b"\xf3\xc3", b"\xf2\xc3")


def load(exe: Path) -> tuple[bytearray, int, list[tuple[int, int, int]]]:
    """(memory image, image base, .pdata records as RVAs) of a PE32+ file."""
    data = exe.read_bytes()
    pe = int.from_bytes(data[0x3C:0x40], "little")
    # MZ header, PE signature, optional header magic 0x20b (PE32+)
    if data[:2] != b"MZ" or data[pe:pe + 4] != b"PE\0\0" or data[pe + 24:pe + 26] != b"\x0b\x02":
        raise SystemExit(f"{exe}: not a PE32+ executable (PE32+ only: the gate reads Win64 .pdata)")
    sections, optsize = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    base, size = struct.unpack_from("<Q", data, opt + 24)[0], struct.unpack_from("<I", data, opt + 56)[0]
    image = bytearray(size)
    for i in range(sections):
        vsize, rva, rawsize, raw = struct.unpack_from("<IIII", data, opt + optsize + 40 * i + 8)
        length = min(vsize, rawsize)
        image[rva:rva + length] = data[raw:raw + length]
    table, tablesize = struct.unpack_from("<II", data, opt + 112 + 3 * 8)
    return image, base, [struct.unpack_from("<III", image, table + i) for i in range(0, tablesize, 12)]


def moves_rsp(image: bytearray, unwind: int) -> bool:
    flags, count = image[unwind] >> 3, image[unwind + 2]
    i = 0
    while i < count:
        op = image[unwind + 5 + 2 * i] & 15
        if op in RSP_OPS:
            return True
        i += SLOTS.get(op, 1)
    if flags & 4:                   # UNW_FLAG_CHAININFO: the primary function's codes follow
        return moves_rsp(image, struct.unpack_from("<I", image, unwind + 4 + 2 * (count + (count & 1)) + 8)[0])
    return False


def check(exe: Path) -> list[str]:
    image, base, records = load(exe)
    insns = code_placement.disassemble(exe)
    starts = sorted(insns)
    _, names = code_placement.read_symbols(exe)
    violations = []
    for begin, end, unwind in records:
        for address in starts[bisect_left(starts, base + begin):bisect_left(starts, base + end)]:
            mnemonic, operands, raw = insns[address]
            if code_placement.effective_instruction(mnemonic, operands)[0] != "call":
                continue
            after = address + len(raw) - base
            rule = ("TAIL" if after >= end else
                    "RET" if image[after:after + 2].startswith(RETURNS) and moves_rsp(image, unwind) else None)
            if rule:
                violations.append(f"{rule} {names.get(base + begin, f'sub_{base + begin:x}')}: "
                                  f"call at {address:x}, return address {base + after:x}, .pdata end {base + end:x}")
    print(f"# {exe}: {len(records)} .pdata functions, {len(violations)} violations")
    return violations


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    violations = [line for exe in sys.argv[1:] for line in check(Path(exe))]
    if violations:
        print(f"PDATA TAIL GATE: FAIL ({len(violations)} return addresses the Win64 unwinder misreads)")
        for line in violations:
            print(" *", line)
        return 1
    print("PDATA TAIL GATE: PASS (every return address lies inside its function and no bare ret follows a call)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
