<p align="center">
  <a href="https://moonbot.pro">
    <img src="assets/moonbot-logo-full.svg" alt="Moonbot" width="199">
  </a>
</p>

<h1 align="center">MoonCompiler</h1>

<p align="center">
  <b>Delphi-compatible Pascal toolchain for Win64 and Linux x86-64</b><br>
  compiler, Unicode RTL, memory manager, and qualification as one integrated whole
</p>

<p align="center">
  <a href="doc/LICENSING.md"><img src="https://img.shields.io/badge/license-GPLv2%2B%20%C2%B7%20modified%20LGPL-4C6EF5" alt="Licenses: GPLv2 or later and modified LGPL"></a>
  <img src="https://img.shields.io/badge/targets-Win64%20%C2%B7%20Linux%20x86--64-8B5CF6" alt="Targets: Win64 and Linux x86-64">
  <a href="https://github.com/Moonbot-Tech/MoonCompiler/releases/latest"><img src="https://img.shields.io/github/v/release/Moonbot-Tech/MoonCompiler?label=release" alt="Latest release"></a>
  <a href="https://github.com/Moonbot-Tech/MoonCompiler/actions/workflows/qualification.yml"><img src="https://github.com/Moonbot-Tech/MoonCompiler/actions/workflows/qualification.yml/badge.svg" alt="Qualification"></a>
</p>

<p align="center">
  <a href="#what-mooncompiler-is-for">What it is for</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#the-build-profile">Build profile</a> ·
  <a href="#changes-from-unleashed">What changed</a> ·
  <a href="#performance">Performance</a> ·
  <a href="#how-it-is-validated">Qualification</a> ·
  <a href="#lazarus">Lazarus</a> ·
  <a href="#documentation">Documentation</a>
</p>

MoonCompiler is a self-contained environment for building modern Delphi code on
Win64 and Linux x86-64. It grew out of a specific need: moving the core of a
high-load cryptocurrency-scalping trading terminal, written in and still being
developed with Delphi 12.2, to Linux.

The starting point was Unleashed, an FPC fork with support for modern Delphi
syntax. Working against a complete production application required substantial
work on its compiler, RTL, and memory manager.

MoonCompiler brings the modified compiler, Unicode RTL, packages, memory
manager, and runtime units together as one supported x86-64 configuration. We
validate and optimize that configuration as a whole.

The supported surface and intentionally retained boundaries are listed in
[Known Issues](doc/KNOWN_ISSUES.md); future improvements are in the
[Backlog](doc/BACKLOG.md). Supported targets are Win64 and Linux x86-64.
32-bit targets, other CPU architectures, and macOS are neither supported nor
planned.

## What MoonCompiler Is For

MoonCompiler lets supported Delphi 12.2 code run on Linux without an application
rewrite. The same toolchain builds native Win64 applications. Compiler and runtime
optimizations target ordinary text, collection and server workloads.

In practice, this means:

- the same source continues to build with Delphi 12.2 and MoonCompiler;
- the Linux version uses the same types, algorithms, and application
  architecture rather than a port with different semantics;
- Unicode, threading, RTTI, exceptions, and the memory manager come from one
  ready-made profile instead of being configured anew for each project;
- the result is validated beyond “it compiled”: tests compare calculations,
  lifetime, ABI, and behaviour at different optimization levels;
- compiler, RTL, and MM performance is measured together on application hot
  paths, and bottlenecks are fixed where they originate—in the compiler, RTL,
  or MM.

## Quick Start

Download the archive for your platform from
[GitHub Releases](https://github.com/Moonbot-Tech/MoonCompiler/releases),
unpack it into a directory named `toolchain`, and clone MoonORMot next to it.
No bootstrap compiler, no clone of this repository and no Python are needed.
Then build a program - this one, or [examples/hello.dpr](examples/hello.dpr):

```pascal
program hello;
begin
  Writeln('Hello from MoonCompiler');
end.
```

Linux:

```bash
mkdir -p ~/moon/toolchain && cd ~/moon
tar -xzf ~/Downloads/mooncompiler-toolchain-v2.0.0-linux-x86-64.tar.gz -C toolchain
git clone https://github.com/Moonbot-Tech/MoonORMot mormot
toolchain/bin/fpc hello.dpr
toolchain/bin/fpc -dRELEASE hello.dpr
```

Win64 PowerShell:

```powershell
New-Item -ItemType Directory -Force C:\Moon | Set-Location
Expand-Archive $HOME\Downloads\mooncompiler-toolchain-v2.0.0-win64.zip -DestinationPath toolchain
git clone https://github.com/Moonbot-Tech/MoonORMot mormot
toolchain\bin\x86_64-win64\fpc.exe hello.dpr
toolchain\bin\x86_64-win64\fpc.exe -dRELEASE hello.dpr
```

`fpc` is the product: it reads only the configuration next to its own binary,
so the two commands are the same on both platforms and from any directory.
Without `-dRELEASE` the program is a Debug build. MoonORMot is not inside the
archive on purpose: the runtime units over mORMot (`System.Zip`,
`System.Net.HttpClient`, `Moon.Diagnostics`, ...) compile against the clone in
`mormot`, and `git pull` there is how it is updated.

Alternatively, build the same toolchain from source with the FPC 3.2.2
bootstrap compiler; this also clones MoonORMot next to the toolchain:

```bash
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
./build compiler
```

```powershell
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
Set-Location MoonCompiler
.\build.ps1 compiler
```

The source-build dependencies and the exact bootstrap commands are in
[Setup](doc/SETUP.md).

That is enough for a normal project. The toolchain's configuration adds the
Unicode RTL, Delphi namespaces, the runtime units and the bundled MM itself.
For a larger project, add a `<Project>.mooncompiler` file next to the `.dpr`
once - a file of compiler options: source trees (`-Fu./**` for a whole tree),
aliases and defines; the daily command stays the same. The format is described
in [Project Build](doc/PROJECT_BUILD.md).

Heavy MM diagnostics can be enabled separately without changing Debug/Release
semantics:

```bash
toolchain/bin/fpc -dFPCX64MM_DIAGNOSTIC hello.dpr
```

## The Build Profile

Users should not have to enumerate internal units or remember their ordering.
The product compiler automatically adds the required prefix before the user's
`uses` clause:

- Win64: bundled MM → `fpwinmonitor`;
- Linux x86-64: bundled MM → `cthreads` → `cwstring` → `fpmonitor`.

Plain `String` always means `UnicodeString`. The byte domain is declared
explicitly with `AnsiString`, `RawByteString`, or `TBytes`. Debug and Release
use one validated runtime-check profile: I/O checking is enabled, while
overflow, range, and stack checking are disabled. Release uses `-O3` and
AUTOINLINE; the presence of line information does not change program semantics.
The installed Unicode RTL and the application-facing packages are built with
the same `-O3` (`scripts/rtl-profile.txt`, one definition for both drivers):
an application spends much of its time inside RTL code, and that code is
optimized and aligned like the application's own. At `-O3` the compiler puts
procedure entries and loop heads on 32 bytes (`CODEALIGN`); the hand-laid
assembler routines of the RTL and of the bundled MM carry their own layout in
their source - the entry on a 64-byte line, the short form of a forward jump
written out as bytes where the assembler's single sizing pass would take the
long one ([ASM layout rules](doc/ASM_LAYOUT_RULES.md)). The code placement
draft of the internal assembler is off; `MOONCOMPILER_PLACEMENT=1` in the
environment switches it on
([Optimizer, Code placement](doc/OPTIMIZER.md#code-placement)). The toolchain
records the exact profile, and `qualification/build-driver/rtl_profile_gate.py`
proves the installed RTL and package witness objects against it.

The product runtime can be explicitly disabled with
`-dMOONCOMPILER_VANILLA_RUNTIME`; Valgrind and ASan builds use `cmem` instead
of the bundled MM.

For the full layout of profiles and dependencies, see [Setup](doc/SETUP.md)
and [Project Build](doc/PROJECT_BUILD.md).

## Changes from Unleashed

### Compiler and Language

The repository contains more than 120 individual correctness, compatibility,
and performance fixes across the compiler and RTL. The supported Delphi surface
includes inline variables, anonymous methods and `reference to`, generics,
advanced and managed records, attributes, extended RTTI, and namespaces. For
example:

- after loop unrolling, the optimizer reused a stale table address, causing AES
  to diverge from FIPS-197 starting with the second round;
- Win64 code generation for `Currency * Currency` truncated an intermediate
  result to 64 bits and corrupted exact financial arithmetic;
- an exception from `Initialize` or `Assign` on a managed record or array left
  leaks or caused repeated finalization of a partially constructed value;
- Linux exception unwinding could restore the wrong nonvolatile register and
  corrupt a live exception object inside `finally`.

For the full catalogue of symptoms, causes, and regression tests, see
[Compiler Fixes](doc/COMPILER_FIXES.md).

`inline; forward;` is accepted, and a unit's own `{$MODE Delphi}` is a no-op
under the product profile instead of a reset of the driver's switches. A
Delphi Win64 assembler body used on Linux is declared `ms_abi_default` (see
[Project Build](doc/PROJECT_BUILD.md#win64-assembler-bodies-on-linux)).

### RTL and API

The product RTL uses `UnicodeString` as the normal `String` and provides the
Delphi surface applications need on both platforms. We fixed managed-value
lifetime, strings and encodings, collections, streams, tasks and threads, RTTI
invocation, file and network helpers, and the platform ABI. Win64 and Linux
build from one source contract; platform differences remain inside the RTL.

Delphi surface that Unleashed lacked and MoonBot/Arbitrage needed on Linux
is written from behavioural contracts and standards, not from Embarcadero
sources:

- `Classes.TBufferedFileStream`, a `TFileStream` with one read/write window
  that is observably identical to the plain stream (the `bufstream` page
  cache, which corrupted seek-back write patterns, is repaired as well);
- `SyncObjs.TLightweightMREW`, the readers/writer lock over the OS primitive
  (SRW lock, pthread rwlock): a zero-filled record is a ready lock, with the
  Linux-only timed `TryBeginRead/TryBeginWrite` as in Delphi;
- `Sockets.sockaddr_storage` (`TSockAddrStorage`, `PSockAddrStorage`) and
  `socklen_t`: the 128-byte, `sockaddr_in6`-aligned peer buffer for
  `fprecvfrom`/`fpaccept` of any family;
- `System.Masks` (`TMask`, `MatchesMask`, `EMaskException`) with the Delphi
  wildcard syntax and its quirks (`*?`, ASCII-only case folding, byte sets);
- `System.ZLib`: the zlib.h functions, `TZCompressionStream` /
  `TZDecompressionStream` and the `ZCompress*`/`ZDecompress*` helpers over
  zlib 1.3.1, linked as private objects on Win64 and Linux (no DLL, no
  `libz.so`; no C runtime on Win64, the C library's `memcpy`/`memset` on
  Linux); MoonORMot compresses through it too (`System.Zip`, mORMot's HTTP
  compression), so a program carries one zlib;
- `System.Net.URLClient` (`TNetHeaders`, `TURLHeaders`, `TURLRequest`,
  `TCertificate`, `ENet*`) without mORMot;
- in [`runtime/mormot`](runtime/mormot/README.md), compiled into each project
  over its own mORMot: `System.Zip` (`TZipFile`, `TZipHeader`, `EZip*` over
  `mormot.core.zip`: entry streams inflated on demand from the mapped
  archive with CRC checking, ZIP64, UTF-8 names, `ExtractAll` that refuses
  escaping names before writing anything), `System.Net.Mime`
  (`TMultipartFormData` over `THttpMultiPartStream`, a flat RFC 7578 body
  that streams its files and reads more than once) and `System.Net.HttpClient`
  (`THTTPClient`, `IHTTPResponse`, `IAsyncResult`, `TCookieManager`,
  `ENetHTTP*`: keep-alive, the redirect table with method changes, cookies
  per host, gzip/deflate through `ContentAsString` or
  `AutomaticDecompression`, progress with abort, TLS validation with the
  handler retry, asynchronous `BeginGet`/`Cancel`);

### Optimizer

The accepted branch includes more than local peephole fixes; it also contains a
dedicated optimization block:

- safe LICM with an explicit effects model;
- ADDRESSGVN and reuse of proven-stable addresses;
- precise register allocation and liveness around Windows SEH and Linux EH;
- shorter FP live ranges and register preservation through exception paths;
- CODEALIGN (entries and loop heads on 32 bytes; the code placement draft of
  the internal assembler is off by default) and x86-64 machine facts checked
  by dedicated gates.

The architecture, safety boundaries, and measured results are described in
[Optimizer](doc/OPTIMIZER.md).

### Memory Manager

The bundled MM is based on the mORMot FPC x86-64 MM and is part of the product
profile. It is included before any user unit and has multithreaded arenas,
validated small and medium size classes, and a separate diagnostic mode with an
allocation registry, poison, structural checks, and a leak report. For details
and licensing, see [Memory Manager](doc/MEMORY_MANAGER.md).

## Performance

Performance is measured by Pulse, the benchmark system included in the
repository. It combines compiler, RTL, and MM microbenchmarks with compact
models of server and trading hot paths. Each case is built with both compilers
from the same Pascal source; speed is considered only after their calculation
results agree.

The second release reduces repeated work in string search, UTF-8 decoding,
dictionaries, loops and resource cleanup. It also speeds up compilation of large
programs with many generated classes and provides a portable direct `fpc` build.
Read [what changed in MoonCompiler 2.0](doc/RELEASE_NOTES.md) for the practical
results, the measured workloads and upgrading instructions.

Selected confirmed examples from the 5 October release measurements:

| Useful operation | CPU cost removed vs Delphi 12.2, Win64 | CPU cost removed vs first Moon release, Win64 / Linux |
|---|---:|---:|
| UTF-16 substring search in a 64-character string | 24% | 52% / 56% |
| Decode 32 Cyrillic characters from UTF-8 | 60% | 83% / 79% |
| Add or update a numeric dictionary entry | 70% | 70% / 68% |
| Fill a reserved dictionary with numeric keys and string values | 13% | 51% / 50% |
| Scan a mixed JSON byte buffer | 32% | 36% / 34% |
| Loop with a short `try/finally` | 37% | 29% / 63% |

These are reductions in the cost of the named work, not whole-application speedups
or a complete-matrix average. Linux comparisons use the previous Moon release;
Delphi comparisons are Windows-only. The [measurement record](doc/evidence/release2/README.md)
identifies the tested source, machines, semantic checks and individual ratios.
The bundled-MM comparison with the standard FPC allocator is a separate test
using the same compiler; it is not a comparison of two compiler products.

To reproduce the complete current-versus-release comparison, configure the two
hosts and their installed toolchains, then run:

```text
python qualification/performance/tools/pulse_both.py --config <hosts.json>
```

For one host, use `pulse_full.py`; both commands use the fixed-work method,
identical-program controls and independent confirmation described in
[Performance Qualification](doc/PERFORMANCE_QUALIFICATION.md).
Earlier measurements remain in the [Pulse history](qualification/performance/PULSE_HISTORY.html)
and [dated snapshots](qualification/performance/CURRENT_RESULTS.md).

## How It Is Validated

A green build of one project is not considered evidence of compatibility.
Qualification is split into independent layers:

| System | What it validates |
|---|---|
| Focused regressions | The exact defect and the neighbouring boundaries of each fix |
| Mega and Omni | Broad language forms, their combinations, and optimization modes |
| Devil | Generated expression classes, ABI, managed lifetime, and a differential oracle |
| Chimera | Whole and split compositions transferred from MoonBot, Arbitrage, mORMot, and other Pascal projects |
| Resident | A multithreaded mix of runtime, collections, crypto, hashing, compression, numerical algorithms, and long-lived managed values |
| Project checks | Both mORMot lines, Lazarus, upstream regressions, and complete forms from other Pascal projects |
| RTL-test | RTL API, boundaries, ownership, exception cleanup, and multithreading |
| Pulse and Heartbeat | A semantic digest plus comparative performance |

Win64 and Linux run Debug/O2/O3 wherever the optimization level is part of the
risk being checked. Light and impact-scoped gates are for the short fix cycle;
full qualification is for a release exact HEAD. See [Testing](doc/TESTING.md)
for commands and a map of the layers.

## Lazarus

The pinned Lazarus version builds and launches with one command:

```bash
./lazarus
```

```powershell
.\lazarus.ps1
```

On its first run, the driver builds the compiler, checks out the supported
Lazarus commit, and creates an isolated IDE configuration. Lazarus sources are
not patched. The toolchain contains two non-overlapping profiles: a normal FPC
ABI for the IDE/LCL itself, and a Unicode product profile for Delphi-compatible
applications.

Lazarus provides the editor, navigation, debugger, and designer. The product
build of a larger `.dpr` is the toolchain's `fpc` with the project's
`.mooncompiler` file next to it, so the IDE does not create a second set of
hidden settings. For details, see [Lazarus setup](doc/SETUP.md#lazarus).

## Repository

- `compiler`, `rtl`, `packages`, `utils` — toolchain;
- `runtime/mm` — the sole product memory manager;
- [`runtime/reporting`](runtime/reporting/README.md) — optional in-process exception and all-thread reports;
- [`runtime/mormot`](runtime/mormot/README.md) — `System.Zip`, `System.Net.Mime`, `System.Net.HttpClient` over the mORMot next to the toolchain, and `MoonORMot.Need`, the MoonORMot version these units require;
- `examples` — minimal Delphi-compatible projects for a quick start;
- `tests` — upstream tests and minimal compiler regressions;
- `RTL-test` — a separate matrix for RTL semantics and lifetime;
- `qualification/suite` — Mega, Omni, Devil, Chimera, corpora, and integration;
- `qualification/performance` — Pulse, Heartbeat, and versioned evidence;
- `.qualification/deps/moonormot` — the ignored, on-demand checkout of the
  exact MoonORMot commit used only by qualification; the pin must equal
  MoonORMot `main`, and `scripts/sync-moonormot.py` keeps it, the runtime
  units' version floor and the bundled MM on that tip together;
- `mormot` — the ignored clone of MoonORMot next to `toolchain` that
  applications build against (`build compiler` creates it when it is missing);
- `doc` — public documentation.

A clone and normal build require only the repository contents and the bootstrap
tools from [Setup](doc/SETUP.md); `build compiler` fetches MoonORMot once for
the applications, and qualification fetches its own pinned checkout.

## Documentation

- [Release notes](doc/RELEASE_NOTES.md) — what the second release changes and how to upgrade;
- [Setup](doc/SETUP.md) — a clean Linux and Win64 installation;
- [Project Build](doc/PROJECT_BUILD.md) — simple and multi-repository projects;
- [Testing](doc/TESTING.md) — Light/full qualification and the role of each layer;
- [Compiler Fixes](doc/COMPILER_FIXES.md) — catalogue of correctness, API, and ABI fixes;
- [Performance Qualification](doc/PERFORMANCE_QUALIFICATION.md) — Pulse methodology;
- [Optimizer](doc/OPTIMIZER.md) — LICM, ADDRESSGVN, RA, and CODEALIGN;
- [Memory Manager](doc/MEMORY_MANAGER.md) — MM, diagnostic mode, and limitations;
- [Diagnostic Reports](doc/DIAGNOSTICS.md) — opt-in file reports and embedded stack symbols;
- [Known Issues](doc/KNOWN_ISSUES.md) — accepted observable boundaries;
- [Backlog](doc/BACKLOG.md) — intentionally deferred improvements;
- [Development](doc/DEVELOPMENT.md) — rules for the next fix;
- [Licensing](doc/LICENSING.md) — licenses, notices, and the linking exception.

## Licensing

The compiler is distributed under GPLv2 or later. The RTL and packages retain
the modified LGPL and FPC static-link exception. The bundled MM retains its
original disjunctive MPL-1.1/GPL/LGPL header and FPC linking exception. For the
complete component map, see [Licensing](doc/LICENSING.md).

The memory manager is based on open-source [Synopse mORMot](https://synopse.info/);
the modified source and original notices are in `runtime/mm`.

---

Moonbot · MoonCompiler — Delphi-compatible Pascal toolchain · [moonbot.pro](https://moonbot.pro)
