# dvl-0021 — `varargs` without `external`: Delphi accepts it; we reject it

The analysis was reconstructed from verdict-gate facts.

## What happens

A routine is declared with `varargs` but is not marked `external`:

```
Error: VarArgs directive (or '...' in MacPas) without CDecl/CPPDecl/MWPascal/StdCall and External
```

Delphi compiles this form.

## Why this is costly

This is a **blocker**: the unit does not compile. The form occurs in wrappers
around C libraries and in transitional layers where a signature is declared
up front and its implementation is supplied later. The only workaround is to
modify third-party source.

Unlike dvl-0020, we are **stricter** than the oracle here, and the cost is an
inability to compile valid Delphi source.

## Reproduction

```
run_devil_reject_gate.py --dcc ...
```

Case `varargs-without-external`, categories `false-reject` and `verdict-split`.
