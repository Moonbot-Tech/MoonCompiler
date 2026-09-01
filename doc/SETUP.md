# Installation

MoonCompiler can be installed from a ready-made toolchain archive or built from
source with the standard FPC 3.2.2 bootstrap compiler. Both paths install the
same two profiles locally in `.moonbot/toolchain`; neither replaces the system
FPC.

## Ready-made Toolchain Archives

Clone the repository, then download the archive for your platform from
[GitHub Releases](https://github.com/Moonbot-Tech/MoonCompiler/releases). The
repository supplies the build driver, project profile, and pinned MM source;
the archive supplies the already-built compiler, RTL, packages, and tools.

Linux x86-64:

```bash
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
./build toolchain ~/Downloads/mooncompiler-toolchain-v1.0.0-linux-x86-64.tar.gz
```

Win64 x86-64 PowerShell:

```powershell
git clone https://github.com/Moonbot-Tech/MoonCompiler.git
Set-Location MoonCompiler
.\build.ps1 toolchain $HOME\Downloads\mooncompiler-toolchain-v1.0.0-win64.zip
```

The installer validates the target platform, extracts into a staging
directory, regenerates both `fpc.cfg` files for the actual checkout path, and
only then replaces the previous toolchain. FPC 3.2.2, GNU Make, and binutils
are not required when installing a release archive.

## Build from Source

Building from source is useful for compiler development or when no release
archive matches the current commit.

### Linux x86-64

Ubuntu/Debian requires Git, GNU Make, binutils, and FPC 3.2.2:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends \
  git make binutils fp-compiler-3.2.2 coreutils util-linux
test "$(fpc -iV)" = 3.2.2

git clone https://github.com/Moonbot-Tech/MoonCompiler.git
cd MoonCompiler
./build compiler
```

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

## Installed Profiles

The build installs two isolated profiles:

| Directory | Purpose |
|---|---|
| `.moonbot/toolchain` | Delphi-compatible applications: Unicode RTL, product runtime, and bundled MM |
| `.moonbot/toolchain/ide` | Lazarus, LCL, and ordinary FPC projects with the original FPC string ABI |

The new toolchain is published transactionally. A failed rebuild does not
replace the last working installation; avoid building an application while the
toolchain itself is being replaced.

After bootstrap, applications are compiled only with the local compiler:

```bash
./build examples/hello.dpr debug
./build examples/hello.dpr release
```

```powershell
.\build.ps1 examples\hello.dpr debug
.\build.ps1 examples\hello.dpr release
```

No runtime support units are needed in the `.dpr`. The compiler itself adds the
bundled MM, threading, Unicode conversion manager, and monitor support in the
correct order. Plain `String` has the Delphi 12.2 `UnicodeString` ABI on both
platforms. Profiles, the manifest, and diagnostic MM are described in
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
pinned Lazarus revision, builds `bigide` with `-O3`, and creates a separate
configuration in `.moonbot/lazarus-config`. The system Lazarus installation and
user configuration are not changed.

An ordinary LCL project builds with the IDE's green button. A Delphi-compatible
application is edited and debugged in Lazarus, but its product build is run by
`build`/`build.ps1`: only this driver applies the manifest, namespaces, Unicode
RTL, and product runtime as one profile.

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
  checkout was switched manually; delete only `.moonbot/lazarus` and run again;
- runtime error 235 at the first `TMonitor.Enter` means the program was built
  in the vanilla profile or without the product driver;
- `Unit cmem would replace the bundled product memory manager` — remove manual
  `cmem` or use the vanilla, Valgrind, or ASan profile;
- `cached dependency is not clean` — a pinned Git dependency in
  `.moonbot/dependencies` has local changes;
- `Win64 binutil is missing` — the FPC bootstrap distribution is incomplete.

Installation verification commands are in [Testing](TESTING.md).
