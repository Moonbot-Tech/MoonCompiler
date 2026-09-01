# dvl-0024 — anonymous `reference to` in a variable declaration

The analysis was reconstructed from verdict-gate facts.

## What happens

The type `reference to procedure` is written directly in a variable declaration
instead of being given a name. Delphi rejects this form; our compiler accepts it.

## Why it is in the journal

This is one-way portability: code written here will not compile with the
oracle. The behaviour itself is sound—the form works.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Case `anonymous-reference-var`, category `false-accept`.
