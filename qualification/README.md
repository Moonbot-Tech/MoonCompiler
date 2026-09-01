# MoonCompiler Qualification

This tree proves one MoonCompiler revision as a complete product toolchain:
compiler, Unicode RTL, packages, bundled memory manager, build profiles, and
the generated code on Win64 and Linux x86-64. It contains several independent
systems because a compiler can pass isolated language tests and still fail
when the same forms meet in a large method, across a PPU boundary, during
exception cleanup, or under concurrent managed lifetime.

## Named test systems

| System | What it proves |
|---|---|
| [**Focused regressions**](suite/docs/TESTS.md#regression-corpus) | Minimal reproductions of repaired compiler and RTL defects, with boundary forms and independent oracles. The suite also imports pinned upstream and issue-tracker cases that belong to the supported product surface. |
| [**Mega**](suite/tests/mega/) | A large hand-written mix of language, RTL, lifetime, exception, threading, and optimizer forms in one program. |
| [**Omni**](suite/tests/mega/omni/) | Generated cross-products of types, operators, consumers, namespaces, PPU boundaries, seeds, and optimization modes. Omni and integrated Mega are the two central programs of the Forms gate. |
| [**Devil**](suite/tests/devil/README.md) | Generated expressions and execution shapes checked for semantics, ABI, managed lifetime, determinism, and Delphi differential behavior. Unknown findings fail closed. |
| [**Chimera**](suite/tests/chimera/README.md) | Whole and split compositions transferred from MoonBot, Arbitrage, mORMot, and other Pascal projects. Comparing the whole form with its decomposed form catches size- and composition-dependent miscompiles. |
| [**Resident**](suite/tests/resident/README.md) | A sustained multithreaded program that mixes runtime services, collections, crypto, compression, exceptions, and managed state while checking every stage digest. |
| [**Plant**](suite/tests/plant/README.md) | Application topology: unit initialization order, registries, factories, callbacks, interfaces, dependency cycles, and optimizer-switch combinations. |
| [**RTL-test**](../RTL-test/) | API and runtime semantics for ownership, strings and streams, containers, tasks, exceptions, RTTI, and threading. |
| [**mORMot**](suite/docs/TESTS.md#mormot) | Two distinct real-library gates: the established product dependency and the current public mORMot corpus, including Linux, Unicode, RTTI, networking, crypto, and MM integration. |
| [**Memory Manager**](suite/tests/memory/README.md) | Small, medium, and large allocation paths; realloc; contention; cross-thread ownership; shutdown; diagnostics; and a fail-closed leak census. |
| [**Optimizer Core**](../doc/OPTIMIZER.md) | Dedicated correctness and scaling gates for effects, CSE, LICM, address reuse, register-sensitive forms, code placement, and deterministic optimized PPUs. |
| [**Pulse**](performance/README.md) / [**Heartbeat**](performance/heartbeat/) | Correctness-digested performance qualification. Pulse separates compiler, RTL, MM, and algorithm families; Heartbeat combines representative server and trading hot paths in one application-shaped workload. |
| [**Qualification Benchmark**](suite/tests/benchmark/README.md) | A compact Linux comparison of integer, floating-point, byte/UTF-8, `Move`, and managed-allocation workloads after an independent semantic oracle passes. |
| [**Lazarus**](../doc/SETUP.md#lazarus) | The pinned IDE/LCL build using the isolated ordinary-FPC ABI profile, separate from the Delphi-compatible product profile. |

The executable sources are indexed in [suite/tests](suite/tests/README.md).
The complete form, runner, and oracle inventory is in
[MoonCompiler Test System](suite/docs/TESTS.md).

## Supporting contracts

| Directory | Contract |
|---|---|
| [`build-driver`](build-driver/) | Project profiles, version identity, dependency isolation, and transactional toolchain replacement. |
| [`pinned-unit`](pinned-unit/README.md) | Automatic runtime-unit order and the exact bundled MM source. |
| [`memory-manager`](memory-manager/README.md) | Product MM profile selection and arena-layout contracts. |
| [`optimizer-core`](optimizer-core/) | Focused optimizer gates and sabotage controls. |
| [`effect-observe`](effect-observe/README.md) | The effect model used by transformations, including calls, aliases, exceptions, and managed state. |
| [`win-stack-default`](win-stack-default/) | Win64 process-stack defaults and explicit override behavior. |
| [`performance`](performance/README.md) | Pulse sources, workloads, measurement tools, and published evidence. |
| [`suite`](suite/README.md) | Cross-platform runners, corpora, manifests, and release ordering. |

## Running the right amount

Build the product toolchain first:

```bash
./build compiler
```

```powershell
.\build.ps1 compiler
```

For ordinary compiler or RTL work, begin with the exact regression and then
use the short cross-subsystem route:

```text
python qualification/suite/scripts/run_devil_targeted.py light
python qualification/suite/scripts/run_devil_targeted.py impact --areas optimizer-codegen
```

`list` prints the available impact areas. The focused, Light, and impact routes
are described in [Testing](../doc/TESTING.md); platform commands are in the
[suite README](suite/README.md).

Full release qualification is deliberately not hidden behind one opaque
command. It combines Win64 and Linux gates, Delphi oracles, both mORMot lines,
the heavy MM matrix, Lazarus, and performance evidence in the explicit order
recorded in [Testing](../doc/TESTING.md#full-release-qualification). Public CI
is the clean-machine barrier for every pushed revision; it is not presented as
a substitute for the external Delphi and heavy release layers.

## Verdict rule

Compilation alone proves only API availability. Runtime tests require an
external source of truth: Delphi 12.2, a specification, a mathematical
invariant, a reference implementation, or an independently computed digest.
Performance results are admitted only after the semantic oracle matches.

Known supported-boundary deviations are versioned in
[Known Issues](../doc/KNOWN_ISSUES.md). A new result that is neither an expected
pass nor an accepted deviation is a finding; runners must not silently update
their oracle to make it green.
