# dvl-0010 — Delphi truncates an `Int64` `case` selector to 32 bits

Found by the `flow` layer, `case-int64` form, seed 111 (`dvl-flow-00008`). Delphi
failed; our compiler answers correctly.

## Form

```pascal
var Sel: Int64;
Sel := 4294967296;          // 2^32
case Sel of
  -2147483648: Res := 1;
  -1:          Res := 2;
   0:          Res := 3;
   1:          Res := 4;
   2147483647: Res := 5;
else
  Res := 9;
end;
```

| compiler | Res |
|---|---|
| ours (every level) | `9` — correct; no label equals 2^32 |
| Delphi 12.2 | `3` — the selector is truncated to 32 bits and reaches the `0` branch |

Delphi `case` labels are limited to 32 bits, but the **selector** remains a full
`Int64`: a value of `label + k*2^32` must go to `else`.

## What this means for the contract

The “replicate Delphi” contract applies to computations, layout, and lifetime.
There is nothing to replicate here: selector truncation loses information; it is
not a dialect. Our compiler already behaves correctly and must not be changed to
match Delphi. The form remains in the known registry as a mismatch in our
favour.
