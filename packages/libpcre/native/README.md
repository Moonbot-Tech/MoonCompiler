# Private static PCRE2

PCRE2 10.49 is pinned by the SHA-256 checked in `build.py`. The original release
archive is retained here. No proprietary Delphi implementation is used.
Only the 16-bit Unicode engine is built; native symbols and C memory helpers
have a `moon_pcre_` prefix. Allocations use the application's Pascal memory
manager. Archives preserve individual objects so the application linker pulls
only the reachable engine code.

Rebuild on Linux with Python 3.12+, CMake, GCC/binutils and the x86-64 MinGW GCC
cross compiler for Windows:

```sh
python3 build.py --target x86_64-linux
python3 build.py --target x86_64-win64
```

Each target's manifest records the source checksum, compiler, flags, unresolved
symbols and archive checksums. The native archive contains optional PCRE2 entry
points that the Pascal interface does not expose: their C locale dependencies
are not pulled into a normal application. Validate the final executable imports,
not just all undefined symbols in the archive. Linux keeps its normal system
libc dependencies; Windows needs only OS imports for the linked engine.

Windows keeps GCC's real stack probing. `gcc/cygwin.S` and `gcc/i386-asm.h` are
unmodified files from GCC 13.3.0, `libgcc/config/i386`, compiled with
`L_chkstk_ms`. The unused configure-time target macros are empty. The function's
symbol is privately renamed after assembly. Sources:
https://github.com/gcc-mirror/gcc/tree/releases/gcc-13.3.0/libgcc/config/i386

PCRE2 retains `LICENSE-PCRE2.txt`; its bundled JIT backend has its own notice in
the source archive. The GCC fragment retains GPLv3 plus the GCC Runtime Library
Exception, whose full texts are included. Binary distributions carry the notices
under `share/doc/mooncompiler`.
