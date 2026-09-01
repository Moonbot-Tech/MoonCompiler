# Medium-arena verification

`medium_single.dpr` is a minimal smoke test of ordinary allocation.

`medium_arenas.dpr` checks more than successful `GetMem`, `ReallocMem`, and
`FreeMem`. It requires the medium-arena profile to be active, creates medium
blocks from eight threads, proves the presence of several pool owners, and
passes blocks to other threads for `ReallocMem` and `FreeMem`. This executes
the owner-recovery path through the aligned pool header on Linux x86-64 and
Win64.

The test must run at least in O2 and O3. A diagnostic build with
`FPCX64MM_DIAGNOSTIC` also checks the internal lists and counters after the
cross-thread workload.

The full instrumentation is checked by
`../suite/tests/memory/memory_mm_diagnostic.dpr` and the
`../suite/scripts/mm/qualify_current_mm.sh` runner. The positive mode checks
the registry, `$A5/$DE` fills, realloc, tagged context, and explicit heap
traversal. Negative modes deliberately create a double free, a foreign pointer,
oversized `FreeMem(P, Size)`, corruption of the small owner, large links, and
deferred small/medium lists, including a worker-thread race. Each must print
exactly the first diagnostic error and exit with code 218.

This is an allocation registry and validation of allocator structures, not a
red-zone or guard-page mode for every block. The full contract, cost, and
boundaries are described in the “Diagnostic instrumentation” section of
`../../doc/MEMORY_MANAGER.md`.

`profile_contract.ps1` and `profile_contract.sh` check the product contract:
the precisely pinned MM must compile with `FPCMM_BOOSTER` and
`FPCMM_MOONSHARD`, and a missing profile must stop compilation.
