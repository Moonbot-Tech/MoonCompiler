#!/usr/bin/env python3
"""Check that two linked ELF64 files differ in .text/.init only by GOT/PLT bindings."""
import argparse
from pathlib import Path
import re
import struct
import subprocess


def elf(path):
    data = path.read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01', path
    header = struct.unpack_from('<HHIQQQIHHHHHH', data, 16)
    entries = [struct.unpack_from('<IIQQQQIIQQ', data, header[5] + i * header[10])
               for i in range(header[11])]
    string_section = entries[header[12]]
    names = data[string_section[4]:string_section[4] + string_section[5]]
    result = {}
    for entry in entries:
        name = names[entry[0]:].split(b'\0', 1)[0].decode()
        result[name] = (entry[3], data[entry[4]:entry[4] + entry[5]])
    return result


def disassemble(path, section):
    output = subprocess.check_output(['objdump', '-d', '-w', '-j', section, str(path)], text=True)
    for line in output.splitlines():
        match = re.match(r'^\s*([0-9a-f]+):\s*((?:[0-9a-f]{2}\s+)+)(.*)$', line)
        if match:
            yield int(match[1], 16), bytes.fromhex(match[2]), match[3].strip()


def plt_bindings(path):
    output = subprocess.check_output(['objdump', '-d', '-j', '.plt', str(path)], text=True)
    return {int(address, 16): name for address, name in
            re.findall(r'^([0-9a-f]+) <([^>]+@plt)>:', output, re.M)}


def got_bindings(sections):
    dynsym = sections['.dynsym'][1]
    dynstr = sections['.dynstr'][1]
    names = []
    for offset in range(0, len(dynsym), 24):
        string_offset = struct.unpack_from('<I', dynsym, offset)[0]
        names.append(dynstr[string_offset:].split(b'\0', 1)[0].decode())
    relocations = {}
    for offset in range(0, len(sections['.rela.dyn'][1]), 24):
        address, info, addend = struct.unpack_from('<QQq', sections['.rela.dyn'][1], offset)
        relocations[address] = (names[info >> 32], info & 0xffffffff, addend)
    got = sections['.got']
    def binding(address):
        assert got[0] <= address <= got[0] + len(got[1]) - 8 and address % 8 == 0, hex(address)
        if address in relocations:
            return ('dynamic',) + relocations[address]
        return ('local', struct.unpack_from('<Q', got[1], address - got[0])[0])
    return binding


def check(full, compact):
    left, right = elf(full), elf(compact)
    lplt, rplt = plt_bindings(full), plt_bindings(compact)
    lgot, rgot = got_bindings(left), got_bindings(right)
    changed = 0
    for section in ('.text', '.init'):
        base, old = left[section]
        assert right[section][0] == base and len(right[section][1]) == len(old), section
        new = right[section][1]
        covered = bytearray(len(old))
        for address, code, assembly in disassemble(full, section):
            start = address - base
            replacement = new[start:start + len(code)]
            assert old[start:start + len(code)] == code, (section, hex(address))
            if code == replacement:
                continue
            changed += 1
            if len(code) == 5 and code[0] in (0xe8, 0xe9):
                old_target = address + 5 + struct.unpack_from('<i', code, 1)[0]
                new_target = address + 5 + struct.unpack_from('<i', replacement, 1)[0]
                assert lplt.get(old_target) is not None and lplt[old_target] == rplt.get(new_target), (hex(address), assembly)
                displacement = 1
            else:
                assert '%rip' in assembly, (hex(address), assembly)
                candidates = []
                for index in range(len(code) - 4):
                    if code[index] & 0xc7 != 0x05:
                        continue
                    old_target = address + len(code) + struct.unpack_from('<i', code, index + 1)[0]
                    new_target = address + len(code) + struct.unpack_from('<i', replacement, index + 1)[0]
                    try:
                        if lgot(old_target) == rgot(new_target):
                            candidates.append(index + 1)
                    except AssertionError:
                        pass
                assert len(candidates) == 1, (hex(address), assembly, candidates)
                displacement = candidates[0]
            assert code[:displacement] == replacement[:displacement]
            assert code[displacement + 4:] == replacement[displacement + 4:], (hex(address), assembly)
            covered[start:start + len(code)] = b'\x01' * len(code)
        assert all(old[i] == new[i] or covered[i] for i in range(len(old))), section
    return changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('full', type=Path)
    parser.add_argument('compact', type=Path)
    args = parser.parse_args()
    print('ELF_LINK_BINDINGS_PASS', check(args.full, args.compact), 'adjusted instructions')
