# dvl-0029 — a quoted character literal selects `AnsiChar` where Delphi selects `Char`

Found by the `pick` layer. The disagreement is in overload selection and
directly violates the reason this compiler uses the Delphi-Unicode ABI: `Char`
is UTF-16 here, yet the literal is routed to a byte overload.

## Status

The proven ASCII portion is fixed: `'a'`, `Chr(97)`, `#$0061`, literal
concatenation, PPU delivery, and `array of const` now follow Unicode
`Char`/`String` semantics.

## Non-ASCII status: fixed

The DCC64 36.0 matrix (UTF-8 BOM source, CP1251 machine) established the exact
model:

- a quoted non-ASCII character representable in the system ANSI code page is
  typed as `AnsiChar` with its ANSI byte: U+044F has `Ord = 255`, U+0451 has
  `Ord = 184`, and U+20AC has `Ord = 136`; an unrepresentable character such as
  U+4E2D or U+00FF under CP1251 remains `Char` with its code point;
- a `#` escape retains the width indicated by its written form: `#$FF` is a
  byte, while `#$044F` and `#1103` are wide (this already matched: the scanner
  distinguishes the magnitude and written length);
- widening a byte literal in a wide context decodes through the same code page,
  so the character survives: assigning the quoted U+044F literal to `WC` gives
  `Ord(WC) = 1103`; its string carries U+044F, while `AnsiString` carries byte
  255.

The repair has two parts:

- **Scanner** (`readstringconstant`): for a one-character wide literal whose
  width originated from a quoted UTF-8 character (a new local flag; escape
  fragments do not set it), pass the character through the current system ANSI
  code-page map. A representable character becomes `_CCHAR` with its ANSI byte;
  otherwise it remains `_CWCHAR`.
- **widestr**: new `charliteralmap`, the `DefaultSystemCodePage` map for the
  Delphi Unicode profile with UTF-8 source. It now drives
  `asciichar2unicode`/`unicode2asciichar`. Previously the first conversion was
  an identity under UTF-8 and assigning the quoted U+044F literal to `WC` would
  have produced U+00FF, corrupting the character. The same map drives
  char-to-string and char-to-char folds in `ncnv`, with no separate changes
  there.

ANSI source files (CP1251 without a BOM) already matched Delphi: their byte
naturally remains `_CCHAR`. Like DCC, the whole axis depends on the ANSI code
page of the build machine; this is literal Delphi semantics.

Pin: `RTL-test/semantic/char_literal_ansi_semantic.dpr` (UTF-8 BOM, complete
matrix; checks run under CP1251 and are neutral under other ACPs) passes with
us and DCC64. The `pick` + `deliver` layers, seed 5, compare 252 checks against
the DCC binary byte-for-byte.

## What happens

```pascal
function Code(const V: AnsiChar): Integer; overload;   { 1000 + Ord }
function Code(const V: Char): Integer; overload;       { 2000 + Ord }
```

The same character written in two forms:

| code point | quoted `a` ours | quoted `a` Delphi | `#$xxxx` ours | `#$xxxx` Delphi |
|---|---|---|---|---|
| U+0061 | **AnsiChar** 97 | Char 97 | Char 97 | Char 97 |
| U+007F | **AnsiChar** 127 | Char 127 | Char 127 | Char 127 |
| U+00FF | Char 255 | Char 255 | Char 255 | Char 255 |
| U+0100 | Char 256 | Char 256 | Char 256 | Char 256 |
| U+044F | **Char** 1103 | AnsiChar 255 | Char 1103 | Char 1103 |

The complete table establishes the mechanism:

- **`#$` notation never diverges**: both sides type it as `Char`. The issue is
  therefore the written form, not the code point.
- `Chr(97)` behaves like a quoted literal rather than `#$0061`: our old build
  chose `AnsiChar`, while Delphi chose `Char`. The rule therefore applied to
  any **folded** character expression fitting in a byte, not only a literal.
- Our old implementation typed a quoted literal by code-point magnitude:
  below U+0080 it was `AnsiChar`, above it was `Char`. Delphi has no such
  threshold.
- This created an internal inconsistency: quoted `a` and `#$0061` denote the
  same character but selected **different** overloads here.

For non-ASCII the divergence was mirrored: Delphi routes the quoted literal to
`AnsiChar` after conversion through the current ANSI code page (under CP1251,
the quoted U+044F literal becomes `$FF`, hence 255), while our old compiler kept
UTF-16. Delphi is the contract oracle, so both ends diverged.

## Why this is costly

The `AnsiChar`/`Char` pair is ordinary string-library API, not an exotic form:
`Append(c: Char)` beside `Append(c: AnsiChar)`, character parsers,
classifiers, and escaping. In a program whose contract is UTF-16 throughout, a
quoted ASCII literal could silently enter the byte half of that pair.

The failure is particularly unpleasant because it affects ASCII—the data for
which “everything works.” Testing only U+044F does not expose it either, since
that follows a different path and can be correct.

## Delivery paths that carry the defect

The `deliver` layer carries the same question through nineteen delivery forms.
The picture mirrors dvl-0028:

| delivery | result |
|---|---|
| **literal directly, parenthesized, double-parenthesized** | **disagreement** |
| **constant from another unit (PPU)** | **disagreement** |
| cast, typed constant, `const` parameter | agreement |
| generic specialization, closure, `with`, thread | agreement |
| `case` branch, `if` branch, result of an inline or non-inline function | agreement |

The defect lasts exactly as long as the value remains **a literal**. Any
delivery that fixes its type removes it.

The PPU row is especially valuable: literal provenance **survives a unit
boundary**. A constant declared in another unit carries the defect with it.
That agrees with the compiler's own statement that constant provenance is
serialized into PPU and means the defect crosses `.ppu` into units where the
source literal is invisible.

## Reproduction

`repro-standalone.dpr` prints the complete table. The file is stored with a
UTF-8 BOM: without it, Delphi reads a quoted non-ASCII literal as two
characters.

In the suite:

```
run_devil_gate.py --seeds 5 --cases 120 --layers pick --profiles release --dcc ...
```

Observation `dvl-pick-char-form-lit-char-picked` turns red.

## Boundary

Verified with `debug`, `o1`, `o2`, and `release`: the old decision was the
same in all profiles, so it was made by the front end rather than the optimizer.
A two-character literal (`'ab'`) does not diverge: both compilers select the
string overload. The old rule's boundary was exactly U+0080.
