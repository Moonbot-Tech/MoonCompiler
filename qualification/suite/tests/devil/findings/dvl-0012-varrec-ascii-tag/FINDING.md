# dvl-0012 — an ASCII character literal enters `array of const` as a byte character

The analysis was reconstructed: the previous text was lost with the working
directory, and the facts were recorded again by running the `chain` layer on the
current compiler.

## Status

Fixed. In Delphi-Unicode mode, an ASCII character and a folded `Chr` have the
`Char`/`WideChar` type, so `array of const` receives `vtWideChar`. Focused
regression: `tests/test/cg/tdelphiunicodeliteral1.pp`; neighbouring explicit
`AnsiChar`/`AnsiString` cases and ObjFPC mode are preserved.

## What happens

A character literal is passed in an open list of heterogeneous arguments
(`array of const`), and the recipient reads the element tag — the tag by which
`TVarRec` declares what it contains.

| build | tag |
|---|---|
| `debug`, `o1`, `o2`, `release` | **2** |
| Delphi 12.2 | **9** |

Two is `vtChar`, a byte character. Nine is `vtWideChar`, a UTF-16 character.
Thus, in a program whose `Char` is contractually sixteen-bit, a literal reaches
the variant list as a byte character.

## Why this is costly

`array of const` carries all formatting and everything that accepts “anything”:
`Format`, logging, and wrappers around external APIs. The receiver decodes an
element by tag, and a byte tag sends it down the branch that reads `VChar` rather
than `VWideChar`. The difference is invisible for ASCII, but the first non-ASCII
character becomes garbage — the error manifests on user data rather than in
tests.

The failure is silent: neither the compiler nor the runtime reports anything.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 40 --layers chain --profiles debug,release --dcc ...
```

The `dvl-chain-<N>-varrec-ascii` observation fails: ours is `2`, the oracle is
`9`.

## Boundaries

Checked in `debug`, `o1`, `o2`, and `release` — the tag is identical in every
profile, so the frontend rather than the optimizer makes the decision.
