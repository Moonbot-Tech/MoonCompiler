#!/usr/bin/env python3
"""Linux x86-64 unwind encoding, fallback, relocation and execution contract.

Requires a built SDK, GNU readelf/nm/ld and an unused --results directory.
Uses only Python's standard library. Generic COMDAT selection and full reporting
remain in generic_sharing_gate.py and run_reporting_gate.py.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def run(command, work, log, expected=0):
    p = subprocess.run([str(x) for x in command], cwd=work, capture_output=True, timeout=90,
                       env=dict(os.environ, LC_ALL='C'))
    text = (p.stdout + p.stderr).decode(errors='replace')
    (work / log).write_text(text, encoding='utf-8')
    assert p.returncode == expected, (command, p.returncode, text[-2500:])
    return text


def frames(exe, work):
    text = run(['readelf', '--wide', '--debug-dump=frames', exe], work, 'frames.log')
    cies, fdes = {}, {}
    for block in re.split(r'\n\s*\n', text):
        cie = re.search(r'^([0-9a-f]+)\s+[0-9a-f]+\s+[0-9a-f]+\s+CIE\b', block, re.M)
        fde = re.search(r' FDE cie=([0-9a-f]+) pc=([0-9a-f]+)\.\.([0-9a-f]+)', block)
        aug = re.search(r'^\s*Augmentation data:[ \t]*([^\n]*)', block, re.M)
        data = bytes.fromhex(aug[1]) if aug else b''
        if cie:
            name = re.search(r'Augmentation:\s*"([^"]*)"', block)[1]
            cies[int(cie[1], 16)] = (name, data)
        elif fde:
            start, end = int(fde[2], 16), int(fde[3], 16)
            assert start not in fdes, ('duplicate FDE', hex(start))
            fdes[start] = (int(fde[1], 16), end - start, data)
    symbols = run(['nm', '--defined-only', exe], work, 'symbols.log')
    result = {}
    for name in ('WITHOUTLSDA', 'WITHLSDA'):
        matches = re.findall(r'^([0-9a-f]+) [tT] UNWINDENCODINGUNIT_\$\$_' + name + r'$', symbols, re.M)
        assert len(matches) == 1, (name, matches)
        cie, size, data = fdes[int(matches[0], 16)]
        augmentation, encoding = cies[cie]
        assert size > 0, (name, size)
        result[name] = dict(augmentation=augmentation, encoding=encoding.hex(),
                            augmentation_bytes=len(data), range=size)
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--config', type=Path)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--results', type=Path, required=True)
    args = ap.parse_args()
    compiler, out = args.compiler.resolve(), args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = args.root.resolve() / 'qualification/suite/tests/unwind-encoding'
    common = [compiler]
    if args.config:
        common += ['-n', '@' + str(args.config.resolve())]
    # Isolate the unwind ABI from the product MM and Pascal I/O's existing -Xa
    # failures. The fixture still verifies all cleanup/exception counts.
    common += ['-dMOONCOMPILER_VANILLA_RUNTIME', '-uMOONBOT_MM_PROFILE_REQUIRED']
    rows = []
    for label, flags, encoding, width in [('small', [], 0x1b, 4), ('large', ['-Xa'], 0, 8),
                                         ('external', ['-Aas'], 0, 8),
                                         ('pie', ['-Cg', '-k-pie'], 0x1b, 4)]:
        work = out / label
        shutil.copytree(source, work)
        run(common + ['-B', '-O2', '-Xs-', *flags, '-Fu' + str(work), '-FU' + str(work),
                      '-FE' + str(work), 'UnwindEncoding.dpr'], work, 'compile.log')
        exe = work / 'UnwindEncoding'
        run([exe], work, 'runtime.log')
        actual = frames(exe, work)
        plain, handled = actual['WITHOUTLSDA'], actual['WITHLSDA']
        assert plain['augmentation'] == 'zR' and plain['augmentation_bytes'] == 0, actual
        assert plain['encoding'] == bytes([encoding]).hex(), actual
        # zPLR: native-width personality + L + R; ld may make the personality PC-relative.
        ciedata = bytes.fromhex(handled['encoding'])
        assert handled['augmentation'] == 'zPLR' and handled['augmentation_bytes'] == width, actual
        assert len(ciedata) == 11 and ciedata[0] in (0, 0x1c) and ciedata[-2:] == bytes([encoding, encoding]), actual
        if label == 'pie':
            assert int.from_bytes(exe.read_bytes()[16:18], 'little') == 3, 'expected ELF ET_DYN'
        rows.append(dict(case=label, functions=actual))
    # Real linker overflow, without allocating a multi-gigabyte function.
    for label, flags, expected in [('small', [], 1), ('large', ['-Xa'], 0)]:
        work = out / ('far-' + label)
        work.mkdir()
        shutil.copyfile(source / 'UnwindRange.pas', work / 'UnwindRange.pas')
        run(common + ['-B', '-O2', *flags, '-FU' + str(work), 'UnwindRange.pas'], work, 'compile.log')
        text = run(['ld', '--unresolved-symbols=ignore-all', '-e', '0', '-Ttext=0x10000',
                    '--section-start=.eh_frame=0x100000000', '-o', 'far.elf', 'UnwindRange.o'],
                   work, 'link.log', expected)
        if expected:
            assert 'R_X86_64_PC32' in text and 'relocation truncated' in text, text
        rows.append(dict(case='far-' + label, expected_exit=expected))
    (out / 'results.json').write_text(json.dumps(dict(
        compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=rows), indent=2))
    print('UNWIND_ENCODING_PASS', len(rows))


if __name__ == '__main__':
    main()
