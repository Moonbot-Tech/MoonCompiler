# dvl-0046 — `StringToGUID` parsed no identifier: a byte string was read through a two-byte pointer

Found by the new `resident` layer—a handwritten production-scale program—on
its first run, in the `rtl-guid` stage. The failure was not silent: the stage
raised `EConvertError` on every iteration for every carrier.

## What happens

`StringToGUID` rejected **every** valid input, including the zero GUID. This
was checked with ten strings, from `{00000000-…}` to `{FFFFFFFF-…}`, in upper
and lower case:

| Input | Delphi 12.2 | Ours |
|---|---|---|
| `{00000000-0000-0000-0000-000000000000}` | Accepted | `EConvertError` |
| `{12345678-1234-1234-1234-123456789ABC}` | Accepted | `EConvertError` |
| `{4D5A0001-0000-0000-0000-0000524553FF}` | Accepted | `EConvertError` |
| `{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}` | Accepted | `EConvertError` |
| The same string in lower case | Accepted | `EConvertError` |

No accepted input could be found: the entire function was broken, not merely an
edge of its domain.

## Mechanics

The chain is short and entirely in the RTL:

`StringToGUID` → `TryStringToGUID` (`rtl/objpas/sysutils/sysuintf.inc`) →
`TGUID.FromString` (`rtl/inc/objpas.inc`).

`FromString` accepts a **`ShortString`**, whose characters each occupy one
byte. It parsed it as follows:

```pascal
var
  sp: PChar;
...
  sp := PChar(Pointer(@S[1])) + cAsStringByteScatter[iByte] - 1;
  PByte(@Guid)[iByte] := ParseHexDigit(sp[0], Result) shl 4 + ParseHexDigit(sp[1], Result);
```

`PChar` in this mode occupies two bytes. Both pointer-arithmetic steps are
therefore twice the `ShortString` character step, and `sp[0]` combines one
“character” from two neighboring bytes. Parsing loses both location and
content: `ParseHexDigit` takes its `else` path, sets `Result := False`, and
the failure propagates upward.

The first half of the function was sound: it validates length and separators
with `ShortString` indexing, byte by byte. That explains the observation: the
string is “valid,” but the result is “not a GUID.”

The hypothesis was checked with a direct probe that repeated the same layout
using two pointers over one `ShortString`:

```
SizeOf(Char)  = 2
SizeOf(S[1])  = 1
via PChar     ok=FALSE  bytes=00000000000000000000000000000000
via PAnsiChar ok=TRUE   bytes=01005A4D0000000000000000524553FF
```

The byte pointer parses correctly: `01005A4D` is `D1=4D5A0001` in this
platform's byte order, and the `524553FF` tail is present. Pointer width is
the only difference.

## The defect is one-way

The reverse conversion works: `GUIDToString` (through `TGUID.AsString`)
produces `{4D5A0001-0000-0000-0000-000000000000}` correctly. A program that
writes an identifier to a string and reads it back therefore fails precisely on
the read: half the contract works and half does not.

## Reproduction

`probe/guid.dpr` passes ten strings through `StringToGUID`, each inside
`try/except`. `probe/guid2.dpr` parses the same `ShortString` beside each
other through two pointers.

Both build with the ordinary driver; the oracle is Delphi 12.2 `dcc64` with
`-U<lib\win64\release> -NSSystem`.

## Why this is costly

`StringToGUID` is the ordinary way to read an identifier from configuration,
a protocol, or a database. Failure arrives as an exception rather than a silent
wrong value, so in production it is not data corruption but a parsing crash—and
everything receiving an identifier as text fails. The only workaround is a
custom parser.

This was not a rare combination but the function in its only form: porting any
code that reads identifiers stops here immediately.

## What this says about coverage

The defect lived in the RTL rather than code generation, which is why none of
the previous layers saw it: they ask the compiler “did you calculate correctly,”
not “does what you built for yourself work correctly.” The `resident` layer
approached it as an ordinary program and found it on its first run.

## Repair result

The first broken invariant was repaired: `ShortString` addressing must have a
one-byte step regardless of the product RTL's default `Char`. In
`TGUID.FromString`, the local `PChar` was replaced with `PAnsiChar`; the
algorithm, layout table, and public signatures were unchanged.

The permanent `tests/test/cg/tunicodeguidparse1.pp` checks uppercase/lowercase,
zero/full GUIDs, direct `TGUID.FromString`, `GUIDToString` round-trip,
missing braces, an invalid separator, and an invalid hex digit. The self-host
bootstrap passed; the O2/O3 focused test and full Win64 repair gate are green.
The gate retains hashes of installed `system.ppu` and `sysutils.ppu`, not
only an unchanged compiler executable.
