# dvl-0027 — a floating literal silently selects `Double` where Delphi requires disambiguation

Found by the `pick` layer (overload resolution), on the `money` × `lit-float`
pair. The disagreement is in the **compilation verdict**: Delphi 12.2 refuses
to build the source; our compiler builds it and chooses a candidate itself.

## What happens

```pascal
function Pick(const V: Double): Integer; overload;
function Pick(const V: Currency): Integer; overload;
...
WriteLn(Pick(1.5));
```

| compiler | result |
|---|---|
| Delphi 12.2 | `E2251 Ambiguous overloaded call to 'Pick'` — build rejected |
| ours | builds and selects `Double` |

Delphi's rejection is not pedantry. A floating literal has no type that makes
one candidate closer than the other, so the language requires the author to
state the choice.

## Why this is costly

The `Double`/`Currency` pair is not contrived: prices are calculated in
`Double`, money is stored in `Currency`, and both overloads naturally coexist
in trading code. Delphi stops the build and makes the author choose. Our
compiler silently chooses `Double`—the path on which money loses decimal
precision. The author receives neither an error nor a warning.

The discrepancy harms portability in both directions:

- code ported from Delphi starts compiling here and acquires behaviour it never
  had before;
- code written here will not compile with Delphi, although the compiler
  contract is to accept what Delphi 12.2 accepts.

## Reproduction

`repro-standalone.dpr` is self-contained: our compiler prints `picked = 1`
(`Double`); Delphi reports `E2251`.

In the suite, use verdict-gate case `double-currency-float-literal`.

## Boundary

Verified with `debug`, `o1`, `o2`, and `release`: all four build and select
`Double`. Making the argument explicit (`Pick(Currency(1.5))`) resolves the
question for both compilers. `Double`/`Single` and `Integer`/`Double` pairs do
not disagree: Delphi chooses a candidate there, and chooses the same one we do.
