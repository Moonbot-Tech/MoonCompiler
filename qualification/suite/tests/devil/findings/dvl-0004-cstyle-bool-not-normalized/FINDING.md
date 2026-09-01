# dvl-0004 — C-style Boolean comparisons are not normalized, and `Ord` reads the wrong domain

Found by Devil, `abi` layer, seed 21: `WordBool`/`ByteBool` fields in a record.
The mismatch was caught through two paths at once — a value check
(`Ord(F <> False)` must be 1) and observation of the raw `Ord`.

## What the repro shows

| expression | Delphi 12.2 | ours (every level) |
|---|---|---|
| `Ord(WordBool(True))` | `FFFF` | `FFFFFFFFFFFFFFFF` |
| `Ord(ByteBool(True))` | `FF` | `FFFFFFFFFFFFFFFF` |
| `Ord(LongBool(True))` | `FFFFFFFFFFFFFFFF` | `FFFFFFFFFFFFFFFF` |
| `Ord(W <> False)` | `1` | `FFFFFFFFFFFFFFFF` |
| `Ord(W = True)` | `1` | `FFFFFFFFFFFFFFFF` |
| `Ord(B <> False)` | `1` | `FFFFFFFFFFFFFFFF` |
| `Ord(L <> False)` | `1` | `FFFFFFFFFFFFFFFF` |

Two independent deviations:

1. **The comparison result is not normalized.** `=`/`<>` must produce a normal
   `Boolean` with value 0 or 1. Ours carries the raw operand bits. Any code such
   as `Ord(A <> B)` in arithmetic (a branch-free count, indexing, summing flags)
   receives `-1` rather than `1`.
2. **`Ord` extends outside its own domain.** Delphi returns the value at the
   type's own width: `WordBool` → `FFFF`, `ByteBool` → `FF`. Ours always sign
   extends to 64 bits.

Logical `and`/`or`/`xor`/`not` on C-style Booleans are already normalized in
this compiler (fixed previously); only relations are not normalized.
