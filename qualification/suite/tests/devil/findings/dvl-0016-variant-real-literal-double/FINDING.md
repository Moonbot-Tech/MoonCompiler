# dvl-0016 — a real literal is stored in `Variant` as `Double`

The analysis was reconstructed from facts in the current run.

## What happens

A real literal is stored in a `Variant`; the observation records its type code.

| build | type code |
|---|---|
| `debug`, `o1`, `o2`, `release` | **5** |
| Delphi 12.2 | **6** |

Five is `varDouble`; six is `varCurrency`. Thus, a literal that the oracle
treats as monetary becomes floating-point in our compiler.

## Why this is costly

The difference is exactly where it costs the most: `Currency` stores four
decimal places exactly, while `Double` is approximate. A literal placed in a
Variant as `Double` loses exactness by the first operation, and the result
diverges in cents. In trading code, this is the worst place for “almost right”.

Relationship: `KNOWN_ISSUES` records a neighbouring divergence — a mixed
`Currency` expression with an untyped literal is not typed as in Delphi. The
root is shared: what a real literal is considered to be before it is stored.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 40 --layers chain --profiles debug,release --dcc ...
```

`dvl-chain-<N>-variant-real` fails.

## Boundaries

Checked in all four profiles — identical.
