# dvl-0030 — concatenating two quoted literals produces an ANSI-typed constant

Found by the `pick` layer, case `dvl-pick-string-form-lit-str-concat`. It is
related to dvl-0029: there the byte type surfaced for a character; here it
surfaces for a string, and not on a literal itself but on the **result of a
fold**.

## Status

Fixed for the proven Delphi-Unicode ASCII class: a standalone literal,
`'a' + 'b'`, and a named constant plus a literal all select `UnicodeString`.
Explicit `AnsiString`, `RawByteString` context, and ObjFPC remain byte-based.
`tests/test/cg/tdelphiunicodeliteral1.pp` verifies this together with adjacent
controls.

## What happens

```pascal
function Take(const V: AnsiString): Integer; overload;      { candidate 1 }
function Take(const V: UnicodeString): Integer; overload;   { candidate 2 }
```

| expression | ours | Delphi 12.2 |
|---|---|---|
| `'ab'` | UnicodeString | UnicodeString |
| `'a' + 'b'` | **AnsiString** | UnicodeString |
| `Part + 'b'`, where `Part = 'a'` | **AnsiString** | UnicodeString |
| `Whole`, where `Whole = 'a' + 'b'` | UnicodeString | UnicodeString |
| `#$0061#$0062` | UnicodeString | UnicodeString |
| `#$0061 + 'b'` | UnicodeString | UnicodeString |
| quoted U+044F literal + `'b'` | UnicodeString | UnicodeString |

The complete table shows the mechanism: the byte type was assigned to the `+`
result only when **both** operands were quoted literals containing characters
that fit in a byte. It was enough for one operand to be written with `#$` or
contain a character above U+00FF for the result to become UTF-16. A named
constant declared with the same addition is UTF-16 too, so the type is reset at
declaration; only the expression at the call site diverges.

## Why this is costly

`Foo('prefix' + Something)` and `Foo('a' + 'b')` are ordinary source forms.
Here they could silently enter the byte half of an overloaded pair, even though
the identical call with a finished `'ab'` literal enters UTF-16. The difference
between two adjacent source lines is visible to neither the author nor the
compiler: there is no warning.

The danger is the same as in dvl-0029: ASCII is broken—the data on which code
is normally tested—while a quoted U+044F character literal makes the result
suddenly correct.

## Reproduction

`repro-standalone.dpr` prints the complete table. The file has a UTF-8 BOM:
without it, Delphi reads a quoted non-ASCII literal as two characters.

In the suite:

```
run_devil_gate.py --seeds 5 --cases 120 --layers pick --profiles release --dcc ...
```

Observation `dvl-pick-string-form-lit-str-concat-picked` turns red.

## Boundary

Verified with `debug`, `o1`, `o2`, and `release`: the same front-end decision
was made in every profile. The `AnsiString`/`UnicodeString` pair is the minimum
pair that exposes it. The four-string family (`string-four`) does not diverge
because it contains more candidates and resolves differently.
