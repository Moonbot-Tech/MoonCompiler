# Dynamic Packages (Win64)

MoonCompiler builds Delphi-style run-time packages on Win64: a `package`
source with `requires` and `contains` clauses produces a DLL whose classes,
VMTs, RTTI, unit initialization and memory manager are shared with the host
program and with the other packages loaded into the process. This is the
structure of large Delphi applications split into a common BPL (base forms,
data-access components) and business BPLs that inherit from it and share its
object instances.

Linux x86-64 is not covered: `tf_supports_packages` is set for the Win64
target only.

## Files

| Delphi | MoonCompiler | Content |
|---|---|---|
| `.dpk` | `.dpk` / `.fpk` | package source (`package`, `requires`, `contains`) |
| `.bpl` | `.fpl` | package library (a PE DLL) |
| `.dcp` | `.fcp` | package symbol file read by `requires` and `-FP` |

A package library has its own extension so that a tool scanning a directory
can tell installable packages from plain DLLs without opening them.

`{$LIBSUFFIX}` and `{$LIBPREFIX}` version the library name as in Delphi
(`rtl290.bpl`): `{$LIBSUFFIX '42'}` in `Base.dpk` yields `Base42.fpl`, still
with the package extension, next to `Base.fcp`. `requires Base` keeps the
package name; a package or host that requires it imports from `Base42.fpl`,
so packages of different versions can sit side by side.

## Building

The order is part of the contract:

1. Compile the units a package contains as ordinary units, **without** `-FP`.
2. Compile the package. `requires` imports from the named packages; the result
   is `<name>.fpl` plus `<name>.fcp`.
3. Build the host with `-FP<name>` for every package it links against, e.g.
   `-FPrtlpkg -FPCommonPkg`.

The package symbol search path is read from the configuration file (`-Fp`
there); give each package directory in the project's `fpc.cfg`.

A host that uses a unit contained in a package must also consume that package.
Otherwise it links its own copy of the unit, the process then holds two copies
of each class, and a cross-module `is` silently returns `False`.

Each package should get its own image base (`-WB`), as with Delphi.

## Package kinds

`{$DESIGNONLY}` and `{$RUNONLY}` are accepted and stored in the `.fcp`.
Declaring both is error 13030; linking a design-only package into a program is
error 13031. The library exports `PACKAGEFLAGS` (bit 0 design-only, bit 1
run-only) and, unless run-only, a `REGPROCS` table of the contained units'
`Register` procedures, for a design-time host.

## Run-time loading

`SysUtils` provides `LoadPackage`, `UnloadPackage`, `InitializePackage` and
`FinalizePackage`. Package units are initialized from the exported
`INITFINAL` table. `UnloadPackage` calls the module-unload hooks; `Classes`
registers `UnRegisterModuleClasses` there, which removes the classes,
aliases and component-palette entries the leaving image registered, so
`GetClass` stays safe after a package that did not unregister its classes is
unloaded.

The unload contract is Delphi's: nothing may keep a reference into an
unloaded image. A class registered by the package, a string constant from its
data section or a method pointer into its code that outlives `UnloadPackage`
is a use-after-unmap in the program, not in the toolchain.

## Runtime prefix

A package does not take the product runtime prefix (bundled memory manager,
monitor). Those are process-wide: the host program installs them once and
every package shares them through the `System` unit of the RTL package it
requires. A package built without `requires` links the RTL statically and has
its own heap, like any DLL.

## ABI

`tf_supports_packages` is a target-wide ABI switch, not a project option. With
it, the compiler addresses data that may live in another module through
`$indirect` slots, so the RTL and all packages are built in that mode. Programs
that do not use packages are built the same way.

## Qualification

`qualification/dynamic-packages/run.ps1 -RunId <id>` builds and runs six
stages: import from a required package, cross-package inheritance and
`is`/`as`, unit initialization in a load-time package, `LoadPackage` /
`GetClass` / `UnloadPackage` including the unload hooks, and package kinds,
`PACKAGEFLAGS`, design-time registration and the two rejections; versioned
library names (`LIBSUFFIX`/`LIBPREFIX`) at load time and at run time.

## Limitations

See [Known Issues](KNOWN_ISSUES.md#dynamic-packages).
