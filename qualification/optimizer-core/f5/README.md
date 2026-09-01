# F5 x86-64 address-reuse gate

`run_f5_gate.py` compares `-O3 -OoNOADDRESSGVN` with explicit
`-O3 -OoADDRESSGVN`.  Both binaries must produce the same deterministic
digest.  The assembly check then proves that repeated `Data[I]` and `Data[J]`
accesses reuse both the scaled element offset and a RIP-relative global-array
base inside one extended basic block.  The same gate separately covers the
actual Heartbeat shape: an open-array parameter whose signed 32-bit indices
would otherwise be extended and scaled for every field access.  Integer and
floating-point butterflies cover both a direct extension/shift chain and the
shared-copy topology emitted under real register pressure.  Dead leaf copies
are removed before their common sign-extension root, so one root shared by
several address groups cannot survive merely because cleanup visited the
groups in an unlucky order.  A two-field record read proves that the profitable
two-use form removes the duplicate extension and scale; companion cases prove
that an index redefinition and both direct and indirect calls remain hard
barriers.  Because a two-use
group has only marginal benefit, another memory operation in the reuse interval
is also a profitability barrier; groups with at least three uses remain
unrestricted by that local rule.  A mixed floating-point record case contains
an explicit unrelated memory write, so the barrier remains present even when
another optimization changes floating-point live ranges and removes an
incidental stack spill.

On Linux the runner resolves `libgcc_s` through the host GCC driver, so a clean
invocation needs no machine-specific `-Fl` argument. Additional compiler
options remain available through repeated `--compiler-option` arguments.
The RIP-base assertion is topology-conditional: Linux may encode the static
symbol directly and legitimately report `bases 0->0`; index-reuse assertions
remain mandatory.

The pass deliberately does not cache loaded values, move memory operations or
cross calls, branches or source-index definitions.  It only removes duplicate,
private address-materialization chains after proving their exact reaching
definition and dead flag result.
