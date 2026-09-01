# dvl-0039 — `Int64` versus `Integer`/`Cardinal`: Delphi selects, we reject

Found by the `deliver` layer (decision × delivery): when the same overload
selection question is compiled after crossing a module boundary, the compiler
hits ambiguity where Delphi 12.2 builds without trouble.

## Status

Fixed by the same pairwise rule as dvl-0028. `Int64` does not fit in `Integer`,
so an `Integer/Cardinal` pair selects `Cardinal`; in an `Int64/UInt64` pair,
`Int64` itself selects signed. If different arguments require opposing
candidates, the result remains ambiguous—no arbitrary majority rule was added.

## What happens

```pascal
function Pick(const V: Integer): Integer; overload;    { candidate 1 }
function Pick(const V: Cardinal): Integer; overload;   { candidate 2 }

var
  W: Int64;
begin
  W := 7;
  WriteLn(Pick(W));
```

| compiler | result |
|---|---|
| Delphi 12.2 | builds and selects **`Cardinal`** |
| ours | `Error: Can't determine which overloaded function to call` |

The outcome is the same for an `Int64` variable and for a function result that
returns `Int64`. It is enough to remove the second candidate (leave `Integer`
against, say, `string`), and we build and select `Integer`, just as Delphi does.
So this is not about `Int64` itself, but about a pair of equally wide candidates
that differ in signedness: Delphi can order them, while we declare a tie.

## Relationship

This is the reverse side of dvl-0028. There, we sent a narrow **unsigned**
argument (`Byte`, `Word`) against the same pair to `Cardinal`, while Delphi sent
it to `Integer`. Here, Delphi sends a wide **signed** argument to `Cardinal`,
whereas we send it nowhere. Therefore it is not one value of the rule that
diverges, but the candidate-ordering rule itself by signedness and width—they
should be fixed together.

## Why this is costly

The rejection is hard: the module does not compile. The `Integer`/`Cardinal`
pair is a common form for encoders, formatters, and WinAPI wrappers, while an
`Int64` argument arrives from any time counter, file size, or exchange
identifier. Code that builds in Delphi for years stops the build here, and the
message does not suggest what to do: both candidates appear equally suitable.

## Reproduction

`repro-standalone.dpr` is self-contained.

Through the suite: verdict-gate case `int64-arg-vs-integer-cardinal`.

## Boundary

Verified under `debug`, `o1`, `o2`, and `release`: all reject it; the front end
makes the decision. `Integer` against an unrelated candidate (`string`) yields
no ambiguity on either side.
