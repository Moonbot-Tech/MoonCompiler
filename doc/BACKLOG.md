# Backlog

This list describes possible follow-up work and the contracts it must preserve.
Current observable compatibility boundaries are recorded in
[Known Deviations](KNOWN_ISSUES.md); delivered improvements are described in the
[second-release notes](RELEASE_NOTES.md).

## Exception capture and unwinding

Further work on real exception handling must retain the original exception
context and the diagnostic consumers that use it. Normal-path `try/finally`
cleanup is already optimized separately. Removing diagnostic capture changes
capability; it is not an interchangeable implementation of the same contract.
Applications can configure capture through [Moon.Diagnostics](DIAGNOSTICS.md).

## Dispatch and temporary ownership

More selective lowering of `case` statements remains possible. A useful rule
must account for selector distributions, branch cost and code size. Grouped
labels that share one action already have their own optimized path; a general
jump-table or tree policy needs evidence for distinct actions and `else` too.

Further elimination of managed temporaries must prove ownership across calls,
mutation, custom Variant operations and exceptions. Dynamic-array value
parameters keep reference ownership; their normal Win64 cleanup no longer needs
the previous small outlined wrapper. Do not substitute `const` semantics for
a value parameter to remove work.

For Variant arithmetic, a worthwhile transformation should remove an entire
temporary, copy or manager call while preserving custom dispatch and
finalization. Small instruction changes inside the existing ABI need stronger
evidence before adoption.

## Growing text and buffers

Possible improvements include formatting numeric pieces directly into an owned
string's tail and reducing temporary strings in concatenation. They must keep
evaluation order, formatting semantics, alias safety and exception behavior.
Builder and container growth changes also need to account for retained memory,
not just allocation counts. Existing reserved-capacity and reuse paths remain
the first choice when the application already knows its output size.

Allocator experiments must also cover combined ownership and copy-on-write,
small and medium growth, and large realloc-copy phases. Isolated allocation
loops alone do not establish a benefit for that combined workload.

## Unified decimal formatting

`FormatFloat`, `Format`, `FloatToStrF`, and `Str` use different digit-generation
paths. A coherent follow-up would share a digits/exponent/sign/guard/sticky core,
retain a separate fixed-point path for `Currency`, and qualify all APIs on
Delphi, Win64 and Linux. The observable boundary is described in
[Known Deviations](KNOWN_ISSUES.md#floating-point-edge-cases).

## Debug location of captured locals

Generated code accesses a captured local through its closure field, but DWARF
can still describe the original stack slot after capture remapping. A complete
repair must describe the closure-based location before and after closure
creation, including nested and escaped captures, without dropping the variable
from debug information. This concerns debugger inspection, not the generated
program's access to the value.

## Experimental code placement

The code-placement draft is off by default. Its bounded relaxation can leave
one internal jump target near a cache-line end in the Linux Unicode and wide
`TStringHelper.Split` forms. The qualification fixture names those exact forms;
it does not allow an arbitrary replacement or an additional violation.

A follow-up must make padding decisions converge without relying on a fortunate
layout or excessive relaxation passes. Increasing the retry limit alone was not
accepted as a general solution. See [Code placement](OPTIMIZER.md#code-placement).

## Deferred small-free backlog

The allocator has no idle or background drain for queued small frees. Under
sustained contention on one size class, pools can retain storage after the live
object population falls. The empty-pool handoff does not itself bound pending
queues. A further repair needs a defined completion or backpressure policy and
measurements of allocation/free latency, contention and retained memory. Merely
processing several more pools in one slow free does not establish such a bound.

## Address hoisting in loops with writes

The current static-address hoist is restricted to read-only inner loops. A
broader rule must account for aliasing, useful memory operations, register
pressure, short trips and executed padding. Its acceptance matrix must include
both aliasing and nonaliasing buffers at controlled placements. Removing one
address instruction does not by itself establish a profitable general rule.
