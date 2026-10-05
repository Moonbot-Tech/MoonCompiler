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
python RTL-test/run.py --jobs 8
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

After bootstrap, both application profiles receive the following minimum
check, run with the toolchain's plain `fpc` from the program's directory (the
product profile is the toolchain's own `fpc.cfg`; no driver takes part):

```bash
cd qualification/suite/tests/smoke
../../../../toolchain/bin/fpc -B build_smoke.dpr && ./build_smoke
../../../../toolchain/bin/fpc -B -dRELEASE build_smoke.dpr && ./build_smoke
```

```powershell
Set-Location .\qualification\suite\tests\smoke
..\..\..\..\toolchain\bin\x86_64-win64\fpc.exe -B build_smoke.dpr; .\build_smoke.exe
..\..\..\..\toolchain\bin\x86_64-win64\fpc.exe -B -dRELEASE build_smoke.dpr; .\build_smoke.exe
```

Both builds print `MOONBOT_BUILD_OK`. The source does not list the MM, `cthreads`,
or a monitor unit, so the smoke test also checks the automatic runtime prefix.
`examples/zip.dpr`, built the same way, prints `ZIP_EXAMPLE_OK`: it compiles
`System.Zip` over the `mormot` directory next to `toolchain`, as a project
does, and with it the MoonORMot version floor of the runtime units
(`runtime/mormot/MoonORMot.Need.pas`). CI runs both programs on both
platforms.

## Full Devil

Win64 with the Delphi 12.2 oracle:

```powershell
python .\qualification\suite\scripts\run_devil_all.py --jobs 8 `
  --dcc "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe" `
  --dcc-lib "C:\Program Files (x86)\Embarcadero\Studio\23.0\lib\win64\release"
```

`--jobs 8` is an example worker budget, not a requirement for every machine.
Use a budget that fits the available cores and memory; the release controller
passes its configured budget automatically. Independent stages and their nested
compilers share that limit, so waiting on one worker does not serialize the whole
suite. Cold-build and determinism checks keep their rebuilds. Later warm-PPU
checks reuse the artifacts whose source and inputs have already been validated.

On the 5 October 2026 integrated compiler, the complete Devil gate took 9 min
21 s on the Windows host and 12 min 12 s on the Linux host, with eight and sixteen
worker slots respectively. These are measured examples, not duration limits or
a promise for another host; full release qualification also builds the product,
checks its distribution and runs Pulse.

The runner creates a separate directory in `qualification/suite/results/runs`,
does not change the tracked corpus, and stops fail closed on an unknown finding,
an empty set, or an infrastructure error. Mutation mode is not part of a normal
release run. The aggregate multi-seed stage has a separate four-hour
`--main-timeout`; each generated executable keeps the five-minute
`--program-timeout`.

## Platform contracts

The build driver and runtime are checked separately from language corpora:

```powershell
.\qualification\pinned-unit\run.ps1
.\qualification\memory-manager\profile_contract.ps1
python .\qualification\memory-manager\mm_failure_gate.py `
  --compiler <ppcx64> --config <moon-base.cfg> `
  --mm .\runtime\mm\mormot.core.fpcx64mm.pas `
  --out <new-directory> --group all
python .\qualification\memory-manager\mm_profile_matrix.py
python .\qualification\memory-manager\mm_layout_gate.py
python .\qualification\build-driver\rtl_asm_layout_gate.py
python .\qualification\optimizer-core\placement\run_placement_fixture_gate.py
python .\qualification\optimizer-core\placement\run_branch_pad_gate.py
python .\qualification\optimizer-core\shl-lea\run_shl_lea_gate.py
python .\qualification\optimizer-core\loop-address\run_loop_address_gate.py --compiler <ppcx64> --config <moon-base.cfg> --objdump <objdump> --output <new-directory>
python .\qualification\optimizer-core\loop-regvar\run_loop_regvar_gate.py
python .\qualification\optimizer-core\real-folds\run_real_folds_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\consttemp-lifetime\run_consttemp_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\compiler-asm-numbers\run_gate.py --compiler <ppcx64>
python .\qualification\optimizer-core\getter-borrow\run_getter_borrow_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\value-in-register\run_value_in_register_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\try-nested\run_try_nested_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\nested-local\run_nested_local_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\record-fields\run_record_fields_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\block-locals\run_block_locals_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\operand-forms\run_operand_forms_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\sqr-fold\run_sqr_fold_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\const-register\run_const_register_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\fold-guards\run_fold_guards_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\optimizer-core\memory-order\run_memory_order_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\thread-pool\run_gate.py --output <new-directory>
python .\qualification\thread-pool\monitor_exit_gate.py --output <new-directory>
python .\qualification\optimizer-core\divmod\run_divmod_pair_gate.py --compiler <ppcx64> --config <moon-base.cfg>
python .\qualification\optimizer-core\range-loop\run_range_loop_gate.py --compiler <ppcx64> --config <moon-base.cfg>
python .\qualification\optimizer-core\resources\run_jump_tracking_gate.py --bootstrap <ppcx64> --config <vanilla fpc.cfg> --output <new-directory>
python .\qualification\compiler-private-ppu\run_ppu_private_crc_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\compiler-alias-lifetime\run_alias_lifetime_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python .\qualification\compiler-alias-lifetime\run_alias_reload_gate.py --source .\compiler --compiler <ppcx64> --build-config <vanilla-fpc.cfg> --msg2inc <installed-msg2inc> --config <moon-base.cfg> --output <new-directory>
python .\qualification\managed-array-copy\run_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
.\qualification\build-driver\atomic_swap.ps1
python .\qualification\build-driver\config_contract_gate.py
python .\qualification\build-driver\product_config_gate.py
python .\qualification\build-driver\unit_scope_gate.py
python .\qualification\build-driver\zlib_objects_gate.py
python .\qualification\build-driver\rtl_profile_gate.py
python .\qualification\build-driver\compiler_selfbuild_gate.py --compiler <ppcx64> --config <vanilla fpc.cfg> --product-config <moon-base.cfg>
.\qualification\win-stack-default\run.ps1 -RunId stack-win64-current
```

```bash
./qualification/pinned-unit/run.sh
./qualification/memory-manager/profile_contract.sh
python3 ./qualification/memory-manager/mm_failure_gate.py \
  --compiler <ppcx64> --config <moon-base.cfg> \
  --mm ./runtime/mm/mormot.core.fpcx64mm.pas \
  --out <new-directory> --group all
python3 ./qualification/memory-manager/mm_profile_matrix.py
python3 ./qualification/memory-manager/mm_layout_gate.py
python3 ./qualification/build-driver/rtl_asm_layout_gate.py
python3 ./qualification/optimizer-core/placement/run_placement_fixture_gate.py
python3 ./qualification/optimizer-core/placement/run_branch_pad_gate.py --compiler <ppcx64>
python3 ./qualification/optimizer-core/shl-lea/run_shl_lea_gate.py --compiler <ppcx64>
python3 ./qualification/optimizer-core/loop-address/run_loop_address_gate.py --compiler <ppcx64> --config <moon-base.cfg> --objdump <objdump> --output <new-directory>
python3 ./qualification/optimizer-core/loop-regvar/run_loop_regvar_gate.py
python3 ./qualification/optimizer-core/real-folds/run_real_folds_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/consttemp-lifetime/run_consttemp_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/compiler-asm-numbers/run_gate.py --compiler <ppcx64>
python3 ./qualification/optimizer-core/getter-borrow/run_getter_borrow_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/value-in-register/run_value_in_register_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/try-nested/run_try_nested_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/nested-local/run_nested_local_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/record-fields/run_record_fields_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/block-locals/run_block_locals_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/operand-forms/run_operand_forms_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/sqr-fold/run_sqr_fold_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/const-register/run_const_register_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/fold-guards/run_fold_guards_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/optimizer-core/memory-order/run_memory_order_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/thread-pool/run_gate.py --output <new-directory>
python3 ./qualification/thread-pool/monitor_exit_gate.py --output <new-directory>
python3 ./qualification/optimizer-core/divmod/run_divmod_pair_gate.py --compiler <ppcx64> --config <moon-base.cfg>
python3 ./qualification/optimizer-core/range-loop/run_range_loop_gate.py --compiler <ppcx64> --config <moon-base.cfg>
python3 ./qualification/optimizer-core/resources/run_jump_tracking_gate.py --bootstrap <ppcx64> --config <vanilla fpc.cfg> --output <new-directory>
python3 ./qualification/compiler-private-ppu/run_ppu_private_crc_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/compiler-alias-lifetime/run_alias_lifetime_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/compiler-alias-lifetime/run_alias_reload_gate.py --source ./compiler --compiler <ppcx64> --build-config <vanilla-fpc.cfg> --msg2inc <installed-msg2inc> --config <moon-base.cfg> --output <new-directory>
python3 ./qualification/managed-array-copy/run_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
./qualification/build-driver/atomic_swap.sh
python3 ./qualification/build-driver/config_contract_gate.py
python3 ./qualification/build-driver/product_config_gate.py
python3 ./qualification/build-driver/unit_scope_gate.py
python3 ./qualification/build-driver/rtl_profile_gate.py
python3 ./qualification/build-driver/compiler_selfbuild_gate.py --compiler <ppcx64> --config <vanilla fpc.cfg> --product-config <moon-base.cfg> --msg2inc <msg2inc>
```

These gates prove the pinned MM, allocation-failure ownership and pending
handoff (`mm_failure_gate.py`), managed-array acquisition rollback, private-PPU
invalidation, strong-alias semantics, persistent-temp lifetime, the numbers
the inline assembler reads (`compiler-asm-numbers/run_gate.py`: every
spelling of its inventory, AT&T and Intel, assembles to the bytes of GNU as or
Delphi 12.2, or stops the compilation with its message), the read-only
loop-address transform, the registers of spilled values across call-free
loops and the operand order of memory compares in loops
(`run_loop_regvar_gate.py`), real constants folded after inlining and real
min/max over an element or a field (`run_real_folds_gate.py`), the folds that
ask what they do with an evaluation (`run_fold_guards_gate.py`), `x*x` of an
element squared in place (`run_sqr_fold_gate.py`), the direct reads of inlined
string and array getters (`run_getter_borrow_gate.py`), a value the program
has in a register not read back from memory (`run_value_in_register_gate.py`),
the registers of a
routine with `try` and a nested routine or an anonymous function, and its
values on every exception path (`run_try_nested_gate.py`), a loop over a local
array or string which a nested routine replaces during a call
(`run_nested_local_gate.py`), the fields of a local record which a loop keeps in
registers and the ones somebody looks at in the record
(`run_record_fields_gate.py`), the registers of the locals declared where they
are used (`run_block_locals_gate.py`), the operands which name their memory
themselves, whatever registers the allocator gave
(`run_operand_forms_gate.py`), the thread pool's
delivery across the queue, idle and exit interleavings (`thread-pool/run_gate.py`)
and its monitor staying while work waits behind a busy worker
(`thread-pool/monitor_exit_gate.py`), one hardware division for a `div`/`mod`
pair of the same operands (`run_divmod_pair_gate.py`), no range helper in a
proven full-range loop over an array (`run_range_loop_gate.py`), the order of
a read and a write of one memory under two names in the x86 peephole and its
optimizations where the memory is certainly another one
(`run_memory_order_gate.py`), every
jump-tracking list of the MOV optimizer released while the compiler compiles
itself at -O3 (`run_jump_tracking_gate.py`), the MM over its `FPCMM_*` profiles, each at -O3 and at
-O- (the Release and Debug levels a program compiles the pinned unit with),
with every jump it writes out as bytes on the instruction of its mnemonic
(`mm_profile_matrix.py`), the hand-laid MM hot paths (`mm_layout_gate.py`,
see [MEMORY_MANAGER.md](MEMORY_MANAGER.md#hand-laid-hot-paths)), the hand-laid
assembler routines of the RTL (`rtl_asm_layout_gate.py`: `Move`, the compare,
index and fill families and the string assign/compare helpers keep their
entries on 64-byte lines, their loops inside a line and no branch on a 32-byte
boundary, checked on an executable that first proves the same routines
against Pascal references, and every jump they write out as bytes reaches
the instruction of its mnemonic, System and Math rebuilt with the RTL make's
own command lines - GNU make as for `rtl_profile_gate.py`; see
[ASM_LAYOUT_RULES.md](ASM_LAYOUT_RULES.md); and every routine of the installed
toolchain and of that executable keeps its unwind contract:
`qualification/performance/tools/unwind_frames.py` walks each routine and
compares the stack depth and the saved callee-saved registers at every
instruction with its CFI (Linux) or `.pdata`/`.xdata` (Win64), after a fixture
of described and silent frames shows the walk reports exactly the silent ones;
three groups pass by name - `fpc_longjmp`, the Linux start stubs `SI_*` below
`PASCALMAIN`, and three MoonORMot MM routines on Linux, see
[ASM_LAYOUT_RULES.md](ASM_LAYOUT_RULES.md#unwinding-hand-written-frames)),
the code placement draft in compiled code, which is off by default and which
these two gates switch on with `MOONCOMPILER_PLACEMENT=1` (`run_placement_fixture_gate.py`: a
fixture of loop, leaf, call-loop, branch-dense and set-test shapes built at
`-O3` breaks none of the placement rules; `run_branch_pad_gate.py`: 504
loops around the short-jump limit compile, print one digest at `-O2`, `-O3`
and `-O3 -OoNOCODEALIGN` and keep the rules; `run_shl_lea_gate.py`: the
peephole miscompile the placement work uncovered; see
[OPTIMIZER.md](OPTIMIZER.md#code-placement)), automatic
runtime-unit order, Debug/Release
checks, Unicode ABI, transactional toolchain swap, manifest isolation, the
audited `fpc.cfg` contract (`config_contract_gate.py`: only the template's
lines, no directives, internal assembler kept, `-ap`/`-ao`/`-Aas`
distinguished and the external assembler warned about, `NOPATCHRTL` built
into the compiler), Delphi's unit scope (`unit_scope_gate.py`: Win64 qualified
and short `Winapi.*` spellings share the installed bindings in Debug/Release,
including generic PPUs, while a project's own unit and explicit alias retain
priority; on both targets reverse aliases bind to the physical module and
cannot hide an explicit unit under a namespace; no unit on
the product path takes the short name of a `System.X` unit the product ships
unless the configuration aliases it, and `uses zLib, Zip` written as in Delphi
builds, runs and carries one zlib: no zlib library imported - DLL on Windows,
`NEEDED` on Linux - and no zlib build other than `System.ZLib`'s, by zlib's own
version marks in the image; a program with units `ZLib` and `Zip` of its own
runs with them - beside it, in a `-Fu` of its command line, in a `-Fu` of its
project file, in a subdirectory of its `**` tree - and `zlib.ppu` and
`zip.ppu` another build left in the tree do not take the names), the zlib
objects of `System.ZLib` on Win64 and Linux
(`zlib_objects_gate.py`: every object keeps `.pdata`/`.xdata` or `.eh_frame`
and `unwind_frames.py` finds each routine described, and zlib's own `zmemcpy`
and `zmemzero` each have a loop that stores 8 bytes or more a step, or zlib
copies and clears through the C library's `memcpy` and `memset` (Linux) -
after the gate has taken the byte loop of the first objects for a byte copy
and a 16-byte loop not - `crc32.o` carries zlib's braided CRC, and
`longest_match` of `deflate.o` compares two bytes at a time; how fast they
are against Delphi is the full stage's `zlib_delphi_gate.py`), the RTL profile
(`rtl_profile_gate.py`: the options recorded by the driver start with
`scripts/rtl-profile.txt`, and witness
units rebuilt with them - types, sysutils, math and the Classes bundle -
equal the installed objects byte for byte; `Generics.Hashes` separately
proves the same profile reached an application-facing package, including
non-debug sections, relocations and symbols; recorded compiler/RTL/package
hashes are mandatory; GNU make from `MOONBOT_MAKE`,
next to `MOONBOT_BOOTSTRAP_FPC`, or `--make`), the compiler's own build
(`compiler_selfbuild_gate.py`: the sources refuse the product Unicode ABI,
and a compiler built from them survives an incremental rebuild of itself
after an interface change under heaptrc with released memory kept - the
unit-reload path that crashed the product compiler on 2026-09-15), and the
platform stack contract. CI builds the complete toolchain while
`PPC_CONFIG_PATH` points to a deliberately invalid configuration, proving that
every compiler invocation is isolated with `-n`. Linux runs the installed
`toolchain/bin/fpc` with its configuration; bare `ppcx64 -n` is not a
product environment.

## mORMot and memory manager

Product mORMot and the current public corpus are distinct tests: the former
reproduces a real application dependency, while the latter broadens compiler/RTL
coverage. The heavy MM matrix separately checks small/medium/large paths,
threads, realloc, shutdown, and the fail-closed leak report.

Linux commands from `qualification/suite`:

```bash
python3 runner.py prepare
python3 runner.py mormot --compiler moonbot-compiler-beta --option O2 --option O3
python3 scripts/run_tftp_shutdown_gate.py

scripts/mm/qualify_current_mm.sh ../../.qualification/mm-full \
  ../../toolchain/bin/fpc ../../toolchain/etc/moon-base.cfg \
  ../../runtime/mm/mormot.core.fpcx64mm.pas

scripts/mm/run_mormot_mm_gate.sh ../../.qualification/deps/moonormot \
  ../../runtime/mm/mormot.core.fpcx64mm.pas ../../.qualification/mormot-mm \
  ../../toolchain/bin/fpc ../../toolchain/etc/moon-base.cfg
```

The name `moonbot-compiler-beta` is an immutable key in the historical oracle
dataset, not a product version or release status.

### MoonORMot records

The repository holds three records of MoonORMot, all of which must name the
tip of `Moonbot-Tech/MoonORMot` `main`:

| Record | Where | Who reads it |
|---|---|---|
| the qualification pin | `mormot.sources.current.commit` in `qualification/suite/runner_manifest.json` | `runner.py`: the checkout in `.qualification/deps/moonormot` is advanced to it |
| the version floor | `runtime/moonormot.need.inc` (the number in MoonORMot's `moonormot.version.inc` on that commit) | `runtime/mormot/MoonORMot.Need.pas`, compiled into every project that uses a runtime unit over mORMot: an older MoonORMot fails the build |
| the bundled memory manager | `runtime/mm/mormot.core.fpcx64mm.pas` | the product configuration pins it; it must equal `core/mormot.core.fpcx64mm.pas` of the pin byte for byte (line endings aside) |

`runner.py prepare` (and every mORMot stage) proves all three before anything
runs: the pin is the remote branch tip, the floor is the version on the pin,
the memory manager is the pin's. A mismatch is a `RuntimeError` naming the
record. The compiler itself never reads the network; the records are
maintained by one command:

```bash
python3 scripts/sync-moonormot.py --check   # compare with main, change nothing; exit 1 on drift
python3 scripts/sync-moonormot.py           # move all three to the tip of main
```

The plain run refuses (exit 2) to copy the memory manager when the bundled
copy differs from the memory manager of the *old* pin, because that means the
copy was edited here and the edit never reached MoonORMot; carry the edit
over first. `qualification/suite/tests/test_sync_moonormot.py` runs the
script against throw-away repositories.

`.github/workflows/moonormot-sync.yml` runs the check once a day. When main
moved, it moves the records on a Linux and on a Win64 runner, builds the
toolchain on each and runs `run_runtime_mormot_gate.py`, the memory-manager
gates and the product smoke (the memory manager has platform branches, so
both platforms must pass); both green means one commit on `main` from
`github-actions[bot]`, and only if `main` and MoonORMot `main` are still
what the gates ran against - otherwise the run stops and the next one starts
over on the new state; red means an issue labelled `moonormot-drift` and no
commit. The rule for a MoonORMot change is therefore: push it to MoonORMot
`main`, then run the script here and the gates above (or let the Action do
it the next morning).

## Diagnostic reports

After rebuilding the product compiler/RTL, run the dedicated file-content gate.
The results directory must be new; the runner never deletes an existing one.

```bash
python3 qualification/suite/scripts/run_reporting_gate.py \
  --compiler toolchain/bin/ppcx64 \
  --rtl toolchain/lib/fpc/3.3.1/units/x86_64-linux/rtl \
  --results .qualification/reporting-linux --product-mm
```

```powershell
python qualification\suite\scripts\run_reporting_gate.py `
  --compiler toolchain\bin\x86_64-win64\ppcx64.exe `
  --rtl toolchain\units\x86_64-win64\rtl `
  --results .qualification\reporting-win64 --product-mm
```

Linux additionally needs `libunwind.so.8`, OpenSSL and the normal GCC
development linker input. ZIP/HTTP tests use the existing bundled mORMot source
and static objects; the runner supplies their paths. No curl/archive package is
needed. The runner uses the `openssl` command to create a short-lived loopback
certificate from the repository's existing public test key; on Windows it also
finds the copy bundled with Git for Windows. No new key is generated.
They start a loopback-only receiver, compare uploaded multipart bytes with the
closed ZIP and its original report content, and cover names/directories, server rejection,
redirects, acknowledgement failure, timeout, untrusted TLS, local write failure and simultaneous
uploads without the report lock. No production endpoint is contacted.
Compiler and RTL must come from the same rebuild. The runner deliberately
uses `-n`, explicit fresh unit directories and the product MM; it does not reuse
project PPUs. Besides `runtime/reporting`, `runtime/mormot` and the
MoonORMot checkout, its unit path holds the installed toolchain as a whole -
`--rtl` and every installed package next to it, as the toolchain's
configuration names them (`units/<target>/*`) - not a list of the packages
the tests happen to need: under this compiler MoonORMot compresses through
`System.ZLib` of `vcl-compat`. It checks O-/O2/O3, actual names from an exe-only deployment,
exception ownership and all-thread snapshots, then replays existing exception
and managed-lifetime regressions with capture off/on. The old raw-object and
custom-address raise tests are compatibility controls, not new Delphi oracles.
Timing of the caught-raise loop is recorded separately in `summary.json`.
The switch tests verify thread isolation, global propagation, nested restoration,
original hardware/Pascal exception semantics, existing-context ownership and
manual sampling of a worker whose exception capture is disabled. Benchmarks run
inside a worker, with capture enabled, disabled per thread and disabled globally;
the no-module binary is separate. Toggle-pair cost is measured without throws.
Linux also exercises a successful HTTPS upload using a loopback certificate
trusted only by the child process, without changing system trust.

For Delphi/Eureka comparison, compile `tests/smoke/diagnostic_raise_bench.pas`
from this suite with Delphi 12.2/Win64 in Release, once without Eureka units and
once with `EUREKA`. Postprocess the latter using the installed Eureka `ecc32`
and the application's real `.eof` profile; do not put a private profile in Git.
Then run `scripts/measure_eureka_reporting.py --baseline <plain.exe>
--eureka <processed.exe> --results <new-directory>` from the suite. It verifies
active Eureka and records seven fresh worker-process measurements for each
mode, alternating their order. It does not equate Eureka's larger feature
profile with the smaller Moon.Diagnostics collector.

Also build and run `examples/diagnostics.dpr` with the toolchain's `fpc`,
without and with `-dRELEASE`; this checks profile integration independently
of the focused runner. API,
capture semantics and deployment requirements are in [Diagnostic Reports](DIAGNOSTICS.md).

## runtime/mormot: System.Zip, System.Net.Mime, System.Net.HttpClient

The units of `runtime/mormot` are compiled into each project over the
project's mORMot, so their gate compiles the three contract tests against the
installed toolchain plus the qualification checkout of MoonORMot (or
`--mormot PATH`), with `runtime/mormot` ahead of the installed units, and runs
them; the HTTP contract runs against a loopback HTTP/HTTPS server that records
every request. The units name `MoonORMot.Need` in their uses, so the gate also
proves that the version floor accepts the pinned MoonORMot. The results
directory must not exist:

```bash
python3 qualification/suite/scripts/run_runtime_mormot_gate.py \
  --compiler toolchain/bin/ppcx64 \
  --rtl toolchain/lib/fpc/3.3.1/units/x86_64-linux/rtl \
  --results .qualification/mormot-linux --product-mm
```

```powershell
python qualification\suite\scripts\run_runtime_mormot_gate.py `
  --compiler toolchain\bin\x86_64-win64\ppcx64.exe `
  --rtl toolchain\units\x86_64-win64\rtl `
  --results .qualification\mormot-win64 --product-mm
```

The default modes are `-O-` and `-O3`; `--modes O- O2 O3` includes `-O2`.
`zip_contract`: an archive written by Python's `zipfile`
(embedded bytes) read entry by entry with its known sizes, CRCs, times and
names, from a stream with a non-zero base; archives written here read back
and checked against APPNOTE's layout, then read by `zipfile` in the gate
(names, methods, the UTF-8 flag, contents, `testzip`); data descriptors with
stored, deflated and empty entries, read and appended twice; a damaged CRC caught
by `CheckCrc` and by `Read(Bytes)`, including an empty entry; an unfinished
deflate member and output beyond its declared size refused; nonzero stream
write positions and replacement of an old stream tail; truncated and empty input; an encrypted
entry refused; names leaving the extraction directory refused before anything
is written; a stored entry whose uncompressed size overruns its bytes
refused; on Linux a symlink whose target leaves the directory refused
before anything is written, and a relative symlink created as a link; a
hand-made ZIP64 central directory; `ExtractAll` with
subdirectories and a piecewise read of a 2 MB entry. `mime_contract`: the
body split at the announced boundary, every part's headers and content, the
file part streamed intact, a second read of the same size, `Add*` after the
body was read refused, a missing file failing at `AddFile`. `httpclient_contract`:
methods and statuses, property/per-call header merging, the redirect table with its method
changes and the `MaxRedirects` refusal, gzip/deflate/raw deflate and charsets
through `ContentAsString` and `AutomaticDecompression`, valid compressed
bodies around 64/128 KB output boundaries, a truncated gzip
member refused on both paths, `ContentAsString` bounded by the received
bytes when the caller stream is longer, `Post(TStrings)` in
UTF-8 and Windows-1251, cookies per host, `OnReceiveData` with abort,
keep-alive over one connection, no replay of a POST/PATCH that the server
processed before disconnecting without an answer, response/body/connection timeouts,
`BeginGet`/`Cancel`/`EndAsyncHTTP`, immediate cancellation, TLS refusal and the
`OnValidateServerCertificate` retry, a multipart upload parsed by Python.
Linux repeats the HTTP run with `SSL_CERT_FILE` trusting the fixture
certificate (trusted pass, other-host refusal). The loopback certificates
come from the repository's public test key through the `openssl` command, as
for the reporting gate; no production endpoint is contacted. A failure of the
loopback server itself is printed as `SERVER ERROR`, so it is not mistaken
for a client failure. `--http-executable PATH` runs an already built copy
of `httpclient_contract` (for the Delphi audit: the same source compiled by
`dcc64`) against the gate's servers instead of compiling it; the zip and
mime contracts are skipped in that mode and the run is labelled `foreign`.

## Full release qualification

Use the [release controller](../qualification/release/README.md) to collect
failures and resume unchanged evidence. Its two-host route requires Light and
Medium green on both hosts before starting heavy corpora. Independent jobs and
Devil seeds/profiles share explicit worker/memory budgets; the release Pulse
report runs after functional and archive checks on an idle host. The `plan`
command prepares and inspects the route without starting qualification.

Before release, run the following on one exact HEAD:

1. a clean bootstrap and product smoke on Win64 and Linux x86-64;
2. focused, Light, and full Mega/Omni/Devil/Chimera/Resident corpora;
3. RTL-test in Debug/O2/O3 and platform API/ABI gates;
4. upstream compiler regressions and the issue-tracker corpus in fail-closed
   mode;
5. both mORMot lines, TFTP lifetime, and the full MM matrix;
6. Lazarus bootstrap in the IDE profile;
7. the configuration contracts (`config_contract_gate.py`,
   `product_config_gate.py`), the MoonORMot records
   (`scripts/sync-moonormot.py --check`) and toolchain rollback fault
   injection;
8. Pulse only after semantic oracles match completely;
9. a final check of the diff, documentation, and reproducibility of evidence.

Run the complete route with:

```text
python qualification/release/qualify_both.py plan --config <hosts.json>
python qualification/release/qualify_both.py run --config <hosts.json>
```

`plan` does not build or run tests. The full route uses fresh evidence where inputs
changed and retains matching evidence with its original provenance. Final Light
runs on the final committed source and verifies the exact installed artifact that
passed Full; it does not replace that artifact with another build. Explicit
compiler self-build and determinism tests still rebuild.

`--skip-pulse` is available for an explicitly scoped correctness-only check. Its
verdict says `correctness-without-pulse` and is not complete release qualification.
A full release run uses a separate ledger with Pulse enabled. An ordinary repair
uses Focused + Light + impact checks; there is no need to restart unchanged heavy
corpora after a documentation-only edit.

The Medium stage runs the regressions of compiler repairs on both targets with
the product configuration: the focused repair gate
(`qualification/suite/scripts/run_win64_repair_gate.py`, inventory
`win64-repairs` in `qualification/suite/runner_manifest.json`; a case that
names `targets` runs only there). The upstream suite runs the tests of
`tests/test` on Linux only at the full stage, with its base RTL and without the
product-profile ones. An optimizer repair whose defect is a lost optimization
also keeps its sentry under `qualification/optimizer-core`, which reads the
code shape its value test does not see; the Medium stage runs each of them on
both targets. It also runs the Pulse contracts
(`qualification/performance/tools/run_contracts.py`, see
[PERFORMANCE_QUALIFICATION.md](PERFORMANCE_QUALIFICATION.md)): the tests of the
Pulse tools and the case-loop judge over every Pulse program, on both targets.

## Public CI

`.github/workflows/qualification.yml` builds the toolchain with the standard
driver on clean Win64 and Ubuntu runners, then runs platform contracts, focused
regressions, broad language/RTL gates, and product smoke. CI is a fast public
barrier, but does not replace local full qualification with Delphi, mORMot, and
the heavy MM/Pulse matrix. The release matrix runs every gate CI runs, on the
same platform: `test_every_gate_ci_runs_is_a_release_job`
(`qualification/release/test_qualify.py`, the Light controller stage) fails
on a gate CI starts and no matrix job does.

`.github/workflows/release.yml` builds the release archives and smoke-tests
each one the way a user installs it: unpacked outside the clone, MoonORMot
cloned next to it, `hello.dpr`, `zip.dpr` and the resource smoke built with
plain `fpc` in both profiles; then the archive is installed with
`build toolchain` and the configuration contracts run over the installed copy.
`.github/workflows/moonormot-sync.yml` is the daily check of the MoonORMot
records described above.

Windows PowerShell steps check each native command's exit code immediately;
a later successful command must never hide an earlier failure. The workflow
contract test injects a native failure at every position in both multi-command
qualification steps and verifies that execution stops there.
