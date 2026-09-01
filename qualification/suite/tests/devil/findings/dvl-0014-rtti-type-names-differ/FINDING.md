# dvl-0014 — RTTI type names and kinds differ from Delphi

The analysis was reconstructed from facts in the current run. This is an
**observation**, not a failure: the program computes correctly, but what it sees
through type tables differs from the oracle.

## What happens

| observation | ours | Delphi 12.2 |
|---|---|---|
| string type name (`dvl-uni-<N>-typename`) | `UnicodeString` | `string` |
| real type kind (`dvl-lang-<N>-real-type`) | **5** | different |
| element type kind (`dvl-lang-<N>-real-element-type`) | **5** | **6** |

The name difference follows from the implementation: our `string` is an alias,
and the table carries the concrete type name. The kind difference follows from
each implementation having its own numbering of kinds.

## Why this is only an observation

None of these values changes the computation. The risk is elsewhere: code that
**compares a type name to a string** or relies on a numeric kind value behaves
differently. Such code appears in serializers and mappings.

For that reason, the suite pipeline carries not a kind number but the fact that
it matches a named constant; otherwise the pipeline would fail on a difference
that has no substantive meaning.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 60 --layers uni,lang --profiles debug,release --dcc ...
```

## Boundaries

Checked in `debug`, `o1`, `o2`, and `release` — identical in all profiles; only
the oracle differs.
