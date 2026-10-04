# Private zlib objects of System.ZLib (Win64, Linux)

`System.ZLib` (`packages/vcl-compat/src/system.zlib.pp`) is the Delphi
`System.ZLib` surface written for MoonCompiler from its behavioural contract
and RFC 1950/1951/1952. The compression code behind it is **zlib 1.3.1**
under the zlib licence; the upstream archive is unmodified, and `build.py`
adjusts Win64's candidate check after extraction. No Embarcadero source was consulted.

`zlib-1.3.1.tar.gz` is the upstream release archive
(SHA-256 `9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`,
[madler/zlib v1.3.1](https://github.com/madler/zlib/releases/tag/v1.3.1)).
Keep [zlib's notice](LICENSE-zlib.txt) with distributions containing these
objects; it is independent of the Pascal unit's licence.

## One zlib in a program

The unit links the shipped objects of its target through `{$L}`:
`x86_64-win64/moonzlib_*.o` on Win64, `x86_64-linux/moonzlib_*.o` on Linux.
The package installs them next to `system.zlib.ppu`, where the compiler looks
for a unit's linked objects, so an application build needs no C compiler,
DLL, `libz.so`, library path or `-Fl`, and runs on a machine without a zlib of
its own. mORMot compresses through the same unit: the compiler defines
`MOONCOMPILER_SYSTEM_ZLIB`, and MoonORMot's `mormot.lib.z` then takes
`System.ZLib` (its `ZLIBRTL` choice, the one Delphi Win64 makes) instead of
mORMot's static zlib 1.2.11 on Win64 or the system `libz` on Linux - so
`System.Zip`, mORMot's HTTP compression and the rest go through these objects
too (on Linux mORMot keeps libdeflate for its whole-buffer calls and
checksums). `qualification/build-driver/unit_scope_gate.py` requires of a
program written as Delphi code (`uses zLib, Zip`) that it imports no zlib
library and carries no zlib build other than this one.

## Build

The Win64 objects are freestanding: `-DZ_SOLO` removes every C library call
(memory comes from the `z_stream` allocator, which the unit always supplies),
and the remaining flags keep GCC from inventing `memcpy`/`memset` calls or
stack probes. The Linux objects are built as the distributions build zlib,
without `-DZ_SOLO`: every Linux program of this toolchain links the C library
(the system unit's PSABI exception handling links `libc` and `libgcc_s`,
`rtl/inc/psabieh.inc`), and zlib copies and clears through its `memcpy` and
`memset`, which the C library picks for the processor when the program loads;
zlib's default allocator comes along (`malloc`/`free`) and is never called,
the unit hands every stream its own. The objects keep their unwind tables
(`.pdata`/`.xdata` on Win64, `.eh_frame` on Linux): the unit's allocator
raises `EOutOfMemory` from inside
`deflateInit`/`inflate`, and a buffer that is not there faults inside them,
so the unwinder has to find its way through every zlib frame to the caller's
`except` (built without them, as the first Win64 objects were, every zlib
routine that moves `rsp` looked like a leaf to it). `-DZ_SOLO` also makes zlib
copy through its own `zmemcpy` (`NO_MEMCPY`), which `-O2` left a loop over
single bytes: `zutil.c` and the inflate side are compiled at `-O3` (16 bytes a
step), the deflate side at `-O2` with `LIT_MEM` (two symbol buffers, 16 KB
more a deflate stream, every deflate 3-5 % cheaper). On Linux the same
16-byte loops made an exchange websocket message 4-9 % dearer than the system
`libz` on Zen 2 and 2 % on Haswell (the window copy after every `inflate`
call); with the C library's `memcpy` it is within 3 % of it. `-DZ_SOLO`
further leaves `zutil.h` and `zconf.h` without the 4- and 8-byte integer
types, and `crc32.c` without them computes the CRC a byte a step instead of its braided
five words (a 1 KB table instead of 9 KB); the flags name them
(`-DZ_U4=unsigned -DZ_U8="unsigned long long"`, the same on both targets), which
changes `crc32.c` only - a ZIP entry, whose CRC mORMot computes over
`System.ZLib`, is 3.7 % cheaper to write on Win64. Linux builds `deflate.c`
with `UNALIGNED_OK`, as Debian and Ubuntu build their amd64 zlib: its
`longest_match` checks candidates and extends matches two bytes at a time;
without it a ZIP entry of the market history was 3.9-5.3 % dearer to write
than with Ubuntu's `libz`, with it 0.4-1.8 % cheaper. On Win64 that flag made
the 4.6 KB trade packet 1.3-2.2 % dearer, although the ZIP entry and fastest
history improved by 3.4 % and 4.4 %. The Win64 build keeps the two-byte
candidate check but extends matches byte by byte. In a product Pulse series
(7 fresh processes per side, same oracle, sibling-idle samples), this change
made the packet 1.5-1.8 % and ZIP entry 1.7 % cheaper than the full flag;
fastest history stayed level. The identical-binary control was within 0.2 %.
The Linux objects are
position-independent (they link into a PIE and into a shared library) with
hidden symbols (`-fvisibility=hidden`, zlib's own `HAVE_HIDDEN`: a shared
library does not export them, calls and table reads between them go direct),
and name what a distribution's GCC may switch on by itself
(`-fcf-protection=none`, `-fno-stack-clash-protection`), so that their code is
the one of these flags on any Linux; their references outside the zlib set
are `_GLOBAL_OFFSET_TABLE_`, which the linker defines, and the C library's
`memcpy`, `memset`, `malloc` and `free`.
`qualification/build-driver/zlib_objects_gate.py` checks the installed objects
of each target for their unwind tables, for a copy and a clear that store
8 bytes or more a step (or those of the C library), for the braided CRC and
for the target's candidate check and match extension.
Every symbol, including upstream data tables, is renamed with the prefix
`moon_zlib_`, so an application that also links another zlib sees no
interposition. The build refuses to finish while an
object still references a symbol outside that set. `gz*` file functions and
the C `compress`/`uncompress` helpers are not compiled: the unit implements
the latter in Pascal over the streaming calls.

To rebuild the eight objects of a target with GCC (or Clang for that target)
and binutils:

```sh
python3 build.py --target x86_64-win64 --cc x86_64-w64-mingw32-gcc
python3 build.py --target x86_64-win64 --cc clang --clang --nm llvm-nm --objcopy llvm-objcopy
python3 build.py --target x86_64-linux            # on Linux, gcc
```

The shipped Win64 objects come from MinGW-Builds GCC 16.1.0, the Linux ones
from Ubuntu 24.04's GCC 13.3.0; `build.py` rebuilds each set byte for byte with
its compiler.

`z_stream` is 88 bytes on Win64 (`uLong` is 32-bit) and 112 bytes on Linux;
`TZLong` in the unit follows the C type per target, and
`RTL-test/semantic/zlib_semantic.dpr` checks the record size against the C
layout along with the framing, the check values of the RFCs and the stream
classes.
