# dvl-0048 — fixed: `Split` on an empty string returns an empty array

Found by the `resident` layer, `text-split-join` stage, through arbitration
with Delphi 12.2.

## What happens

| Input | Ours | Delphi 12.2 |
|---|---|---|
| **`''.Split([','])`** | **1 part** (empty string) | **0 parts** |
| `','.Split([','])` | 2 | 2 |
| `'a'.Split([','])` | 1 | 1 |
| `'a,,b'.Split([','])` | 3 | 3 |
| `',a'.Split([','])` | 2 | 2 |
| `'a,'.Split([','])` | 2 | 2 |
| `''.Split([','], ExcludeEmpty)` | 0 | 0 |

Exactly one case differs: empty input. All others, including empty parts in the
middle, at the edges, and consecutively, match. Parsing is otherwise identical;
only the degenerate input can diverge.

## Why this is costly

Splitting a string by a separator is the ordinary first step in reading a
configuration value, header, or protocol field. Typical code is:

```pascal
for var Part in Line.Split([',']) do
  Handle(Part);
```

For an empty string Delphi does not enter the body, whereas we entered it once
with an empty string. Everything then depends on `Handle`: at best an extra
empty list entry, at worst an attempt to parse an empty field as a number or
key. There is no compile error or warning and no difference for nonempty input,
so it appears at the boundary that is tested least often.

## Reproduction

`probe/rest.dpr`, `--- split` section: seven input forms in succession, each
printing the part count. It builds with the ordinary driver; the oracle is
Delphi 12.2 `dcc64` with `-U<lib\win64\release> -NSSystem`.

## Cause and repair

Both master implementations of `TStringHelper.Split` entered their loop with
`LastSep = Length(Self) = 0`. The degenerate source was consequently treated as
one zero-length field. Delphi first checks for an empty source and returns
`nil`, without considering separators/options/count.

The same early invariant was added to exactly two master overloads: character
and string separators. Every public wrapper reaches them; the nonempty loop,
quote parsing, and array growth are unchanged.

`tdelphisplitempty1` checks the full empty class (both separator kinds,
options/count/quotes, and an empty separator array) plus neighboring nonempty
forms. It passed Delphi 12.2, our exact RTL under O-/O2/O3, and the 72-row Win64
repair gate.
