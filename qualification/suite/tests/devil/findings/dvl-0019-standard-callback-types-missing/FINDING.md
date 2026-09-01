# dvl-0019 — `TProc`, `TFunc<T>`, and `TPredicate<T>` are missing from the RTL

## Current status

Fixed in product `SysUtils`: callback types with up to four arguments are now
published. Regression: `tests/test/cg/tmoondelphicallbacktypes1.pp`.

The analysis was reconstructed from verdict-gate facts.

## What happens

Three standard wrapper types around anonymous routines, declared by Delphi in
`System.SysUtils`, cannot be found in our RTL:

```
Error: Identifier not found "TPredicate"
```

The verdict gate keeps three cases — `stdtype-tproc`, `stdtype-tfunc`, and
`stdtype-tpredicate` — each with the verdict “must compile”.

## Why this is costly

This is a code-porting blocker, not an inconvenience. `TProc` and `TFunc<T>`
are the vocabulary in which half of modern Delphi code is written: callbacks,
deferred actions, higher-order functions, and interfaces of the “give me an
action” kind. A unit using them does not build at all, and the only workaround
is editing foreign source to declare its own same-named types, which then
conflict on return to Delphi.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Cases: `stdtype-tproc`, `stdtype-tfunc`, `stdtype-tpredicate`; finding types:
`false-reject` and `verdict-split`.
