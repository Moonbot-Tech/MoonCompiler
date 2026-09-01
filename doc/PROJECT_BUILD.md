# Building Applications

`build` and `build.ps1` define the full application profile: compiler, RTL,
namespaces, runtime units, memory manager, checks, and PPU directories. A
project does not need to keep its own list of MoonCompiler internal switches.

```bash
./build Project.dpr debug
./build Project.dpr release
./build Project.dpr debug --diagnostic-mm
```

```powershell
.\build.ps1 Project.dpr debug
.\build.ps1 Project.dpr release
.\build.ps1 Project.dpr debug -DiagnosticMM
```

The executable is created next to the `.dpr`; intermediate files and the unit
cache are under `.moonbot`.

## Profiles

| Property | Debug | Release |
|---|---:|---:|
| Optimization | `-O-` | `-O3`, AUTOINLINE |
| I/O checking | enabled | enabled |
| Assertions | enabled | disabled |
| Overflow/range/stack checking | disabled | disabled |

This set matches the validated profile of the original Delphi application.
Qualification tests that require `-Co`, `-Cr`, or `-Ct` enable them only for
their own repro. The presence of line information does not change Debug/Release
semantics.

`--diagnostic-mm`/`-DiagnosticMM` is an independent modifier: it preserves the
Debug profile but rebuilds the MM with an allocation registry, poison,
structural checks, and a leak report in a separate unit cache. This is a heavy
diagnostic mode, not a benchmark profile. For details, see [Memory
Manager](MEMORY_MANAGER.md#extended-diagnostics).

## Runtime by Default

The compiler adds support units before the user's `uses` clause:

- Win64: bundled MM → `fpwinmonitor`;
- Linux x86-64: bundled MM → `cthreads` → `cwstring` → `fpmonitor`.

Consequently, an ordinary entry point contains only application units. The old
explicit prefix is permitted but redundant. A late `cmem` in the product profile
is rejected because it would silently replace the allocator already installed.

The bundled MM is selected by its exact source with `--pinned-unit`, rather than
by the first same-named file in `-Fu`. An external mORMot cannot silently
replace the process memory manager.

Plain `String` and `Char` have the Delphi 12.2 Unicode ABI. Byte data is
explicitly declared as `AnsiString`, `RawByteString`, or `TBytes`. On Linux,
table-based PSABI exception unwinding is a target property and requires no
hidden define.

For experiments with the normal FPC runtime, there is an explicit opt-out:

```text
-dMOONCOMPILER_VANILLA_RUNTIME
```

Valgrind and ASan profiles select `cmem` through the compiler driver. These are
the only supported ways to disable the bundled product runtime.

## Project Without a Manifest

If no `<project>.mooncompiler` is next to the `.dpr`, the driver recursively
includes the project directory. This is enough for a self-contained application.

## Large-Project Manifest

For multiple source trees, unit aliases, and external Git dependencies, keep
`Project.mooncompiler` next to `Project.dpr`. It is a versioned UTF-8 file:

```text
source=src
source=../Common
alias=Custom.Name=LegacyName
dependency=indy|https://github.com/IndySockets/Indy.git|0123456789abcdef0123456789abcdef01234567|Lib
```

Blank lines and lines beginning with `#` are ignored.

| Directive | Meaning |
|---|---|
| `source=PATH` | recursive source tree; a relative path is resolved from the manifest |
| `alias=Public.Name=RealUnit` | an additional unit name without a second type identity |
| `dependency=NAME\|URL\|COMMIT\|ROOTS` | Git dependency, full 40-character commit, and a comma-separated list of source roots |

A dependency is fetched once into
`.moonbot/dependencies/NAME/COMMIT`. Before the build, the driver requires the
exact HEAD and a clean tree. Every declared root and file/directory link is
verified physically; broken, cyclic, external links and paths escaping the
checkout are rejected before the compiler runs. This check does not constrain
the project's ordinary live `source=` trees.

A private URL uses the machine's Git credentials. MoonCompiler does not retain
passwords or rewrite URLs.

## What the Driver Guarantees

- only `.moonbot/toolchain` is used, never a random system FPC;
- Win64 and Linux receive one Delphi/Unicode application ABI;
- Debug, Release, and diagnostic MM have separate PPU caches;
- the logical path to the `.dpr` is retained even through a local source view;
- a dependency has an exact revision and physically isolated source roots;
- the executable does not depend on manual `-Fu` or runtime-unit ordering.

These properties are enforced by
`qualification/build-driver/project_profile_gate.py`: it creates an external
Git checkout, aliases, and a logical source view; builds Debug, Release, and
diagnostic MM; and verifies both allowed and prohibited dependency paths.

Toolchain and Lazarus installation are described in [Setup](SETUP.md); test
profiles are in [Testing](TESTING.md).
