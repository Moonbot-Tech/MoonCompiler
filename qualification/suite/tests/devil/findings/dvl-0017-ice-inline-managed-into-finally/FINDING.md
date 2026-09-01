# dvl-0017 — `Internal error 200405231`: inlining a managed routine into `finally`

## Current status

Fixed with a narrow eligibility guard: a void procedure with a potentially late
managed temporary is not inlined into a caller without a cleanup frame.
Managed-result inlining remains enabled. Regression:
`tests/test/cg/tmooninlinemanagedexprfinally1.pp`.

The analysis was reconstructed from facts in the current run; the previous text
was lost with the working directory.

## What happens

A small routine that works with a managed value (a string) is called from a
`finally` body. The compiler decides to inline it — and crashes:

```
Fatal: Internal error 200405231
```

The program does not build at all. The form is kept by a stress gate:
`inline-managed-finally` builds several such routines and calls them from a
protected region.

## Why this is costly

This is an internal error, not a diagnostic: the author receives no source line
that explains what is wrong. The form is commonplace — appending a string in
`finally` (logging, tracing, cleanup with a record). The production profile,
where inlining is enabled, fails.

One consequence for the suite itself: Devil's instrumented runtime remains
outside the inliner (`{$optimization noautoinline}`) because of this finding —
otherwise it would take down every layer that writes a trail.

## Reproduction

```
run_devil_stress_gate.py --cases 24
```

Case `dvl_stress_<N>_inline_managed_finally` fails with type `internal-error`.
The resolved registry tags it by error number, so the gate treats it as known
and does not fail because of it.

## Boundaries

Reproduces in the `release` profile; in `debug`, there is no inlining and no
crash.
