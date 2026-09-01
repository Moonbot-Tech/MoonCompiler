# dvl-0070 — `TArray.BinarySearch` returned the middle of an equal run

Status: **fixed**.

## Observation

For `[0,0,1,1,1,2,3,3]`, DCC64 36.0 returns indices `0` and `2` for keys `0`
and `1`. MoonCompiler returned `1` and `3`; for five equal elements, it returned
`2` instead of `0`. This reproduced consistently on Win64 Debug/O1/O2/O3 and
Linux O2. The exact independent repro is [`probe/bsearch2.dpr`](probe/bsearch2.dpr).

This is a live contract in `MoonBot/MarketsU.pas`: after searching for a
`TTrade`, the code walks the run of trades with the same time from `FoundIndex`.
A different index changes the splice boundary and the set of prints entering the
history.

## First violated invariant

DCC RTL implements a lower-bound search: upon equality, it records that a match
was found but continues narrowing the right boundary to the left. Our
`TArrayHelper<T>` already had the same structure and calculated `imax := imid`,
but immediately followed it with `Exit(True)`. It therefore returned an
incidental midpoint instead of the first equal item.

The fix removes only the premature exit in both helper overloads:
Delphi-compatible `AFoundIndex` and the extended `TBinarySearchResult`. Miss,
insertion point, zero-count, range validation, and the number of comparisons
outside the equal run remain unchanged.

[`probe/bsearch.dpr`](probe/bsearch.dpr) retains the original product form with
a fuzzy comparer as provenance. The comparator itself is non-transitive and
therefore cannot be a general binary-search oracle; ordinary integer duplicates,
ranged search, and a run of identical values prove the fix.

Permanent checks are in `RTL-test/semantic/array_list_span_semantic.dpr`, the
product smoke test, and Omni's broad collection layer. Extended Chimera executes
the exact tape join with repeated timestamps.

## Consequence discovered for MoonBot

The correct lower bound exposed a separate defect in a live caller. In
`MarketsU.JoinHOrders`, advancing through the found run is guarded by
`FoundIndex > 0`. If a matching run starts at element zero, Delphi correctly
returns `0`, the condition is not satisfied, and already saved trades are added
again. Moon's former midpoint result happened to mask this branch by returning a
positive index more often.

The full Chimera is therefore intentionally red on `splice-drop` at present:
its oracle must not be weakened and the incorrect RTL semantics must not be
restored. The compiler/RTL fix is proven independently; the caller must advance
the run for every `Found`, including at index `0`, after which the exact product
composition must become green.
