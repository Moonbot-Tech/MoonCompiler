# dvl-0005 — a constant array index outside the bounds is accepted silently

## Current status

Fixed: the original signed/unsigned constant is checked before rangedef
conversion, independently of `{$R-}`. Permanent regressions:
`tests/test/cg/tmoonarrayconstindex1.pp` and a qualification compile-fail
fixture.

Found by the `reject` layer: compilation itself is the observable outcome, and
here our compiler and Delphi issue different verdicts for the same program.

## Repro

```pascal
var
  A: array[0..3] of Integer;
begin
  A[9] := 1;
  WriteLn(A[0]);
end.
```

| compiler | verdict |
|---|---|
| Delphi 12.2 | `E1012 Constant expression violates subrange bounds` |
| ours (`-O2`) | compiles without a single diagnostic |

The index is a constant and the array bounds are known at compile time, so this
is not a `{$R+}` question: the write is provably outside the object. Delphi
stops the build; we emit a binary that overwrites adjacent memory.

## Why this matters for the product

This is the only class of defect found that produces not merely an incorrect
number but silent corruption of adjacent memory — in a release build and with no
runtime checking at all.
