# Building Applications

An application is built with the toolchain's own `fpc`, from any directory,
the same way on Windows and Linux:

```bash
<root>/toolchain/bin/fpc Project.dpr
<root>/toolchain/bin/fpc -dRELEASE Project.dpr
```

```powershell
<root>\toolchain\bin\x86_64-win64\fpc.exe Project.dpr
<root>\toolchain\bin\x86_64-win64\fpc.exe -dRELEASE Project.dpr
```

`<root>` is the directory that holds `toolchain` and, next to it, `mormot`
(see [Setup](SETUP.md)). The whole application profile - Delphi mode, the
Unicode RTL, namespaces and unit aliases, the runtime units, the bundled
memory manager, the checks of each profile - is the toolchain's own
`fpc.cfg`. A project keeps no list of MoonCompiler switches, and no build
driver or script takes part: `fpc` is the product.

The executable is created next to the `.dpr`; the compiled units go to
`units/<target>/<profile>` under the project directory (`x86_64-win64` or
`x86_64-linux`; `debug`, `release`, `debug-diagnostic`,
`release-diagnostic`), created on demand. Each profile has its own directory
because a PPU does not record the options it was compiled with: a shared
directory would silently link a Release program from Debug units.

## Windows API unit names

On Win64 the product configuration maps Delphi's `Winapi.*` names to the
installed FPC bindings. Qualified and short names share one unit and its
types, including when different source units use different spellings.
No aliases are needed in the project's `.mooncompiler` file.

| Delphi unit names (with or without `Winapi.`) | Installed binding |
|---|---|
| `Windows`, `Messages`, `WinSock`, `WinSock2` | Same short name in the RTL and `rtl-extra` |
| `ActiveX`, `CommCtrl`, `CommDlg`, `DwmApi`, `FlatSB`, `ImageHlp`, `Imm`, `MMSystem`, `MultiMon`, `Nb30`, `Ole2`, `RichEdit`, `ShellAPI`, `SHFolder`, `ShlObj`, `ShLwApi`, `UrlMon`, `UxTheme`, `WinHTTP`, `WinInet`, `WinSpool` | Same short name in `winunits-base` |
| `AccCtrl`, `AclAPI`, `Cpl`, `Dlgs`, `IpExport`, `IpHlpApi`, `IpRtrMib`, `IpTypes`, `PsAPI`, `Qos`, `RegStr`, `TlHelp32`, `UserEnv`, `WinCred`, `Winsafer`, `WinSvc`, `WTSApi32` | `Jwa` + short name in `winunits-jedi` |

This covers unit names backed by these headers; their declarations remain
those of FPC. It does not add missing Delphi API units such as `Winapi.D3D11`.
A project's own unit takes priority over a configured alias, and an explicit
alias in its options file can override the mapping. Listing the same unit
twice in one `uses` clause, for example `Windows, Winapi.Windows`, is rejected
as in Delphi.

## Profiles

| Property | Debug (default) | Release (`-dRELEASE`) |
|---|---:|---:|
| Optimization | `-O-` | `-O3`, AUTOINLINE |
| I/O checking | enabled | enabled |
| Assertions | enabled | disabled |
| Overflow/range/stack checking | disabled | disabled |
| Defines | `DEBUG` | `RELEASE` |

This set matches the validated profile of the original Delphi application.
Qualification tests that require `-Co`, `-Cr`, or `-Ct` enable them only for
their own repro. Line information (`-gl -gw3`) is present in both profiles and
does not change program semantics. The profile is a `#IFDEF RELEASE` block in
`fpc.cfg`: `-dRELEASE` on the command line selects the Release branch, and
`DEBUG` is undefined there, so a Debug-only check cannot survive into a
Release build.

`-dFPCX64MM_DIAGNOSTIC` is an independent modifier: it keeps the profile and
rebuilds the memory manager with an allocation registry, poison, structural
checks and a leak report, in the `*-diagnostic` unit directory. This is a
heavy diagnostic mode, not a benchmark profile; see [Memory
Manager](MEMORY_MANAGER.md#extended-diagnostics).

## Runtime by Default

The compiler adds support units before the user's `uses` clause:

- Win64: bundled MM → `fpwinmonitor`;
- Linux x86-64: bundled MM → `cthreads` → `cwstring` → `fpmonitor`.

Consequently, an ordinary entry point contains only application units. The old
explicit prefix is permitted but redundant. A late `cmem` in the product profile
is rejected because it would silently replace the allocator already installed.

The bundled MM is selected by its exact source with `--pinned-unit` in
`moon-base.cfg`, rather than by the first same-named file in `-Fu`. An
external mORMot cannot replace the process memory manager; a project file or
a configuration cannot re-pin it either, only the command line can.

Plain `String` and `Char` have the Delphi 12.2 Unicode ABI. Byte data is
explicitly declared as `AnsiString`, `RawByteString`, or `TBytes`. On Linux,
table-based PSABI exception unwinding is a target property and requires no
hidden define.

Linux x86-64 keeps the native 10-byte x87 `Extended`, while Delphi 12.2 Win64
uses an 8-byte `Double` representation. Persisted records, wire formats, shared
memory, and cross-platform binary APIs must use explicit `Double` rather than
`Extended`.

### Win64 assembler bodies on Linux

Delphi assembler routines are written for the Win64 convention: arguments in
`rcx`, `rdx`, `r8`, `r9` and `xmm0`..`xmm3`, a 32-byte shadow space above the
return address. On Linux the SysV convention passes arguments in `rdi`, `rsi`,
`rdx`, `rcx`, so the same body silently computes on the wrong registers. Mark
such a routine with the FPC calling-convention modifier, which Delphi does not
know:

```pascal
function CalcSum(P: Pointer; Len: Integer): Cardinal; {$IFDEF FPC}ms_abi_default;{$ENDIF}
asm
  ...
end;
```

The routine is then called with the Win64 convention on every target and its
body runs unchanged; on Win64 the modifier changes nothing. A procedural type
that receives such a routine carries the same modifier. There is no
unit-wide directive for this: a per-unit switch would have to apply to every
declaration after it (the convention is fixed when the declaration is parsed,
before any body is seen), and a register shuffle inside the body would cost
moves on every call of exactly the short helpers this is about.

For experiments with the normal FPC runtime, there is an explicit opt-out:

```text
-dMOONCOMPILER_VANILLA_RUNTIME
```

Valgrind and ASan profiles select `cmem` on the command line. These are the
only supported ways to disable the bundled product runtime.

## Project Without a Project File

If no `<Project>.mooncompiler` is next to the `.dpr`, the compiler searches
the project directory, the toolchain units and the `mormot` directory next to
the toolchain. This is enough for a self-contained application.

## Large-Project File

For several source trees, unit aliases and defines, keep `Project.mooncompiler`
next to `Project.dpr`. It is a versioned UTF-8 file of compiler options, one
per line, exactly as they would be written on the command line; the compiler
reads it by itself after the toolchain configuration and before the command
line, so a command-line option overrides the file and the file overrides the
configuration. Its defines are read once more before the configuration, so a
`-dRELEASE` in the file selects the Release profile exactly as it does on the
command line (Release branch of `fpc.cfg`, `release` unit directory, no
`DEBUG`), and a command-line `-uRELEASE` still turns that off. Blank lines
and lines beginning with `#` are ignored. Relative paths are resolved from
the file's own directory, whatever the current directory is.

Windows command-line paths and environment variables support Unicode names
independently of the system ANSI code page. This does not change the encoding
of Pascal source files: use `{$CODEPAGE UTF8}` for UTF-8 source when needed.
On Windows, the `.mooncompiler` reader accepts UTF-8 with or without a BOM.
Other Windows config and response files (`@options.cfg`) retain the system
encoding by default; save them as UTF-8 with a BOM to use names outside that
encoding. Each included config file selects its own encoding by the same rules.
Options occupy whole lines, so spaces within a path do not require shell
quotes in these files.

```text
# Project.mooncompiler
-Fu./**
-Fu../Common
-Fu../Indy/**
-UaCustom.Name=LegacyName
-dSOME_FEATURE
```

| Line | Meaning |
|---|---|
| `-Fu<dir>` | one source directory |
| `-Fu<dir>/*` | the directory's immediate subdirectories (stock FPC) |
| `-Fu<dir>/**` | the directory and every subdirectory, any depth |
| `-Fi<dir>`, `-Fl<dir>`, `-Fo<dir>` | include, library and object directories, the same forms |
| `-Ua<Public.Name>=<RealUnit>` | an additional unit name for an existing unit |
| `-d<NAME>`, `-u<NAME>` | defines |
| `-FU<dir>`, `-FE<dir>` | unit output and executable directories, replacing the defaults above |

`**` takes every directory of the tree, whatever its name: `Lib`, `lib`,
`win64`, `debug`, `bin` or `backup` are directories like any other. Two
kinds stay out, recognized by what they are rather than by a name:

- a hidden directory, whose name starts with a dot (`.git` and the other
  version control, IDE and tool state), is not entered - as a shell's `**`
  does not enter it;
- build output, a directory that holds compiled units (`.ppu`) and no Pascal
  source (`.pas`, `.pp`, `.p`): the `units/<target>/<profile>` directories
  above, a Lazarus `lib/<cpu>-<os>`, any `-FU` directory. A unit found there
  instead of its source would be linked as it is, compiled with other
  options - the reason each profile has a unit directory of its own. Its
  subdirectories are still searched.

If a directory contains both source and PPU files, `**` searches its sources
but not its PPUs: an unrelated source in a build directory must not make an
old PPU from that directory win over the project's source. The current
profile's PPU is still found first in its output directory. A binary-only
unit distribution needs an explicit `-Fu<dir>`.

A directory comes before its subdirectories, and they follow in sorted
order (byte order of the names); a line of the project file and the command
line give the same order. A directory link or junction is walked like a
directory, except one that leads back into a directory it lies in, which
would repeat the tree inside itself. Two units of the same name in different
directories under one `**` produce a warning naming both files; the first in
order wins, as with any unit path, so an IDE backup copy kept in a
subdirectory next to its original (Lazarus `backup/`, Delphi `__recovery/`)
never replaces the original.

A tree is walked once, when the option is read. A directory in which the
walk saw no Pascal source and no compiled unit - data, logs, documentation,
another toolchain's build output, a directory of `.o`/`.a` files - is not
looked into for units (it is for object files and libraries), so a large
tree costs little more than its directories that hold units. Entries of
every search path are compared as the file system compares names: on Linux
`Src` and `src` are two directories, on Windows one.

Paths are searched in the order they are written - the command line's
first, then the project file's line by line, as on a command line - and all
of them before the toolchain's own. A project that carries its own mORMot in
one of its trees therefore builds against that mORMot; whatever it does not
have is found in the `mormot` directory next to the toolchain. The same holds
for the unit aliases of the toolchain's `fpc.cfg` (`-UaZLib=System.ZLib`):
they give way to a unit of the project of that name, as Delphi takes a
project's `ZLib.pas` before its unit scope `System` - a unit the search itself
takes from the project's paths, so a `ZLib.pas` in a `**` tree wins and an
old `zlib.ppu` left there does not. An alias of the project file or of the
command line holds even then, as Delphi's `-A` does.

The old manifest lines `source=`, `alias=` and `dependency=` are not options
and stop the build with an error naming the file and the line. Git
dependencies are the project's own business: clone them where the project
file points.

## mORMot

Toolchain units that build on mORMot - `System.Zip`, `System.Net.Mime`,
`System.Net.HttpClient` (`runtime/mormot`) and `Moon.Diagnostics` with its
ZIP/HTTP backends (`runtime/reporting`) - are compiled into each project
against the mORMot the project sees: `mormot.core.zip`, `mormot.net.client`
and the rest come from the project's trees or from the `mormot` directory
next to the toolchain, the same way as every other unit. Both runtime
directories are always on the unit path, so `uses System.Zip;` is all an
application needs. There is no second mORMot and no build feature to switch
on.

The units were written and qualified against
[`Moonbot-Tech/MoonORMot`](https://github.com/Moonbot-Tech/MoonORMot). Each
of them names `MoonORMot.Need` in its uses, and that unit compares
`MOONORMOT_VERSION` of the mORMot found on the path with the version in
`runtime/moonormot.need.inc`:

- older: the build stops with `MoonORMot is older than this toolchain
  requires: run git pull in the mormot directory next to the toolchain`;
- equal or newer: accepted; the number is a floor, not a pin;
- a mORMot without the constant (upstream, or a fork): accepted as it is.

How the floor is kept on the tip of MoonORMot `main`, together with the
qualification pin and the bundled memory manager, is in "MoonORMot records"
of [Testing](TESTING.md).

A project's own mORMot - on the command line, in the project file or in one
of its `**` trees - builds like the one next to the toolchain: `fpc` reads
its configuration, and the toolchain's units are on the path. A build that
leaves the product configuration out reads `moon-base.cfg` instead
(`-n @moon-base.cfg`, as most qualification gates do), which names the
installed units as a whole and the bundled memory manager. A build that
reads no configuration at all names all of it itself, the RTL's unit
directory included, and mORMot needs units of the toolchain's packages:
`variants` of `rtl-objpas`, and under this compiler `System.ZLib` of
`vcl-compat`, through which `mormot.lib.z` compresses
([One zlib in a program](COMPILER_FIXES.md#one-zlib-in-a-program)). Such a
build takes the installed units as a whole (`units/<target>/*`), not a list
of packages: a list without `vcl-compat` stops at
`mormot.lib.z.pas(72,3) Fatal: Can't find unit System.ZLib used by
mormot.lib.z`.

## What the Configuration Guarantees

- only `toolchain` is used, never a system FPC: the product compiler reads
  the `fpc.cfg` next to its own binary and nothing from the current
  directory, the home directory or `/etc` (`-n`, `@file` and
  `PPC_CONFIG_PATH` remain for qualification);
- Win64 and Linux receive one Delphi/Unicode application ABI;
- Debug, Release, and diagnostic MM have separate unit directories;
- the executable does not depend on manual `-Fu` or runtime-unit ordering;
- `moon-base.cfg` carries the audited toolchain paths, the parser switches,
  the ABI defines and the pinned memory manager, and no directive; the
  qualification gates read exactly this file with `-n @moon-base.cfg`. No
  line names a host path: on Linux the compiler finds the libgcc directory
  that every program links against by itself at link time
  (`/usr/lib/gcc/<triplet>/<version>` and the `lib64` variant, newest
  first), so the toolchain works wherever it is unpacked;
- `fpc.cfg` includes `moon-base.cfg` and adds the application profile: Delphi
  mode switches, the `System.*` namespace and aliases, the runtime and
  `mormot` paths, line information, the checks, and the
  `#IFDEF RELEASE` block;
- the RTL and packages carry the profile declared in `scripts/rtl-profile.txt`
  (`-O3` with `CODEALIGN`, the code placement draft of the internal assembler
  off, line information): the driver records
  the exact options in `toolchain/profile.txt`, and
  `qualification/build-driver/rtl_profile_gate.py` rebuilds witness units
  with them and requires the installed objects byte for byte.

`qualification/build-driver/config_contract_gate.py` parses `moon-base.cfg`
and the IDE configuration exactly as the compiler does, requires the audited
line set in order, rejects every directive, and checks that the product
compiler keeps its internal assembler with this configuration and locks down
the command-line boundary: `-ap` keeps the internal writer, while `-ao`,
`-Aas` and `-al -Aas` select the external assembler and the compiler warns
that the object is not the one its internal assembler writes; the compiler also defines
`NOPATCHRTL` by itself, and `-uNOPATCHRTL` still switches it off.
`qualification/build-driver/product_config_gate.py` checks `fpc.cfg` by its
result, as a black box from a foreign directory: poisoned configurations in
the current and home directories are ignored; Debug and Release build from
their own unit directories and both the program and a unit compiled with it
report `SizeOf(Char)`, the mode, `UNICODE`, the memory manager,
`DEBUG`/`RELEASE` and the assertion state as expected, with the two objects
of the unit different and a Debug build after a Release build still Debug;
a project file with relative paths works from another directory and a
`-dRELEASE` in it selects the Release profile (overridden by `-uRELEASE`);
`-Fu./**` warns on a duplicate unit and walks a tree of 4301 directories;
`-Fu../Indy/**` finds units under Indy's `Lib/`, and a project with its own
mORMot in its tree builds against its own `lib/` as well; a Release build
after a Debug one does not take the Debug unit through `**`, from the
default unit directories or from `-FU` directories of any name; one tree
gives the same order from the project file and from the command line, a
hidden directory is not entered, `Src/` and `src/` are both searched on
Linux, a directory link is followed but not back into its own tree, and no
unit is looked for in a directory where the walk saw no unit file;
the version macros are defined, and a pin from a project file is rejected.

Toolchain and Lazarus installation are described in [Setup](SETUP.md); test
profiles are in [Testing](TESTING.md).
