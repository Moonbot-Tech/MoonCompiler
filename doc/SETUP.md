# Installation

MoonCompiler is installed from a ready-made toolchain archive or built from
source with the standard FPC 3.2.2 bootstrap compiler. Either way the result
is one directory, `toolchain`, with MoonORMot in a directory named `mormot`
next to it:

```text
<root>/toolchain    the compiler, RTL, packages, tools, runtime units, fpc.cfg
<root>/mormot       a clone of https://github.com/Moonbot-Tech/MoonORMot (branch main)
```

Neither replaces the system FPC. The toolchain's `fpc` is the product: it
reads only its own configuration, and applications are built with it from
any directory (see [Project Build](PROJECT_BUILD.md)).

## Ready-made Toolchain Archives

Download the archive for your platform from
[GitHub Releases](https://github.com/Moonbot-Tech/MoonCompiler/releases),
unpack it into a directory named `toolchain`, and put MoonORMot next to it.
No bootstrap compiler, no clone of this repository and no Python are needed;
Git is needed for the MoonORMot clone (without Git, download the `main`
branch of MoonORMot as a zip from GitHub and unpack it as `mormot`).

Linux x86-64 (`hello.dpr` is any program, for example the one in the Quick
Start of the [README](../README.md) or `examples/hello.dpr` of this
repository):

```bash
mkdir -p ~/moon/toolchain && cd ~/moon
tar -xzf ~/Downloads/mooncompiler-toolchain-v1.0.0-linux-x86-64.tar.gz -C toolchain
git clone https://github.com/Moonbot-Tech/MoonORMot mormot
toolchain/bin/fpc hello.dpr && ./hello
```

Win64 x86-64 PowerShell:

```powershell
New-Item -ItemType Directory -Force C:\Moon | Set-Location
Expand-Archive $HOME\Downloads\mooncompiler-toolchain-v1.0.0-win64.zip -DestinationPath toolchain
git clone https://github.com/Moonbot-Tech/MoonORMot mormot
toolchain\bin\x86_64-win64\fpc.exe hello.dpr; .\hello.exe
```

The archive is complete: the compiler, the Unicode RTL and packages, the
tools, the runtime units (`toolchain/runtime`) and both configuration files
with paths relative to the compiler's own directory, so the toolchain works
from wherever it is unpacked. MoonORMot is deliberately not inside the
archive: the runtime units compile against whatever is in `mormot`, and
`git pull` there is how it is updated (the units refuse a MoonORMot older
than the one they were qualified with, and say so).

On Linux every program links `libgcc_s` (the RTL's PSABI exception
handling), and `ld` finds the unversioned `libgcc_s.so` only in gcc's own
directory. The configuration names no such host path: the compiler finds
`/usr/lib/gcc/<triplet>/<version>` (or the `lib64` variant) by itself at link
time, so the archive works on any distribution that has gcc installed.
Programs that use RTTI `Invoke` (`System.JSON.Serializers` does) also link
`libffi`, and `ld` needs its unversioned `libffi.so`: on Debian/Ubuntu that is
`libffi-dev`, the runtime `libffi8` alone is not enough.

The archive can also be installed from a clone of this repository with the
driver:

```bash
sudo apt-get install --no-install-recommends git gcc libffi-dev
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
./build toolchain ~/Downloads/mooncompiler-toolchain-v1.0.0-linux-x86-64.tar.gz
```

```powershell
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
Set-Location MoonCompiler
.\build.ps1 toolchain $HOME\Downloads\mooncompiler-toolchain-v1.0.0-win64.zip
```

The driver validates the target platform, extracts into a staging directory
and only then replaces the previous `toolchain`; it renders the IDE
profile's configuration for the clone (that file names its toolchain by an
absolute path, see below). It clones MoonORMot into `mormot` next to the
toolchain when that directory does not exist yet, and never touches an
existing one. FPC 3.2.2, GNU Make and binutils are not required when
installing a release archive.

## Build from Source

Building from source is useful for compiler development or when no release
archive matches the current commit.

### Linux x86-64

Ubuntu/Debian requires Git, GNU Make, binutils, gcc and FPC 3.2.2, and the
RTL tests need `libffi-dev` (RTTI `Invoke`, see above):

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends \
  git make binutils gcc fp-compiler-3.2.2 coreutils util-linux libffi-dev
test "$(fpc -iV)" = 3.2.2

git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
./build compiler
```

`gcc` compiles nothing here, but every Linux program's link step needs its
`libgcc_s`, which the compiler finds in gcc's directory by itself.

If the bootstrap compiler is not on `PATH`:

```bash
MOONBOT_BOOTSTRAP_FPC=/path/to/fpc ./build compiler
```

Python 3 is not required to build the compiler or applications. It is needed
only for qualification scripts.

### Win64 x86-64

Git, PowerShell, and the Win64 FPC 3.2.2 distribution are required. Next to
`fpc.exe`, the distribution must include GNU `make.exe`, `fpcmkcfg.exe`, and the
target binutils `x86_64-win64-*.exe`.

```powershell
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
Set-Location MoonCompiler
.\build.ps1 compiler -Bootstrap C:\FPC\3.2.2\bin\i386-win32\fpc.exe
```

If `fpc.exe` is already on `PATH`, `-Bootstrap` is unnecessary. If `make.exe`
is installed separately, pass its path with `-Make` or the `MOONBOT_MAKE`
environment variable.

The repository includes a helper that downloads the official combined Win32
and Win64 FPC distribution, verifies its checksum, and installs a complete
bootstrap into an isolated directory:

```powershell
$Bootstrap = .\scripts\Install-FpcBootstrap.ps1
.\build.ps1 compiler -Bootstrap $Bootstrap
```

The combined distribution matters: a Win32-only installation can compile the
bootstrap stages but does not contain the Win64 target binutils needed by the
published toolchain.

Python 3 is needed only for qualification. If it is not on `PATH`, set its full
path in `$env:PYTHON`.

### What `build compiler` leaves behind

`build compiler` installs the toolchain into `toolchain` inside the clone,
copies `runtime/` into it, and clones MoonORMot into `mormot` next to it if
that directory does not exist (an existing directory, a symbolic link or a
junction to your own clone is left alone; without Git or network it prints a
warning and the runtime units over mORMot are simply unavailable until
`mormot` is there). Both directories are ignored by Git.

## Installed Profiles

The build installs two isolated profiles:

| Directory | Purpose |
|---|---|
| `toolchain` | Delphi-compatible applications: Unicode RTL, product runtime, and bundled MM |
| `toolchain/ide` | Lazarus, LCL, and ordinary FPC projects with the original FPC string ABI |

The product profile has two configuration files next to the compiler
(`toolchain/bin/x86_64-win64` on Win64, `toolchain/etc` on Linux):

| File | Holds | Read by |
|---|---|---|
| `moon-base.cfg` | the toolchain paths, the parser switches, the ABI defines, the pinned memory manager; no directive, no host path | the qualification gates (`-n @moon-base.cfg`) |
| `fpc.cfg` | `#INCLUDE moon-base.cfg` plus the application profile: Delphi mode, `System.*` namespace and aliases, the runtime and `mormot` paths, line information, checks, the `#IFDEF RELEASE` block | `fpc` for every application build |

Every path is written from `$FPCBINDIR`, the directory of the running
compiler, which is what makes the archive relocatable. The IDE profile's
`fpc.cfg` (`toolchain/ide`) is the exception: the qualification gates run
the product compiler with that configuration, so it names the IDE toolchain
by an absolute path, and the drivers render it for the clone at build and at
install; in a raw unpack it still names the build machine's path, which
matters only to Lazarus and compiler development, both of which start from a
clone.
`qualification/build-driver/config_contract_gate.py` reads `moon-base.cfg`
and the IDE configuration back the way the compiler does and fails on any
line outside the audited set or on any directive;
`qualification/build-driver/product_config_gate.py` checks `fpc.cfg` by its
result from a foreign directory. Qualification and release CI run both gates
on freshly built and release-archive toolchains.

The product profile's RTL and packages are compiled with the optimisation
profile declared in `scripts/rtl-profile.txt` (`-O3` with `CODEALIGN`, the
code placement draft of the internal assembler off, plus line information);
the IDE profile keeps
`-O2`. The driver records the exact options in `toolchain/profile.txt`
(the archive carries the record too), and
`python qualification/build-driver/rtl_profile_gate.py` rebuilds witness
units with them and requires the installed objects byte for byte.

The new toolchain is published transactionally. A failed rebuild does not
replace the last working installation; avoid building an application while the
toolchain itself is being replaced.

After installation, applications are compiled only with the local compiler:

```bash
toolchain/bin/fpc examples/hello.dpr
toolchain/bin/fpc -dRELEASE examples/hello.dpr
```

```powershell
toolchain\bin\x86_64-win64\fpc.exe examples\hello.dpr
toolchain\bin\x86_64-win64\fpc.exe -dRELEASE examples\hello.dpr
```

No runtime support units are needed in the `.dpr`. The compiler itself adds the
bundled MM, threading, Unicode conversion manager, and monitor support in the
correct order. Plain `String` has the Delphi 12.2 `UnicodeString` ABI on both
platforms. Profiles, the project file, and the diagnostic MM are described in
[Project Build](PROJECT_BUILD.md).

## Lazarus

MoonCompiler provides a pinned Lazarus version and a separate profile so the
IDE/LCL cannot mix with the Unicode ABI of the application toolchain.

Win64:

```powershell
.\lazarus.ps1
```

Linux x86-64:

```bash
sudo apt-get install libgtk-3-dev
./lazarus
```

On the first run, the driver builds the compiler if needed, checks out the
pinned Lazarus revision in `lazarus-src`, builds `bigide` with `-O3`, and creates
a separate configuration in `lazarus-config`. The system Lazarus installation and
user configuration are not changed.

An ordinary LCL project builds with the IDE's green button. A Delphi-compatible
application is edited and debugged in Lazarus, and its product build is the
toolchain's `fpc` with the project's `.mooncompiler` file next to the `.dpr`:
the same profile, namespaces, Unicode RTL and product runtime as everywhere
else, with no second set of settings inside the IDE.

The repository pins one compatible Lazarus revision. Do not update the
generated checkout with `git pull`: changing the IDE revision is a separate,
validated MoonCompiler update.

## Common Errors

- `bootstrap compiler must be FPC 3.2.2` — a bootstrap compiler of another
  version was selected;
- `the archive is not a complete ... MoonCompiler toolchain` — the archive is
  damaged or belongs to the other platform;
- `GNU make.exe was not found` — pass the path with `-Make` or `MOONBOT_MAKE`;
- `MoonCompiler is not built` — run `build compiler` first;
- `the IDE profile is missing` — rebuild the compiler with the current driver;
- `managed Lazarus checkout is not at the supported commit` — the generated
  checkout was switched manually; delete only `lazarus-src` and run again;
- `Can't find unit mormot.core.zip` (or another `mormot.*` unit) while
  `System.Zip`, `System.Net.HttpClient` or `Moon.Diagnostics` is used — there
  is no `mormot` directory next to `toolchain`; clone MoonORMot there;
- `MoonORMot is older than this toolchain requires` — `git pull` in the
  `mormot` directory (or in the project's own mORMot tree);
- runtime error 235 at the first `TMonitor.Enter` means the program was built
  in the vanilla profile or with a configuration other than the toolchain's;
- `Unit cmem would replace the bundled product memory manager` — remove manual
  `cmem` or use the vanilla, Valgrind, or ASan profile;
- `Illegal parameter: source=...` from a `.mooncompiler` file — the file uses
  the retired manifest syntax; it is a file of compiler options now
  ([Project Build](PROJECT_BUILD.md));
- `Win64 binutil is missing` — the FPC bootstrap distribution is incomplete;
- on Linux, `cannot find -lgcc_s` at link time — no `libgcc_s.so` under
  `/usr/lib/gcc` or `/usr/lib64/gcc`; install the distribution's gcc
  package;
- on Linux, `cannot find -lffi` at link time — the program uses RTTI `Invoke`
  and the unversioned `libffi.so` is missing; install `libffi-dev` (Debian/Ubuntu).

Installation verification commands are in [Testing](TESTING.md).
