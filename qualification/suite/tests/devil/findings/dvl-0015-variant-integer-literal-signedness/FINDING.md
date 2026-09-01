# dvl-0015 — an integer literal in `Variant` is typed with a signed carrier type

The analysis was reconstructed from facts in the current run.

## What happens

An integer literal is stored in a `Variant`, and the observation records the
type code that the Variant assigns itself.

| build | type code |
|---|---|
| `debug`, `o1`, `o2`, `release` | **`$10`** |
| Delphi 12.2 | **`$11`** |

`$10` is `varShortInt`, a signed byte; `$11` is `varByte`, an unsigned byte.
The same literal is therefore signed in our compiler and unsigned in the oracle.

## Why this is costly

The type that a Variant adopts when written determines everything that follows:
comparison, arithmetic inside the Variant, conversion on read, and what a
recipient on the other side sees. A value stored as a signed byte is read
differently at the boundary of the range than one stored as unsigned.

The danger is typical for this family: no difference appears for small values;
it appears at the edge.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 40 --layers chain --profiles debug,release --dcc ...
```

`dvl-chain-<N>-variant-small` fails.

## Boundaries

Checked in all four profiles — identical in each; the frontend makes the
decision.

## Status: fixed

DCC64 36.0 matrix (24 literals across the full numeric axis plus assignment
forms): Delphi selects a carrier type by **value** — the smallest unsigned type
for nonnegative values (`varByte`/`varWord`/`varLongWord`/`varInt64`), and the
smallest signed type for negative values
(`varShortInt`/`varSmallInt`/`varInteger`/`varInt64`). The rule applies to every
“value form”: a bare literal, a parenthesized literal, an untyped constant, and
any folded constant expression — even one containing typed casts
(`Integer(2)+3` → `varByte`, `SizeOf(Int64)*8` → `varByte`): the DCC constant
folder recomputes the result type by value. A direct cast (`Integer(5)` →
`varInteger`), a typed constant, and a variable carry the carrier type of their
formal type.

The fix is in assignment-operator selection (`ncnv.pas`,
`te_convert_operator`): for an integer constant in a Variant value form, the
operator is retargeted to the Delphi carrier type. Two traits distinguish a
value form: the constant's def equals the minimal def for its value (expression
folds recreate the def from the value through `genintconstnode`, while
intrinsics carry their formal type), and the node lacks `nf_explicit` — a
simplifier fold of an explicit cast normally marks its folded constant with it.
This also covers tautological casts (`ShortInt(5)`, `SmallInt(300)`), which are
indistinguishable by the def alone. The infrastructure is untouched: overload
resolution, uint64 adaptation, and comparisons work as before.

The false “Range check error” warning for
`V := 2147483648..2^32-1` was also removed (DCC is silent): the inline body of
the dword operator passed a constant to the longint parameter `varfromInt` by an
implicit conversion. The bitwise reinterpretation is now stated with an explicit
cast (`variant.inc`); the constant folder is silent and code generation is the
same.

Deliberate boundary (measured by the matrix, not observed in the layer):
`V := SizeOf(X)` / `V := Length(S)` without arithmetic differ along the formal
type axis of intrinsics (DCC has `Cardinal`/`Integer`; we have 64-bit types) —
an existing divergence unrelated to carrier type.

The matrix also exposed and documented a separate axis — Variant arithmetic
(domain overflow and narrowing conversions): DCC divergences and facts are
pinned by `variant_int_arith_semantic`; the deliberately deferred performance
remainder for numeric Variant operations is described as PB-007 in the root
[`BACKLOG.md`](../../../../../../doc/BACKLOG.md).

Pin: `RTL-test/semantic/variant_int_carrier_semantic.dpr` (green under DCC64 as
well). The chain layer, seeds 3 and 4 against the DCC binary: 567 checks,
byte-for-byte identical digests; the registry entry was removed.
