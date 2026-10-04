# Backlog

This list contains measured, user-visible performance tails and tooling
limitations that are correct today and deliberately deferred. Research ideas,
test-suite expansion, and upstream contribution plans are not presented as
product limitations. Runtime correctness defects, compiler crashes, ABI
violations, and build failures are never moved here.

Ratios below come from the final 2026-08-30 Pulse snapshot. The complete data
and methodology are in
[`qualification/performance/CURRENT_RESULTS.md`](../qualification/performance/CURRENT_RESULTS.md).

## Exception raise and managed cleanup

A real raise/catch takes about 5702 CPU cycles versus 3618 in Delphi 12.2,
roughly 2084 excess cycles. Assignment and `try` without an exception are
already faster than Delphi; the remaining cost is in raise, unwind, handler
dispatch, and managed cleanup. Exceptions are not a routine MoonBot or
Arbitrage hot path, so a broad unwind repair is deferred.

## Reserved dictionary construction

Building `TDictionary<UInt64,UnicodeString>` with `Capacity := 100` takes 307.4
versus 175.7 cycles per element (`1.749x`), about 13,000 excess cycles for the
one-time build. Lookup in the same table is at parity or faster. A future repair
must separate allocation, zeroing, capacity policy, hashing, and managed-value
lifetime without degrading lookup.

## Dense `case` dispatch

A uniform eight-way `case` takes 6.47 versus 3.89 cycles (`1.663x`). A direct
jump-table experiment made an unpredictable selector `2.73x` slower, so no
global strategy was accepted. Any revisit must compare the current lowering,
a balanced tree, and a jump table across uniform, skewed, and sequential
selectors, including code size.

## Dynamic array passed by value

Inlining the direct refcount operation improved the case from `1.550x` to
`1.180x` (about 18.4 versus 15.7 cycles). Assignment is faster than Delphi and
`const` passing is at parity. The remaining approximately 2.8 cycles are in the
call-site helper contour; changing compiler lowering is deferred until a
material application consumer appears.

## Infrequent `TStringBuilder` growth

The common `Append(UnicodeString)` path is fixed. Reuse, reserve, and growth
improved from `1.58/1.68/1.88x` to `1.119/1.253/1.444x`; ordinary quick growth
is about `1.199x`. Only occasional buffer expansion remains, so another change
needs a focused realloc-phase result rather than the aggregate case.

## Short-piece string concatenation

`rtl/unicode-concat-32` (`s := s + 'part-' + IntToStr(j)`, 32 pieces) costs
61.7 cycles per piece on Zen 3 against Delphi's 85-103; the +17.6% of the
Stage 2 review was the product placement (`fpc_unicodestr_concat_multi` and
`DecimalString32` in the same op-cache sets, `qualification/performance/README.md`),
the code is 8% faster than the 2026-09-06 baseline. Two RTL changes were
measured and declined on 2026-09-21: skipping `MemSize` in `SetLength` when
the string does not grow and copying pieces of up to 16 bytes inline in
`concat_multi` give 54.2 cycles (-12%) with two extra branches on every call
in the core string routines and a lazier shrink heuristic - not worth it for a
path that is not hot in the product. The real ceiling is elsewhere: the same
loop written into one preallocated buffer with the digits formatted in place
costs 9.2 cycles per piece (7.7 with the buffer reused), so a compiler fusion
of `s := s + <literal> + IntToStr(x)` that formats into the tail of `s`
without the temporary string would be worth about 54 -> 25-30; the numbers
and programs come from a local exploratory stand outside this repository.

## Variant numeric operations

The remaining `1.238x` is distributed across temporary Variant copying,
operator dispatch, and finalization. A repair is worthwhile only if it removes
an entire temporary, copy, or manager call; saving a few instructions inside
the existing Variant ABI does not justify the risk.

## Win64 MM five-stage scenario

The bundled MM is 3–7% slower than the MM baseline only in `managed-five-hop`;
Linux is at `0.999x`. The scenario combines ownership/COW, small and medium
reallocation, and large realloc-copy. It must be decomposed into exact-volume
phases before changing the allocator.

## Unified decimal formatting

`FormatFloat`, `Format`, `FloatToStrF`, and `Str` still use different
digit-generation paths and can diverge at decimal half-boundaries and signed
zero. A local change to one formatter would only move the discrepancy. The
proper repair is one digits/exponent/sign/guard/sticky core, a separate
fixed-point path for `Currency`, and a complete Delphi/Win64/Linux matrix. The
observable boundary is described in [Known Deviations](KNOWN_ISSUES.md#floating-point-edge-cases).

## Debug location of captured locals

Generated code reads and writes a captured local through its closure field,
but DWARF can still describe the original stack slot after the capture remap.
Runtime behaviour is correct; the limitation affects inspecting that variable
in a debugger. A complete repair must emit the closure-based location before
and after closure creation, for nested and escaped captures, without merely
dropping the variable from debug information.

## A jump target of `TStringHelper.Split` stays in the last 12 bytes of a line (Linux)

With the code placement draft switched on (off by default), the internal
assembler keeps a label a jump reaches out of the last 12 bytes of a 64-byte
line when the block in front of it can carry the pad as prefixes
(doc/OPTIMIZER.md, "Code placement"). A pad that has changed eight times is
kept as it is, so that the layout passes end, and for one code shape of the
Linux RTL - `TStringHelper.Split` for `UnicodeString` and `WideString` - the
limit finds the pad in the state that leaves the label on byte 59 of its
line. The routine is cold, the gate of the stand chains carries the two as a
ceiling (`--assert R4,RT=2`) and separately requires the exact Unicode/Wide
`TStringHelper.Split` identities. A different violation cannot silently take
the place of either one, and a third violation fails the gate.

Three ways out were measured on both machines and none pays for itself: no
change limit for target pads (the RTL's biggest unit then needs 63 of the 64
allowed relaxation passes instead of 15), a kept pad that keeps its decision
without the block rule (oscillates to the pass limit on the placement
fixture), and eight more attempts for a pad kept in that one state (reaches
zero violations on both systems, but the acceptance gate flags Win64
`stringbuilder-replace` 1.109, `object-create-free-plain` 1.060,
`variant-vartostr-int` 1.061 and Linux `random-double` 1.060 at a geomean of
1.0002 and 0.9983). A repair has to make the pad's decision independent of
the code behind it, so that it converges without a limit.

## Deferred small-free backlog

Under sustained contention on a small size class, queued frees can retain
substantial pool storage even with few live application objects. The current
allocator has no idle/background drain. The Win64 empty-pool handoff preserves
this existing resource boundary; the single-block retention bound does not
include pending queues.

A bounded continuation through four retired pools processed more queued blocks
but still left 3955 of 4095 blocks after the last user free in a deterministic
stand. A long same-class contention case still accumulated over 700 MB with
that candidate. It was not integrated: it adds slow-free state and work without
defining when cleanup must finish or bounding retained memory. A further
repair must choose and measure a completion/backpressure policy, including its
allocation/free latency, contention and memory effects.

## Address hoisting in loops with writes

The current static-address hoist is restricted to read-only inner loops.
A general read/write candidate improved nonalias buffer updates by about
5.5–15.1% in a shared-buffer placement matrix, but an alias case lost 0.26%
with a stable A/A control. Removing an inner LEA changed SpanAlign padding:
the function grew from 110 to 201 bytes and executed additional outer padding.

A future profitability rule must account for the actual inner body, useful
memory consumers and executed padding. Preserve the reduction, one/two/three/
four-field matrices, alias/nonalias, histogram, pressure and short-trip controls
at real placements with identical data buffers. A fixed magic pad or a general
placement-policy switch based on one winning reduction is not a solution.
