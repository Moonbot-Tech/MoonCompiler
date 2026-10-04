# Performance qualification v2

Pulse must explain how generated programs changed: useful work that became
cheaper, work that became more expensive, and the importance of any trade-off.
Start with the [purpose of Pulse](../../doc/PERFORMANCE_QUALIFICATION.md#the-question-pulse-must-answer).
Case counts are not a product verdict. `Move(X,X,N)` is no longer a performance
case; its accepted cost buys the ordinary copy path an omitted equality check.

One release comparison: `python qualification/performance/tools/pulse_both.py`
(host settings: `tools/pulse_both.example.json`). `REPORT.md` contains the top 10
useful gains, top 10 practical regressions/TODO, accepted trade-offs and numerical
open risks. Every case remains in `CASES.md`. The default plan uses 12 fresh pairs
with equal work; controls and isolated codegen probes do not fill the release top.
Selected gains and losses then receive an independent 12-pair confirmation
inside the same invocation. Unreproduced effects stay visible as open risks.
One machine alone: `python3 qualification/performance/tools/pulse_full.py
--baseline-toolchain <A> --candidate-toolchain <B> --output <dir>`, minutes on a
free machine; how long on each of our machines and what Pulse needs from the
machine are in [the qualification doc](../../doc/PERFORMANCE_QUALIFICATION.md#the-question-pulse-must-answer).

Pulse builds Moon programs with the selected toolchain's complete `fpc.cfg`
and `RELEASE` defined. `moon-base.cfg` alone does not select the application's
language or Release profile. For old toolchains without `moon-base.cfg`,
`tools/pulse_legacy_release.cfg` supplies the options of the September 6
release's build driver, after its template config. Both configuration inputs
are included in the recorded identity.

`test_pulse_profile.py` checks the effective language, Unicode, namespace,
defines and runtime checks with a real compiler when `PULSE_TEST_TOOLCHAIN`
names an installed toolchain. `PULSE_TEST_MM_SOURCE` optionally selects its
matching allocator source. Deliberately wrong defines, I/O checks and
assertions must still fail that program.

The architecture, mandatory diversity axes, and measurement methodology are
described in
[`../../doc/PERFORMANCE_QUALIFICATION.md`](../../doc/PERFORMANCE_QUALIFICATION.md).

The standalone `tools/qualify_measurement_method.py` requires
`--control-toolchain <frozen toolchain> --control-mm-source <its allocator source>`.
The allocator must agree with that toolchain's configured unit pin. Its work64/work66
control, also used by `pulse_full.py`, changes exactly one decoded counter instruction
in each of the four small statistical functions; image size and all other bytes stay
identical. These control builds retain symbols explicitly. Binutils `objdump` and
`nm` are required, as for the placement checks.

The current result is published in [`CURRENT_RESULTS.md`](CURRENT_RESULTS.md),
and deliberately deferred improvements are in
[`../../doc/BACKLOG.md`](../../doc/BACKLOG.md).

## Current state

Pulse consists of independent programs across compiler, RTL, MM, and workload
layers. `local-pressure` measures the cost of calling a procedure with
0/100/300 separately named unmanaged and managed locals. These are not arrays:
the generator deliberately creates separate symbols to measure the actual stack
frame and the compiler's init/final code.

The RTL IntToStr, FloatToStr, Str, and numeric Format cases repeat a fixed block of
32 inputs per calibrated iteration and report 32 operations per iteration.
Calibration changes only the number of whole blocks, so the argument and
digit-count distribution stays identical across measured systems.

The separate `dictionary` program checks `TDictionary<TKey,TValue>` scaling at
100 and 10,000 elements. The matrix includes `UInt64 -> UInt64`,
`UnicodeString -> UInt64`, and `UInt64 -> UnicodeString`; each type separately
measures growing build, build with preset capacity, mixed hit/miss lookup, and
remove/reinsert churn. The broader `rtl-collections` retains independent cases
for collisions, custom comparer, enumeration, and the remaining containers.

The separate `mormot-json` program measures the actual JSON API of the bundled
established product mORMot from one source for Delphi 12.2, Moon with the
bundled MM, and Moon with the standard FPC MM. It generates JSON outside the
measured section and separately checks record, `TDocVariant`, and object
load/round-trip on small, medium, and large documents. The `json` group remains
low level: `byte-scan-*` is only byte traversal, while `parse-*` is an in-house
teaching parser; these results are not presented as mORMot speed.

The `zlib` program compresses on the product's paths through `System.ZLib`, as
MoonBot calls it: a MoonStreamer trade packet (raw deflate through
`TZCompressionStream` and back through `TZDecompressionStream` with
`CopyFrom(Z, 0)`), the 1 MB candle blob of MoonProto (zlib format), the market
history at the fastest level written part by part, and 256 permessage-deflate
frames of an exchange websocket inflated on one stream. The `engine-*` cases do
one piece of that work twice, through `System.ZLib` and through `mormot.lib.z`,
so one run compares the zlib a MoonCompiler program links for each (the same
one zlib; built with `-uMOONCOMPILER_SYSTEM_ZLIB`, `mormot.lib.z` takes mORMot's
own - its static zlib 1.2.11 on Win64, the system libz on Linux) and, on
Delphi, the RTL zlib behind both. The `zip-*` cases zip the market history
into an archive in memory and read it back through `System.Zip`, as MoonBot
stores a market's data. The data is generated
alike for every compiler; a digest depends on what went in and came out, never
on the compressed bytes. The release has no `System.ZLib`: the program is left
out of a release comparison; `tools/zlib_delphi_gate.py` holds the product forms
to Delphi 12.2 in the Win64 full stage instead.

The `heartbeat` program is one composite application-shaped program with
several independently measured hot-path lines. It does not construct its own
server: it contains no network, files, logs, or infrastructure—only the
computational core of application work. On deterministic synthetic data, the
original data loop separately and end-to-end measures: generating exchange-info
JSON in two ways (direct String+Format code and mORMot DocVariant must produce
byte-for-byte identical documents—an embedded differential gate), parsing
DocVariant into market objects with a string symbol dictionary, byte-scanning a
trade-message stream with dictionary lookup into rings of 16-byte trades,
Sum(P*Q)/VWAP/min-max/rolling aggregates over the rings, radix-2 FFT and paired
correlation over price series, generic market sorting through an interface
comparer, and a text report through `Format`. This emulates the shape of an
application workload, not a MoonBot measurement: the code is standalone; only
the data distributions resemble production.

Additional lines model a large exchange order book (binary-search delta with
rare delete/reinsert and market-order sweep/VWAP), `Int64` sorting on
random/sorted/reverse/duplicate-heavy data, a binary request/cache/response
pass with a session dictionary and preallocated response, and a preallocated
timer min-heap. The complete JSON/market proof is calculated outside the
measured section, and the new state/output lines hash the whole final result;
these values are part of the cross-compiler oracle. A fast result must not come
at the cost of an unnoticed state or output distortion.

The `product-forms` program holds MoonBot's own hot routines with its data
layout (`product-forms/pulse_product_model.pas`, the bodies of `MarketsU.pas`,
`TradeTypes.pas` and `HelpClasses.pas` trimmed to what they compute): the
per-trade update of the recent price, the windows over the trade history, the
hour deltas over the packed 5-minute candles, the rebuild of the candles, a
market by name through the list and the dictionary, the batch over all markets.
The data are fields of the market objects and globals of that unit, not of the
program; Delphi 12.2 and MoonCompiler give one digest per case.

Each executable accepts `quick`, `medium`, or `long` mode. Only `quick` is used
during development; `medium` runs at important checkpoints; `long` is for
final qualification.

`repairs/pulse_repairs.dpr` is the compact causal performance gate for a repair
series. It is intentionally Moon-only and is run against pinned
`moon-baseline,moon-candidate` toolchains; the default Delphi/Moon run excludes
it. If a completed medium or long run fails only on process drift,
`pulse.py retry <result-directory>` repeats only the rejected mirrored case
matrices and never turns persistent drift into an aggregate result.

The coverage contract is checked separately:

```powershell
uv run qualification/performance/tools/check_coverage.py
uv run qualification/performance/tools/check_coverage.py --release
uv run python -m unittest discover qualification/performance/tools
uv run qualification/performance/tools/check_case_loads.py <pulse executables>
```

The development check requires a complete plan and the presence of already
implemented sources. The release check additionally fails while at least one
mandatory family remains `planned`.

## Measurement controls

The method A/A batches and the long preflight's A/A and 64-to-66 work control
use one stack phase: `PULSE_STACK_PHASE=0`, so each case enters with
`rsp mod 4096 = 4088`. A random initial stack can put a spill at the same page
offset as a data load and change the cost of identical bytes. For example,
the StdDev control on Haswell was about 10% slower at one such phase; its
clean core, sibling and frequency checks still passed. The canonical phase
keeps that variable constant in the measurement controls, including retries.
Multithread controls keep their ordinary call path. Actual full Pulse pairs
continue to use the selected stack grid; this control is no guarantee that
every workload or stack phase is stable. The recorded phase, raw samples,
quality checks and accuracy thresholds remain part of the result.
Each raw process log and result record retains the full program and case name.
The per-attempt directory uses a stable program/case digest plus repeat and
attempt numbers, avoiding a duplicate long case name in nested release output
paths without merging distinct cases or retries.

## Why a row goes red with the same code

The CPU does not decode a hot loop again and again: once decoded, its
instructions sit in a small cache of decoded instructions (the "op cache",
Zen 3: 4 K macro-ops) and the front end replays them from there. That cache
is a shelf of **64 boxes with 8 slots each**. Which box a piece of code lands
in is decided by nothing but its address: every 64-byte line of code goes to
box `(address / 64) mod 64` — the line's position inside its 4 KiB page. A
slot holds up to 8 consecutive decoded instructions of one line, and a new
slot starts wherever the fetch *enters* the line: at the function entry, at
the instruction after a `call` (the return lands there), at a jump target.
So a 64-byte line with three such entry points takes three or four slots.

A hot path is a handful of lines spread over several functions. Which box
each line falls into is set by the linker, which lays functions out by their
sizes; nothing chooses the boxes on purpose. Usually the lines spread out and
everything fits. Sometimes three hot lines of three different functions land
at the same page offset — the same box — and need nine slots of its eight.
Then every iteration one of them is thrown out and fetched again through the
decoders, then the next one, and the front end runs at decoder speed for the
whole path: on the dictionary update case that was +20% with byte-identical
instructions, ICFetch 100 per 1000 cycles instead of 0.3, no cache misses, no
mispredicts. Moving *any one* of the three lines by 64 bytes — any other
offset — made the same bytes 4% faster than the baseline. A build that
happened to be fast (`wantprefix=false` in the handoff) was fast because a
padding change had shifted the RTL by 64 bytes and one tenant left the box;
the DS prefixes it was credited with cost nothing (measured in pure assembler
on three machines: a prefix is free while the instruction stays ≤ 8 bytes).
The full proof with the patched binaries is in
`doc-int/experiments/prefix-lab/DICT_REGRESSION.md`.

What follows from that:

- **One linked executable is one lottery ticket.** The same source, linked
  with a different padding or one more unit, draws different boxes. This is
  the "coin" of `doc/ASM_LAYOUT_RULES.md` and why Pulse measures four
  placements of every binary (`-dPULSE_FILLER_k`): a baseline/candidate
  ratio from one ticket each is the lottery, not the change. The family
  estimator (`stand_ab_gate.py`) is the judge; a red single number is not.
- **The instructions of the slow build are innocent until the boxes are
  counted.** A red row whose disassembly is the same (or nearly) as the
  green one is the boxes with high probability; the fix is a placement, not
  an emitter change, and any emitter change would move the lottery again.
- **The worst tenants are small hot functions with several `call`s in one
  line** (a 67-byte `SetValue` with two virtual calls: entry + two return
  addresses = three entry points, four slots) and hot loops whose head and
  return addresses share a line. Fewer hot lines means fewer tenants: after
  the flat dictionary path (`evidence/dictionary-flat-20260921`) the whole
  update loop lives in two functions and its family spread fell to 0.3%.
- Placing entry points and return addresses on purpose (a linker or
  compiler that spreads the hot lines of one path over the boxes) is
  possible and was not done; until then the answer to a red row is the
  diagnostic below.

## A red row: first the op-cache sets, then the code

Before touching the emitter or the RTL for a row that got slower with the
same instructions (the tool uses the vendors' words: a box is a *set*, a slot
is a *way*):

1. Profile the case on both sides (elevated ETW timer sampling, one run each):

   ```powershell
   powershell -File qualification/performance/tools/profile_xperf.ps1 -Out base.txt -Command "<baseline exe> <case args>"
   powershell -File qualification/performance/tools/profile_xperf.ps1 -Out cand.txt -Command "<candidate exe> <case args>"
   ```

   Several runs share one hidden elevation: `-Jobs jobs.txt` with one
   `<dump><TAB><command>` line per run; each run keeps its own dump.

   On Linux: `perf record -e cpu-clock:u <exe> <args>; perf script -F ip > cand.txt`
   and `--profile-format perf` below (binutils `objdump`/`nm` on the path; the
   executable must carry symbols, `-gw3`, like every Pulse build the placement
   gate accepts).

2. Count the hot lines per set:

   ```powershell
   python qualification/performance/tools/opcache_sets.py <candidate exe> --profile cand.txt --min-samples 2 --suggest
   ```

   A set marked `OVERFLOW` (more estimated entries than ways) that the
   baseline does not have is the cause; `--suggest` names the smallest
   single-function move that clears it, `--shift SYMBOL=+64` shows the
   occupancy after such a move. Without a profile, `--hot REGEX` marks whole
   functions (every line, cold parts too) and `--pulse RESULT --case NAME`
   takes the measured Pulse body with its direct callees — a first look only:
   virtual and indirect calls are not followed.

3. Confirm it is placement, not code: run the case through the placement
   families (`scripts/Pulse-Family.ps1`, `-dPULSE_FILLER_k`). A collision that
   appears in one family and not another is the address lottery; the family
   estimator of `stand_ab_gate.py`, not the single number, accepts or rejects.

Exit code 1 means at least one overflowing set; `--json` writes the
occupancy for a side-by-side diff. `test_opcache_sets.py` holds the model's
own negative controls (no overflow without a hot collision, cold lines of a
hot function not counted).

## Updating generated source

From the repository directory:

```powershell
uv run qualification/performance/tools/generate_local_pressure.py
```

The generated include is kept in Git. After generation, review it as an
ordinary source diff. The generator is not run on every build.

## MoonCompiler, Win64 Release

```powershell
$Root = (Get-Location).Path
$Source = "$Root\qualification\performance\local-pressure"
$Output = "$Source\build-moon"
New-Item -ItemType Directory -Force $Output | Out-Null
& "$Root\toolchain\bin\x86_64-win64\fpc.exe" `
  -n -dRELEASE "@$Root\toolchain\bin\x86_64-win64\fpc.cfg" -B `
  "-Fu$Root\qualification\performance\common" `
  "-FE$Output" "-FU$Output" `
  "$Source\local_pressure.dpr"
& "$Output\local_pressure.exe" quick all
```

## Delphi 12.2, Win64 Release

Open a RAD Studio command environment or call `rsvars.bat`, then:

```powershell
MSBuild.exe qualification/performance/local-pressure/local_pressure.dproj `
  /t:Build /p:Config=Release /p:Platform=Win64
& qualification/performance/local-pressure/build-delphi/local_pressure.exe `
  quick all
```

Both processes pin the benchmark thread to the first available CPU themselves.
Logs are compared without manually retyping numbers:

```powershell
uv run qualification/performance/tools/compare_local_pressure.py `
  qualification/performance/results/local-pressure/delphi.log `
  qualification/performance/results/local-pressure/moon.log `
  --baseline-name Delphi --candidate-name Moon
```

The comparator calculates `ticks/call` from short batch samples. The primary
number is the half-sample mode of the dense cluster; upper interrupt/deschedule
outliers are filtered only when they exceed
`median + max(12 * MAD, median)`, that is, at least twice the median. The
report retains median, mean, min, max, and the exact count of discarded samples.
Raw logs are never replaced by a summary table.

Gross `ticks/call` includes loop and indirect-call overhead and is therefore
the honest primary number. The separate derived `case - empty` table shows the
body cost relative to an identical empty call site; it does not replace the
gross result. The cost of two TSC reads is measured once per batch, published
as `tsc_overhead`, and not silently subtracted.

`results` and build directories are intentionally excluded from Git. The final
qualification runner stores versioned evidence separately together with
compiler/config/MM, source, and executable hashes.
