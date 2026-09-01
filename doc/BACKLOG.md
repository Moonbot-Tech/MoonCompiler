# BACKLOG

## Deferred improvements

This is the single list of proven but deliberately deferred engineering tasks.
They do not change the correctness of supported MoonCompiler programs and do
not block the public release. The reason for deferring each item is specific:
low absolute cost, no proven hot-path consumer, or the need for a broad
architectural repair instead of a local patch.

A correctness defect, compiler crash, Win64/Linux ABI violation, or build
failure of a supported application must not be moved here. Such findings remain
release blockers. Public semantic limitations are described in
[`KNOWN_ISSUES.md`](KNOWN_ISSUES.md); an unresolved correctness defect must not
be moved here.

The exact Pulse figures below refer to the final 2026-08-30 snapshot. Evidence
and the final summary are in
[`qualification/performance/CURRENT_RESULTS.md`](../qualification/performance/CURRENT_RESULTS.md)
and `qualification/performance/evidence/release-final-20260830/`.

## Runtime and RTL

### PB-001 — `raise/catch` and managed exception cleanup

A real throw/catch takes about 5702 CPU cycles versus 3618 in Delphi 12.2:
roughly 2084 excess cycles. Assign-only and a `try` without an exception are
already faster than Delphi; managed cleanup slows down only together with
raise/unwind. This is one exception-runtime root cause, not a defect in managed
assignment, the MM, or register allocation.

Exceptions are not a routine hot path in MoonBot or Arbitrage. Return to this
task by the phases of raise, personality/unwind, handler dispatch, and cleanup,
without trying to accelerate the composite with one local patch.

### PB-002 — reserved `TDictionary` construction

For `TDictionary<UInt64,UnicodeString>` with `Capacity := 100`, the final
build case takes 307.4 versus 175.7 cycles per element (`1.749x`), or about
13 thousand excess cycles for the entire one-time build. Lookup in the same
table is at parity with or faster than Delphi; managed churn is already fixed.
The large numeric form separately points to allocation/zeroing of a large array.

This is the cost of construction/configuration, not lookup. Before a repair,
separate allocation, zeroing, capacity policy, hashing, and managed-value
lifetime; lookup must not be degraded for an attractive aggregate build-case
number.

### PB-003 — `TList<UnicodeString>.InsertRange`

The final composite shows 102.0 versus 62.9 cycles per normalized inserted
element (`1.622x`), but it also builds the source list of 4096 strings and
destroys the final managed sequence. It does not prove the same gap within one
`InsertRange`. A focused bulk-incref A/B was faster than Delphi (`0.884x`),
and adjacent `AddRange` and `Clear` are also faster.

Before another repair, a phase split is required: prepared source, tail move,
addref of new elements, and finalization. Changing a container on the basis of
one composite number is forbidden.

### PB-004 — dense `case` strategy

Uniform 8-way `case` remains 6.47 versus 3.89 cycles per dispatch (`1.663x`).
A direct jump-table probe worsened an unpredictable selector to `2.73x`, so a
global replacement was rejected.

The next evidence-driven study is a balanced tree versus the current strategy
on uniform, skewed, and sequential distributions, with code-size and branch
prediction controls. One strategy cannot be declared better from a single
selector.

### PB-005 — remaining dynamic-array by-value cost

After direct `lock xadd` inside the refcount helper, by-value improved from
`1.550x` to `1.180x` (about 18.4 versus 15.7 cycles). Ordinary assignment is
faster than Delphi (`0.834x`), and `const` passing is at parity (`0.997x`).
The remaining roughly 2.8 cycles are in the call-site helper contour. Extending
compiler lowering for this delta is justified only after a notable real consumer
appears.

### PB-006 — infrequent `TStringBuilder` growth/realloc

The main exact `Append(UnicodeString)` is already fixed. Reuse/reserve/growth
improved from `1.58/1.68/1.88x` to `1.119/1.253/1.444x`, while ordinary quick
growth is about `1.199x`. Only infrequent buffer expansion remains open; no
new hot-path repair is needed without a separate realloc-phase A/B.

### PB-007 — `managed/variant-numeric`

The remaining `1.238x` is spread across temporary Variant copying, operator
invocation, and finalization. The next repair makes sense only if it removes an
entire temp/copy/manager operation. Saving a few cycles within the existing
chain does not justify changing the Variant ABI.

## Memory manager and runtime contracts

### PB-008 — Win64 MM `managed-five-hop`

The bundled MM is 3–7% slower than the MM baseline only in the mixed five-stage
scenario; Linux yields `0.999x`. The form mixes ownership/COW, small/medium
realloc, and large realloc-copy. It must first be decomposed into independent
exact-volume subscenarios, and only the first proven causal repair is accepted.

### PB-009 — alternative MM small-class table

The production baseline of `44 classes + padding` is accepted as safe. In the
future it may be compared with FastMM5-like 51 classes and a trace-derived table
of no more than 44 boundaries. The decision is made only from production
allocation traces, fragmentation, cache locality, and the full realloc range,
not one synthetic loop.

### PB-010 — lightweight production MM telemetry

FastMM-like `LiveCapacityBytes`, `OsHeldBytes`, and computed `Efficiency`
are needed, but without new lock/atomic operations on the ordinary small
`GetMem/FreeMem` hot path and without enlarging the object header. The assumed
path is the sum of existing shard counters, updates of medium/large counters
inside already-held locks, and an infrequent OS-held delta near
`mmap`/`VirtualAlloc`.

### PB-011 — expanded Linux stack qualification

The current product contract already fixes 1 MiB + guard for `TThread` and
`BeginThread`; the main thread inherits `RLIMIT_STACK`, while raw pthread
inherits the glibc policy. After release, expand pressure/overflow subprocess
stress and guard/rlimit measurement. This strengthens evidence; it is not a
known runtime error.

## Compiler optimizer

### PB-012 — missed inline dvl-0068

The hot form with a `const` record parameter and a write to external state is
not inlined, but computes the correct result. This is a measured missed
optimization, not a correctness defect.

### PB-013 — next architectural LICM/GVN/RA pass

The current block is accepted and verified. A further pass is possible only with
separate consumers and includes:

- remove the call barrier only for exact locals proven inaccessible to the
  callee;
- select LICM candidates by a calculated score rather than traversal order;
- replace the general mixed-width FP fallback with a per-value dependency model;
- measure and, if necessary, index repeated SEHREGVAR tree scans;
- investigate bounded/PGO `CODEALIGN` on a real label-heavy consumer.

None of these items is currently wrong-code. The accepted architecture and its
evidence boundaries are documented in [`OPTIMIZER.md`](OPTIMIZER.md).

### PB-014 — proof-gated hoist of the string COW check

Every indexed write `S[I] := X` correctly calls `*_str_unique`. One COW check
before a loop is permitted only for a local, non-address-taken base without
assignment, capture, `var/out` alias, or opaque call, and a zero-trip must not
change the refcount or materialize a constant. A complete Ansi/Unicode/Wide
semantic+ASM matrix is required; until then the current correct codegen remains
unchanged.

## Semantics and upstream

### PB-015 — unified decimal representation

`FormatFloat`, `Format`, `FloatToStrF`, and `Str` still use different
digit-generation paths and diverge at half-boundaries and signed zero. A local
fix to one formatter would merely move the discrepancy. One exact
digits/exponent/sign/guard/sticky core, a separate fixed-point path for
`Currency`, and a complete cross-API DCC/Win64/Linux matrix are required. The
public boundary remains described in
[`KNOWN_ISSUES.md`](KNOWN_ISSUES.md#inconsistent-double-rounding-in-text-apis).

### PB-016 — narrow upstream PRs for modern mORMot

After publication readiness, split the integration Linux/FPC patch into
independent PRs: Unicode RTL signatures, Unicode POSIX boundaries, and only
after a separate repro, extended record RTTI. Every PR must preserve the
ordinary ANSI FPC profile and use current upstream patterns; a shared seven-file
patch must not be sent.

## Closed signals that must not return to the backlog

- `runtime for 0..255`: full Pulse showed 2.21 versus 1.64 cycles/iteration,
  but the isolated same body yields `0.99x`, and Moon emits a shorter loop.
  The gap changes with code address relative to frontend/uop-cache boundaries.
  This is a general layout signal for a specific executable, not a defect in
  `for` lowering.
- Ordinary `try/finally`: a real `Lock; try ... finally Unlock` yields
  `1.026x`; the loss in an empty micro-loop also proved to be a layout/placement
  effect.
- `IntToHex(UInt64,16)`, the main `TStringBuilder.Append`, JSON/TDocVariant,
  numeric dictionary lookup, and `System.Move` already have accepted repairs or
  proven parity. Their old ratios are not open tasks.
