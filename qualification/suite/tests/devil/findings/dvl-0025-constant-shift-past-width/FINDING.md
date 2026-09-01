# dvl-0025 — constant shift at or past the type width: Delphi rejects it; we accept it

The analysis was reconstructed from verdict-gate facts.

## What happens

A constant shift count equals or exceeds the width of the operand type. Delphi
refuses to compile this form; our compiler accepts it and emits code.

## Why it is in the journal

The form is questionable in its own right: the result of shifting by the full
width is not defined consistently, which is precisely why the oracle prohibits
it. By accepting it, we permit source with no Delphi equivalent.

The suite does not assess the numeric result here—the arithmetic restriction is
already enforced. This entry concerns the compilation verdict only.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Case `shift-count-past-width`, category `false-accept`.
