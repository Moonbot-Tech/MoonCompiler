# dvl-0020 — `inline` with an open array: Delphi rejects it, we accept it

The analysis was reconstructed from verdict-gate facts.

## What happens

A routine with an open array among its parameters is marked `inline`.

| compiler | verdict |
|---|---|
| Delphi 12.2 | `E2439 Inline function must not have open array argument` |
| ours | compiles |

## Why this matters even though nothing breaks

This is one-way portability: a unit written here will not compile in Delphi,
and the author learns that at the most inconvenient time — during porting. Our
behaviour itself is more permissive and causes no harm.

The entry remains in the journal for a product-owner decision: whether the
oracle's strictness is mandatory. For now, the mismatch is considered allowed
and is recorded.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Case `inline-open-array`, types `false-accept` and `verdict-split`.
