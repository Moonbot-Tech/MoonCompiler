# MoonCompiler Memory Manager

MoonCompiler uses one product allocator:
`runtime/mm/mormot.core.fpcx64mm.pas`. It is based on
[mORMot `fpcx64mm`](https://github.com/synopse/mORMot2/blob/master/src/core/mormot.core.fpcx64mm.pas),
but ships with the toolchain and is built in one precisely defined
configuration for Win64 and Linux x86-64.

The rest of mORMot is not embedded in the compiler. A project may use any
compatible library version; the process allocator remains part of the
MoonCompiler profile.

## Why `fpcx64mm`

Arnaud Bouchez designed `fpcx64mm` for multithreaded x86-64 services. It is not
a `malloc` wrapper: its main paths are written in x86-64 assembler and request
memory directly from the OS.

Key allocator properties:

- tiny/small allocations use a size-class table and pools;
- multiple arenas with thread-ID affinity reduce contention and preserve data
  locality;
- when a small/medium lock is busy, a free can enter a deferred-free list
  instead of blocking the calling thread in an OS wait;
- medium blocks use bitmap bins, a pre-reserved chunk, and four independent
  arenas in `FPCMM_BOOSTER`;
- large blocks are mapped directly through `mmap`/`VirtualAlloc`, and Linux can
  grow them through `mremap` without mandatory copying;
- hot paths use SSE2/ERMS and avoid a shared libc allocator;
- built-in statistics report small/medium/large memory volumes and actual
  OS sleeps caused by contention.

### Deferred frees and retained memory

When a small-class lock is busy, FreeMem can queue the block. The program no
longer owns it, but its pool cannot release that storage until pending frees
are processed. GetMem checks the pending queue before acquiring a class lock;
if the queue lock is busy it can continue with another block or pool. Slow
FreeMem currently processes pending blocks only through the first pool
retirement. There is no background or idle-time drain.

Consequently, a small fixed number of simultaneously live application objects
does not bound queued storage under sustained class contention. Memory can
remain held after workers become idle, then fall as later allocation/free
activity drains the queues. This is separate from the bounded single-block
retention policy and from the backing medium-owner mapping. It is also present
before the Win64 empty-pool handoff; that handoff does not claim to repair it.
A partial drain budget was tested and did not establish a memory bound or
idle cleanup. The remaining work is recorded in [Backlog](BACKLOG.md#deferred-small-free-backlog).

### Arnaud's comparison with libc

In August 2026, Arnaud repeated a comparison of current `fpcx64mm` and glibc
on Linux x86-64: 512 connections, 10 threads, and the same endpoints from
mORMot's official TechEmpower example. Results in requests per second:

| Workload | `FPCMM_SERVER` | `FPCMM_BOOSTER` | glibc |
|---|---:|---:|---:|
| `/plaintext` | ~1.23 M | 1.234 M | 1.277 M |
| `/json` | ~1.16 M | 1.191 M | 1.217 M |
| `/rawfortunes` | ~1.07 M | 1.086 M | 1.107 M |
| `/fortunes`, ORM + Mustache | 103–105 K | 117.2 K | 117.2 K |

glibc was 3–5% faster on the light paths. `FPCMM_BOOSTER` matched it on
allocation-heavy `/fortunes`. Resident memory was nearly identical
(`14–15 MiB`), while virtual address space was about `82 MiB` for BOOSTER
versus `730 MiB` for glibc. Across 63–67 million small allocations, both
`fpcx64mm` profiles entered OS sleep only 1–3 times. Full conditions and raw
figures: [The Point about current mormot.core.fpcx64mm.pas unit](https://synopse.info/forum/viewtopic.php?id=7597).

In the 30 August 2026 Pulse snapshot, the same MoonCompiler was built with
the bundled MM and with the standard FPC MM. On the allocator group, the
bundled MM achieved a `0.6069×` geometric mean: it completed the same work
`1.65×` faster on average. The method and the full snapshot are in the
[release evidence](../qualification/performance/evidence/release-final-20260830/EVIDENCE.md).

The second release's selected allocator and runtime measurements are recorded
separately in the [release notes](RELEASE_NOTES.md) and their
[measurement record](evidence/release2/README.md). The dated August snapshot
does not describe the current compiler's complete performance.

The product profile therefore uses `FPCMM_BOOSTER`, not the standard FPC MM or
libc.

## Allocation failure contract

With the normal `ReturnNilIfGrowHeapFails = False`, an allocation that cannot
be satisfied reports FPC runtime error 203 (`EOutOfMemory` when SysUtils is
active). With `ReturnNilIfGrowHeapFails = True`, it returns nil. A failed
`ReallocMem(P, Size)` preserves P, its previous data and capacity, and its
allocator-list membership; the old block remains valid for a later retry or
`FreeMem`. Failed reserve/commit growth also releases any partial Windows
reservation before falling back or reporting failure. Requests whose header
and rounding would overflow fail before requesting storage.

The usual tiny/small leaf GetMem and FreeMem paths gain no error check or
wrapper. Error handling runs after allocator locks are released. Successful
large allocations do check size overflow; successful large remaps check the
result before publishing it. Windows medium-pool refill uses a small checked
helper to keep ordinary medium-bin instructions at their previous positions.
A returning refill, including nil-mode, leaves the sole unlock to its caller;
the helper releases the lock only before a nonreturning OOM raise. The
[targeted failure gates](../qualification/memory-manager/FAILURE_GATES.md)
exercise OS rollback, unwind registers and lock ownership in private test copies.
Linux manual GetMem, AllocMem and ReallocMem frames carry DWARF unwind rules;
metadata is not executed on successful calls.

## Allocator extensions

This section was checked against `mORMot2/master` `a333a689` from
2 September 2026. Fixes already accepted upstream are not listed here as
MoonCompiler changes.

### Sharding all small classes

Upstream `FPCMM_BOOSTER` distributes tiny blocks up to 256 bytes and
user-medium blocks across arenas. `FPCMM_MOONSHARD` extends sharding to all 44
logical small classes up to 2608 bytes:

- 32 arenas are selected by a thread-ID hash;
- the original size-rounding table remains intact—there are no new classes or
  different data fragmentation;
- each arena occupies exactly 64 cache-line entries, or 4096 bytes;
- 20 tail entries are not selected by size lookup. This costs about 40 KiB of
  static metadata for all arenas, while arena selection remains shift/add with
  no division or extra hot-path branch;
- the first two tail entries of the primary arena retain a cold same-size
  fallback after the arenas are exhausted;
- larger small classes retain an empty pool only after repeated single-block
  churn. Draining a later multi-block workload clears that history and releases
  the pool; the reset runs on the cold pool-release path, not on every `GetMem`;
- Linux uses a shortened fast-get path; on both Win64 and Linux, the profile is
  chosen at compile time, with no runtime dispatch between implementations.

Single-block retention is per `(arena, class)` slot, including the larger
small classes. A conservative structural bound is one pool for each of
the 44 classes in 32 arenas plus the two primary fallback slots: at
`MaximumSmallBlockPoolSize` this is less than 91.70 MiB. This is an upper
bound on this specific policy, not measured usage or a bound on total
allocator memory; medium standby mappings and deferred-free queues are
separate. A drained pool that served multiple simultaneous blocks is
released to its medium owner,
so that storage becomes available to other sizes instead of remaining
reserved for its previous small class.

The original `FPCMM_MOONSHARD` mapping inherited 127 backing medium owners from
the 64-slot arena geometry. Every initialized owner may retain a 1.25 MiB
prefetch mapping; the final `Fragment` state had 86 such standby mappings, or
112,721,920 bytes. The product profile now uses 45 backing owners. This is the
smallest count that preserves both direct isolation properties: all 44
addressable classes in one row remain distinct, and the existing unused-slot
skip after the base row followed by the coprime 45/64 stride assigns one class
in all 32 shards to distinct owners.

The compact mapping can make different `(shard, class)` pairs share a backing
owner. It is therefore a deliberate memory/parallelism trade-off selected for
the measured product workload, not a claim of universal collision freedom. A
coordinated diagonal synthetic workload can favor the 127-owner layout; the
comparison remains an internal upstream-research item rather than part of the
release contract.

On the production-shaped `Fragment` replay, this reduced standby memory by
91.86%, total unused allocator capacity by 60.23%, and total memory held from
the OS by 110,100,480 bytes (10.23%). The semantic digest and requested live
bytes were unchanged. Interleaved Linux runs of the concurrent ownership and
realloc workload retained the same 2.41-second median; targeted chaos, fuzz,
cross-thread ownership, hot-pool lifecycle, and saturation checks also passed.
The measurements and exact counter definitions are in the
[`Fragment` report](../qualification/suite/tests/memory/fragment/README.md).

### Product profile and allocator installation

The compiler inserts the MM as the first unit before the user's `uses`, and the
toolchain's `moon-base.cfg` pins the exact unit-name-to-source mapping and
required defines (the source is the copy the toolchain carries in its own
`runtime/mm`, named relative to the compiler's directory):

```text
--pinned-unit=mormot.core.fpcx64mm=$FPCBINDIR/../../runtime/mm/mormot.core.fpcx64mm.pas
-dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dNOPATCHRTL
```

The pinned unit is resolved before ordinary PPU/packages/`-Fu`; `uses ... in`
cannot replace it with another file. The unit itself aborts compilation when
the product profile is incomplete or `FPCMM_DISABLE`/`FPCMM_STANDALONE` would
prevent allocator installation.

`NOPATCHRTL` is also a symbol the compiler defines by itself on x86-64
(options.pas, next to `FPC`): mORMot's `RedirectRtl` copies its replacement
string routines over the RTL's by lengths measured on stock FPC and fixes a
`jmp fpc_freemem` it searches for in the copy; the MoonCompiler RTL has its
own routines (other lengths, other tails), so a stock mORMot compiled
without the symbol crashes on the first string free. Whoever takes this
compiler with their own mORMot copy is safe without knowing about the
switch; the profile line above is kept for clarity, and `-uNOPATCHRTL` on
the command line switches the patch back on for measurements against it
(`config_contract_gate.py` checks both directions).

On Win64, `fpwinmonitor` is added automatically after the MM; on Linux,
`cthreads`, `cwstring`, and `fpmonitor` are added. Users do not need to carry
this runtime prefix between projects. The explicit opt-out for vanilla-runtime
experiments is `-dMOONCOMPILER_VANILLA_RUNTIME`. Valgrind and ASan add `cmem`
before all other units instead of the product MM.

### Correct process shutdown

The product MM does not free arenas during ordinary unit finalization. At that
point, earlier runtime units may still finalize strings, interfaces, and other
managed values allocated by the same allocator.

Moon RTL provides a post-finalization callback. Once every unit has finished,
the MM performs a leak census, restores the previous manager, and frees the
arenas. This preserves correct lifetime, a working leak report, and complete
process cleanup. Early teardown remains available only for specialized
diagnostics through `FPCMM_UNINSTALL_AT_EXIT`.

### Memory telemetry

`CurrentHeapStatus` is the inexpensive snapshot intended for periodic
monitoring. It reads counters the allocator already maintains and adds no
writes, branches, locks, or atomics to `GetMem`, `FreeMem`, or `ReallocMem`.
Besides the existing live small-block and active medium/large mapping totals,
it reports:

- `MediumStandbyBytes` — medium-pool mappings retained by prefetch;
- `OsHeldBytes` — active medium mappings + standby medium mappings + live
  large mappings, i.e. memory currently held from the OS by the allocator.

The cheap snapshot deliberately does not claim an exact live-medium byte
count. The allocator does not store the caller's original requested size, and
maintaining a rounded live-medium counter on every allocation/free added
7-8% to an isolated 17 KiB allocation cycle. The accepted implementation keeps
the generated hot paths byte-identical to the version without telemetry.

`CurrentHeapFragmentationStatus` is the explicit detailed query. It pauses the
existing allocator arenas and walks their physical block chains, returning
live small/medium/large capacity, reusable medium holes, deferred frees,
small-pool capacity and completely empty small pools, unfed arena tails,
standby pools, OS-held bytes, and the largest reusable medium block. It is
intended for diagnostics and controlled sampling, not for a request hot path.

Live values are allocator capacity rounded to size classes and include block
headers; they are not the sum of the original requested byte counts. A caller
that tracks requested bytes can compare that total with the scan directly, as
the `Fragment` workload does.

### Extended diagnostics

`FPCX64MM_DIAGNOSTIC` replaces every entry point of the installed
`TMemoryManager` with checking wrappers and maintains a separate registry of
live allocations. Each entry records the address, requested and actual size,
small/medium/large kind, owner/header, sequence number, and an optional short
context.

The mode detects:

- a double `FreeMem`, a foreign pointer, or an interior pointer;
- an incorrect size in `FreeMem(P, Size)`;
- inconsistent kind/header/owner data and small-block geometry;
- corruption, a cycle, or invalid membership in deferred small/medium lists;
- large-block list corruption;
- corruption of the diagnostic registry itself.

New memory is filled with `$A5` and the payload area of freed memory with `$DE`.
`Fpcx64mmDebugSetContext()` labels subsequent allocations with a phase name, and
`Fpcx64mmDebugVerifyHeap()` checks the entire heap at a chosen quiescent point.
The first fault is printed as `FPCX64MM_DIAGNOSTIC first-violation ...`, after
which the process exits directly through the OS with code 218.

The standard registry supports 131072 concurrent allocations.
`FPCX64MM_DIAGNOSTIC_LARGE` raises it to 4194304 entries and needs about
328 MiB of metadata; this is a qualification mode, not a production benchmark.

This is not a full equivalent of FastMM FullDebugMode: blocks have no red zones
or guard pages. A write beyond the requested size but within rounded capacity
is not guaranteed to be detected immediately. Corrupt allocator metadata,
owners, and list links are caught by the next affected operation or an explicit
`Fpcx64mmDebugVerifyHeap()`.

One define enables diagnostics separately without changing the Debug or
Release semantics; the compiled units go to their own `*-diagnostic`
directory, so a diagnostic build never mixes with a normal one:

```bash
toolchain/bin/fpc -dFPCX64MM_DIAGNOSTIC Project.dpr
```

```powershell
toolchain\bin\x86_64-win64\fpc.exe -dFPCX64MM_DIAGNOSTIC Project.dpr
```

### Small-block live accounting

`CurrentHeapStatus.SmallBlocks` does not count blocks already accepted by
`FreeMem` that are still awaiting recycling in a deferred list. The snapshot remains
lock-free and clamps its result to zero during concurrent counter changes, so
monitoring does not receive a falsely elevated count of live objects.

### ABI on supported operating systems

Linux `_FreeMem` uses caller-saved `RSI` and does not spend `push/pop` preserving
it. Win64's full `_FreeMemSlow` path retains `RBX`: both `RSI` and `RBX` are nonvolatile there, and moving
state into `RSI` degraded Moon-generated loops where the caller keeps its counter
in `ESI`. The choice is made by conditional compilation; there is no runtime
branch on the hot path.

### Hand-laid hot paths

`_GetMem`, `_FreeMem` and `_ReallocMem` follow
[ASM_LAYOUT_RULES.md](ASM_LAYOUT_RULES.md). On Win64, the normal tiny/small
paths are **leaf front-ends**. Calls, medium/large operations, pool retirement
and exceptional reallocations enter separate ABI-correct framed `*Slow`
routines. The leaf exits use no nonvolatile register saves and keep the Win64
shadow-space and unwind obligations in the framed callees. Linux retains the
separate monolithic System V layout and the `FPCMM_MS_LINUX_FASTGET` path.

A Win64 leaf that has proved a small pool is empty and must be released
hands its still-held class lock and decoded pool to a framed cold helper.
This avoids unlocking, decoding the same header again and acquiring the
same lock in `_FreeMemSlow`. The helper retires the same pool through
`FreeMediumBlock`; it does not retain additional pools or change medium
free-list selection. A pending cross-thread free follows the existing
unlock/slow path: an empty pending queue is not proof that a pool is empty.
Keeping the lock can change concurrent reuse: a competing allocation
cannot refill that pool in the former unlock/relock window. It may use
another pool, so unchanged retention rules do not guarantee identical
addresses, contention cost or peak memory under the same request stream.

In Win64 `_FreeMem`, an uncontended small-block release executes inline. A
single-block sequential pool (`BlocksInUse = 1`, `FirstFreeBlock = nil`) stays
on this path if the class is at most 256 bytes or has a proven reuse score;
otherwise the cold retirement path handles it. This preserves the
intent of the earlier 256-byte direct exit but is **not** the same binary
layout as the old monolithic routine.

The leaf/framed split gives Win64 two copies of the allocator paths, and the
framed `_ReallocMemSlow` uses the second one: it calls `_GetMemSlow` and
`_FreeMemSlow`, not the leaf wrappers. A block that is being reallocated sits
between the program's own `GetMem` and `FreeMem`, so the leaf copy would serve
two live blocks of two size classes in turn, and one set of instructions doing
that is measurably dearer on Zen 3 than two sets doing one block each: two live
blocks through one copy cost 70 cycles, through two copies 49, which is twice
the 24 of a single block (the likely cause is predictor state kept per
instruction address that flips between the two blocks; it was not measured
with performance counters).
`ReallocMem(64 -> 128)` went from 100 cycles to 80; the monolithic release
allocator, one copy for everything, took 90. `_ReallocMemSlow` is entered only
from the leaf `_ReallocMem` and starts from what the leaf has read (`P^` in
`r8`, the block header in `r9`) instead of loading both again.

When a medium reallocation cannot stay in place, the leaf front-end passes the
decoded block to the framed routine. That routine supplies the Win64 shadow
space and unwind metadata required by its helper calls. A request that fits
the existing block returns directly through the leaf path; this is common in
string and array growth. The copying changes below also improve the measured
chains that require a new allocation.

### Zeroing and copying

`_AllocMem` (a fresh dynamic array goes through it: `SetLength` of an empty
array is `AllocMem`) zeroes the block, and a `ReallocMem` that cannot stay in
place copies it. Upstream does both with a 16-byte SSE2 loop below 256 bytes and
with `rep stosd` / `rep movsb` from 256 bytes on (`FPCMM_ERMS`, part of the
product profile). The `rep` instructions have a start-up cost that upstream
assumed to be small. Measured, cycles for one block (`qualification/memory-manager/zero_fill_map.dpr`,
`copy_map.dpr`; best..worst of the four 16-byte alignments of the block):

| Bytes | Zen 3 `rep stosd` | Cascade Lake `rep stosd` | SSE2, two 16-byte stores per turn (both) |
|---:|---:|---:|---:|
| 256 | 84..85 | 23..34 | 16 |
| 512 | 75..97 | 37..43 | 32 |
| 768 | 83..105 | 42..54 | 48 |
| 1024 | 91..112 | 49..66 | 64 |
| 2048 | 125..146 | 72 | 128 |

| Bytes | Zen 3 `rep movsb` | Cascade Lake `rep movsb` | SSE2, two 16-byte copies per turn (both) |
|---:|---:|---:|---:|
| 256 | 35..49 | 35..39 | 16..18 |
| 512 | 42..86 | 46..49 | 32..34 |
| 768 | 51..65 | 55..56 | 48..50 |
| 1024 | 59..73 | 63..68 | 64..66 |

The loop with two 16-byte steps per turn moves 16 bytes a cycle on both
processors with nothing to start, so the middle sizes use it:

- zeroing: below `ErmsFillMinSize`, a variable that starts at 768 and that
  `InitializeMemoryManager` raises to 2048 on an `AuthenticAMD` processor
  (`cpuid`), because `rep stosd` needs about 80 cycles to start on Zen 3 and
  about 25 on Cascade Lake; on both, `rep stosd` is also 15-22 cycles slower
  when the block lies on every second 16-byte boundary;
- copying: below `ErmsMoveMinSize` = 1024 on every processor.

Below 256 bytes nothing changes (the 16-byte loop), above the thresholds nothing
changes either (`rep`). The new loops perform the same 16-byte steps as the
16-byte loop, two per turn; the one or two steps that are left at the end are
done as "the next one" and "the last one of the sequence", which are the same
step when one was left, so there is no branch on the parity and never a step
more than before. `memory_zero_copy_contract.dpr` (in the profile contract of
both systems) proves it for every size from 1 to 5000 bytes: zeroed contents,
preserved contents, and an untouched header and body of the neighbour block,
under both values of the zeroing threshold (test hook
`Fpcx64mmTestErmsFillMinSize`, `FPCMM_ERMSFILL_TEST`); the start-up value is
checked against the processor vendor. Removing the masking of the last step
makes the test fail (checked for both loops).

The targeted zero/copy experiment measured cycles per operation on the Ryzen
5800X (release / before / after) and TSC ticks on the Xeon W-2295 (before / after):

| Case | Ryzen | Xeon |
|---|---|---|
| `hot-rtl/dynarray-setlength-double-64` | 147.3 / 154.3 / **74.5** | 127.6 / **92.8** |
| `mm/realloc-grow` | 53.7 / 55.1 / **50.8** | 62.9 / **57.9** |
| `mm/realloc-shrink` | 27.4 / 29.2 / **26.9** | 36.7 / **34.7** |
| every other `mm` and allocator-bound `hot-rtl` case | unchanged | unchanged |

The measured growth and shrink chains also improve over the monolithic release.

The product gate `qualification/memory-manager/mm_layout_gate.py` builds and
runs `mm_probe.dpr`, checks 64-byte entries and 32-byte branch/fusion sites in
the current leaf **and all three Win64 slow routines**, as well as the Linux
monolithic routines. Its residue limits describe the present binary, not an
earlier label/offset layout. `RTL-test/semantic/mm_hotpath_stress_semantic.dpr`
checks cross-thread free and leaks; `mm_profile_matrix.py` tests the profile
variants. Layout-gate success is a placement invariant, not proof of faster
allocation; causal performance requires a same-source MM/profile A/B.

## What is not part of the product profile

- The new upstream default `FPCMM_SERVER` does not affect MoonCompiler: the
  profile always explicitly selects `FPCMM_BOOSTER + FPCMM_MOONSHARD`.
- `VirtualAlloc2(MEM_64K_PAGES)` speeds up dense large buffers but nearly doubles
  the time for sparse 1–2 MiB allocations that touch one page. Without proven
  access density, this trade-off is not enabled globally.
- Replacing Win64 `mul` with `imul` left seven small/medium workloads within
  `0.984×..1.006×`; a hot path is not changed without a measurable gain.

## Validation

MM qualification covers the pinned source/profile, small/medium/large
boundaries, cross-thread realloc/free, ownership transfer, contention,
shutdown, release/diagnostic chaos, and the older mORMot product line. Commands
are in [Testing](TESTING.md#mormot-and-memory-manager).  The hand layout of
the hot paths is gated by `qualification/memory-manager/mm_layout_gate.py`
and stressed by `RTL-test/semantic/mm_hotpath_stress_semantic.dpr`.

Leak gates fail closed: the MM prints paired
`FPCMM_REPORTMEMORYLEAKS_BEGIN/DONE` markers, and the runner requires exactly one
completed report per process. No leak messages without `DONE` is not a success.
Dedicated regressions prove a late managed finalizer and a deliberately lost
block that must appear in the census.

The table of 44 classes and 32 arenas is the measured product baseline, not an
architectural limit. A different class or arena count is accepted only from a
full production allocation trace, fragmentation data, and the complete realloc
range; no synthetic-loop alternative has met that bar.

## Origin and license

Arnaud Bouchez of Synopse wrote the source unit. It is based on Pierre le
Riche's FastMM4 and is available under MPL 1.1, GPL 2.0+, or LGPL 2.1+ with
the FPC static-linking exception. The original header is retained; the full
text is in [`runtime/mm/LICENSE.md`](../runtime/mm/LICENSE.md).
