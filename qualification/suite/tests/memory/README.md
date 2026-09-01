# Bundled Memory Manager Qualification

These programs qualify the memory manager shipped in
`runtime/mm/mormot.core.fpcx64mm.pas`. The release verdict belongs to the
runner, not to an individually compiled `.dpr`: the runner pins the compiler,
configuration, and MM source; selects the product or standalone profile; and
checks the required positive and negative outcomes.

## Run the matrix

Build the current toolchain, then run the Linux matrix from
`qualification/suite` with a new output directory:

```bash
scripts/mm/qualify_current_mm.sh ../../.qualification/mm-full \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg \
  ../../runtime/mm/mormot.core.fpcx64mm.pas
```

The output root must not already exist. Success creates a hashed evidence tree
and prints `CURRENT_MM_QUALIFICATION_PASS`.

The complementary product-mORMot gate uses the same pinned MM in the complete
2.3.8832 test program:

```bash
scripts/mm/run_mormot_mm_gate.sh ../vendor/mormot-product \
  ../../runtime/mm/mormot.core.fpcx64mm.pas ../../.qualification/mormot-mm \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg
```

It executes all 18 classes selected by the runner, requires a completed leak
census for every class, and rejects any reported small, medium, or large block
leak. The only accepted failed-assertion count is the runner's exact external
DNS environment deviation. A separately recognized Core Base debugging exit
must still report zero failed assertions.

## What the main runner proves

| Layer | Programs and oracle |
|---|---|
| Deferred finalization | `memory_small_pool_last_free_finalize`, `memory_small_last_free_finalize`, and `memory_medium_last_free_finalize` each pass 100 isolated processes with no failed run. |
| Product boundaries | `memory_large_boundary` checks allocation capacity and first/last-byte access around the large-block transitions. |
| Hot small-pool reuse | `memory_hot_small_pool` proves that a larger small-block class releases cold empty pools, activates reuse only after repeated churn, and then returns the retained block without changing live-block accounting. |
| Deterministic breadth | `memory_mega full` checks zero-size and realloc contracts, size classes, every configured realloc transition, pool lifecycle, a shadow-model fuzz pass, cross-thread ownership transfer, and saturation. |
| Concurrent composition | `memory_massive quick` runs a five-thread ownership pipeline, remote realloc/free, forced `GetMem` contention, both deferred-free lists, and managed-value COW/refcount/unwind. It runs once normally and once with diagnostics enabled. |
| Randomized composition | `memory_chaos all` mixes raw blocks, RTL-managed values, cross-thread release, realloc, and valid exit-time finalization in release and diagnostic profiles. |
| Fail-closed diagnostics | `memory_mm_diagnostic` proves the healthy path and leak reporting, then requires exit code 218 plus a first-violation record for double free, bad size, foreign pointer, damaged owner/link/queues, and a worker-thread double free. |

Phase timings emitted by `memory_massive` are provenance, not a performance
verdict. Correctness depends on the structural checks, exact completion
markers, exit codes, and leak census.

## Other sources in this directory

The release runner intentionally does not invoke `medium_contention`,
`medium_owner_stress`, `memory_small_arena_collision`,
`memory_footprint_10x10m`, `memfuzz`, `memspeed`, `mm_crossmachine`, or
`MemProf`. They are focused experiments, profilers, or comparison workloads;
their output is not a release qualification result. The dated
`memory_mega_historical_20260805` source is retained as a historical input and
is not the current Mega implementation.

Benchmark methodology and the rules for comparing machines are documented in
[Measuring the bundled memory manager](../../docs/MEMORY_BENCHMARK.md). The
release order and the distinction between standalone and product probes are in
[MoonCompiler Test System](../../docs/TESTS.md#memory-manager).
