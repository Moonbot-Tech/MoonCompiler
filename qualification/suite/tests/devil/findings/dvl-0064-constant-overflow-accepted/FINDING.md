# dvl-0064 — Delphi-incompatible constant overflow was accepted

Status: **fixed**.

## Observed divergence

```pascal
const
  Wrapped = High(Int64) + 1;
```

Delphi 12.2 Win64 rejects the declaration with `E2099 Overflow in conversion or
arithmetic operation`. MoonCompiler accepts it in every profile and materializes
`UInt64(9223372036854775808)`.

This is not runtime wrap under `{$Q-}`. Delphi requires a diagnostic both in a
constant declaration and for the source constant expression in a procedure body.
Permitted wrap arises when an already-checked runtime operation becomes constant
only after AUTOINLINE.

Two causes met here. The inherited FPC checked only whether the mathematical
result fit in either signed or unsigned 64 bits, and therefore lost the signed
domain of the `Int64 + Int64` operation. Fix `4351bb322` additionally allowed
post-AUTOINLINE wrap for any fold. The primary fix separated the source fold
from repeated simplification after inlining, but left another gap: ordinary
reassociation could itself make two runtime constants adjacent and incorrectly
apply the source-constant-expression rule to them.

The final boundary retains provenance on precisely the optimizer-created
internal node. Under `{$Q-}`, it folds by the runtime rules of the selected
integer type; under `{$Q+}`, add/multiply are not reassociated at all, so the
check remains at the original runtime point. Explicit user grouping such as
`Seed + (P1 + P2)` continues to be diagnosed as an overflowing constant
subexpression.

## Evidence

- [`repro.dpr`](repro.dpr) — the exact minimal form;
- DCC64 36.0: compile failure `E2099`;
- pre-fix MoonCompiler: build/run succeeds on Debug/O1/O2/O3 and prints
  `9223372036854775808`;
- post-fix focused tests: source declaration/body folds for signed add,
  subtract, multiply, and unsigned overflow are rejected; an explicitly
  unsigned in-range constant is accepted, while `tautoinline2.pp` retains
  runtime wrap after AUTOINLINE for add/subtract/multiply;
- exact DCC64 matrix: ungrouped `Seed + P1 + P2` under `{$Q-}` produces
  `606290991`; under `{$Q+}` it compiles and raises runtime overflow; explicit
  `Seed + (P1 + P2)` is rejected at compile time;
- `tdelphiconstarithoverflow7..9.pp` pin unchecked runtime wrap, checked
  runtime overflow, and the negative source-parenthesized control; Omni repeats
  add/multiply in both modes.

## Fix boundary

The boundary is pinned not by an incidental DCC answer or the line location,
but by the operation's provenance: a source constant expression diagnoses
overflow; an already-checked runtime operation retains checked or modular
semantics after AUTOINLINE and optimizer reassociation.
