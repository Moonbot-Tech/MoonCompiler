# Fragment

`Fragment` preserves a stateful allocation-history workload from a loaded
network application. It is an MM qualification workload, not a normal CPU
benchmark: its purpose is to compare live object bytes with memory retained by
allocator pools while realistic JSON, gzip, order-book, and cross-thread
allocation traffic is running.

The replay keeps both a whole workload and independent correctness checks. At
every epoch it verifies the expected live object count and byte total, checks
the first and last byte of every retained allocation, and finishes with a
stable application-level digest of the parsed market data. A result is useful
only when these semantic checks agree.

## Current status

The source and allocator scanner are preserved here, but the workload is not
registered in the release matrix yet. One piece is intentionally still
pending:

1. The two original event streams are about 237 MB each and are not committed.
   They need a compact deterministic replacement that retains the relevant
   allocation-size and lifetime distributions.
The public light snapshot reports already-maintained small/large counters and
all memory held from the OS without taking allocator locks or adding writes to
allocation paths. The explicit heavy snapshot pauses and walks the allocator
arenas to split active capacity into live small/medium blocks, reusable holes,
small-pool slack, unfed tails, standby pools, and the largest free block.
`Fragment` records the overlapping views side by side. They may differ briefly
under concurrent allocation: the heavy scan is a paused consistent snapshot,
while the light counters intentionally remain lock-free.

## Evidence from the full capture

Three Win64 runs before and after the allocator change produced the same
semantic endpoint: 3,692 symbols, signature `1304581783522889589`, and 891,744
live replay objects occupying 443,608,322 requested bytes. Each value below is
the median final sample from three runs because exact pool topology varies with
thread scheduling.

| Metric | Before compact backing arenas | Current MM | Change | Saved Delphi baseline |
|---|---:|---:|---:|---:|
| Active medium reserved | 550,502,400 bytes | 545,259,520 bytes | -0.95% | 474,474,848 bytes |
| Reusable medium holes | 18,346,480 bytes | 16,168,832 bytes | -11.87% | 23,405,320 bytes |
| Unfed arena tails | 43,153,840 bytes | 40,011,776 bytes | -7.28% | not separated |
| Standby/prefetch reserve | 112,721,920 bytes | 9,175,040 bytes | -91.86% | no comparable counter |
| Unused capacity including standby | 180,690,944 bytes | 71,852,496 bytes | -60.23% | not compared |
| Total memory held from the OS | 1,075,970,048 bytes | 965,869,568 bytes | -10.23% | no comparable counter |

The `compact`, `serial`, and `no-bursts` controls still left 9.48-12.10% unused
capacity in active MoonCompiler pools, versus 1.38-4.78% in the corresponding
saved Delphi controls. This rules out a single JSON document or only the
cross-thread interleaving as the entire explanation.

The main avoidable cost was not live objects or reusable holes. The original
`MOONSHARD` mapping used 127 backing medium owners; 86 of them retained a
1.25 MiB prefetch mapping in the final replay state. `MOONSHARD` has 44 real
small classes and 32 front-end shards. The current layout uses 45 backing
owners: the smallest count that keeps all 44 classes in one shard distinct. The
existing unused-slot skip after the base row followed by the coprime 45/64
stride also keeps one class distinct across all 32 shards. This sharply reduces
unused standby mappings.

Different `(shard, class)` pairs can share one backing owner in the compact
layout. The change is therefore a product-profile memory/parallelism trade-off,
not a globally collision-free remapping. A coordinated diagonal synthetic
workload can favor 127 owners, so a possible upstream compact profile remains a
separate research item; the release claim here is limited to the measured
`Fragment` result and the qualification workloads below.

The three current runs had the same application digest as the three preceding
runs. Median elapsed time was 16.02 seconds versus 16.20 seconds before the
change; this is treated as no slowdown, not as a claimed speedup. A focused
Linux comparison of the concurrent ownership/realloc workload also had the
same 2.41-second median. The current allocator additionally passed its physical
status check, hot-pool lifecycle, randomized concurrent chaos, 12 million
shadow-model fuzz operations, cross-thread ownership cases, and a 30-second
saturation run.

The complete workload ran about 1.39 times faster under MoonCompiler than the
saved Delphi executable, but that number includes compiler, RTL, JSON, gzip,
and MM effects. It is not an isolated allocator-speed claim.

## Provenance

The original stand is `MoonBot/src/Test/MemDiag/FragmentationBench`. The checked
in source keeps the production-shaped parser, compression routines, order-book
buffers, allocation scheduler, and replay format while replacing the large
MoonBot helper unit with the three JSON helpers actually used by this workload.
