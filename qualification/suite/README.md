# Qualification suite

This directory checks the current MoonCompiler sources, RTL, bundled MM, and
two mORMot layers. Required fixtures are in the repository; the public
additional mORMot corpus is fetched by its runner from the pinned manifest.

## Preparation

From the repository root:

```bash
./build compiler
cd qualification/suite
```

On Win64, prepare the compiler as follows:

```powershell
.\build.ps1 compiler
```

The full mORMot gate runs natively on Linux x86-64. On its first run, it fetches
the exact public corpus itself. `qualification/prepare.sh` or
`qualification/prepare.ps1` can be invoked in advance for a standalone run;
they are not a mandatory hidden step.

The full runner targets Linux because mORMot static inputs and some integration
gates use the Linux runtime. The Win64 target has separate native gates and is
mandatory before release.

For daily development, first use the short route from the root:

```text
python qualification/suite/scripts/run_devil_targeted.py light
python qualification/suite/scripts/run_devil_targeted.py impact --areas rtl-containers
```

`list` prints all impact areas. The full commands below are for a release
snapshot, not after every local change.

## Core Linux layers

```bash
python3 runner.py fixtures --compiler moonbot-compiler-beta --option O2 --option O3
python3 runner.py mega --compiler moonbot-compiler-beta --option O2 --option O3
python3 runner.py mormot --compiler moonbot-compiler-beta --option O2 --option O3
python3 runner.py upstream --compiler moonbot-compiler-beta --option O2 --option O3
python3 runner.py benchmark --compiler moonbot-compiler-beta --option O3
```

- `fixtures` — minimal repros with independent oracles;
- `mega` — the original Mega with intertwined runtime/lifetime/thread forms;
- `mormot` — established product mORMot and the new public mORMot compiler corpus;
- `upstream` — core tests within the Delphi application-contract boundary;
- `benchmark` — only after correctness.

Chimera and Resident belong to the composition layer: the former transfers
whole and split forms of real Pascal applications; the latter mixes runtime,
threads, collections, crypto/compression, and managed lifetime for a long time.
Their exact commands and place in full qualification are maintained by
[`docs/TESTS.md`](docs/TESTS.md).

Omni/integrated and focused integration gates:

```bash
FPC=../../.moonbot/toolchain/bin/fpc
CFG=../../.moonbot/toolchain/etc/fpc.cfg

scripts/run_forms_gate.sh "$FPC" "$CFG" forms-001
scripts/run_service_regressions_gate.sh "$FPC" "$CFG" service-001
scripts/run_rtl_api_surface_gate.sh rtl-api-linux-001
scripts/run_namespace_scope_gate.sh "$FPC" "$CFG" namespace-001
scripts/run_monitor_gate.sh "$FPC" "$CFG" monitor-001
scripts/run_exception_capture_gate.sh "$FPC" "$CFG" exception-001
scripts/run_rtti_gettypes_gate.sh "$FPC" "$CFG" rtti-001
scripts/run_extra_corpus.sh "$FPC" "$CFG"
```

## Win64

From the repository root:

```powershell
.\qualification\pinned-unit\run.ps1
.\qualification\memory-manager\profile_contract.ps1
.\qualification\memory-manager\medium_arenas.ps1
.\qualification\suite\scripts\run_extra_corpus.ps1

.\qualification\suite\scripts\run_forms_gate.ps1 `
  -Compiler .\.moonbot\toolchain\bin\x86_64-win64\ppcx64.exe `
  -Config .\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg `
  -RunId forms-win64-001

.\qualification\suite\scripts\run_rtl_api_surface_gate.ps1 `
  -RunId rtl-api-win64-001

python .\qualification\suite\scripts\run_win64_repair_gate.py `
  .\.moonbot\toolchain\bin\x86_64-win64\ppcx64.exe `
  .\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg `
  . win64-repairs-001
```

The Forms gate executes both central programs (`Omni` and integrated Mega), O2/O3,
and all six seeds with the exact-set oracle. Selected Win64 repairs do not
replace it.

## Memory manager

From this directory on Linux:

```bash
scripts/mm/qualify_current_mm.sh ../../.qualification/mm-full \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg \
  ../../runtime/mm/mormot.core.fpcx64mm.pas

scripts/mm/run_mormot_mm_gate.sh ../vendor/mormot-product \
  ../../runtime/mm/mormot.core.fpcx64mm.pas ../../.qualification/mormot-mm \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg
```

## Full description

[docs/TESTS.md](docs/TESTS.md) explains oracles, Known Deviations, the
composition of Mega/Omni, both mORMot layers, MM, and the release-qualification
order. [docs/LAB_SETUP.md](docs/LAB_SETUP.md) describes only additional
historical/reference toolchains; they are not needed for ordinary work.
