# Measuring the bundled memory manager

MM correctness and speed are checked separately. Any benchmark counts only
after the complete `qualify_current_mm.sh`; a fast incorrect allocator is not a
candidate.

## Why one workload is insufficient

MoonBot mostly allocates short-lived strings and small buffers, but it also
grows dynamic arrays and strings through medium sizes. Therefore, the suite
measures several independent profiles:

- small get/free operations within one size class and across different classes;
- many operations falling in one size class;
- mixed small/medium;
- user-medium around 17 KiB and 100 KiB;
- cross-thread allocate/realloc/free;
- five-hop transfer of sole ownership across different threads, including
  managed COW/refcount and raw realloc up to 2 MiB;
- forced GetMem contention in every MoonShard arena and both deferred-free
  lists;
- a MoonBot-like size distribution from a saved memory profile.

A single-thread process before creating its first thread has
`IsMultiThread=false` and bypasses locks. Production MoonBot is always
multithreaded, so mandatory single-thread numbers are taken after activating
`IsMultiThread=true`; otherwise both sides look artificially faster. For our
x64mm, the measured cost of the locked small path was about 12.8 ns/op versus
about 6.1 ns/op for Delphi FastMM4, but the bundled MM scaled substantially
better and overtook FastMM4 at approximately two threads.

## Comparing different machines

Raw Windows/Delphi and Linux/FPC nanoseconds cannot be divided directly. Each
binary runs the same independent calibrators:

- `CAL-INT` — pure integer/branch work without allocation;
- `CAL-BW` — the same memory-copy kernel;
- workload digest — proof of the same volume and result of work.

Small profiles are normalized by `CAL-INT`, large memory-bound profiles by
`CAL-BW`. The report always retains raw time, calibration, digest, compiler,
MM source hash, flags, CPU/OS, and several samples. Only matching profiles with
a green digest can be compared.

## What sharding proved

Before user-medium sharding, one `MediumBlockInfo` serialized the entire mixed
workload. The control experiment changed only one size: at 100,500 bytes four
threads took about 4.7 s, while at 17,000 bytes, which already falls on the
sharded small path, the same test took about 0.30 s. After layer B, the measured
Linux result was:

| Profile, 4 threads | Before medium sharding | After |
|---|---:|---:|
| first medium byte, 17,497 | 429.0 ns/op | 21.0 ns/op |
| medium block, 100,500 | 437.8 ns/op | 25.5 ns/op |
| mixed workload | 4 505 ms | 200 ms |
| small-only control | 300 ms | 300 ms |

The small control did not change, so the gain is localized specifically to the
eliminated shared medium lock rather than obtained by changing the volume of
work.

## Running

Sources are in `tests/memory`; the overall procedure is in [TESTS.md](TESTS.md).
A retainable result uses only the exact compiler/MM pins and a new output
directory. Run the benchmark on an idle host after correctness, without a
parallel mORMot/mega/other benchmark. Repeat a noisy sample rather than claim
it as an improvement or regression.

## Limitation of conclusions

Sharding fixes contention and does not promise a win for every individual
get/free. FastMM4 remains cheaper on the rare single-thread locked hot path.
Therefore, further optimizations are permissible only when all ownership,
finalization, and diagnostic gates are retained; disabling ABA protection or
correctness checks for a number is forbidden.
