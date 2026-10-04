# Private static instruction decoder

The decoder is **Zydis 4.1.1** under MIT, not copied or translated EurekaLog code.
The small Pascal/C bridge and report integration are original Moon.Diagnostics
code. EurekaLog was inspected only to understand the kind of diagnostic output.

`zydis-4.1.1.tar.gz` contains unmodified upstream `include`/`src` trees and licences:

- [Zydis](https://github.com/zyantific/zydis/tree/a2278f1d254e492f6a6b39f6cb5d1f5d515659dc),
  commit `a2278f1d254e492f6a6b39f6cb5d1f5d515659dc`;
- [Zycore](https://github.com/zyantific/zycore-c/tree/0b2432ced0884fd152b471d97ecf0258ff4d859f),
  commit `0b2432ced0884fd152b471d97ecf0258ff4d859f`.

Keep [Zydis's notice](LICENSE-Zydis.txt) and [Zycore's notice](LICENSE-Zycore.txt)
with distributions containing this decoder. They are independent of the Pascal
module's licence.

## Build and delivery

Normal Pascal builds consume the shipped `libmoon_decode_linux.a` or
`libmoon_decode_win64.a` automatically. No new shared library, package installation,
C compiler or disassembler executable is needed on the application machine.
The build drivers always supply `-Fl<compiler>/runtime/reporting/native`:
FPC intentionally stores only a static archive's basename in a PPU. Direct
low-level builds that reuse PPUs must supply this library path too.

To rebuild both archives on Linux, use Python 3.12+, Clang and the LLVM tools
(`llvm-ar`, `llvm-nm`, `llvm-objcopy`):

```sh
python3 build.py --target linux
python3 build.py --target win64
```

This builds freestanding code without libc. Encoder/segment utilities are omitted;
the decoder and Intel formatter retain the upstream instruction-set support.
Symbols are prefixed `moon_diag_`, including upstream data tables, so they do not
collide with another library's Zydis. Only fixed caller-owned buffers are used by
the bridge: no heap allocation, global mutable decoder or lazy initialization.

At a hardware fault the bridge decodes **one instruction**, without text, to find
ordinary memory operands. FS/GS-relative and vector-indexed addressing are omitted
because their complete address state is not captured. At report time the same
decoder formats saved bytes as Intel syntax. This is not an instruction trace or
a custom implementation of the x86 instruction set.
