# dvl-0022 — set element outside its range: Delphi accepts it; we crash

The analysis was reconstructed from verdict-gate facts.

## What happens

A set constructor contains a value outside the range of its base type. Delphi
accepts the form (with a range diagnostic); our compiler reaches the assembler
and crashes there.

## Why this is costly

The failure occurs during code emission rather than parsing, so the message
does not describe the source form but internal machinery. The author sees an
assembler error and looks in the wrong place.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Case `set-element-out-of-range`.
