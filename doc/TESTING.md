# MoonCompiler Testing

MoonCompiler is tested at three levels: the specific fix, the affected area,
and the complete product. A short cycle does not replace release qualification,
and a full run is not needed after every local change.

## Working cycle

1. **Focused regression** — the smallest failing form, nearby boundaries, and
   an independent oracle.
2. **Light** — a short selection from different subsystems that catches a broad
   class of accidental breakage.
3. **Impact-scoped** — every test in an area affected by the diff.
4. **Full** — both platforms, every corpus, and benchmarks on the exact HEAD
   before release.

```powershell
python qualification\suite\scripts\run_devil_targeted.py light
python qualification\suite\scripts\run_devil_targeted.py list
python qualification\suite\scripts\run_devil_targeted.py impact `
  --areas optimizer-codegen,exceptions
```

On Linux, use the same commands with `python3` and `/` in paths. Available
impact areas: `frontend`, `generics-ppu`, `managed-lifetime`,
`optimizer-codegen`, `abi-asm`, `exceptions`, `threads`, `rtti-attributes`,
`strings-unicode`, `rtl-containers`, `initialization`.

Choose a focused test from the first violated invariant. Lowering and managed
lifetime usually need Debug/O2/O3; optimizer and codegen need O2/O3 on the
affected target. After an RTL change, also run:

```text
python RTL-test/run.py
```

## What counts as proof

Every test needs an external source of truth: Delphi 12.2, a specification, a
mathematical invariant, or an alternative implementation. The current
MoonCompiler result is not an oracle by itself.

A repair is not accepted if the test turns green by disabling AUTOINLINE, loop
unroll, range checking, or another affected mechanism. A compile-only check is
sufficient only for API surface; semantics, lifetime, and ABI are verified by
execution. A performance case enters statistics only after its semantic digest
matches.

## Qualification systems

| Layer | What it catches |
|---|---|
| Focused regressions | the exact defect, its boundaries, and negative controls |
| Mega | large preselected language and RTL combinations |
| Omni | the cross-product of types, operators, consumers, PPU, and optimization modes |
| Devil | generated expressions, ABI, managed lifetime, determinism, and a differential oracle |
| Chimera | whole and fragmented compositions from MoonBot, Arbitrage, mORMot, and other Pascal projects |
| Resident | a sustained multithreaded mix of runtime, collections, crypto, compression, and managed state |
| RTL-test | RTL API, ownership, exceptions, streams, containers, and threading |
| mORMot | two real-world lines of a large library and their Linux/Unicode/RTTI surface |
| Lazarus | bootstrap IDE/LCL in a separate FPC-ABI profile |
| Pulse / Heartbeat | semantic digest and comparative compiler, RTL, and MM speed |

A detailed inventory of forms, runners, and oracles is in
[`qualification/suite/docs/TESTS.md`](../qualification/suite/docs/TESTS.md).

## Product smoke

After bootstrap, both application profiles receive the following minimum check:

```bash
./build qualification/suite/tests/smoke/build_smoke.dpr debug
./qualification/suite/tests/smoke/build_smoke
./build qualification/suite/tests/smoke/build_smoke.dpr release
./qualification/suite/tests/smoke/build_smoke
```

```powershell
.\build.ps1 .\qualification\suite\tests\smoke\build_smoke.dpr debug
.\qualification\suite\tests\smoke\build_smoke.exe
.\build.ps1 .\qualification\suite\tests\smoke\build_smoke.dpr release
.\qualification\suite\tests\smoke\build_smoke.exe
```

Both builds print `MOONBOT_BUILD_OK`. The source does not list the MM, `cthreads`,
or a monitor unit, so the smoke test also checks the automatic runtime prefix.

## Full Devil

Win64 with the Delphi 12.2 oracle:

```powershell
python .\qualification\suite\scripts\run_devil_all.py `
  --dcc "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" `
  --dcc-lib "C:\Program Files (x86)\Embarcadero\Studio\23.0\lib\win64\release"
```

The runner creates a separate directory in `qualification/suite/results/runs`,
does not change the tracked corpus, and stops fail closed on an unknown finding,
an empty set, or an infrastructure error. Mutation mode is not part of a normal
release run.

## Platform contracts

The build driver and runtime are checked separately from language corpora:

```powershell
.\qualification\pinned-unit\run.ps1
.\qualification\memory-manager\profile_contract.ps1
.\qualification\build-driver\atomic_swap.ps1
python .\qualification\build-driver\project_profile_gate.py
.\qualification\win-stack-default\run.ps1 -RunId stack-win64-current
```

```bash
./qualification/pinned-unit/run.sh
./qualification/memory-manager/profile_contract.sh
./qualification/build-driver/atomic_swap.sh
python3 ./qualification/build-driver/project_profile_gate.py
```

These gates prove the pinned MM, automatic runtime-unit order, Debug/Release
checks, Unicode ABI, transactional toolchain swap, manifest isolation, and the
platform stack contract. Linux runs the installed
`.moonbot/toolchain/bin/fpc` with its configuration; bare `ppcx64 -n` is not a
product environment.

## mORMot and memory manager

Product mORMot and the current public corpus are distinct tests: the former
reproduces a real application dependency, while the latter broadens compiler/RTL
coverage. The heavy MM matrix separately checks small/medium/large paths,
threads, realloc, shutdown, and the fail-closed leak report.

Linux commands from `qualification/suite`:

```bash
python3 runner.py mormot --compiler moonbot-compiler-beta --option O2 --option O3
python3 scripts/run_tftp_shutdown_gate.py

scripts/mm/qualify_current_mm.sh ../../.qualification/mm-full \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg \
  ../../runtime/mm/mormot.core.fpcx64mm.pas

scripts/mm/run_mormot_mm_gate.sh ../vendor/mormot-product \
  ../../runtime/mm/mormot.core.fpcx64mm.pas ../../.qualification/mormot-mm \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg
```

The name `moonbot-compiler-beta` is an immutable key in the historical oracle
dataset, not a product version or release status.

## Full release qualification

Before release, run the following on one exact HEAD:

1. a clean bootstrap and product smoke on Win64 and Linux x86-64;
2. focused, Light, and full Mega/Omni/Devil/Chimera/Resident corpora;
3. RTL-test in Debug/O2/O3 and platform API/ABI gates;
4. upstream compiler regressions and the issue-tracker corpus in fail-closed
   mode;
5. both mORMot lines, TFTP lifetime, and the full MM matrix;
6. Lazarus bootstrap in the IDE profile;
7. build-driver manifest, dependency isolation, and rollback fault injection;
8. Pulse only after semantic oracles match completely;
9. a final check of the diff, documentation, and reproducibility of evidence.

The full run is deliberately heavy. An ordinary repair uses a minimal
Focused + Light + impact set; repeat Full only before a newly published revision.

## Public CI

`.github/workflows/qualification.yml` builds the toolchain with the standard
driver on clean Win64 and Ubuntu runners, then runs platform contracts, focused
regressions, broad language/RTL gates, and product smoke. CI is a fast public
barrier, but does not replace local full qualification with Delphi, mORMot, and
the heavy MM/Pulse matrix.
