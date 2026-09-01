# Performance qualification v2

The architecture, mandatory diversity axes, and measurement methodology are
described in
[`../../doc/PERFORMANCE_QUALIFICATION.md`](../../doc/PERFORMANCE_QUALIFICATION.md).

The current result is published in [`CURRENT_RESULTS.md`](CURRENT_RESULTS.md),
and deliberately deferred improvements are in
[`../../doc/BACKLOG.md`](../../doc/BACKLOG.md).

## Current state

Pulse consists of independent programs across compiler, RTL, MM, and workload
layers. `local-pressure` measures the cost of calling a procedure with
0/100/300 separately named unmanaged and managed locals. These are not arrays:
the generator deliberately creates separate symbols to measure the actual stack
frame and the compiler's init/final code.

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

Each executable accepts `quick`, `medium`, or `long` mode. Only `quick` is used
during development; `medium` runs at important checkpoints; `long` is for
final qualification.

The coverage contract is checked separately:

```powershell
uv run qualification/performance/tools/check_coverage.py
uv run qualification/performance/tools/check_coverage.py --release
uv run python -m unittest discover qualification/performance/tools
```

The development check requires a complete plan and the presence of already
implemented sources. The release check additionally fails while at least one
mandatory family remains `planned`.

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
& "$Root\.moonbot\toolchain\bin\x86_64-win64\fpc.exe" `
  -n "@$Root\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg" `
  -Mdelphi -O3 -B `
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
