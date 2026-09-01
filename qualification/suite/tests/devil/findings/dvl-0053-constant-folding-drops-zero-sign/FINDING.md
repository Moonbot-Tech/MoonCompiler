# dvl-0053 — O2/O3 CSE merged `+0.0` and `-0.0`

Found by the `resident` layer, `float` family: the negative-zero bit sign
disappeared only after optimization.

## What happened

| expression | O- | O2/O3 before the fix | Delphi 12.2 |
|---|---:|---:|---:|
| `0.0` | `0000000000000000` | `0000000000000000` | `0000000000000000` |
| `-0.0` beside `+0.0` | `8000000000000000` | `0000000000000000` | `8000000000000000` |
| `0.0 * -1.0` | `8000000000000000` | `0000000000000000` | `8000000000000000` |
| runtime `X * -1.0` | `8000000000000000` | `8000000000000000` | `8000000000000000` |

Constant folding and emission of real constants were correct: in O-, the
literal and the result of constant multiplication retained the sign bit. The
error occurred later. `trealconstnode.docompare` compared real constants only
numerically, and IEEE-754 defines `+0.0 = -0.0`. CSE therefore treated two
different bit patterns as one node and substituted a previously loaded positive
zero.

## Why this is incorrect

Equality under comparison does not make values interchangeable. The sign of zero
is observable bitwise and participates in division, sign copying, and some
transcendental operations. The optimizer has no right to change it without
explicitly permitted fast-math semantics.

## Fix

`trealconstnode.docompare` still requires numerical equality, but in the normal
mode additionally compares the sign bit. With fast math enabled, the previous
merging remains allowed. Currency, nonzero values, NaN, and infinity are
unaffected.

This is the same semantic approach used by current upstream FPC: distinguish
`+0` and `-0` when comparing constant nodes unless fast math is enabled.

## Evidence

- `probe/negzero.dpr` is the original diagnostic form; it is now fail-closed
  and terminates with `done` without an artificial division by zero;
- `tests/test/cg/tdelphinegativezero1.pp` is the permanent regression: adjacent
  `+0/-0` in both orders, seven folded forms, and runtime controls;
- Delphi 12.2 and our compiler produce identical sign bits;
- our compiler passes the test in O-, O2, and O3.

Status: **fixed**.
