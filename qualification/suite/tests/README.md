# Qualification Test Programs

This directory contains the executable inputs of the MoonCompiler
qualification suite. It is organized by what each layer proves, not by Pascal
language feature. Run these programs through the scripts in [`../scripts`](../scripts)
or the top-level `runner.py`; compiling an arbitrary file directly does not
reproduce the product profile or its oracle.

| Directory | Purpose |
|---|---|
| [`smoke`](smoke) | focused compiler/RTL regressions and the product build-driver smoke test |
| [`mega`](mega) | broad intertwined language, runtime, lifetime, and threading forms; also contains Omni and integrated Mega |
| [`devil`](devil/README.md) | generated differential matrices, ABI and optimizer effects, plus the finding registry |
| [`plant`](plant) | application topology: initialization order, callbacks, registries, interfaces, and unit cycles |
| [`chimera`](chimera/README.md) | whole and split compositions transferred from production Pascal applications |
| [`resident`](resident/README.md) | long-lived multithreaded composition of runtime, algorithms, managed values, and optimizer forms |
| [`rtl-api`](rtl-api/SURFACE.md) | selected Delphi 12.2 RTL declarations and basic semantics used by the product |
| [`rtti`](rtti) | RTTI catalog, transitive dependencies, PPU boundaries, and runtime invocation |
| [`memory`](memory) | bundled-MM boundaries, contention, finalization, diagnostics, and stress workloads |
| [`optimizer-core`](optimizer-core) | cross-unit and PPU contracts for LICM, ADDRESSGVN, and register allocation |
| [`compiler-crash`](compiler-crash) | permanently retained minimized compiler-crash reproductions |
| [`corpus-extra`](corpus-extra/README.md) | neighbouring upstream controls outside the main generated corpus |
| [`known`](known) | exact executable forms for accepted or previously classified behaviour |
| [`mormot`](mormot) | focused mORMot regressions that complement the two complete mORMot corpora |
| [`benchmark`](benchmark) | correctness-digested qualification workloads; performance is interpreted only after semantic agreement |

The complete map of oracles, profiles, expected deviations, Light/impact/full
routes, and release gates is in [MoonCompiler Test System](../docs/TESTS.md).
The suite entry point and platform commands are in the
[qualification README](../README.md).
