# dvl-0042 — COFF bigobj lost a Win64 unwind-symbol section number

## Manifestation

A large generated Win64 module failed to link:

```text
Error: Undefined symbol: $unwind$P$DEVIL_$$_DVLLINK00103_11$INT64$$INT64
Fatal: There were 1 errors compiling module, stopping
```

The name of the missing entry changed with program size and composition. That
created the false appearance of a `try/finally` generation error or unstable
compiler state.

## First broken invariant

The Devil object contains more than 65,535 COFF sections. The writer therefore
correctly switches to Microsoft COFF bigobj, where a symbol record's
`SectionNumber` is 32-bit. Before emission, however,
`TCoffObjOutput.create_symbols` stored `objsym.objsection.index` in a local
`Word`.

The exact failing object had 155,905 sections. The section-number sequence of
adjacent unwind symbols was:

```text
65534 -> 0 -> 2 -> 4
```

Zero meant an undefined symbol: index 65,536 was truncated to 16 bits before
the bigobj writer was called. The unwind record itself was emitted, but the
symbol table referenced no section for it.

## Repair

`sectionval` was widened from `Word` to `LongInt`, matching the existing
`write_symbol` parameter type. Ordinary COFF is unchanged: its writer still
emits a 16-bit field. Bigobj no longer loses high bits. No new unwind algorithm,
program-size limit, or linker workaround was added.

## Permanent proof

[`run_win64_bigobj_unwind_gate.py`](../../../../scripts/run_win64_bigobj_unwind_gate.py)
generates 12,000 actually called procedures with `try/finally`, builds them
with `-CX -XX -O2`, verifies the bigobj header and more than 65,535 sections,
then runs the finished executable.

On the pre-fix compiler the gate failed on undefined `$unwind$...`. On the
repaired compiler:

```text
WIN64_BIGOBJ_UNWIND_PASS routines=12000 sections=72017
```

The gate retains hashes of the compiler, configuration, and source with the
compile/runtime verdict. This is a separate Win64 target-specific regression:
ordinary small tests cannot physically cross the 16-bit COFF section-number
boundary.
