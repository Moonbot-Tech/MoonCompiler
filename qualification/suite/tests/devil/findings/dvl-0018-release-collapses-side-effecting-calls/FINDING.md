# dvl-0018 — `release` collapses two calls to a side-effecting function

## Current status

Fixed in CONSTPROP: global/static storage is no longer treated as a local
constant across intervening calls. Regression:
`tests/test/cg/tmoonconstpropglobalcalls1.pp`.

The analysis was reconstructed from facts in the current run.

## What happens

The same expression calls a function that counts its calls twice. The language
requires two calls — the side effect is observable.

| build | `calls` check |
|---|---|
| `debug`, `o1`, `o2` | correct |
| Delphi 12.2 | correct |
| **`release`** | **failed: counted 1 instead of 2** |

At full optimization, the two calls are treated as one subexpression and only
one executes. The second side effect disappears.

## Why this is costly

A side-effecting function inside an expression is ordinary: a counter, issuing
the next identifier, reading from a stream, acquiring a lock. Collapsing changes
not the value but the **number of events**, which is precisely why an ordinary
result check does not see it: the result is correct.

This is the only defect in the suite that required changing the measurement
approach itself: its trap was removed from the chains and lives in a separate
sentinel because it changes the **number of passes**, not a value, and corrupts
the end-to-end digest differently from every other defect.

## Boundary observed during reconstruction

In the same layer, the `total` observation also differs between our `debug` and
Delphi (`30` versus `40`) — a **different** mismatch concerning operand
evaluation order, unrelated to collapsing. They must not be combined.

## Reproduction

```
run_devil_gate.py --seeds 3,4 --cases 60 --layers inl --profiles debug,o1,o2,release --dcc ...
```

Only the `dvl-inl-<N>-calls` check fails, and only in `release`.
