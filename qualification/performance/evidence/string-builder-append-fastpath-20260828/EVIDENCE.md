# TStringBuilder: exact fast path for string Append

Date: 2026-08-28. Target profile: Win64 O3, MoonCompiler with the bundled MM.

## First violated invariant

The phase probe separated object creation, buffer growth, Append to a
preallocated buffer, reuse of a ready buffer, and ToString. Creation and
ToString were already at parity. Even without growth, each string Append went
through the shared `PrepareGap`, and the actual RTL object contained a separate
helper call on every iteration.

For exact `TStringBuilder.Append(UnicodeString)`, a specialized path remains:
`MaxCapacity` check, rare `GrowTo`, `Move`, then publication of `FLength`.
Exception construction is moved to a `noinline` cold helper. The important
contract is retained: if the check or growth raises, the builder's visible
length and contents do not change; descendants continue through virtual
`DoAppend`.

## Focused A/B

Five interleaved process pairs, quick, median thread cycles per Append:

| Phase | Before | After |
|---|---:|---:|
| append with growth | about `1.88x` Delphi | `1.444x` |
| append to a preallocated buffer | about `1.68x` | `1.253x` |
| append to a reused buffer | about `1.58x` | `1.119x` |

The standard Pulse quick preserved the semantic digest and produced:

- `builder-growth-64k`: `1.199x` instead of the stable medium baseline `1.262x`;
- `builder-append-prepared-floats-64`: `1.071x` versus the `1.054x` baseline—
  remains within ordinary quick-run variance; no regression is claimed.

## Correctness

`RTL-test/semantic/string_builder_transaction_semantic.dpr` passes
Debug/O2/O3. An exact MaxCapacity regression for string Append was added: an
exception is mandatory and the previous string must be retained.

Full qualification was deliberately not run at this stage.
