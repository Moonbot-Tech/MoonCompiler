#!/usr/bin/env python3
"""Build a private, static PCRE2-16 with Unicode and JIT for a product target."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

VERSION = '10.49'
SHA256 = '929f0b20e62879252a15886b06c89f1edef61a363cbd5826fb041080a5e557ae'
parser = argparse.ArgumentParser(__doc__)
parser.add_argument('--target', required=True, choices=['x86_64-win64', 'x86_64-linux'])
args = parser.parse_args()
here = Path(__file__).resolve().parent
archive = here / f'pcre2-{VERSION}.tar.gz'
if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    raise SystemExit('PCRE2 source checksum mismatch')
prefix = 'x86_64-w64-mingw32-' if args.target == 'x86_64-win64' else ''
cc, nm = (prefix + x for x in ('gcc', 'nm'))
runtime = {'malloc', 'free', 'memcpy', 'memmove', 'memset', 'memcmp', 'memchr', 'strlen', 'strcmp', 'strncmp', 'strchr'}
with tempfile.TemporaryDirectory(prefix='moon-pcre2-') as temporary:
    temp = Path(temporary)
    with tarfile.open(archive) as source:
        source.extractall(temp, filter='data')
    root = temp / f'pcre2-{VERSION}'
    build = temp / 'build'
    flags = ('-O2 -DNDEBUG -ffreestanding -fno-builtin -fno-stack-protector '
             '-fasynchronous-unwind-tables -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -fstack-usage')
    if not prefix:
        flags += ' -fPIC -fvisibility=hidden -fcf-protection=none'
    config = ['cmake', '-S', str(root), '-B', str(build), '-DBUILD_SHARED_LIBS=OFF',
              '-DPCRE2_BUILD_PCRE2_8=OFF', '-DPCRE2_BUILD_PCRE2_16=ON', '-DPCRE2_BUILD_PCRE2_32=OFF',
              '-DPCRE2_BUILD_TESTS=OFF', '-DPCRE2_BUILD_PCRE2GREP=OFF', '-DPCRE2_SUPPORT_JIT=ON',
              '-DPCRE2_SUPPORT_UNICODE=ON', '-DCMAKE_C_COMPILER=' + cc]
    if prefix:
        config += ['-DCMAKE_SYSTEM_NAME=Windows']
    def compile_library(extra):
        subprocess.run(config + ['-DCMAKE_C_FLAGS=' + flags + ' ' + extra], check=True)
        subprocess.run(['cmake', '--build', str(build), '--target', 'pcre2-16-static', '-j', '8'], check=True)
        libraries = list(build.rglob('libpcre2-16.a'))
        if len(libraries) != 1:
            raise RuntimeError(f'Expected one PCRE2 archive, found {libraries}')
        return libraries[0]
    library = compile_library('')
    defined = set()
    undefined = set()
    for line in subprocess.check_output([nm, '-g', '-P', str(library)], text=True).splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0].startswith('.'):
            continue
        (undefined if fields[1] == 'U' else defined).add(fields[0])
    print('PCRE2 native dependencies:', sorted(undefined - defined), flush=True)
    names = defined | (undefined & runtime)
    library = compile_library(' '.join('-D' + n + '=moon_pcre_' + n for n in sorted(names)))
    target = here / args.target
    target.mkdir(exist_ok=True)
    # Preserve individual COFF/ELF sections and their relocation addends. The
    # application linker pulls only the engine objects that it actually uses.
    output = target / 'libmoonpcre2.a'
    output.write_bytes(library.read_bytes())
    if prefix:
        probe = temp / 'moon_pcre_stack_probe.o'
        # The selected GCC runtime fragment needs no configure-time target macros.
        (temp / 'auto-target.h').write_text('')
        subprocess.run([cc, '-c', '-DL_chkstk_ms', '-I' + str(temp),
                        str(here / 'gcc' / 'cygwin.S'), '-o', str(probe)], check=True)
        subprocess.run([prefix + 'ar', 'r', str(output), str(probe)], check=True)
        subprocess.run([prefix + 'objcopy', '--redefine-sym', '___chkstk_ms=moon_pcre_chkstk', str(output)], check=True)
        imports = temp / 'kernel32.def'
        imports.write_text('LIBRARY KERNEL32.dll\nEXPORTS\n' + '\n'.join([
            'CloseHandle', 'CreateMutexA', 'GetSystemInfo', 'ReleaseMutex',
            'VirtualAlloc', 'VirtualFree', 'WaitForSingleObject']) + '\n')
        subprocess.run([prefix + 'dlltool', '-d', str(imports), '-l', 'libmoonpcre_os.a',
                        '--temp-prefix', 'moonpcre_os_'], cwd=target, check=True)
    symbols = subprocess.check_output([nm, '-g', '-P', str(output)], text=True)
    defined, undefined = set(), set()
    for line in symbols.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == 'U':
            undefined.add(fields[0])
        elif len(fields) >= 3 and fields[1] in 'TDRBSC':
            defined.add(fields[0])
    if any(not name.startswith(('moon_pcre_', '.refptr.')) for name in defined):
        raise RuntimeError('Unprefixed native definition')
    manifest = {
        'source': f'https://github.com/PCRE2Project/pcre2/releases/download/pcre2-{VERSION}/{archive.name}',
        'source_sha256': SHA256,
        'compiler': subprocess.check_output([cc, '--version'], text=True).splitlines()[0],
        'options': flags,
        'unresolved': sorted(undefined - defined),
        'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(target.glob('*.a'))},
    }
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'{output}: {output.stat().st_size} bytes, SHA256 {hashlib.sha256(output.read_bytes()).hexdigest()}')
