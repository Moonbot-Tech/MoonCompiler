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
manager, and build driver together as one supported x86-64 configuration. We
validate and optimize that configuration as a whole.

The supported surface and intentionally retained boundaries are listed in
[Known Issues](doc/KNOWN_ISSUES.md); future improvements are in the
[Backlog](doc/BACKLOG.md). Supported targets are Win64 and Linux x86-64.
32-bit targets, other CPU architectures, and macOS are neither supported nor
planned.

## What MoonCompiler Is For

MoonCompiler lets Delphi 12.2 code run on Linux without a rewrite—and, in our
measurements, it will usually run faster than under Delphi. The same toolchain
also builds native Win64 applications.

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

Clone the repository first. It contains the build driver, project profile, and
the pinned MM source used by the installed toolchain:

```bash
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
```

The shortest path is to download the archive for your platform from
[GitHub Releases](https://github.com/Moonbot-Tech/MoonCompiler/releases) and
install it into the clone. No bootstrap compiler is required.

Linux:

```bash
./build toolchain ~/Downloads/mooncompiler-toolchain-v1.0.0-linux-x86-64.tar.gz
./build examples/hello.dpr debug
./build examples/hello.dpr release
```

Win64 PowerShell:

```powershell
.\build.ps1 toolchain $HOME\Downloads\mooncompiler-toolchain-v1.0.0-win64.zip
.\build.ps1 examples\hello.dpr debug
.\build.ps1 examples\hello.dpr release
```

Alternatively, build the same toolchain from source with the FPC 3.2.2
bootstrap compiler:

```bash
./build compiler
```

```powershell
.\build.ps1 compiler
```

The source-build dependencies and exact bootstrap commands are listed in
[Setup](doc/SETUP.md). Afterwards, application projects are always compiled
with the pinned compiler in `.moonbot/toolchain`, regardless of how it was
installed.

That is enough for a normal project. The driver adds the Unicode RTL, Delphi
namespaces, required runtime units, and bundled MM itself. For a larger project,
add a `<project>.mooncompiler` file next to the `.dpr` once, containing source
trees, aliases, and pinned Git dependencies; the daily command stays the same.
The format is described in [Project Build](doc/PROJECT_BUILD.md).

Heavy MM diagnostics can be enabled separately without changing Debug/Release
semantics:

```bash
./build examples/hello.dpr debug --diagnostic-mm
```

```powershell
.\build.ps1 examples\hello.dpr debug -DiagnosticMM
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

The product runtime can be explicitly disabled with
`-dMOONCOMPILER_VANILLA_RUNTIME`; Valgrind and ASan profiles automatically use
`cmem` instead of the bundled MM.

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

### RTL and API

The product RTL uses `UnicodeString` as the normal `String` and provides the
Delphi surface applications need on both platforms. We fixed managed-value
lifetime, strings and encodings, collections, streams, tasks and threads, RTTI
invocation, file and network helpers, and the platform ABI. Win64 and Linux
build from one source contract; platform differences remain inside the RTL.

### Optimizer

The accepted branch includes more than local peephole fixes; it also contains a
dedicated optimization block:

- safe LICM with an explicit effects model;
- ADDRESSGVN and reuse of proven-stable addresses;
- precise register allocation and liveness around Windows SEH and Linux EH;
- shorter FP live ranges and register preservation through exception paths;
- CODEALIGN and x86-64 machine facts checked by dedicated gates.

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

Across the 243 cases shared by the original baseline and final snapshot,
Moon/Unleashed was at parity with Delphi (`0.9978×`), while current Moon reached
`0.7625×`. Our compiler/RTL/MM optimization series accounts for the entire gain
on this set: the current version is `1.31×` faster than the original. The final
extended matrix contains 744 cases, where Moon is `1.20×` faster than Delphi
12.2. Across twenty Heartbeat application hot paths, the advantage is `1.22×`.
Separately, the bundled MM is `1.65×` faster than the standard FPC MM on
allocator workloads with the same compiler and source. Stock FPC is absent from
the table because it cannot compile the Delphi code under test.

| Workload | Comparison | Cases | Moon result |
|---|---|---:|---:|
| Compiler/RTL/MM optimization series | Moon now / Moon before work began | 243 shared | `1.31×` faster |
| Full matrix: ABI, code generation, RTL, MM, and application workloads | Delphi 12.2 + FastMM4 | 744 | `1.20×` faster |
| Heartbeat: server and trading hot paths | Delphi 12.2 + FastMM4 | 20 | `1.22×` faster |
| RTL: strings, numbers, streams, and helpers | Delphi 12.2 + FastMM4 | 77 | `1.45×` faster |
| Collections | Delphi 12.2 + FastMM4 | 48 | `1.37×` faster |
| JSON through the mORMot API | Delphi 12.2 + FastMM4 | 18 | `1.16×` faster |
| Memory allocation | Standard FPC MM with the same MoonCompiler | 15 | Bundled MM `1.65×` faster |

The complete report, including all cases and source numbers, is
[release-final-20260830](qualification/performance/evidence/release-final-20260830/REPORT.md).
Result changes after each optimization stage are retained in the
[Pulse history](qualification/performance/PULSE_HISTORY.html). For methodology
and calculation rules, see [Performance Qualification](doc/PERFORMANCE_QUALIFICATION.md).
For the known slow tail, see [Backlog](doc/BACKLOG.md).

To reproduce the medium snapshot on Win64 from a RAD Studio command environment:

```powershell
python qualification\performance\tools\pulse.py run `
  --mode medium --systems delphi,moon,moon-default `
  --tag local-medium
```

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

Lazarus provides the editor, navigation, debugger, and designer. The same
`build`/`build.ps1` performs the final product build of a larger `.dpr`, so the
IDE does not create a second set of hidden settings. For details, see [Lazarus
setup](doc/SETUP.md#lazarus).

## Repository

- `compiler`, `rtl`, `packages`, `utils` — toolchain;
- `runtime/mm` — the sole product memory manager;
- `examples` — minimal Delphi-compatible projects for a quick start;
- `tests` — upstream tests and minimal compiler regressions;
- `RTL-test` — a separate matrix for RTL semantics and lifetime;
- `qualification/suite` — Mega, Omni, Devil, Chimera, corpora, and integration;
- `qualification/performance` — Pulse, Heartbeat, and versioned evidence;
- `qualification/vendor/mormot-product` — the pinned mORMot 2.3.8832 product
  corpus without its own MM;
- `doc` — public documentation.

A clone and normal build require only the repository contents and the bootstrap
tools from [Setup](doc/SETUP.md).

## Documentation

- [Setup](doc/SETUP.md) — a clean Linux and Win64 installation;
- [Project Build](doc/PROJECT_BUILD.md) — simple and multi-repository projects;
- [Testing](doc/TESTING.md) — Light/full qualification and the role of each layer;
- [Compiler Fixes](doc/COMPILER_FIXES.md) — catalogue of correctness, API, and ABI fixes;
- [Performance Qualification](doc/PERFORMANCE_QUALIFICATION.md) — Pulse methodology;
- [Optimizer](doc/OPTIMIZER.md) — LICM, ADDRESSGVN, RA, and CODEALIGN;
- [Memory Manager](doc/MEMORY_MANAGER.md) — MM, diagnostic mode, and limitations;
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
