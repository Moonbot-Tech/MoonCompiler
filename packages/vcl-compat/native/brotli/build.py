#!/usr/bin/env python3
"""Rebuild the private Brotli 1.2.0 decoder object for one product target.

Applications link the shipped object and require no C toolchain or Brotli DLL.
The upstream archive is verified and unmodified. All public symbols are renamed
to avoid interposing a different Brotli that an application might also link.
Memory/copy functions bind to the Pascal unit, using the application's MM.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile

SHA256 = '816c96e8e8f193b40151dad7e8ff37b1221d019dbcb9c35cd3fadbfe6477dfec'
parser = argparse.ArgumentParser(__doc__)
parser.add_argument('--target', required=True, choices=['x86_64-win64', 'x86_64-linux'])
parser.add_argument('--cc', default='gcc')
parser.add_argument('--nm', default='nm')
args = parser.parse_args()
here = Path(__file__).resolve().parent
archive = here / 'brotli-1.2.0.tar.gz'
if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    raise SystemExit('Brotli source archive checksum mismatch')

with tempfile.TemporaryDirectory(prefix='moon-brotli-') as temporary:
    temp = Path(temporary)
    with tarfile.open(archive) as source:
        source.extractall(temp, filter='data')
    root = temp / 'brotli-1.2.0'
    flags = ['-O2', '-DNDEBUG', '-DBROTLI_STATIC', '-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=0', '-ffreestanding', '-fno-builtin',
             '-fno-stack-protector', '-fno-tree-loop-distribute-patterns',
             '-fasynchronous-unwind-tables', '-I' + str(root / 'c/include')]
    if args.target == 'x86_64-win64':
        flags += ['-mno-stack-arg-probe']
    else:
        flags += ['-fPIC', '-fvisibility=hidden', '-fcf-protection=none', '-fno-stack-clash-protection']
    objects = []
    sources = sorted([*(root / 'c/common').glob('*.c'), *(root / 'c/dec').glob('*.c')])
    for source in sources:
        obj = temp / (source.parent.name + '_' + source.stem + '.o')
        subprocess.run([args.cc, *flags, '-c', str(source), '-o', str(obj)], check=True)
        objects.append(obj)
    symbols = subprocess.check_output([args.nm, '--extern-only', '--format=posix', *map(str, objects)], text=True)
    names = set()
    external = set()
    for line in symbols.splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0].startswith('.'):
            continue
        if fields[1] == 'U':
            external.add(fields[0])
        else:
            names.add(fields[0])
    runtime = {'malloc', 'free', 'memcpy', 'memmove', 'memset'}
    allowed = runtime | {'_GLOBAL_OFFSET_TABLE_'}
    if external - names - allowed:
        raise SystemExit(f'Unexpected Brotli dependencies: {sorted(external - names - allowed)}')
    # Rename C identifiers before compilation so compiler-generated COFF
    # .refptr symbols and their COMDAT sections receive the same namespace.
    defines = [f'-D{name}=moon_brotli_{name}' for name in sorted(names | (external & runtime))]
    target = here / args.target
    target.mkdir(exist_ok=True)
    for source, obj in zip(sources, objects):
        subprocess.run([args.cc, *flags, *defines, '-c', str(source), '-o', str(obj)], check=True)
        exported = subprocess.check_output([args.nm, '--extern-only', '--format=posix', str(obj)], text=True)
        for line in exported.splitlines():
            fields = line.split()
            if len(fields) < 2:
                continue
            name = fields[0]
            if not (name.startswith(('moon_brotli_', '.refptr.moon_brotli_')) or name == '_GLOBAL_OFFSET_TABLE_'):
                raise SystemExit(f'Unprefixed Brotli symbol: {name}')
        output = target / ('moonbrotli_' + obj.name)
        output.write_bytes(obj.read_bytes())
        print(f'{output}: {output.stat().st_size} bytes, SHA256 {hashlib.sha256(output.read_bytes()).hexdigest()}')
