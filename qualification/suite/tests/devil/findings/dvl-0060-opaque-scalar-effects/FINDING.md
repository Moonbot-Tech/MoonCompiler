# dvl-0060 — O3 preserved a scalar across an opaque memory change

## Status: fixed

The finding was closed by the causal fix `858f10c27`: the two loop passes no
longer trust only direct node-DFA definitions where a value can change through
memory.

## What happened

There were two independent wrong-code forms:

- strength reduction treated a global/static scalar as invariant even though an
  ordinary or procedure-variable call changed it within the loop; exact
  arithmetic should have produced `17`, but O3 continued to use the old value;
- constant propagation carried the initial constant of a captured local across
  the loop even though a nested routine changed the variable in the parent
  frame between two uses; the result became `441` instead of `651`.

Debug/O1/O2 and Delphi produced the correct results. The divergence appeared
only in O3, so an ordinary build check did not detect it.

## Fix

Invariance is now proven from the actual storage class:

- a local and value parameter must be registerable, not captured,
  not address-taken/volatile, and not defined in the loop body;
- static/global is checked against the shared effect model of the final tree:
  it sees call/assembler/pointer aliasing and a direct write introduced after
  AUTOINLINE;
- constant propagation carries a scalar across a loop only for a compiler temp
  or genuinely registerable storage.

The safe immutable local control remains optimizable: the fix does not disable
O3, strength reduction, or constant propagation as a whole.

## Permanent evidence

- `tests/test/cg/tloopopaqueeffects1.pp` — call, procvar, nested parent frame,
  pointer escape, mutable index, and a positive local control;
- `tests/test/cg/tloopfutureinvariants1.pp` — zero-trip trap, managed result,
  inline mutation, for-step latch, and adjacent boundaries for future
  optimizations;
- Devil optimizer-effects matrix — combinations of mutation routes, side-effect
  positions, loop forms, and integer ABIs.

The exact results and causal history are retained in `COMPILER_FIXES.md` and
`FINDINGS_JOURNAL.md`.

Later, the full Devil run found dvl-0062 — the same error after cross-unit
AUTOINLINE, when the call had already disappeared from the tree. The corrective
change did not expand the local prohibition list: the former scan was removed,
and the legality check now uses the shared `opteffect` model of the final tree.
