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

The bundled `runtime/mm/mormot.core.fpcx64mm.pas` is the exact pinned unit. An
MM from an external mORMot checkout cannot replace it through `-Fu` ordering.

`qualification/vendor/mormot-product` is a versioned test fixture. A newer
mORMot is fetched through the manifest as a separate corpus. Updating the
dependency, adapting the corpus, and changing the compiler or RTL are separate
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
