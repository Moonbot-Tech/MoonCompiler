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

In the final Pulse run, the same MoonCompiler was built with the bundled MM and
with the standard FPC MM. On the allocator group, the bundled MM achieved a
`0.6069×` geometric mean: it completed the same work `1.65×` faster on
average. The method and the full snapshot are in the
[release evidence](../qualification/performance/evidence/release-final-20260830/EVIDENCE.md).

The product profile therefore uses `FPCMM_BOOSTER`, not the standard FPC MM or
libc.

## What MoonCompiler adds over current upstream

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

### Product profile and allocator installation

The compiler inserts the MM as the first unit before the user's `uses`, and the
build driver pins the exact unit-name-to-source mapping and required defines:

```text
--pinned-unit=mormot.core.fpcx64mm=<repo>/runtime/mm/mormot.core.fpcx64mm.pas
-dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD
```

The pinned unit is resolved before ordinary PPU/packages/`-Fu`; `uses ... in`
cannot replace it with another file. The unit itself aborts compilation when
the product profile is incomplete or `FPCMM_DISABLE`/`FPCMM_STANDALONE` would
prevent allocator installation.

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

The public driver enables diagnostics separately without changing normal Debug
semantics:

```bash
./build Project.dpr debug --diagnostic-mm
```

```powershell
.\build.ps1 Project.dpr debug -DiagnosticMM
```

### Exact live accounting

`CurrentHeapStatus.SmallBlocks` does not count blocks already accepted by
`FreeMem` that are still awaiting recycling in a deferred list. The snapshot remains
lock-free and clamps its result to zero during concurrent counter changes, so
monitoring does not receive a falsely elevated count of live objects.

### ABI on supported operating systems

Linux `_FreeMem` uses caller-saved `RSI` and does not spend `push/pop` preserving
it. Win64 retains `RBX`: both `RSI` and `RBX` are nonvolatile there, and moving
state into `RSI` degraded Moon-generated loops where the caller keeps its counter
in `ESI`. The choice is made by conditional compilation; there is no runtime
branch on the hot path.

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
are in [Testing](TESTING.md#mormot-and-memory-manager).

Leak gates fail closed: the MM prints paired
`FPCMM_REPORTMEMORYLEAKS_BEGIN/DONE` markers, and the runner requires exactly one
completed report per process. No leak messages without `DONE` is not a success.
Dedicated regressions prove a late managed finalizer and a deliberately lost
block that must appear in the census.

The table of 44 classes and 32 arenas is the current product baseline, not an
architectural limit. Experiments with a different number of classes/arenas and
a profile of real allocations are deferred as PB-009 in [Backlog](BACKLOG.md).

## Origin and license

Arnaud Bouchez of Synopse wrote the source unit. It is based on Pierre le
Riche's FastMM4 and is available under MPL 1.1, GPL 2.0+, or LGPL 2.1+ with
the FPC static-linking exception. The original header is retained; the full
text is in [`runtime/mm/LICENSE.md`](../runtime/mm/LICENSE.md).
