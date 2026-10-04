# Allocation failure and pending-reason regressions

Run against an explicit compiler, its matching complete RTL configuration, and
the exact bundled MM source. The runner copies the source into a new output
directory, replaces only its MM pin in a private config, and leaves the supplied
compiler/config/source untouched. It refuses an existing output directory.

```text
python qualification/memory-manager/mm_failure_gate.py --compiler /path/to/ppcx64 --config /path/to/moon-base.cfg --mm runtime/mm/mormot.core.fpcx64mm.pas --out /new/directory --group all
```

Groups:

- `oom`: uninstrumented raw/managed contract, then OS-boundary failures on
  product and NOMREMAP. Linux also checks NOSFRAME and RBX/R14 across actual
  exception propagation. Failed realloc must preserve pointer, data, capacity
  and large-list membership; failed commit must release its new reservation.
- `ownership` (Windows): a second native thread attempts the medium lock at
  the nil-return boundary between the refill helper and its caller. It must
  fail to acquire: only the caller unlocks a returning allocation failure.
  The helper unlocks only before a nonreturning OOM raise.
- `handoff` (Windows): force one deferred free, pause a different free at its
  pending continuation, then consume the queue before resuming it. Both a
  hot single-block pool and a still-live multi-member pool are checked. A
  pending reason must not be reclassified as an empty-pool handoff.
- `all`: all groups supported on the current platform.

Fault/observer/barrier code exists solely in private test copies. There are no
fault controls or per-operation counters in the shipped allocator. These
instrumented binaries are semantic oracles, not performance measurements.
The runner records commands, source/executable hashes and every fresh-process
outcome in `results.json`; build logs remain beside each fixture. A timeout,
unexpected exception or missing success marker fails the gate.

The ordinary profile matrix and linked layout checks remain separate in
`mm_profile_matrix.py` and `mm_layout_gate.py`. These focused gates do not
claim full product qualification or a bound on deferred-free backlog. An idle
allocator does not automatically drain that existing queue; memory may remain
mapped until later allocator work processes it.
