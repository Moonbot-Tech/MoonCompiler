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


def cfa_encoding(common, out):
    """Exercise the normative width boundaries using actual assembled code distances."""
    distances = (0, 1, 63, 64, 255, 256, 65535, 65536)
    source = 'program CfaEncoding; {$asmmode att}\n'
    for distance in distances:
        source += (f"procedure Adv{distance}; assembler; nostackframe; public name 'Adv{distance}';\n"
                   'asm\n.cfi_def_cfa_offset 8\n')
        source += '.balign 1\n' if distance == 0 else 'nop\n' * distance
        source += '.cfi_def_cfa_offset 8\nend;\n'
    source += """procedure SavedRegister; assembler; nostackframe; public name 'SavedRegister';
asm
pushq %rbx
.cfi_def_cfa_offset 16
.cfi_offset %rbx,-16
nop
popq %rbx
.cfi_def_cfa_offset 8
.cfi_restore %rbx
end;
begin
"""
    source += ''.join(f'Adv{distance};\n' for distance in distances)
    source += 'SavedRegister; Halt(0); end.\n'
    rows = []
    for label, flags in [('small', []), ('large', ['-Xa']), ('external', ['-Aas'])]:
        work = out / ('cfa-' + label)
        work.mkdir()
        (work / 'CfaEncoding.dpr').write_text(source)
        run(common + ['-B', '-O2', '-Xs-', *flags, '-FU.', '-FE.', 'CfaEncoding.dpr'], work, 'compile.log')
        exe = work / 'CfaEncoding'
        run([exe], work, 'runtime.log')
        text = run(['readelf', '--wide', '--debug-dump=frames', exe], work, 'frames.log')
        symbols = run(['nm', '--defined-only', exe], work, 'symbols.log')
        fdes = {}
        for block in re.split(r'\n\s*\n', text):
            match = re.search(r'^([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+FDE cie=[0-9a-f]+ '
                              r'pc=([0-9a-f]+)\.\.([0-9a-f]+)', block, re.M)
            if match:
                offset, length, start, end = [int(value, 16) for value in match.groups()]
                fdes[start] = dict(offset=offset, length=length, size=end-start, body=block)
        cases = []
        for distance in distances:
            matches = re.findall(r'^([0-9a-f]+) [tT] Adv' + str(distance) + r'$', symbols, re.M)
            assert len(matches) == 1, (distance, matches)
            frame = fdes[int(matches[0], 16)]
            advances = [(kind, int(delta)) for kind, delta in
                        re.findall(r'DW_CFA_(advance_loc[124]?):\s+(\d+) to', frame['body'])]
            assert frame['size'] == distance + 1, (label, distance, frame)
            assert sum(delta for _, delta in advances) == distance, (label, distance, advances)
            if label != 'external':
                kind = ('advance_loc' if distance <= 63 else 'advance_loc1' if distance <= 255
                        else 'advance_loc2' if distance <= 65535 else 'advance_loc4')
                assert advances == ([] if distance == 0 else [(kind, distance)]), (label, distance, advances)
            cases.append(dict(distance=distance, advances=advances, length=frame['length']))
        matches = re.findall(r'^([0-9a-f]+) [tT] SavedRegister$', symbols, re.M)
        assert len(matches) == 1, matches
        saved = fdes[int(matches[0], 16)]['body']
        assert 'DW_CFA_offset: r3 (rbx) at cfa-16' in saved, saved
        assert 'DW_CFA_restore: r3 (rbx)' in saved, saved
        assert 'DW_CFA_offset_extended' not in saved and 'DW_CFA_restore_extended' not in saved, saved
        if label == 'small':
            assert all((frame['length'] + 4) % 4 == 0 for frame in fdes.values())
            assert any((case['length'] + 4) % 8 == 4 for case in cases), cases
        rows.append(dict(case='cfa-' + label, functions=cases))
    return rows


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
    rows.extend(cfa_encoding(common, out))
    (out / 'results.json').write_text(json.dumps(dict(
        compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=rows), indent=2))
    print('UNWIND_ENCODING_PASS', len(rows))


if __name__ == '__main__':
    main()
