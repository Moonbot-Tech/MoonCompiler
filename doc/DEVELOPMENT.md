# Developing MoonCompiler

MoonCompiler accepts changes by root cause, not by the pass/fail status of an
individual test. This document defines requirements for compiler, RTL, runtime,
and MM patches.

## One Intent, One Commit

A complete commit contains:

1. the first violated invariant;
2. the minimal causal fix;
3. a permanent regression test with an independent oracle;
4. neighbouring negative controls;
5. a short explanation of the validation result.

Fold corrective commits into their original intent before publishing. File
moves, formatting, and generated-evidence updates are not mixed with semantic
changes.

## What Is Not a Fix

- disabling AUTOINLINE, LICM, range checking, or an entire optimization level;
- a cast or workaround in an application project instead of a compiler/RTL fix;
- updating expected output with MoonCompiler's own answer;
- adding an allow-list without proof that the form is outside the supported
  contract;
- speeding up a composite case without understanding the work that disappeared;
- a platform branch that duplicates a common invariant without an ABI reason.

A Known Issue is permitted only for a precisely described observable boundary
that cannot be safely fixed in the current release. A correctness defect in
supported code remains a blocker; a proven optimization of minor importance may
be placed in the [Backlog](BACKLOG.md).

## How to Find the Minimal Fix

The causal chain must be closed from the source form to the observable result:

```text
parser/type system → AST → optimizer → target lowering → RTL/runtime → result
```

First compare the Delphi oracle, optimization levels, and targets. Then
minimize the first point of divergence and read the producer and every consumer
of the flag, type, or ABI being changed. Before editing, check whether an
existing general mechanism should be fixed instead of adding a second branch.

After the final change, reread the complete diff. Every newly added check,
temporary, branch, and abstraction must be necessary; this is especially
important on compiler and runtime hot paths.

## Test Scope

Choose validation in proportion to risk:

- a focused repro — always;
- Light — after any compiler/RTL/runtime fix;
- impact-scoped — for the affected areas;
- both platforms — for shared lowering, ABI, exceptions, threading, and MM;
- Full — before a release point or after a broad architectural series.

Exact commands and the system map are in [Testing](TESTING.md). A new test must
fail closed: it must distinguish “nothing ran” from PASS.

## Fast Compiler Iteration

After the full toolchain has been installed once, rebuild only the current
compiler sources with:

```powershell
.\build.ps1 backend-dev
```

```bash
./build backend-dev
```

This command always uses the ordinary FPC-ABI IDE profile, rebuilds every
compiler unit in an isolated staging tree, rejects a product-ABI configuration,
and smoke-tests the resulting backend before publishing it atomically under
`dev-backend`. The output directory is ignored by Git; the command is
versioned because every clean checkout and automated build needs the same safe
path. `provenance.txt` records the source fingerprint, Git state, parent
compiler/config hashes, and resulting backend hash.

Use the resulting `ppcx64` directly with the product or IDE `fpc.cfg` required
by the test. Do not copy it into `compiler`, and do not reuse compiler-unit PPUs
from a different profile.

## Product Runtime

A normal program contains no runtime support prefix in `uses`. The compiler
automatically includes:

- Win64: bundled MM → `fpwinmonitor`;
- Linux x86-64: bundled MM → `cthreads` → `cwstring` → `fpmonitor`.

Changing this order affects startup, allocator ownership, Unicode, threads,
monitors, and shutdown, so it requires a separate platform-contract gate. The
explicit `-dMOONCOMPILER_VANILLA_RUNTIME` opt-out and Valgrind/ASan with `cmem`
must remain operational: the product runtime is the default, not a hidden
inability to build a control configuration.

The product-profile `String`/`Char` use the Delphi Unicode ABI. The IDE/Lazarus
build in a separate, normal FPC-ABI profile; mixing PPUs from the two profiles
is forbidden.

## Memory Manager and External Corpora

The repository holds three records of MoonORMot that must all name the tip
of `Moonbot-Tech/MoonORMot` `main`: the qualification pin in
`runner_manifest.json`, the version floor in `runtime/moonormot.need.inc`
(compiled into every project through `runtime/mormot/MoonORMot.Need.pas`),
and the bundled `runtime/mm/mormot.core.fpcx64mm.pas`, a byte-for-byte copy
(apart from line endings) of the pin's memory manager. An MM from an external
mORMot checkout cannot replace the bundled one through `-Fu` ordering.
Qualification fetches MoonORMot, requires the pin to equal remote `main`,
the floor to equal the version on the pin and the copy to equal the pin's
file; a clean runner-managed checkout advances automatically, while local
edits or an origin mismatch stop qualification.

A change to MoonORMot is pushed to its `main` first (the MoonORMot repository
raises its own version number when a push forgets to), then
`scripts/sync-moonormot.py` moves the three records here and the mORMot and
memory-manager gates run; `.github/workflows/moonormot-sync.yml` does the
same once a day. A memory-manager repair is made in MoonORMot, never only in
the bundled copy: the script refuses to overwrite a copy that differs from
the old pin's file.

MoonORMot and the newer public mORMot compiler corpus are fetched through the
manifest into ignored `.qualification/deps` checkouts; applications build
against the separate `mormot` clone next to `toolchain`. Updating a
dependency, adapting a corpus, and changing the compiler or RTL are separate
intents and are not combined into one patch.

For an upstream PR, separate independent root causes and retain the original
license headers. Do not present a product-specific profile as a universal
upstream improvement without symmetric controls.

## Public Documentation

`doc` contains only current user-facing and technical contracts. Working
journals, audit rounds, machine-specific paths, temporary hashes, and rejected
hypotheses stay in local `doc-int` and are not published.

A new public capability must appear at least in README/Setup or Project Build;
a new limitation belongs in Known Issues; a deferred optimization belongs in the
Backlog; a proven fix belongs in Compiler Fixes.
