# Stable dynamic-array loop bases

`run_loop_base_gate.py` proves the post-LICM dynamic-array base-reuse rule on
native x86-64.  It compiles `tests/test/cg/tloopdynarraybase1.pp` at `-O-`,
`-O2`, and three `-O3` configurations: `-OoNOSTRENGTH`, explicit
`-OoSTRENGTH`, and the product default.

All five executables must return the same fixed semantic result.  Assembly
checks then require one fewer stack descriptor load in read-only scalar,
record, managed-element, pointer-element, local-array, and value-parameter
loops.  The original index arithmetic remains in the loop; this phase caches
only the descriptor value and runs after LICM has finalized invariant index
expressions.
An additional three-array loop must retire exactly two descriptor loads,
freezing the per-loop register-pressure cap independently of which tied bases
are selected.

The negative matrix keeps the relevant descriptor structure unchanged for a
single use, range/overflow-checked access, an element-writing loop, direct
descriptor reassignment, an opaque call, a by-reference call, uses split
between nested loop owners, a `constref` parameter, an ordinary global, and a
threadvar descriptor.  These cases freeze both the public memory contract and
the deliberately conservative read-only profitability boundary.  Product
`-O3` must match explicit enablement; the independent `-OoNOSTRENGTH` build
proves that the structural change belongs to loop strength optimization rather
than frontend lowering or the assembler.
