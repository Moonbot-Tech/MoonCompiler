#!/usr/bin/env python3
"""Rebuild the shipped static decoder using Clang and LLVM tools (no C runtime).

Normal Pascal builds use the shipped archives and do not need a C compiler.
Run on Linux: python3 build.py --target linux (or --target win64).
"""
import argparse
from pathlib import Path
import subprocess
import tarfile
import tempfile

p = argparse.ArgumentParser(__doc__)
p.add_argument('--target', choices=('linux', 'win64'), required=True)
p.add_argument('--cc', default='clang')
p.add_argument('--ar', default='llvm-ar')
p.add_argument('--nm', default='llvm-nm')
p.add_argument('--objcopy', default='llvm-objcopy')
a = p.parse_args()
here = Path(__file__).resolve().parent
sources = ('Decoder DecoderData Formatter FormatterATT FormatterBase FormatterBuffer '
           'FormatterIntel Mnemonic Register SharedData String Utils').split()
with tempfile.TemporaryDirectory(prefix='moon-decoder-') as temp:
    temp = Path(temp)
    with tarfile.open(here / 'zydis-4.1.1.tar.gz') as archive:
        archive.extractall(temp, filter='data')
    core = temp / 'dependencies/zycore'
    flags = ['-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
             '-DZYAN_NO_LIBC', '-DZYDIS_STATIC_BUILD', '-DZYCORE_STATIC_BUILD',
             '-DZYDIS_DISABLE_ENCODER', '-DZYDIS_DISABLE_SEGMENT', '-DNDEBUG',
             f'-I{temp / "include"}', f'-I{temp / "src"}', f'-I{core / "include"}']
    if a.target == 'win64':
        flags += ['--target=x86_64-w64-windows-gnu']
    else:
        flags += ['--target=x86_64-linux-gnu', '-fPIC']
    inputs = [temp / 'src' / f'{name}.c' for name in sources]
    inputs += [core / 'src' / f'{name}.c' for name in ('String', 'Format', 'Vector', 'Allocator')]
    inputs += [here / 'moon_decode.c']
    objects = []
    for i, source in enumerate(inputs):
        obj = temp / f'{i}.o'
        subprocess.run([a.cc, *flags, '-c', str(source), '-o', str(obj)], check=True)
        objects.append(str(obj))
    # Private namespace, including upstream's generic table names: linking this
    # module must not interpose an application's independently linked Zydis.
    symbols = subprocess.check_output([a.nm, '--defined-only', '--extern-only',
                                       '--format=posix', *objects], text=True)
    names = sorted({parts[0] for line in symbols.splitlines()
                    if len(parts := line.split()) >= 3})
    mapping = temp / 'symbols.txt'
    mapping.write_text(''.join(f'{name} moon_diag_{name}\n' for name in names), encoding='ascii')
    for obj in objects:
        subprocess.run([a.objcopy, f'--redefine-syms={mapping}', obj], check=True)
    output = here / f'libmoon_decode_{a.target}.a'
    # Fresh archive: do not retain obsolete members from an earlier build.
    candidate = temp / output.name
    subprocess.run([a.ar, 'rcs', str(candidate), *objects], check=True)
    output.write_bytes(candidate.read_bytes())
    print(f'{output.name}: {output.stat().st_size} bytes')
