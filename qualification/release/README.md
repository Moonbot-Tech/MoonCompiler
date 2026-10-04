# Release qualification

The purpose is to find all actionable failures cheaply, repair them together,
then qualify the complete candidate once. No corpus, optimization level,
semantic oracle, archive test, or platform is removed to make the run faster.
A partial pass is never a release pass. Performance gains, regressions and
accepted trade-offs come from the Pulse report, not a vote over test counts.

## Prepare and inspect without starting qualification

Copy `hosts.example.json` to an ignored local configuration and set the two
checkout paths, Python executables, baseline toolchains/MM sources, run
folders, SSH command and resource budgets. Both checkouts must contain the
same committed candidate. Each host owns its own run folder and evidence.
The baseline is a frozen installed release, including its original MM; an
older archive can use an explicit `baseline_mm_source` from its source tree.
The RTL profile gate takes GNU make from `MOONBOT_MAKE`, next to
`MOONBOT_BOOTSTRAP_FPC`, from the bootstrap `scripts/Install-FpcBootstrap.ps1`
installs, or from `PATH`, in that order.
The optimizer PPU gate uses that bootstrap separately from the product compiler:
`MOONBOT_BOOTSTRAP_FPC` overrides its path; otherwise Windows uses the installer's
`%LOCALAPPDATA%\MoonCompiler\bootstrap\3.2.2\bin\i386-win32\fpc.exe`, and Linux
uses `/usr/bin/fpc`. CI passes its already installed 3.2.2 bootstrap explicitly.
The old compiler must build a real PPU which the product then rejects with a
PPU version diagnostic; a missing dependency cannot count as a negative pass.
This short `optimizer_ppu` prerequisite runs in Light on every invocation,
including resume and final Light. Its external compiler, configuration and RTL
are outside the installed product's content identity, so an earlier result is
never reused for it.

```powershell
python qualification/release/qualify_both.py plan --config .qualification/release-hosts.json
```

This command only prints the route and commands. It does not connect to a
host, build a compiler, create run state, or execute any qualification gate.
The per-host `qualify.py plan --run-dir PATH --platform win64 --mode full`
validates the local matrix and displays stages, worker slots, estimates and
timeout ceilings without executing jobs. Use `linux` for the other platform.

## The authorized release run

When the owner asks to start qualification:

```powershell
python qualification/release/qualify_both.py run --config .qualification/release-hosts.json
```

The coordinator checks clean tracked sources and equal HEADs, then runs each
stage on Windows and Linux concurrently. Both must succeed before advancing:

1. **Light:** build and short broad/runner checks.
2. **Medium:** focused semantic, RTL, ABI, layout, configuration and API gates.
3. **Full functional:** complete Devil, upstream and mORMot/MM corpora.
4. **Delivery:** archive consumer/install smoke and Lazarus.
5. **Pulse:** the complete fixed-work comparison with short A/A controls and
   independent confirmation of the release shortlist, on an otherwise idle host.
6. **Final Light:** replay on the frozen final HEAD, plus the history audit.

The coordinator synchronizes the hosts at Light, Medium, Full and final Light.
Inside Full, each host enforces functional -> delivery -> Pulse barriers.
A failure does not cancel unrelated checks within its stage. It blocks later
stages; the report retains every failure and every completed attempt. Fix the
findings as a batch, update both checkouts, and repeat the same command/run
folders. The candidate is frozen again at the beginning of that invocation.
A changed HEAD after final Light has begun requires new run folders.

The coordinator does not update source checkouts. Install the intended committed
revision on both hosts before running it. Do not rebuild or edit a checkout
while its qualification is active.

For one-host diagnosis, `qualify.py run --run-dir PATH --mode light|medium|full`
uses the same stage barriers. Supply `--baseline-toolchain PATH` (and, when
needed, `--baseline-mm-source FILE`) for Full. `--mode light --final` is allowed
only after every Full job is green for current inputs. `status` reads its ledger.

## Optimizer and object-format contracts

Medium (including Light) and the two platform CI jobs run these installed-toolchain checks:

| Jobs | Required evidence |
|---|---|
| `effect_model`, `effect_identity` | Safe/dangerous storage and instruction effects; real compiler-temp and lexical-with carriers; observe off/on code, runtime and generic PPU identity. |
| `licm`, `licm_ppu` | Integer hoists remain useful, unsafe neighbours remain inside the loop, and PPU consumers own the optimization decision. |
| `exact_licm` | Exactly representable integer-to-FP conversions leave the loop; rounding modes, FP flags, mutation, aliases and register pressure preserve their semantics and existing integer hoists. |
| `setcc_compare` | Runtime answers and Pascal code shape retain useful SETcc/CMP1 removal, valid multiplication and indirect-call flags boundaries. |
| `tail_forwarding` | Installed Debug/Release profiles preserve runtime, unwind, cleanup and explicit frame contracts; Release removes eligible forwarding calls and frames. |
| `value_relations` | Unchanged integer comparisons retain their relation across floating comparisons and internal joins; ordinary scans remove a redundant branch while preserving NaN and mutation semantics. |
| `machine_facts` | Exact implicit USE/DEF facts, deterministic diagnostics with unchanged code, and rejection of stale generation facts. |
| `seh_regvar`, `address_gvn`, `managed_load_cse`, `loop_base` | Runtime oracles plus generated-code controls with the pass enabled, disabled and at its default; both useful work removal and unsafe boundaries are checked. |
| `optimizer_ppu` | Cold artifact determinism, warm PPU reuse and rejection of a real legacy PPU. |
| `zeroext` | Seeds 1 and 24 through expression, unary, folding, unit and generic carriers in four compiler modes; no findings or accepted deviations. |
| `win_bigobj`, `linux_large_elf` | Actual large object section indexes and successful link/run beyond the small-object format boundary. Each runs only on its target OS. |
| `win_stack` | Win64 default and explicit stack sizes with both linkers, plus internal-linker runtime checks. |

These tests use the installed compiler and RTL after the build dependency.
Medium and both platform CI jobs also run source-only `setcc_ir`, `value_forward_ir`
and `value_relations_ir`. They build the actual compiler peephole and its dependencies
into fresh units using the ordinary IDE config. They check flags lifetime and legal
LEA scales, register/address representation, and preserved relations through joins
and writes. Their input signatures include the compiler sources as well as their
fixtures and installed toolchain. They are not installed-archive checks.
Zeroext also uses installed package units, including `SyncObjs` and Linux
`pthreads`; a minimal RTL-only transport needs those packages built by the same
compiler. Its explicit `--toolchain` selects the installed compiler, config and
MM source together, overriding lab environment variables in release and CI.
The Win64 stack gate needs the external linker shipped by the build.
Object-format checks have separate 1000/1300-second outer ceilings; they are
ordinary functional gates, rather than timing thresholds. Every new job requires
its own success marker as well as a zero exit code. Full includes all Medium jobs.

Research and destructive checks have separate entry points:

- On an idle host with a complete toolchain, run
  `python qualification/optimizer-core/f2/run_f2_perf.py` and
  `python qualification/optimizer-core/f3/run_f3_scaling.py` for loop-cost and
  compiler-scaling experiments. Their timing limits do not gate ordinary CI.
- In a disposable **Windows** clone with source RTL already built, run
  `python qualification/effect-observe/run_effect_sabotage.py --fpc BOOTSTRAP_FPC --make GNU_MAKE`
  and `python qualification/optimizer-core/f2/run_f2_sabotage.py --fpc BOOTSTRAP_FPC --make GNU_MAKE`.
  They mutate sources, rebuild and restore with Git; never run them in a checkout
  containing work to preserve. Stale mutation anchors require investigation, not
  an EXPECT update. Their Windows compiler/source-RTL layout is a prerequisite.
- For the Linux RTTI transition lab, use
  `bash qualification/suite/scripts/run_rtti_ppu_version_gate.sh OLD_TOOLCHAIN NEW_TOOLCHAIN qualification/suite/results/rtti-ppu-lab`.
  Both toolchains need `bin/fpc` and `etc/moon-base.cfg`; the old RTTI-capable lab
  build is distinct from the ordinary 3.2.2 bootstrap. This checks the actual old
  RTTI PPU and the new type catalog; the ordinary catalog gate remains mandatory.
- `qualification/optimizer-core/placement/tls_gd_pad_semantic/run_gate.py`
  requires a compiler and RTL both built with `-dtls_threadvars`, passed with
  `--compiler` and `--rtl`. The product's relocate-based TLS does not exercise
  that ABI. Use this lab gate when changing the GD TLS path.

Generators, minimizers and corpus preparation feed the corresponding gates;
they are not additional product verdicts. The `run_memory_mega.sh` wrapper's
runtime contract is already exercised by Full's `mm_current` job.

## Parallel work and resume

`--jobs` is a shared worker budget, including nested pools. `--memory-mb`
limits the sum of the working-set estimates declared in `matrix.json`.
These are scheduling estimates, not OS memory limits or measured guarantees.
Defaults are four slots and 8192 MiB; the host example gives separate budgets
for a development workstation and a larger Linux host. Measure actual peaks
and durations during the first authorized run before increasing concurrency.

Functional jobs may overlap when their resources differ. Jobs sharing the
suite/dependency trees or mORMot network fixtures retain the `suite` resource
lock. Product rebuilds and Pulse run alone. RTL-test already uses private
scratch directories; Forms/tracker/MM outputs belong to the current job.

The reporting gate accepts `--jobs`: independent profiles and exception/lifetime
cases run in bounded pools, with private build directories, reports, attachments
and HTTP/TLS receivers. Every original cold rebuild and assertion remains;
cases within a stateful profile keep their order. Its timing samples start only
after all correctness workers finish. The matrix reserves four worker slots
for this gate. No shared PPU cache is introduced.

Full Devil reserves its worker slots from the outer controller. Its independent
stages have separate work directories. Its main sweep divides the same budget
between seeds and optimization profiles. Every seed has its own generated
sources; each profile executes in its own output directory, isolating the
`dvl_io_*.tmp` files. A cold build precedes its PPU-reuse build; the latter
actually omits `-B`. Cross-profile and Delphi comparisons still see all builds.
Determinism compares two cold builds before PPU reuse changes their artifacts.

Successful Devil stages and seeds have persistent checkpoints. Stage log hashes
and input identities guard reuse; failed stages/seeds repeat. Main checkpoints
retain compiler/runtime output used by the oracle. Reports are written as seeds
finish, so an interrupted sweep keeps its completed evidence. Wall-budget
forecasting happens between waves; a partial wave set cannot report success.

A discovery pass carries only while the test command, test sources, parameters
and dependency inputs match. Dependencies on the product build use the actual
installed toolchain and MM content identity. Only the `built_utc` line of the
installed `profile.txt` is excluded: rebuilding identical product bytes at a
later time does not change the product. All profile options and witness hashes
remain inputs; the complete receipt stays in the archive and evidence.
A compiler source/comment edit can
trigger a rebuild; if it produces the same toolchain bytes, unaffected expensive
tests keep their evidence. Changing test sources or product bytes invalidates
those passes. The build input list stays conservative; this is not a heuristic
that guesses whether a compiler change matters. Baseline byte changes require
a new ledger. State cannot move to another host or checkout. Old ledgers without
these identities are conservatively rechecked.

Each completed matrix job also records its log content identity. Missing or
changed logs prevent reuse and final completion; discovery repeats only the jobs
whose evidence was lost. Final Light verifies the Full logs before and after
replay, so a status entry alone cannot replace the original execution evidence.

The final replay rejects source drift or a rebuilt product that differs from
Full discovery. Carried observations retain their original HEAD; the final
record establishes byte identity and fresh Light evidence at the final HEAD.
Repack/audit history once after repairs, then finish HEAD-bound delivery checks
and final Light. Do not restart the heavy corpora solely to change commit IDs.

## Performance and delivery evidence

`pulse_release.py` uses the new Pulse report instead of the old long four-placement
A/A+B/C acceptance chain. The detailed placement workflow remains available for
investigating a particular code/layout effect. Short A/A controls remain part of
every release comparison; a failed control or mismatched semantic digest blocks
completion. Useful slowdowns and open numerical risks remain in `REPORT.md` for
human release review. A successful measurement is not approval of its trade-offs.

Archive smoke packages the installed toolchain, unpacks outside the repository,
places pinned MoonORMot beside it, builds/runs Debug and Release consumers, then
installs the archive through `build toolchain` in a separate checkout. This is
part of Full, including individual failure logs and binary witness hashes.

`FINAL_EXACT_HEAD_PASS` means the functional/delivery route and measurement
completed with the required provenance. It does not publish a release or turn
Pulse regressions into an accepted performance decision.

## Verification of the controller itself

```text
python -m unittest discover -s qualification/release -p "test_*.py"
python -m unittest qualification.suite.tests.test_devil_runner_contracts
```

These use temporary synthetic jobs, fake compiler calls and small runner
fixtures. They do not run the product qualification, Full Devil or Pulse.
The checks cover stage/host barriers, failure collection, nested budgets,
resume, changed source/product identities, PPU reuse and report validation.
They also run in public CI and the Light controller stage.

No new whole-release duration is claimed until the first authorized real run.
The 24 September Pulse observation was about 10 minutes plus under one minute
of confirmation per host. Historical sequential Full Devil timings are not
used as estimates for the new parallel runner.
