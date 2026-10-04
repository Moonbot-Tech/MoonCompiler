"""Lazy linked-code evidence with constants preserved in the identity hash."""
from __future__ import annotations

from bisect import bisect_left, bisect_right
from collections.abc import Mapping
from dataclasses import asdict
import hashlib
from pathlib import Path
import re

import code_placement as cp


RIP = re.compile(r"\brip(?P<sign>[+-])(?P<distance>0x[0-9a-f]+)\b", re.I)
ELF_RELOCATION = re.compile(r'^([0-9a-f]+)\s+(R_X86_64_\w+)\s+', re.I)


def absolute_relocations(executable: Path) -> dict[int, int]:
    with executable.open('rb') as stream:
        if stream.read(4) != b'\x7fELF':
            return {}
    sections = {}
    for line in cp.run([cp.tool('objdump'), '-h', str(executable)]).splitlines():
        fields = line.split()
        if len(fields) >= 4 and fields[0].isdigit():
            sections[fields[1]] = int(fields[3], 16)
    result = {}
    count = 0
    section = None
    widths = {'R_X86_64_32': 4, 'R_X86_64_32S': 4, 'R_X86_64_64': 8}
    for line in cp.run([cp.tool('objdump'), '-r', str(executable)]).splitlines():
        header = re.match(r'RELOCATION RECORDS FOR \[(.+)\]:', line)
        if header:
            section = header[1]
        match = ELF_RELOCATION.match(line)
        if match:
            count += 1
            if match[2] in widths:
                result[sections[section] + int(match[1], 16)] = widths[match[2]]
    if not count:
        raise ValueError(f'{executable}: ELF static relocations missing; build with -k--emit-relocs')
    return result


def padding(raw: bytes) -> bool:
    """Only architectural NOPs, never a 32-bit LEA that zeroes the high half."""
    index = 0
    while index < len(raw) and raw[index] in (0x66, 0x67, 0x2e, 0x3e, 0x26, 0x36, 0x64, 0x65):
        index += 1
    return raw[index:] == b"\x90" or raw[index:index + 2] == b"\x0f\x1f"


class ImageShapes(Mapping):
    def __init__(self, executable: Path):
        self.executable = executable
        self.relocations = absolute_relocations(executable)
        self.procedures = {begin: (name, begin, end) for name, begin, end in cp.procedures(executable)
                           if not name.startswith(('DEBUGSTART_', 'DEBUGEND_'))}
        self.starts = sorted(self.procedures)
        anchors = [begin for name, begin, _ in self.procedures.values()
                   if 'PULSE_HARNESS' in name.upper() and '_$$_PULSERUNCASE$' in name.upper()]
        if len(anchors) != 1:
            raise ValueError(f'{executable}: missing or ambiguous PulseRunCase anchor')
        self.anchor = anchors[0]
        self.instructions = cp.linear_disassembly(executable)
        self.addresses = sorted(self.instructions)
        self.decoded = set()
        self.symbols = {}
        for line in cp.run([cp.tool('nm'), str(executable)]).splitlines():
            match = cp.NM_LINE.match(line)
            if match:
                address, _, name = match.groups()
                if not name.startswith(('DEBUGSTART_', 'DEBUGEND_')):
                    self.symbols.setdefault(int(address, 16), name)
        self.symbol_starts = sorted(self.symbols)
        self.cache = {}
        self.unresolved_data = set()

    def __iter__(self):
        return iter(self.procedures)

    def __len__(self):
        return len(self.procedures)

    def addresses_in(self, begin: int, end: int) -> list[int]:
        return self.addresses[bisect_left(self.addresses, begin):bisect_left(self.addresses, end)]

    def decode_procedure(self, begin: int) -> None:
        if begin in self.decoded:
            return
        _, begin, end = self.procedures[begin]
        cp.repair_overlaps(self.executable, self.instructions, (begin, end))
        self.addresses = sorted(self.instructions)
        self.decoded.add(begin)

    def symbolic_address(self, target: int) -> str:
        position = bisect_right(self.symbol_starts, target) - 1
        if position < 0:
            raise ValueError(f'address {target:x} has no linked symbol identity')
        begin = self.symbol_starts[position]
        if begin != target:
            self.unresolved_data.add(target)
            return f'unknown-data-after[{self.symbols[begin]}]+{target - begin:x}'
        return self.symbols[begin]

    def branch_identity(self, target: int) -> str:
        position = bisect_right(self.starts, target) - 1
        if position >= 0:
            name, begin, end = self.procedures[self.starts[position]]
            if begin <= target < end:
                self.decode_procedure(begin)
                if target not in self.instructions:
                    raise ValueError(f'branch into an undecoded instruction: {target:x}')
                ordinal = sum(not padding(self.instructions[address][2])
                              for address in self.addresses_in(begin, target))
                return f'{name}@instruction{ordinal}'
        if target not in self.symbols:
            raise ValueError(f'unresolved direct branch target: {target:x}')
        return self.symbols[target]

    def address_identity(self, target: int) -> str:
        if self.starts[0] <= target < self.procedures[self.starts[-1]][2]:
            position = bisect_right(self.addresses, target) - 1
            address = self.addresses[position]
            if address <= target < address + len(self.instructions[address][2]):
                # Exception location pointers may identify a byte within an
                # instruction. Direct control-flow targets may not.
                return self.branch_identity(address) + f'+byte{target - address}'
        return self.symbolic_address(target)

    def proof_instructions(self, begin: int, end: int) -> list[str]:
        self.decode_procedure(begin)
        normalized = []
        for address in self.addresses_in(begin, end):
            mnemonic, operands, raw = self.instructions[address]
            if padding(raw):
                continue
            branch = cp.BRANCH_TARGET.match(operands)
            if (mnemonic == 'call' or mnemonic.startswith('j') or mnemonic in cp.JUMPS) and branch:
                operands = self.branch_identity(int(branch.group(1), 16))
            else:
                def relocate(match):
                    distance = int(match['distance'], 16)
                    if match['sign'] == '-':
                        distance = -distance
                    target = (address + len(raw) + distance) & 0xffffffffffffffff
                    return 'rip[' + self.address_identity(target) + ']'
                operands = RIP.sub(relocate, operands)
                for offset in range(len(raw)):
                    width = self.relocations.get(address + offset)
                    if width:
                        if offset + width > len(raw):
                            raise ValueError(f'relocation crosses instruction at {address:x}')
                        target = int.from_bytes(raw[offset:offset + width], 'little')
                        token = re.compile(r'(?<![0-9a-f])0x' + f'{target:x}' + r'(?![0-9a-f])', re.I)
                        operands, count = token.subn('address[' + self.address_identity(target) + ']', operands)
                        if count != 1:
                            raise ValueError(f'unresolved absolute relocation at {address + offset:x}')
            normalized.append(mnemonic + ' ' + operands)
        return normalized

    def proof_hash(self, begin: int, end: int) -> str:
        return hashlib.sha256('\n'.join(self.proof_instructions(begin, end)).encode()).hexdigest()

    def __getitem__(self, begin: int) -> dict:
        if begin in self.cache:
            return self.cache[begin]
        self.decode_procedure(begin)
        name, begin, end = self.procedures[begin]
        shape = asdict(cp.analyze(name, begin, end, self.instructions))
        calls, branches = [], []
        for address in self.addresses_in(begin, end):
            mnemonic, operands, raw = self.instructions[address]
            if mnemonic == 'call' or mnemonic.startswith('j') or mnemonic in cp.JUMPS:
                match = cp.BRANCH_TARGET.match(operands)
                target = int(match.group(1), 16) if match else None
                entry = {'at': address, 'offset': address - begin, 'mod64': address % 64,
                         'bytes': len(raw), 'target': target,
                         'target_mod64': target % 64 if target is not None else None,
                         'instruction': mnemonic + ' ' + operands}
                (calls if mnemonic == 'call' else branches).append(entry)
        self.unresolved_data = set()
        fingerprint = self.proof_hash(begin, end)
        shape.update(calls=calls, branches=branches, proof_sha256=fingerprint,
                     unresolved_data_references=sorted(self.unresolved_data))
        self.cache[begin] = shape
        return shape
