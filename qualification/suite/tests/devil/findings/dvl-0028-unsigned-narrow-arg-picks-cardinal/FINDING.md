# dvl-0028 — a `Byte`/`Word` argument selects `Cardinal`, while Delphi selects `Integer`

Found by the `pick` layer. The disagreement is not in the value but in **which
overload is called**.

## Status

Fixed by a general rule for `Integer/Cardinal` and `Int64/UInt64` pairs. If the
complete static range of an argument type fits the signed candidate, the signed
candidate is selected; otherwise the unsigned candidate is selected. The rule
applies only to a genuine tie in precisely such a pair and does not affect
`var/out`, Variant, or ObjFPC. Matrix `tests/test/cg/tdelphiintpair1.pp` checks
both declaration orders, subranges, all widths, and boundary literals.

## What happens

```pascal
function Pick(const V: Integer): Integer; overload;   { candidate 1 }
function Pick(const V: Cardinal): Integer; overload;  { candidate 2 }
```

| argument | ours | Delphi 12.2 |
|---|---|---|
| `Byte` | **`Cardinal`** | `Integer` |
| `Word` | **`Cardinal`** | `Integer` |
| `SmallInt` | `Integer` | `Integer` |

In other words, our old implementation propagated the unsigned nature of a
narrow type into candidate selection. Delphi does not: both narrow types fit
completely in `Integer`, so it wins regardless of signedness.

## Why this is costly

The “same operation, signed or unsigned” pair is normal in encoders and
formatters: `Put(Integer)` writes zigzag encoding while `Put(Cardinal)` writes
the raw value; `Hex(Integer)` prints as signed while `Hex(Cardinal)` prints as
unsigned. A byte or word from a parsed packet could reach the other half of
such a pair here than it does in Delphi. There is no error or warning: bytes on
the wire or characters in a log diverge while the source looks identical.

The defect is doubly silent. For small values the two overloads produce the
same result, so the difference appears only when the sign matters.

## Delivery paths that carry the defect

The `deliver` layer carries the same question through nineteen argument-delivery
forms. The boundary is sharp:

| delivery | result |
|---|---|
| literal directly, parenthesized, double-parenthesized | agreement |
| `x + 0`, `x - 0`, `x * 1`, `x or 0` | agreement |
| constant from another unit (PPU) | agreement |
| from a worker thread | agreement |
| **cast to a narrow type** | **disagreement** |
| **typed constant** | **disagreement** |
| **through a `const` parameter** | **disagreement** |
| **through generic specialization** | **disagreement** |
| **from a closure, `with`, a `case` branch, or an `if` branch** | **disagreement** |
| **from the result of an inline or non-inline function** | **disagreement** |

This means that both compilers agree while a value remains **a constant with
provenance**. The rule diverges once the value has a **type**: any delivery that
gives the argument a narrow typed carrier activates the defect. The repair
therefore belongs in candidate ordering by signedness and width, not literal
parsing. dvl-0039, the opposite side of the same pair, lives there too.

## Reproduction

`repro-standalone.dpr` is self-contained and shows all three arguments.

In the suite:

```
run_devil_gate.py --seeds 5 --cases 120 --layers pick --profiles release --dcc ...
```

Observation `dvl-pick-int-sign-var-byte-picked` turns red: `release` returns
`2`; Delphi returns `1`.

## Boundary

Verified with `debug`, `o1`, `o2`, and `release`: all four previously selected
`Cardinal`, so this is a front-end decision, not an optimizer decision.
`SmallInt` and `ShortInt` do not diverge. The complete eight-integer candidate
set (`ShortInt..UInt64`, `int-width` family) does not diverge either: the defect
lives specifically in the two-candidate pair of the same width.
