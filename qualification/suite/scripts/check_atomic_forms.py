"""Check that the two Mega cascades actually exercise an atomic on a spilled address."""

import re
import subprocess
import sys
from pathlib import Path


def check(objdump, obj):
    def dump(*options):
        return subprocess.check_output([objdump, *options, obj], text=True, errors="replace")

    headers = dump("-h")
    for name, opcode in (("cascadecompare", "cmpxchg"), ("cascadeadd", "xadd")):
        section = re.search(r"^\s*\d+\s+(\.text\S*\$\$_" + name + r"\$\S+)\s", headers, re.I | re.M)
        if not section:
            sys.exit(f"{obj}: missing Mega function {name}")
        body = dump("-d", "-Mintel", "--no-show-raw-insn", "-j", section[1]).lower()
        instructions = re.findall(r"^\s*[0-9a-f]+:\s+(.+)$", body, re.M)
        locked = [op for op in instructions if op.split()[0] == "lock"]
        for op in locked:
            if op.split()[1:2] != [opcode]:
                sys.exit(f"{name}: expected lock {opcode}, decoded {op}")
        if len(locked) != 20:
            sys.exit(f"{name}: expected 20 locked operations, found {len(locked)}")

        # Look for a reload of the address itself. Several operands may be
        # reloaded together, in any registers and at any offsets.
        restored = set()
        for op in instructions:
            if op.startswith("lock ") and any(re.search(r"\[" + reg + r"\b", op) for reg in restored):
                break
            reload = re.fullmatch(r"mov\s+(r\w+),qword ptr \[r[bs]p[^\]]*\]", op)
            if reload:
                restored.add(reload[1])
            else:
                restored.clear()
        else:
            sys.exit(f"{name}: no locked {opcode} used an address reloaded from the stack")


if __name__ == "__main__":
    compiler, obj = map(Path, sys.argv[1:])
    beside = compiler.resolve().with_name("objdump.exe")
    check(beside if beside.is_file() else "objdump", obj)
