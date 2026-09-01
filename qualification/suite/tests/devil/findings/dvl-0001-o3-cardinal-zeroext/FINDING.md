# dvl-0001 — O3 loses zero-extension in `UInt64(Cardinal(Integer))`

Found by Devil on its very first run: `expr` layer, seed 1, case
`dvl-expr-00203`. `dvl-expr-00203-form` (form against the runtime model) failed,
while `-model` remained green and O-/O1/O2 passed in full. The profiles
disagreed.

## What happens

`repro.dpr`, Win64, same source:

| mode | `R` | `R shr 32` |
|---|---|---|
| `-O2` | `2713250968` (`00000000A1B8EC98`) | 0 |
| `-O3` | `18446744072127835288` (`FFFFFFFFA1B8EC98`) | `4294967295` |

`R := RawI32(Arr[1])`, where

```pascal
function RawI32(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(V));
end;
```

`Cardinal(V)` must truncate to 32 unsigned bits; subsequent extension to
`UInt64` must fill with zeroes. At O3, the upper 32 bits receive sign extension
from the negative `Integer`. This is not a printing artefact: `R shr 32` and a
direct comparison with a constant show the same result.

## What is required to reproduce it

Verified by varying each factor separately:

- the argument is an **array element**; the defect disappears with a scalar
  variable;
- in the same procedure, the result is consumed by `IntToHex(R, 16)`; when it
  is consumed only through `WriteLn(R shr 32, ' ', R)`, the defect disappears;
- `with`, procedure parameters, a separate unit, a prior value of `R`, and a
  write to a global are unnecessary; none affect the outcome.

## Status: fixed

Devil dvl-0043 provided a third form and led to the first broken invariant. A
long-range x86 peephole saw
`mov narrow-constant,reg ... movzx/movsx reg,reg`, removed the second operation,
and widened the first `mov`. The immediate was not truncated to its original
8/16/32-bit width, so the eliminated narrowing vanished from machine semantics.

The shared helper now first normalizes the immediate to its original width, then
applies the required signed/unsigned extension. This fixes not just one form but
the whole dvl-0001/dvl-0026/dvl-0043 family. The permanent
`run_devil_zeroext_gate.py` validates five layers, seeds 1 and 24, and four
profiles; after the fix, all 1,268 checks agree across Debug/O1/O2/O3.

## Related cases found after expanding the axes

The same root cause — an unsigned narrowing before 64-bit extension is lost at
`-O3` — is now caught by Devil in four independent layers:

- `expr`: result of a narrow-type binary operation (`dvl-expr-*-form`);
- `unary`: `Succ`/`Pred`/`not` on `ShortInt`/`SmallInt`/`Byte`/`Word`;
- `fold`: the “literal op runtime operand” form (`*-half-vs-runtime`); here the
  defect is already visible at `-O2`;
- `unit`: a value passed through a generic record from another module
  (`dvl-unit-*-generic`).

In every case, `-O-`, `-O1`, and Delphi 12.2 produce the correct result.
