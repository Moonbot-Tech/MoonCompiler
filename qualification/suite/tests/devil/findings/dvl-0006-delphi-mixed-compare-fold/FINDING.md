# dvl-0006 — Delphi contradicts itself when comparing `UInt64` with a negative `Int64`

Found by the `cmp` layer, seed 73, case `dvl-cmp-00013`. **Delphi** failed here;
our compiler is consistent.

## Form

```pascal
OpA: UInt64 = 4294967297;
OpB: Int64  = -1424625046537609188;

RtRaw   := Ord(OpA < OpB);                       // runtime
FoldRaw := Ord(UInt64($100000001) < Int64(-1424625046537609188));  // fold
```

| compiler | fold | runtime |
|---|---|---|
| Delphi 12.2 | `1` (True) | `0` (False) |
| ours (every level) | consistent with itself | consistent |

When folding the constant comparison, Delphi converts both operands to the
unsigned domain — the negative value becomes huge, so `4294967297 < huge` is
True. At runtime, Delphi instead compares mathematically (and itself emits
warning W1023 “Comparing signed and unsigned types - widened both operands”),
producing False.

## What to do about it

This is not a defect in our compiler: the same expression gives one answer in
both forms. The “replicate Delphi” contract is indeterminate at this point —
there is no single behaviour to replicate, because Delphi itself depends on
whether the operands are constants or variables.

The product owner must decide: either intentionally remain consistent
(mathematical comparison always) or reproduce Delphi's inconsistency. Until a
decision, the form remains in the known registry so it cannot mask a new issue.
