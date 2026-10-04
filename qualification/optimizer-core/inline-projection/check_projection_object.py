#!/usr/bin/env python3
"""Check native objdump -dr --no-show-raw-insn output for tinlineborrowedprojection1."""
from pathlib import Path
import re
import sys


def check(listing):
    bodies = {}
    for name, body in re.findall(
            r'^[0-9a-f]+ <([^>]+)>:\n(.*?)(?=^[0-9a-f]+ <|^Disassembly of section |\Z)', listing, re.M | re.S):
        name = name.upper().split('_$$_')[-1].split('$')[0]
        bodies[name] = body
    for name in ('FIELDSHAPE', 'ELEMENTSHAPE', 'POINTERSHAPE', 'RECORDSHAPE', 'PLAINSHAPE'):
        if name not in bodies:
            raise ValueError('missing ' + name)
        if re.search(r'\bcallq?\s|BORROW(?:FIELD|ELEMENT|POINTER|RECORD|PLAIN)\$', bodies[name], re.I):
            raise ValueError(name + ' still calls a helper instead of reading the descriptor')
    owned = bodies.get('OWNEDSHAPE', '').upper()
    for name in ('OWNRECORD', 'OWNARRAY'):
        if name not in owned:
            raise ValueError('owning producer below projection lost its call boundary: ' + name)


if __name__ == '__main__':
    try:
        check(Path(sys.argv[1]).read_text(encoding='utf-8'))
    except ValueError as error:
        sys.exit('INLINE_PROJECTION_FAIL ' + str(error))
    print('INLINE_PROJECTION_PASS')
