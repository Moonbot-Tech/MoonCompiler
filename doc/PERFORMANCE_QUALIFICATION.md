# MoonCompiler Performance Qualification

Pulse is MoonCompiler's in-repository benchmark system. It measures the
compiler, RTL, and memory manager from one Pascal source file and does not
accept a speed result until the semantic digest matches.

## The question Pulse must answer

One invocation must explain whether generated programs run better, worse, or
make a concrete trade-off: which useful work improved, what became more
expensive, on which inputs and machine, and why that cost is acceptable.
This concerns executable performance, including RTL and MM, not compiler build
speed. Case counts and a global geometric mean cannot decide product quality.
A dense size/alignment matrix is not a collection of independent votes.

Reports distinguish application-shaped workloads, ordinary operations,
isolated code-generation mechanisms, boundary inputs, and measurement controls.
Every slowdown needs its cost and practical meaning. A microbenchmark percentage
is not an application percentage. Mixed gains and losses do not automatically
constitute an accepted trade-off; their relationship and importance must be
explained. A Windows improvement with Linux unchanged is a Windows improvement,
not an inconclusive result.

Self-copy `Move(X,X,N)` is removed from the performance corpus. Its slowdown is
an accepted trade-off for ordinary `Move(X,Y,N)` avoiding an address-equality
check. Semantic self-copy tests remain. Do not reopen it as a performance defect.

Measurement uncertainty is a limitation of Pulse, not a property of the compiler.
Do not hide a clear large effect behind a precision threshold: a cost ratio of
0.26–0.28 establishes the direction even without a 0.5% estimate. Conversely,
do not label unresolved measurements as unchanged. A run with unresolved useful
operations has not yet provided a complete answer.

The release report (`pulse_both.py`, or `pulse_full.py` for one host) starts with
the top 10 improvements in useful work, the top 10 regressions for the next
optimization TODO, and explicitly accepted trade-offs. It ranks relative cost
changes, with one representative per operation/size family, and
shows both hosts. This ranking does not invent application-frequency weights.
Isolated instruction/ABI tests and measurement controls remain in `CASES.md`;
they cannot fill the release top 10. `MEASUREMENTS.md` contains technical details.

Run `python qualification/performance/tools/pulse_both.py --config <hosts.json>`.
Copy `qualification/performance/tools/pulse_both.example.json` for the host
configuration. The tool synchronizes the measurement sources into the configured
Linux benchmark checkout; use a dedicated checkout. `--cases program/pattern`
restricts the scope; an omitted selector runs the complete corpus.

One machine's standard pass is `pulse_full.py --baseline-toolchain <A>
--candidate-toolchain <B> --output <dir>`: the whole corpus, 12 fresh pairs per
case and independent confirmation of the selected headline changes and sentinels.
On a free machine it takes minutes; main 1e040aa37 against itself on 29.09,
including the build of the programs:

| Machine | CPU | Pairs of cores | Cases run alone | Pass |
| --- | --- | ---: | ---: | ---: |
| AMD3 | Ryzen 5 3600 (Zen 2), 6 cores | 2 | 66 | 12.6 min |
| AMD4 | Ryzen 7 7700 (Zen 4), 8 cores | 3 | 42 | 9.5 min |

`REPORT.md` and `MEASUREMENTS.md` state the time of every pass.
Before measuring, Pulse prints an advisory when this host has no L2 calibration
or fewer than two measurement core pairs. It reports the selected scope and
planned case pairs; stage progress and rejected-process counts remain visible
during the run. Elapsed time alone is not a failed measurement or a timeout.

Pulse measures on the CPUs it is given, on Linux those of its affinity (`taskset -c`), on Windows
the cores of its process mask, and needs four physical cores at least: pairs of
them measure, the rest carries the runner, which keeps off the measurement cores
and their SMT siblings. Other work on those cores costs rejected processes and
waits (below); give Pulse free cores for the length of a pass instead of
measuring on a loaded machine. A program that pins more workers than the
multithread set has cores (`threads`: eight, `PINNED_WORKERS` in
`pulse_full.py`) is left out on a smaller machine and named in `REPORT.md` and
in the result's `unhostable`.

A program that needs a unit an older toolchain does not have
(`PROGRAM_TOOLCHAIN_UNITS` in `pulse.py`: the `zlib` program and `System.ZLib`,
which the release predates) is not built with that toolchain; the run compares
it only between the systems that built it and names it in `REPORT.md` and in
the result's `left_out`, instead of failing. The release report accepts such a
program when only the released toolchain left it out; the candidate builds
every program.

The release comparison has no Delphi side, and the first release has no `System.ZLib`
to compare with. `zlib_delphi_gate.py` (Win64 full stage, next to the release
report) measures the eight product forms of the `zlib` program against Delphi
12.2 - the six of `System.ZLib` and the two ZIP forms of `System.Zip`, which
compresses through the same zlib - and fails when a form is slower: every
process pair of the row above 1.05.
A row passes when every pair is at or below 1.05, whatever Pulse says about the
stability of its ratio; pairs on both sides of the line are measured again,
and still undecided they fail as unresolved, not as slower. The zlib build of
28.09 morning, which copied a byte a step, made the websocket frames
1.247-1.305 times as slow as Delphi in every pair. Like any Windows Pulse run it
needs a quiet core: on 29.09 the host's measurement pair decided all six rows
at the first attempt (pairs within 0.853-0.936 for the deflate forms and the
websocket, 0.467-0.493 for inflate), while on a core the host's builds shared,
single processes ran up to twice as slow (the websocket from 736 to 1451 cycles
per frame under Delphi) and two rows stayed unresolved after three attempts.

The measurement plan is fixed before reading results: 12 fresh process pairs
per case, with alternating core/order assignment. A separate unscored calibration
chooses equal iteration counts for both sides, including batched Move cases.
The faster side determines the work count so large gains are still measurable;
the slower side is allowed to take longer than the calibration target. Both the
one-iteration oracle and measured-work digests must match. `--pairs` can change
the fixed plan (minimum 6); there is no optional stopping after a pleasing result
and no shared confirmation budget starving the last categories.

Pair i calls the measured case with the stack pointer at phase i·336 mod 4096
on both sides (`--stack-phase grid`, the default; `fixed` keeps the executable's
own phase, `N` puts every pair on one phase). The harness reads
`PULSE_STACK_PHASE`: unset or `fixed` is the plain call, `N` the phase. It takes
the shift from its own rsp, so warmup, calibration and samples meet the case at
one phase. Without the grid the phase is frozen per build and environment on
Windows and random per process on Linux; with it the median covers the page
reproducibly on both. `PULSE_CASE` prints the case-entry `stack_rsp`;
`MEASUREMENTS.md` shows each side's cheapest and dearest process with the phase
of the dearest.

A case of a concurrent category runs alone when its L2 misses exceed 0.2 per
1000 cycles on this machine, or were never measured here: unknown traffic is not
light traffic, so a missing calibration lengthens the run instead of weakening
it. `pulse_l2_calibration.py` measures the rates into
`qualification/performance/pulse_l2_misses.json`, one section per machine keyed
by its host name; another host, even with the same OS, uses none. The section
records the counted event: the core's requests to L3 with hardware prefetches,
on Linux Intel `0x4f2e` and on Linux AMD (Zen 2 to Zen 5) the sum
`0x964+0xff71+0xff72` (demand misses of both L1 caches in L2 plus L2 prefetches
missing L2), both defaults; Windows names its xperf source with `--event`, and
any event may be a sum `a+b`. The runner logs `PULSE_EXCLUSIVE` for every case
run alone this way; `MEASUREMENTS.md` names the calibration used and the cases
missing from it. The calibration writes a host section only when every discovered
`workloads/stream-*` case was measured clean and is over the threshold, and both
register-only controls (`calibration/asm-dependent-add`, `codegen/dep-add`) were
measured clean and are under it. Other cases rejected three times are listed as
`unclean` and omitted from that host section, so Pulse runs them exclusively.
The host section replaces its predecessor instead of retaining any old rates;
the clean rates are judged and written unrounded. The calibration
spreads the cases over the single-CPU cores of `pulse_full` (a case's own L2
misses do not depend on another core), judges every process by its core and its
SMT sibling as a pass does, and repeats a rejected case on a core it has not run
on yet, up to three processes: a core whose sibling stays busy does not decide a
case. On a hybrid CPU (Raptor Lake) Pulse measures on the big cores only: the
harness's cycle counter belongs to the `cpu_core` PMU and does not run on an
E-core.
Windows calibration accepts `--windows-profile-interval` in 100 ns xperf
units (default 1221) and records the chosen interval in its host section.
A different interval still needs the same clean-process and all discovered event controls;
it never changes Pulse's own measurement settings.

A single-CPU process starts on its core only when the 2 s before it held no
foreign work there: the core's busy time in that window, less the CPU time of
the runner's own processes inside it (Windows `QueryProcessCycleTime`, Linux the
child's rusage), is within 5% of the window. A watch reads the idle of every CPU
every 10 ms, and the window never starts inside one of the runner's own
processes. After its own last process the core rests 50 ms, idle, before the
next (`--core-rest-ms`). A process is rejected, and its pair repeated within the
pair's three attempts, when the core admission or SMT sibling check fails. A
core that stays busy is waited for at most 2 s plus the rest plus 1 s, then the
process starts and is rejected. `MEASUREMENTS.md` counts the rejections.

On Windows, single-core categories target 60 ms of total timed work across
three samples. This gives a calibration margin above the existing 50 ms minimum
for observing sibling idle during useful work. When that window is observable
and its counters are present, the sibling must be at least 99% idle across the
timed samples. Process creation, exit and later runner bookkeeping are outside
that work window. A shorter window or missing sample counters retains the
whole-process sibling check; it does not receive an automatic pass. Linux keeps
its existing durations and whole-process sibling check; the multithread policy
is unchanged. The equal-work calibration,
semantic checks, twelve process pairs and independent confirmation still
apply.

From 25.09 to 29.09 the runner slept 2 s before every
process instead: it saw the same foreign work, and a full pass took 2.3 hours on
HEL1 and 15-16 hours on a machine without a calibration section. The
runner keeps itself off the measurement cores and their siblings and creates the
process suspended, so the benchmark has its CPU from its first instruction. The
pairs of a stage run in rounds, pair r of every case before pair r+1 of any
(the first round, with each case's iteration calibration, whole before the
others): the pairs of one case spread over the whole stage, and a passing
disturbance of the machine meets one pair of many cases, not every pair of one.

The runner sets `PULSE_CHAIN=1`:
65536 dependent adds before and after every sample, outside every counted window,
give each sample's core clock against the TSC (`chain_before`/`chain_after`; the
shorter of the two, since an interrupt only lengthens a chain). On
Windows a single-CPU case costs its thread's cycles (TSC ticks while it ran) at
that clock: core cycles, as the PMU counts them on Linux. `PULSE_CASE` also
prints the data a case works on, passed with its own `PulseRunCaseData` call:
`data_src` and `data_dst` for Move, `data_items` for the storage of a prepared
list or dictionary and the AoS array. `PULSE_SAMPLE` prints `block=`, the block
a case body allocated in that sample, for the IntToStr and dictionary-build
cases.

For each metric, Pulse reports the median paired cost ratio, its exact
distribution-free two-sided confidence interval of at least 95% (inversion of
the binomial sign test), and the full observed range. With 12 pairs the interval
is the third through tenth ordered ratios; all 12 observations remain in raw
data. The interval estimates the typical process cost, **not a worst-case bound
or a latency percentile**. A gain/loss clears the 1% CPU/time or 5% memory
threshold with the entire median interval; equivalence fits entirely inside it.
When every process of one side costs less CPU/time than every process of the
other, the row is that direction whatever the interval says, marked
non-overlapping (with equal distributions such a split of 12 and 12 has the
chance 7.4·10⁻⁷); memory keeps its threshold.
Ranges crossing a decision boundary remain explicit numerical risks. These are
per-case exploratory intervals, not a simultaneous guarantee for the whole
corpus. Changelog claims must name the tested operation, inputs and host.

After the screen, each host independently repeats the selected top 10 gains and
top 10 losses with 12 new pairs, another A/A control, and one case per process
(including Move). The same direction must be established in both passes before
it enters the release top. The two estimates stay separate. A failed confirmation
becomes an explicit open risk; an unconfirmed runner-up cannot quietly replace
it. This guards against selecting a lucky process mode out of a large corpus.
Ordinary Move gains (the accepted trade-off) and the ordinary `RoundTo(-2)`
sentinel also receive confirmation so the report can quantify these decisions.

Raw records are stored in `result.raw.json.gz`; compact `result.json` binds them
by SHA-256. Reanalysis requires the matching raw data and a separate output
directory. It never overwrites the measurement or interprets another host's
counters using the local OS. Direction, uncertainty, correctness and the human
decision to accept a trade-off remain separate. Exit 0 means measurement completed
with matching semantics, A/A and enough valid pairs; it is not a release PASS.
Losses and uncertain directions remain in the report and never become a generic
console verdict. In JSON, `measurement_completed` describes execution;
`passed` remains the stricter legacy acceptance flag, not a release decision.

The placement-family workflow below is a separate, slower diagnostic for
attribution and acceptance. Its range rules are not the release report's median
confidence interval.

## What is measured

Tests are grouped by what they measure, not by the order in which they were
added:

| Group | Examples |
|---|---|
| Codegen and ABI | calls, loops, branches, integer/FP, records, managed ABI |
| RTL | strings, numbers, formatting, streams, encodings, tasks |
| Collections | list/queue/stack/dictionary, growth, search, deletion, managed values |
| Memory manager | small/medium/large allocation, realloc, threads, fragmentation |
| Algorithms | sort, search, hash, crypto, compression, numeric kernels |
| JSON | parse/generate through the mORMot API actually used |
| Heartbeat | compact models of parser, order book, buffers, correlation, FFT, and server hot paths |
| Product forms | MoonBot's own hot routines with its data layout: trades, candles, market lookup, the batch over markets |

A microbenchmark reports the cost of one specific operation. Heartbeat checks
that local wins survive in a composition where pointers, managed values, calls,
loops, and register pressure coexist.

`product-forms` holds the hot routines of the product as MoonBot writes them
(`MarketsU.pas`, `TradeTypes.pas`, `HelpClasses.pas`, `Vars.pas`), with the
data where MoonBot keeps it: the per-trade `UpdateRecentPrice`, the windows
over the trade history (`GetMaxPrice`, `CalcBv_SV`, `CalcBv_SV_Precise` under
its lock with the ring), the hour deltas over the packed 5-minute candles, the
rebuild of the candles from the trades, a market looked up by name through the
list and through the dictionary, the batch over all markets through the base
`TEnumerator`. The data are fields of the market objects, the market list and
the globals of a unit of their own; the case body takes the list into a local
and calls the routine. A form measured with its data in globals of the program
is another form: the inliner does not treat them as another unit's data, and
the first getter rows of `repairs` did not show the product's cost that way.
Delphi 12.2 builds the program too, with one digest per case, so its rows are
in the default Delphi/Moon matrix as well as in the release comparison. New
rows go into a program of their own: rows added to an existing program move the
code of all its rows, and their numbers change with it.

## Compared systems

- `delphi` — Delphi 12.2 Win64 with its standard FastMM4;
- `moon` — MoonCompiler with the bundled MM;
- `moon-default` — the same MoonCompiler with the standard FPC MM;
- `moon-baseline`/`moon-candidate` — two MoonCompiler versions for causal A/B.

Stock FPC is not a common column: it does not build the tested Delphi 12.2
surface with the same Unicode RTL. Its components are compared in isolation
where physically possible; for example, `moon` versus `moon-default` separates the
allocator's contribution from the compiler and RTL.

## Measurement rules

Every comparison case:

1. is built by the systems selected for that comparison from one source file;
2. performs the same workload and prints a semantic digest;
3. is warmed up before measurement;
4. runs in several separate processes, each from a new hash-verified copy of
   the canonical executable; the disposable image is removed after the process;
5. uses the median sample of each process, then adjacent baseline/candidate
   process ratios, without discarding slow processes or selecting one timing mode;
   TSC is used for multi-thread cases and when thread cycles are unavailable;
   `pulse_full.py` takes Windows thread cycles at the sample's chain clock, while
   `pulse.py` and the placement families compare the thread cycles themselves.

Two-system and placement-family comparisons use local mirrored B,C,C,B blocks.
All process centers, their full spread, and paired-ratio spread remain in the
report. A common frequency change can leave the paired ratios stable; different
timing modes must not be trimmed away to manufacture stability. A paired spread
over 15%, or a middle-half sample spread over 15% within a process, leaves the
measurement unresolved. This detects uncertainty; it does not identify its cause
as machine noise, code placement, or runtime state. Same-binary A/A runs are the
control before attributing a small difference to changed code.

A case loop keeps what it needs in locals. A global reloaded in the loop sits
at a page offset fixed by the link; when the case's own stores hit that offset,
the reload waits on them (4K aliasing). `pulse_move` reloaded its size right
after each copy to a page start, and Zen 3 made its copies of 127-320 bytes
up to 2.3 times as slow, depending on the layout of the code behind `Move`.
`check_case_loads.py` disassembles every case body and work body and rejects a
load from `.data`/`.bss` whose address is the same on every pass of its loop
unless `case_loop_loads.txt` lists it with its reason: a global of the product
itself, the global inputs or table of a workload kernel as written, a managed
input whose stack copy would be reloaded all the same, or a prepared input a
store trace of the case found unaliased. The address comes from RIP, from an
absolute address the ELF linker wrote into the instruction, or from a register
that holds a global's address (`lea` of it on Win64, `movabs` on Linux) or an
index the loop computes again on each pass from values it does not change
(`GetterKeys[I and 15]` in the loop over `J`, through `lea` or `cdqe` too) or
reads from a stack slot it does not write (an outer counter the compiler
spilled). An address with a register the loop carries from pass to pass, or
loads from other memory, walks the case's data, an element or a pointer per
pass: that is the measured work, not a reload, and it is not judged. Win64
reads such an element through a register loaded by `lea`; an ELF image without
PIC writes the array's address into the instruction beside the index,
`[rax*8+0x6100b0]`, which the judge took for a global until 29.09 (120 reads in
12 programs of the Linux corpus). A load only one target's code has is listed
in `case_loop_loads_win64.txt` or `case_loop_loads_linux.txt`, read with the
common list for images of that target.
`test_check_case_loads.py` runs it over every program the tree's toolchain
builds.

The Medium stage of the release runs these contracts:
`qualification/performance/tools/run_contracts.py` runs every test of the
Pulse tools, the coverage manifest against the programs included, and the
case-loop judge over every program, on Win64 and on Linux. A skipped judge
fails the run on either platform. On 28.09 the rows of `repairs` added that week
reloaded their globals in 22 loads, and nothing ran the judge.

For placement families, one shared estimator feeds the main report, family
summary, and acceptance gate: median paired ratio per placement, then median
over the four placements. A direction must survive all four placements. Mixed
directions remain placement-dependent; overlapping timing ranges never prove
parity. Unresolved rows retain diagnostic ratios but do not enter aggregates,
and a green subset cannot produce a full acceptance PASS.

The existing filler units move later linked units, but did not move the checked
program-local ABI and loop procedures. Old four-member families therefore do not
by themselves prove four placements of those targets. Each Pulse program now
also includes `pulse_program_prefix.inc`: variants 1/2/3 keep an ordinary Pascal
procedure containing 64/128/192 extra bytes before the program's other procedures.
Its sole call finishes before `PulseInitialize`; the plain variant has no prefix.
Actual shifts also include the procedure's prologue and section alignment.
The unit fillers remain in place. `Pulse-Family.ps1` verifies representative
target addresses and instruction hashes whenever ABI or loops are requested;
other-only runs make no claim of passing this check. It can also be run with
`python qualification/performance/tools/check_program_placement.py <result-directory>`.
Use `Pulse-Family.ps1 -Cases <program/case>` for a focused row. The checker
distinguishes procedure entries by their 4 KiB page offset because equal mod64
addresses can occupy different decoded-instruction cache sets. The output records entry
and loop addresses, including mod64;
four distinct addresses do not imply every possible intra-line alignment was tested.

Rows explicitly tagged `asm-reference` or `calibration` are diagnostic controls.
Their semantic digests remain mandatory, while their times do not contribute to
product geomeans or product regression counts. A reference slowing down is not
automatically a slowdown in the RTL routine compared with it.

In reports, the ratio is `Moon / reference`:

- `0.80×` — MoonCompiler takes 80% of the reference time, so is `1.25×`
  faster;
- `1.00×` — parity;
- `1.20×` — MoonCompiler is 20% slower.

Historical reports include geometric means as descriptive statistics only;
they do not establish the value or acceptability of a change.

## Product RTL profile

The product Unicode RTL and the application-facing packages are compiled with
one optimisation profile, declared in `scripts/rtl-profile.txt` and read by
both build drivers (`build.ps1`, `build`). Until 2026-09-17 the drivers built
the RTL at `-O2` while every application and every measurement above was
compiled at `-O3`, and nothing recorded or checked that. The profile is now
`-O3 -gw3`, chosen on the RTL profile stand by the same acceptance gate as a
compiler placement rule: the two candidates were built from the same tree and
the same compiler (variants A = `-O2` and K = `-O3`), the quick Pulse
`hot-rtl` and `repairs` programs ran in four placements times two runs on
both machines, and `stand_ab_gate.py` judged the families.

| K (`-O3`) against A (`-O2`), same tree and compiler | Win64 (Zen 3) | Linux (Xeon W-2295) |
|---|---:|---:|
| geomean of the family medians | `0.953` (196 cases) | `0.938` (188 cases) |
| hot-rtl | `0.952` (141) | `0.917` (133) |
| repairs | `0.957` (55) | `0.990` (55) |
| faster beyond the placement band | 57 | 52 |
| slower beyond the placement band | 3 (5–9%: `encoding-utf8-getbytes-32`, `ustr-equal-mismatch-last-12`, `ustr-pos-char-hit-32`) | 4 (`comparemem-64-equal` 1.24, `ring-64/256/1024` 1.10) |

The Linux exceptions are understood and are not the profile itself. The
hand-written `CompareByte` kept its bytes while its entry moved onto a
64-byte line under the placement rules, which re-cut its internal branches on
the 32-byte boundaries; nobody had laid it out. It and the other hot
assembler routines of the RTL were then laid out by hand
([ASM_LAYOUT_RULES.md](ASM_LAYOUT_RULES.md), stand round P25 against K):
`comparemem-64-equal` `0.68` on the Xeon (7.2 ns, under the `-O2` build's
8.5) and `0.90` on Zen 3, `ustr-equal-*` `0.77..0.86` and `0.91..0.92`,
`astr-compare-less-12` `0.82` on the Xeon, nothing slower on either host.
The ring cases inline `GetMem`/`FreeMem` at `-O3` and the register allocator
then keeps the loop's accumulator in memory (Zen 3 is 5% faster on the same
code); that one is in the [Backlog](BACKLOG.md).

The installed toolchain proves its profile: the driver writes
`<toolchain>/profile.txt` (the exact `OPT=` string of the RTL and package
compiles, `placement_draft` - whether the code placement draft of the
internal assembler was on for them, `MOONCOMPILER_PLACEMENT=1` - the
compiler hash, and hashes of `sysutils.o` and the package witness
`generics.hashes.o`), and
`qualification/build-driver/rtl_profile_gate.py` checks that the recorded
options start with the declared profile and that witness units (`types`,
`sysutils`, `math`, and `classes` where the RTL make compiles it on its own)
rebuilt with the recorded command lines into a copy of the installed units
are byte-identical to the installed objects. It also rebuilds
`Generics.Hashes` against the installed package/RTL set and compares every
non-debug section, relocation and symbol with the installed package object.
The witnesses are compiled with the recorded placement mode, whatever the
caller's environment says (the stand chains switch the draft on for their
own compiles). The recorded compiler, the placement mode and both witness
hashes are mandatory. The gate runs after the
configuration contract gate in the qualification and release workflows and in
both stand chains.

## Historical snapshot

The following snapshot was recorded on 2026-08-30 at source HEAD
`64067c9949c24f688c29c048ec3051ddce0b5847`. It predates Stage 2 and the
current fail-closed runner. It is retained as a frozen comparison baseline,
not as evidence or a performance claim for the current HEAD. Release requires
the full fixed-work `pulse_full.py` route after the semantic gates pass, with
source and installed-artifact provenance matching the qualified candidate.

| Workload | Reference | Cases | MoonCompiler result |
|---|---|---:|---:|
| Common cases before/after the repair series | original Moon/Unleashed baseline | 243 | `1.31×` faster |
| Full stable matrix | Delphi 12.2 + FastMM4 | 744 | `1.20×` faster |
| Heartbeat | Delphi 12.2 + FastMM4 | 20 | `1.22×` faster |
| RTL | Delphi 12.2 + FastMM4 | 77 | `1.45×` faster |
| Collections | Delphi 12.2 + FastMM4 | 48 | `1.37×` faster |
| JSON | Delphi 12.2 + FastMM4 | 18 | `1.16×` faster |
| Allocation | standard FPC MM with the same MoonCompiler | 15 | bundled MM `1.65×` faster |

Across the 243 common cases, the original baseline was at parity with Delphi
(`0.9978×`), while the final snapshot was `0.7625×`. The gain across that common
set therefore comes from the MoonCompiler repair series, rather than being
inherited from the original fork.

Full data:

- [final report](../qualification/performance/evidence/release-final-20260830/REPORT.md);
- [evidence and methodology for this run](../qualification/performance/evidence/release-final-20260830/EVIDENCE.md);
- [history of every substantial stage](../qualification/performance/PULSE_HISTORY.html);
- [known deferred tail](BACKLOG.md).

## How to reproduce

For a full release comparison on both configured hosts:

```text
python qualification/performance/tools/pulse_both.py --config <hosts.json>
```

For one host:

```text
python qualification/performance/tools/pulse_full.py --baseline-toolchain <A> --candidate-toolchain <B> --output <dir>
```

Use each toolchain's matching memory-manager source through `--baseline-mm-source`
and `--candidate-mm-source` when it is not available at the default location.
These commands cover the complete selected corpus with calibrated equal work,
twelve pairs and independent confirmation. The complete release controller calls
this same runner; it does not require a separate legacy `long` pass.

On a busy desktop, `pulse_full.py --single-cpus 12,14` can select one quiet pair
of available physical CPUs while retaining the normal multithread CPU set.
The example numbers are specific to a machine: inspect its topology and idle
state first. The selected CPUs must form complete pairs and leave two physical
cores for the runner. The effective plan is printed and recorded. For the full
release controller, use the host setting `pulse_single_cpus` described in the
[release runner guide](../qualification/release/README.md).

### Targeted diagnostic comparisons

The following `pulse.py` commands retain the older multi-system workflow for
focused investigations and reproduction of historical results. They do not
replace the fixed-work release route above.

Win64 medium slice from a RAD Studio command environment:

```powershell
python qualification\performance\tools\pulse.py run `
  --mode medium --systems delphi,moon,moon-default `
  --tag local-medium
```

Without Delphi, Linux measures MoonCompiler and the contribution of the bundled
MM:

```bash
python3 qualification/performance/tools/pulse.py run \
  --mode long --systems moon,moon-default \
  --tag linux-long
```

In this diagnostic runner, `quick` is a preliminary check, while `medium` and
`long` use progressively longer sampling. None of these names selects the
current full release protocol. First run correctness gates for the affected
area; a benchmark does not substitute for semantic qualification.

If a completed `medium` or `long` run is rejected only for process drift, use
`pulse.py retry <result-directory>`. It verifies the recorded executable hashes
and reruns only the rejected cases with their complete mirrored system matrix,
creating a fresh image from each canonical executable again. The removed image
path in the manifest is evidence of the original launch, not the retry input.
Old log hashes and the prior instability remain in the retry history. A later
quiet sample does not erase the earlier distribution or turn that row into a
qualified speed claim; it remains unresolved pending a controlled explanation.
After three targeted retries, a persistently unstable measurement remains a
semantic check and is marked `DRIFT`; its diagnostic ratio stays in the report,
but it is excluded from every aggregate and ranking.

`quick` runs all cases of a program in one process; `medium` and `long` run one
case per process. Earlier cases can change allocator, cache, and runtime state,
so a quick/medium difference is not by itself a regression or a noise estimate.
Preserve the selected mode and case history when reproducing it. Results from
the former single-image runner remain diagnostic and require a fresh run for
acceptance with the new method.

A frozen release baseline from before `profile.txt` may be compared using
`Pulse-Family.ps1 -LegacyBaselineRevision <revision>` (or the gate's
`--legacy-baseline-revision`). This exemption applies only to the baseline and
still requires compiler, configuration, RTL/package witness, and MM hashes.
It records exactly which old binaries ran; it does not retroactively prove the
old build profile. The candidate must retain its normal recorded profile.

For a compiler or RTL repair, the primary causal run compares pinned
`moon-baseline` and `moon-candidate` toolchains with the compact, Moon-only
`repairs` program. It is deliberately separate from the default Delphi/Moon
matrix; a repair whose form is a form of the product also gets a row in
`product-forms`, with the product's data layout, which Delphi builds too. Every case requires an independent semantic oracle; where before/after
timing cannot prove code quality, it also requires a reviewed ASM contract or a
same-process reference kernel with an explicit overhead budget.

## How to accept an optimization

A change is accepted only when all four conditions hold:

1. the oracles and target ABI match;
2. the claimed buyer becomes faster;
3. neighbouring forms are checked; any sustained extra cost has an explicitly
   reviewed trade-off explained in terms of ordinary application work;
4. ASM or a phase split shows exactly which work disappeared.

A ratio change without a machine-code change does not by itself establish a
compiler repair: inspect placement, data addresses and runtime state. If a
composite slows down, first separate allocation, copying, lifetime and the
algorithm itself; one aggregate number is not a
license for an arbitrary RTL change.

## Comparable Pulse placement families

The allocator workload uses complete 16384-allocation size periods. Calibration
changes the number of periods, not the size distribution. Cross-thread free
keeps one 16384-block batch live at a time. Worker checksums are checked against
independent arithmetic expectations.

The bundled memory manager is the product allocator. Eight persistent workers
are selected for fixed preferred rows before timing. Read-only allocator probes
record the actual small-class and backing-owner sharing graphs; virtual pointer
values themselves are not compared between processes. Different class collisions
make a comparison unresolved. A changed backing-owner graph also makes automatic
acceptance unresolved; an intentional memory-manager policy change needs a
separate resource explanation before interpreting its timings.

Cross-thread free currently records only the freeing workers. Its allocations
come from the main thread, whose actual allocator row/class/owner topology is
not recorded. This case therefore remains UNRESOLVED even when worker graphs
match; fixed block distribution and peak alone do not prove comparability.

Every measured case logs its actual callback and a common anchor outside the
timed region. Thread cases additionally log the worker code root. Linked PE/ELF
evidence includes addresses, sizes, raw and normalized hashes, calls, branches,
loop positions, and known direct callee shapes. Known direct callee identities
and instruction fingerprints must also match across fillers; a changed body
under the same symbol name is rejected. Runtime addresses are matched by
anchor offsets, so an ASLR base change does not change code identity. ELF builds
retain static relocation records with `--emit-relocs`; those distinguish address
immediates from ordinary numeric constants.

The placement instruction fingerprint retains ordinary constants and direct
callee identities. Four fillers import the same number of modules and declare
the same prefix procedure, avoiding changes to anonymous types and generic
specialization IDs. Known code relocations and NOP padding are canonicalized.
Unknown data targets and indirect callees remain explicit evidence gaps; this
fingerprint is not a proof of full program semantics or a complete dynamic call
graph. Semantic oracles and the actual input contract remain required.

Use fresh executable copies and a complete matched family for acceptance.
`quick` is diagnostic. Composite operations remain product cases. Only the
previously accepted `Move(P^, P^, N)` self-copy exception is a diagnostic no-op.
An unresolved placement, worker graph, semantic oracle, or timing mode must not
be reported as a performance improvement.

The current PE corpus conservatively leaves seven cases unresolved because a
known direct callee refers to anonymous data without exact linked object
identity: hot-rtl booltostr-true/supports-hit/supports-miss; repairs
stringbuilder-replace; rtl datetime-encode-decode/datetime-format/datetime-ms-arith.
This is an evidence limitation, not a product performance regression. A later
reader may establish bounded data-object identities using exact object bounds,
contents and relocations; nearest-symbol/VMT guesses cannot close this gap.
The 59-case medium methodology matrix does not contain these seven cases.
