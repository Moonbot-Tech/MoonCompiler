# dvl-0011 — O3 corrupts the high half of a 128-bit result

## Current status

Fixed by lane-exact folding of the complete 128-bit payload; this was a
constant-folding defect, not the general backend issue from dvl-0001. Permanent
regression: `RTL-test/semantic/int128_bitwise_fold_semantic.dpr`.

Found by the `i128` layer, seed 1, case `dvl-i128-00030`. Delphi has no 128-bit
integers, so the generator model and differential optimization profiles serve as
the oracle.

## Repro

```pascal
A := Int128(UInt128(UInt64($1)));
B := Int128(UInt128(UInt64($8000000000000000)));
R := A xor B;
```

| level | low | high |
|---|---|---|
| `-O-` | `8000000000000001` | `0000000000000000` |
| `-O2` | `8000000000000001` | `0000000000000000` |
| **`-O3`** | `8000000000000001` | **`FFFFFFFFFFFFFFFF`** |

Both operands have a zero high half, so XOR must leave it zero. At O3, the high
half receives sign extension from the low one: the result's top bit (`8000...`)
is replicated upward.

## Relationship

This has the same signature as dvl-0001 (loss of unsigned narrowing at O3), but
on the 128-bit path: somewhere at O3, a value receives sign extension where it
must be zero-extended. Both findings should be examined together — they may
share one root cause in the backend.
