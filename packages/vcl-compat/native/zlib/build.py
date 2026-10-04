#!/usr/bin/env python3
"""Rebuild the shipped zlib objects of System.ZLib for one target.

Normal Pascal builds use the shipped <target>/moonzlib_*.o and need no C
compiler.  The objects of x86_64-win64 come from MinGW-w64 GCC (or Clang for
x86_64-w64-windows-gnu) and take nothing from a C runtime; those of
x86_64-linux come from a Linux GCC (or Clang for x86_64-linux-gnu) and take
memcpy/memset of the C library every Linux program of the toolchain links.
Both targets use the upstream archive; Win64 patches the short-match check
after extraction, while Linux uses zlib's UNALIGNED_OK path.

Run: python3 build.py [--target x86_64-win64|x86_64-linux] [--cc ...] [--nm ...] [--objcopy ...]
"""
import argparse
from pathlib import Path
import subprocess
import tarfile
import tempfile

TARGETS = {
    # target: (default C compiler, Clang target triple)
    'x86_64-win64': ('x86_64-w64-mingw32-gcc', 'x86_64-w64-windows-gnu'),
    'x86_64-linux': ('gcc', 'x86_64-linux-gnu'),
}
p = argparse.ArgumentParser(__doc__)
p.add_argument('--target', choices=sorted(TARGETS), default='x86_64-win64')
p.add_argument('--cc', help='default: x86_64-w64-mingw32-gcc for Win64, gcc for Linux')
p.add_argument('--nm', default='nm')
p.add_argument('--objcopy', default='objcopy')
p.add_argument('--clang', action='store_true', help='cc is Clang: add the target triple')
a = p.parse_args()
here = Path(__file__).resolve().parent
cc = a.cc or TARGETS[a.target][0]
# gz* file functions, compress/uncompress and the zlib test/example sources
# stay out: System.ZLib implements compress/uncompress in Pascal over these.
sources = 'adler32 crc32 deflate inffast inflate inftrees trees zutil'.split()
with tempfile.TemporaryDirectory(prefix='moon-zlib-') as temp:
    temp = Path(temp)
    with tarfile.open(here / 'zlib-1.3.1.tar.gz') as archive:
        archive.extractall(temp, filter='data')
    src = temp / 'zlib-1.3.1'
    if a.target == 'x86_64-win64':
        # The two-byte candidate check helps large inputs, but extending a
        # match two bytes per step costs the 4.6 KB trade packet on Win64.
        # Keep the candidate check and use the byte scan already in zlib.
        source = src / 'deflate.c'
        code = source.read_bytes()
        patches = (
            (b'    register Byte scan_end1  = scan[best_len - 1];\n'
             b'    register Byte scan_end   = scan[best_len];',
             b'    register ush scan_start = *(ushf*)scan;\n'
             b'    register ush scan_end = *(ushf*)(scan + best_len - 1);'),
            (b'        if (match[best_len]     != scan_end  ||\n'
             b'            match[best_len - 1] != scan_end1 ||\n'
             b'            *match              != *scan     ||\n'
             b'            *++match            != scan[1])      continue;',
             b'        if (*(ushf*)(match + best_len - 1) != scan_end ||\n'
             b'            *(ushf*)match != scan_start) continue;\n'
             b'        match++;'),
            (b'            scan_end1  = scan[best_len - 1];\n'
             b'            scan_end   = scan[best_len];',
             b'            scan_end = *(ushf*)(scan + best_len - 1);'),
        )
        for old, new in patches:
            if code.count(old) != 1:
                raise SystemExit('zlib 1.3.1 deflate.c no longer matches the Win64 candidate-check patch')
            code = code.replace(old, new)
        source.write_bytes(code)
    # Z_SOLO: no C library at all (the allocator comes from the z_stream, the
    # unit always supplies it); the rest keeps GCC from inventing memcpy/memset
    # calls or stack probes, so the Win64 objects have no undefined symbols.
    # The unwind tables (.pdata/.xdata on Win64, .eh_frame on Linux) stay: the
    # allocator of the unit raises EOutOfMemory from inside
    # deflateInit/inflate, and a buffer that is not there faults inside them -
    # the unwinder has to find its way out of every zlib frame to the
    # caller's except.
    flags = ['-O2', '-DZ_SOLO', '-ffreestanding', '-fno-builtin',
             '-fno-stack-protector',
             '-mno-stack-arg-probe', '-Wall']
    # Z_SOLO also keeps zutil.h and zconf.h from naming the 4- and 8-byte
    # integer types, and crc32.c without them drops its braided CRC (five
    # 8-byte words a step) for the table of one byte a step - the CRC of
    # every ZIP entry mORMot writes and of every gzip stream, where zlib
    # 1.2.11 of mORMot ran its 4-byte loop.  Named here, the types are the
    # same on both targets (z_crc_t 32-bit); only crc32.c changes.
    flags += ['-DZ_U4=unsigned', '-DZ_U8=unsigned long long']
    if a.clang:
        flags += [f'--target={TARGETS[a.target][1]}']
    else:
        flags += ['-fno-tree-loop-distribute-patterns']
    # symbols from outside the zlib set the objects may name: position-
    # independent code that reaches data through the GOT names the GOT, which
    # the linker defines (Linux: z_errmsg of the error paths, which zlib
    # declares without ZLIB_INTERNAL), and on Linux what zlib takes from the C
    # library (below)
    linker_symbols = set()
    if a.target == 'x86_64-linux':
        # Position-independent, so that the objects link into a PIE and into
        # a shared library as well; hidden (HAVE_HIDDEN: zlib's ZLIB_INTERNAL,
        # as its configure sets it), so that a shared library does not export
        # them and the calls and table reads between them go direct.  The rest
        # names what a distribution's GCC may switch on by itself (Ubuntu: CET
        # marks at every entry, stack clash probes), so that the code is the
        # one of these flags on every Linux.
        flags += ['-fPIC', '-fvisibility=hidden', '-DHAVE_HIDDEN', '-fcf-protection=none',
                  '-fno-stack-clash-protection']
        # zlib as the distributions build it, without Z_SOLO: every program of
        # this toolchain on Linux links the C library (the system unit's PSABI
        # exception handling links libc and libgcc_s, rtl/inc/psabieh.inc), and
        # zlib then copies and clears through its memcpy/memset, picked for the
        # processor when the program loads, instead of the loops of zutil.c:
        # the window copy after every inflate call made an exchange websocket
        # message 4-9 % dearer than the system libz's on Zen 2 and 2 % on
        # Haswell, with memcpy it is within 3 % either way.  zlib's default
        # allocator comes along (malloc/free) and is never called: System.ZLib
        # hands every stream its own before zlib sees it.  Win64 has no C
        # runtime to take and keeps Z_SOLO.
        flags = [flag for flag in flags if flag not in ('-DZ_SOLO', '-ffreestanding')]
        linker_symbols = {'_GLOBAL_OFFSET_TABLE_', 'memcpy', 'memset', 'malloc', 'free'}
    # Z_SOLO also means NO_MEMCPY (zutil.h): on Win64 zlib copies and clears
    # through its own zmemcpy/zmemzero of zutil.c, a loop over single bytes at -O2 -
    # the window after every inflate call, the input and the output of
    # deflate, the 64 KB hash head at every deflateInit.  -O3 vectorizes
    # those loops (16 bytes a step behind an overlap check, the rest in 8 and
    # single bytes); no library routine comes in, the loop patterns stay
    # loops (-fno-tree-loop-distribute-patterns).  The inflate side takes -O3
    # as well (a websocket message 3-6 % cheaper in Pulse's zlib program); the
    # deflate side stays at -O2, where -O3 made a 4 KB packet 2-3 % dearer.
    # The deflate side takes LIT_MEM (deflate.h): the literals and distances in
    # two buffers instead of one of three bytes a symbol, which 1.2.12 brought
    # with the repair of CVE-2018-25032 (the pending buffer stays clear of the
    # symbols in both layouts).  A deflate stream holds 16 KB more (pending
    # buffer 80 KB instead of 64 at memLevel 8); every deflate row of Pulse's
    # zlib program is 3-5 % cheaper.  deflate.c and trees.c share the layout.
    # Linux takes UNALIGNED_OK, like Debian and Ubuntu's amd64 zlib: both the
    # candidate check and match extension compare two bytes at a time. Win64
    # uses the patched candidate check above and zlib's byte extension: it
    # keeps the gain on large inputs without charging the short trade packet.
    per_source = {name: ['-O3'] for name in ('zutil', 'inflate', 'inffast', 'inftrees')}
    per_source.update({name: ['-DLIT_MEM'] for name in ('deflate', 'trees')})
    if a.target == 'x86_64-linux':
        per_source['deflate'].append('-DUNALIGNED_OK')
    objects = []
    for name in sources:
        obj = temp / f'moonzlib_{name}.o'
        subprocess.run([cc, *flags, *per_source.get(name, []), '-c', str(src / f'{name}.c'), '-o', str(obj)],
                       check=True)
        objects.append(obj)
    # Private namespace: an application may link another zlib (a system libz
    # through another unit, a foreign static one); nothing here may interpose it.
    symbols = subprocess.check_output([a.nm, '--defined-only', '--extern-only',
                                       '--format=posix', *map(str, objects)], text=True)
    names = sorted({parts[0] for line in symbols.splitlines()
                    if len(parts := line.split()) >= 3 and not parts[0].startswith('.')})
    mapping = temp / 'symbols.txt'
    mapping.write_text(''.join(f'{name} moon_zlib_{name}\n' for name in names), encoding='ascii')
    for obj in objects:
        subprocess.run([a.objcopy, f'--redefine-syms={mapping}', str(obj)], check=True)
    undefined = subprocess.check_output([a.nm, '--undefined-only', '--format=posix', *map(str, objects)], text=True)
    stray = sorted({parts[0] for line in undefined.splitlines()
                    if len(parts := line.split()) >= 2 and not parts[0].startswith('moon_zlib_')
                    and parts[0] not in linker_symbols})
    if stray:
        raise SystemExit(f'objects still reference symbols outside the zlib set: {stray}')
    target = here / a.target
    target.mkdir(exist_ok=True)
    for obj in objects:
        (target / obj.name).write_bytes(obj.read_bytes())
        print(f'{a.target}/{obj.name}: {obj.stat().st_size} bytes')
