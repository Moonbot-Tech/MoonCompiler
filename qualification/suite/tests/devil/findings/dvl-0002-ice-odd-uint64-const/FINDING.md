# dvl-0002 — Internal error 200706094 on `Odd(UInt64 constant)` with the top bit set

## Current status

Fixed: folding reads the low bit of the unsigned payload without an intermediate
`Int64`. Permanent regression: `tests/test/cg/tmoonoddconstu641.pp`.

Found by Devil, `unary` layer, seed 3, case `dvl-unary-00081`. The compiler
crashes during compilation, so the outcome is recorded by a gate rather than a
check: the build failed at every optimization level, while Delphi compiled and
ran the same program.

## Repro

Complete `repro.dpr`:

```pascal
if Odd(UInt64($FFFFFFFFFFFFFFFE)) then
  WriteLn('odd')
else
  WriteLn('even');
```

| compiler | result |
|---|---|
| Delphi 12.2 Win64 | compiles and prints `even` |
| MoonCompiler `-O-`, `-O1`, `-O2`, `-O3` | `Fatal: Internal error 200706094` |

## Boundaries verified by enumeration

- `Odd(UInt64($7FFFFFFFFFFFFFFE))` — the top bit clear — compiles;
- the same value in a `UInt64` **variable** rather than a constant compiles;
- the optimization level is irrelevant: it fails even in `-O-`.

The trigger is therefore folding `Odd` on an unsigned 64-bit constant whose
value exceeds `High(Int64)`. The constant appears to enter the signed path and
break an internal invariant; the precise compiler location has not been
localized.

## Why this matters

`Odd` on an unsigned value is an ordinary parity test. A compiler crash has no
source-level workaround other than rewriting the expression.
