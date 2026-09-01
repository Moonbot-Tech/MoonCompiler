# ASM oracle

This is a separate Devil layer, not part of the product Chimera.

In real x86-64 mORMot, many hot functions already execute embedded ASM or
prebuilt `.obj` files, so artificial Pascal versions must not be presented as
the MoonBot/Arbitrage path. The roles here are different: the compiler emits
machine code from Pascal, while an independent handwritten x86-64 implementation
computes the same answer. The comparison catches wrong-code in loops, arithmetic,
pointers, registers, and ABI. The strongest forms use different algorithms or a
single machine instruction against a complete Pascal model: `crc32`, `aesenc`,
several division, search, root, and wide-multiplication paths.

The seven families provide 57 executable comparison groups and cover the Win64
and System V x86-64 calling conventions. `inventory.json` requires every
declared branch to execute; the runner retains compile/run logs and compares
final digests between O2/O3.

Run from the repository root:

```text
uv run python qualification/suite/scripts/run_asm_oracle_gate.py
```

`--profiles` adds Debug/O1. AES-NI and SSE4.2 instructions execute directly,
so the qualification host must support them, as do the current MoonCompiler
Win64/Linux x86-64 test hosts.
