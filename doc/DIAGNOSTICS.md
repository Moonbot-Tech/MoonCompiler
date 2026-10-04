# Diagnostic reports from inside the application

`Moon.Diagnostics` saves exception reports for Win64 and Linux x86-64. Reports
are saved locally before optional HTTP(S) delivery. No debugger or
separate crash-handler process is needed.

## Start

Use the product toolchain with mORMot on its unit path
([dependencies](../runtime/reporting/README.md#dependencies)). Linux also needs
`libunwind.so.8` at runtime. Add the unit and call `InitializeReports` once,
before starting workers or work you want to diagnose:

```pascal
uses Moon.Diagnostics;

begin
  InitializeReports;
  // Start application work and workers here.
end.
```

By default, reports go to `BugReports` beside the executable. The process must
be able to write there. No map-generation step is needed: Debug and Release
already embed the names and source lines in the executable. Keep those sections
when deploying it; stripping them leaves only addresses in the report.

| Event | What the application does |
|---|---|
| Exception unhandled on the main thread | Nothing else; a report is written before normal termination. |
| Exception escaping `TThread.Execute` | Nothing else; a report is written and `FatalException`/`OnTerminate` keep their normal behaviour. |
| Exception caught by the application | Call `WriteExceptionReport('description')` inside `except` if a report is wanted. |
| Acquired exception kept after `except` | Call `WriteExceptionReport(SavedException, 'description')` while the object is alive. |
| Hang or requested snapshot | Call `WriteManualReport('description')` from a responsive thread to sample all OS threads. |

Handled exceptions are not reported automatically. Explicit writers return the
saved file path, or `''` when reporting is disabled or its quota is exhausted.
Exception reports retain the original context, including after `raise;` and
`AcquireExceptionObject`; the application still owns an acquired exception.

## Settings

`InitializeReports('directory', DataProc, 'version')` accepts optional arguments.
For other settings, use `Default(TDiagnosticOptions)`, set only the fields you
need, then call `InitializeReports(Options, DataProc, 'version')`. For example:

```pascal
var Options: TDiagnosticOptions;
begin
  Options := Default(TDiagnosticOptions);
  Options.Directory := 'reports';
  Options.MaxReportsPerRun := 20;
  InitializeReports(Options);
end.
```

| Setting | Default | Effect |
|---|---|---|
| `Directory` | `BugReports` beside the executable | Report directory. An explicit relative path is resolved against the working directory during initialization. |
| `FileName` | No callback (`report` prefix) | Callback returning a filename prefix, not a path or extension. |
| `MaxReportsPerRun` | 10 | Maximum report attempts per process across all threads and report kinds; failed attempts count too. |
| `PostURL` | Empty | Enables synchronous ZIP upload by HTTP(S) after saving the local report. Empty means no upload. |
| `PostFieldName` | `el_upload_file_0` | Multipart field name for the ZIP. |
| `PostTimeoutMS` | 10000 | Socket connection/I/O timeout in milliseconds; not an end-to-end deadline. |
| `PostSuccessText` | Empty | If set, the successful HTTP response must contain this text. HTTP 2xx is always required. |

`DataProc` is an optional callback at report-writing time. Use `Report.Add`
for application fields and `Report.AttachFile` for attachments. The optional
version string is recorded in the report. Callbacks should avoid locks held by
a failed or sampled thread. See [filenames and callbacks](../runtime/reporting/README.md#file-names-and-application-data)
and [delivery details](../runtime/reporting/README.md#optional-zip-and-https-post).

`SetReportsEnabled(False)` disables capture process-wide;
`SetThreadReportsEnabled(False)` does so only for the caller. Both return their
previous state for restoration in `finally`. The default is enabled. See
[the switch details](../runtime/reporting/README.md#disable-capture-on-expected-error-paths).

## Try the example

The [example](../examples/diagnostics.dpr) runs with either profile. Omit
`-dRELEASE` for Debug:

```bash
toolchain/bin/fpc -dRELEASE examples/diagnostics.dpr
./examples/diagnostics
```

```powershell
toolchain\bin\x86_64-win64\fpc.exe -dRELEASE examples\diagnostics.dpr
.\examples\diagnostics.exe
```

The no-argument run writes one caught-exception report and one manual snapshot.
From the executable's directory, run each automatic case separately (use
`.\diagnostics.exe` in PowerShell):

```bash
./diagnostics conversion
./diagnostics file
./diagnostics collection
./diagnostics arithmetic 0
./diagnostics worker
```

These cover `EConvertError`, `EFOpenError`, `EStringListError`, `EDivByZero`,
and an exception escaping `TThread.Execute`. Each writes one report under the
example's explicit `reports` directory. The four main-thread cases exit with
code 1; the worker retains its `FatalException` and the process exits with 0.

For a source-built toolchain, rebuild the compiler and matching RTL first
(`./build compiler` or `.\build.ps1 compiler`); do not mix older PPUs with the
rebuilt RTL.

## Names travel inside the executable

The product build embeds DWARF3 names and source lines in applications and the
RTL/packages. The reporter reads them from the exact executable that failed;
no adjacent map, PPU, source file or postprocessor is needed. The reporting
gate also checks names with only the executable deployed. Keep that executable
for each released version and do not strip its DWARF sections.

External libraries without accessible symbols remain raw addresses. Optimized
inline frames and local variables are not reconstructed. The metadata enlarges
the file without disabling Release optimization or inlining.

## What is captured and when

Exception reports contain class/message, original address, thread ID, up to
128 stack addresses with available names/lines, 18 general-purpose register
values, and up to 4 KiB of readable stack memory captured before unwinding.
Hardware faults also include the OS's XMM/x87/MXCSR snapshot, up to 256 saved code
bytes with readable Intel ASM, small memory fragments addressed by the failing
instruction, and capture-time mapping/access information for the relevant addresses.
See [exact bounds and limitations](../runtime/reporting/README.md#hardware-fault-evidence).
They do not dump arbitrary heap objects or the whole process. Code and memory
are copied during capture, not reread later after the application enters `except`.

For an actual hardware fault, registers come from the original OS context.
For a normal Pascal `raise`, registers describe the capture point in the raise
path, not a retroactively reconstructed earlier instruction. Merely raising
an `EAccessViolation` object does not make it a hardware fault. The report
records this distinction explicitly.

Manual reports collect all thread stacks; they deliberately omit register and
memory dumps. Threads are sampled sequentially, so this is not a globally
atomic snapshot. A hung main can be sampled when another live application
thread requests the report. The module does not invent a watchdog or a way to
invoke itself when no thread can issue a request.

`ApplicationData` runs at **report-writing time**, in the reporting thread.
Use it for operation IDs, relevant state and log files;
those values are not automatically frozen at `raise`. Do not acquire locks
which the failing or hung thread may own. File attachments stream into the
same report as hexadecimal data, using a 4 KiB buffer; no whole-file copy is
held in memory. Hexadecimal encoding doubles the attachment's disk size.

Files are UTF-8 text, exclusively created under the requested directory. A
finished write ends with `MOON_DIAGNOSTIC_END`; `complete=False` means requested
stack data was unavailable/truncated or an optional report section failed.

Raw addresses, registers and captured memory are flushed before symbol lookup.
If lookup raises, `symbolization_error` explains the failure, remaining frames
retain their addresses, and attachments/application data are still attempted.
The reader is not retried for every frame of that report, but the next report
can resolve symbols again. An ordinary address with no symbol is not a reader
failure and is labelled `[symbol unavailable]`.

An exception from `ApplicationData` (including a missing attachment) leaves its
preceding output intact and adds `application_data_error`. The callback is not
restarted or resumed after its failing statement. The report is finished with
`complete=False` and its path is returned. This differs from the initial API,
which propagated callback failures and left the report unfinished.

File output uses one 16 KiB buffer per active report and handles short writes
and Linux `EINTR`. A real output failure is different from missing optional data:
it remains an I/O error for explicit callers, including failure to flush the
last buffer. Automatic reporting cannot replace the original application
exception with a reporter exception. Partial files must not be treated as
successfully finished reports. This buffer reduces write calls; it does not
make the allocating formatter safe after arbitrary heap corruption.

Reports can contain private application data and secrets from stack memory or
attachments. Linux creates files with mode 0600; on Windows use a suitably
restricted report directory. Nothing is uploaded unless `PostURL` is configured.

## Platform machinery and boundaries

**Linux:** install the system `libunwind.so.8` (for example `libunwind8` on
Ubuntu/Debian). It supplies in-process stack unwinding; symbol decoding and
report writing remain Pascal code. The local unwinder API is loaded during
initialization, so missing support fails there rather than at the first crash.
Deployment needs the executable, this library and its normal system
dependencies—not GDB or a crash-collection service.

One unused, initially unblocked real-time signal is reserved for thread
sampling. Raw capture uses no application MM, string formatting or application
locks inside its handler. The caller allows 250 ms per target thread. Blocked,
exited or unresponsive threads are named as unavailable, and a late signal
cannot claim a later request's buffer. Native pthreads are included. Missing
unwind metadata stops the walk rather than guessing return addresses from data.

**Win64:** thread enumeration, temporary suspension, context capture and stack
unwinding use OS APIs. Every successful suspension is paired with a resume in
`finally`; naming and file operations happen after resumption. No injected
code, debugger attachment or VMT replacement is used.

The supported lifecycle is a static executable, initialized once and with its
workers stopped before unit finalization. Dynamically unloading the reporting
unit, fork-after-initialization, asynchronous process destruction, exhausted
thread stacks and a corrupted/exhausted allocator are not qualified recovery
paths. The full formatter allocates memory and cannot promise a complete report
after arbitrary heap corruption. This is not a signal-only emergency minidump.
Exceptions before `InitializeReports`, raw non-`Exception` objects and foreign
native exceptions which the RTL cannot translate are outside automatic report
capture. None of these limits changes normal exception handling.

## Why RTL/compiler changes were necessary

The context must be captured before `except` destroys the original stack, and
must live as long as its exception object. Three optional RTL hooks provide
capture, replacement backtraces on Linux, and the existing `TThread` fatal
boundary. `Exception` owns the snapshot, including reusable RTL exceptions.
Without activation, hook pointers remain nil and no snapshots are allocated.
With activation, each live exception adds roughly 6 KiB; capture TLS is also
roughly 6 KiB per participating thread. The extra fixed storage is shared by the
exception's existing snapshot object, not separate heap allocations per register
or memory fragment. The additional static decoder adds about half a MiB of code
and tables, with no new runtime DLL/so.

Tests exposed two metadata defects, not a reason to turn optimizations off:

- Linux CIE declared 32-bit encoded addresses while emitting native-sized
  addresses. The encoding now matches the bytes. Existing handwritten
  `FpSysCall` push/pop wrappers gained CFA annotations, with identical machine
  instructions; their sleeping callers can now be unwound.
- Win64 counted scope-table bytes as code during intermediate assembler passes.
  That made a function's DWARF range overlap its neighbour. Explicitly placing
  those bytes in `.xdata` fixes names without changing the instructions or
  handler-table payload.

## Validation and cost

The [reporting gate](../qualification/suite/scripts/run_reporting_gate.py)
checks actual report contents, all-thread sampling, a hung main, hardware stack
data, deep recursion, concurrent throws, nested/acquired/reraised exceptions,
reusable RTL exceptions, callback failure, and existing exception/lifetime
regressions with capture both off and on. See [Testing](TESTING.md#diagnostic-reports)
for commands.

The additional [resilience tests](../qualification/suite/tests/smoke/diagnostic_resilience.pas)
inject reader failures, 73-byte short writes, output failures during application
data and final flushing, missing attachments, and recursive report requests.
They check actual retained bytes, recovery in the next report and unchanged
termination on an unhandled application exception. Injection points only exist
with `MOON_DIAGNOSTICS_TEST`; normal builds have neither their pointers nor calls.

These targeted hardening ideas were prompted by an independent
ExceptionLogger experiment.
Its source was not imported: capture, thread lifecycle and report ownership stay
with this module. Report production has its own configurable per-process quota.

On 2026-09-12 the reporting gate passed **201 Win64 and 214 Linux checks** across
O-/O2/O3 with the bundled MM. Both compiler/RTL pairs were rebuilt from the same
source tree. Coverage includes local
reports, mORMot ZIP/HTTP, failures, concurrent uploads, exe-only symbol lookup,
exception/lifetime regressions, and disabled/restored capture. Linux additionally
passes successful verified HTTPS with trust confined to the test child process;
Win64 verifies SChannel rejection of an untrusted root. Both platforms pass the
normal Debug/Release example builds and runs. After removing an unnecessary
test-only inline restriction, all 12 switch cases were rebuilt and rerun on each
platform. This is focused validation, not full compiler release qualification.

**Earlier software-raise benchmark:** the timed operation creates an exception, raises
it and catches it normally. Early capture happens before the application chooses
its handler, to retain the original context. Caught exceptions create no report:
symbolization, ZIP, disk output and HTTP are absent from this loop.

Fresh measurements: one warmed worker; seven fresh processes per mode, rotated
order. MoonCompiler O3 uses 30,000 raises per process, Delphi 12.2 Release uses
3,000; both warm up with 1,000. Each row compares the same exception loop against
its own separately compiled **no-module** baseline. The other three modes use
one identical executable, changing only runtime switches. Units below are
**microseconds per caught exception**, not milliseconds or total run time.

| System | No module | Enabled | Thread disabled | Globally disabled | Added when enabled |
|---|---:|---:|---:|---:|---:|
| MoonCompiler Win64, bundled MM | 1.83 | 3.74 | 1.86 | 1.87 | 1.91 |
| MoonCompiler Linux, bundled MM, lab server | 1.92 | 20.64 | 1.74 | 1.84 | 18.72 |
| Delphi 12.2, EurekaLog 7.16 with the MoonBot profile | 1.17 | 1704.21 | 141.59 | 144.56 | 1703.04 |

Observed no-module/enabled ranges across the seven processes were 1.69–1.99 /
3.30–4.59 µs on MoonCompiler Win64, 1.64–2.17 / 19.41–22.66 µs on Linux, and
1.11–1.43 / 1553.32–1928.66 µs on Delphi/Eureka. Disabled Moon.Diagnostics is
near baseline in this short-stack test; the smaller Linux disabled median is
noise, not evidence that the hooks accelerate exceptions. Normal RTL exception
work remains, as does the initialized 127-frame limit for deeper stacks.

The Eureka row uses the same worker/loop source and verifies actual activation
and deactivation. Its larger profile is **not feature-equivalent** to this
collector. Even disabled Eureka retains measured overhead in this configuration;
these results do not establish a universal ratio for all Eureka profiles.
Linux and Windows are different machines: compare within each row.

A separate no-throw loop measured a disable/restore pair: 2.43 ns on MoonCompiler
Win64, 1.89 ns on Linux, and 4.28 µs on Eureka. The optimized Win64 instructions
still contain both TLS state writes, not an eliminated loop. This is setter cost,
not exception cost; never mix the two. Prefer disabling once per operation or
worker lifetime, as the application already does.

Reproduction: [reporting gate](../qualification/suite/scripts/run_reporting_gate.py),
[shared benchmark source](../qualification/suite/tests/smoke/diagnostic_raise_bench.pas),
[Delphi/Eureka runner](../qualification/suite/scripts/measure_eureka_reporting.py).
Private compiler artifacts, raw samples and the proprietary Eureka profile stay
outside Git. No production MoonBot code or delivery endpoint was changed.

### Hardware evidence extension

The extension was checked separately with twelve controlled hardware-fault
scenarios on **O-/O2/O3, Win64 and Linux**: integer zero division and quotient
overflow, SSE zero division and invalid square root, deferred x87 zero division,
nil-field access, read-only write, misaligned SIMD load, an index into a guard
page, a released parameter, a released object's virtual call, and a readable
eight-byte fragment immediately before an inaccessible page. All 72 exception
reports retained the required evidence. Tests overwrite live FP state and, in
one case, release operand memory in `except` before writing the report: this
checks that the report uses the saved bytes, not a later reread.

The report retains the RTL's exception class, not a decoder's replacement:
`Low(Int64) div -1` currently arrives as `EIntOverflow` on Win64 and `EDivByZero`
on Linux. Saved `idiv` operands distinguish quotient overflow from a zero divisor
even when the class alone does not. This extension does not change RTL mapping.

The two diagnostic-MM double-free controls terminated with the expected
first-violation message and exit 218; they are not counted as exception reports.
Ten decoder controls per platform check addressing, 32-bit address truncation,
RIP-relative addressing, two memory operands, unsupported FS state, LEA and
truncated instructions. Clean and PPU-reuse linking both pass. The existing
reporting gate remains **201/201 Win64 and 214/214 Linux**; normal Debug/Release
example builds and runs also pass. The compiler/RTL binaries for these tests
come from `412d1ad76`; subsequent source commits at the time changed qualification,
not the tested compiler or RTL.

Additional capture cost was measured in a separate out-of-tree test: real invalid
read or integer zero division inside an empty `except`, not a user-written
`raise`. Seven fresh processes per variant, 10,000 caught faults each, rotated
order. No reports are written in the timed loop. Values are median **microseconds
per caught fault**; the baseline column has no diagnostic module at all.

| System / actual fault | No module | Before extra evidence | After | After, thread disabled |
|---|---:|---:|---:|---:|
| Win64 / invalid read | 2.70 | 4.14 | 6.14 | 2.68 |
| Win64 / integer division | 2.03 | 3.74 | 5.10 | 1.97 |
| Linux / invalid read | 7.23 | 17.85 | 19.49 | 7.41 |
| Linux / integer division | 4.85 | 15.83 | 17.94 | 4.88 |

The observed addition is about 1.4–2.1 microseconds, not free. Linux timings had
noticeable host noise (for example the new invalid-read result ranged from
17.55 to 22.36 microseconds); do not interpret Windows/Linux ratios as a compiler
comparison. These rows also must not be directly compared with the earlier
Eureka software-raise benchmark. The test executable grew by about 465 KiB on
Win64; no runtime decoder library is deployed.

### Memory regions and the 256-byte code window

The next extension, checked on 13 September 2026, adds capture-time mapping state,
base/size and access rights, and increases saved code to at most 128 bytes before
RIP plus 128 from RIP. The preceding hardware-evidence cost table predates this
extension; it must not be used as the cost of the current combined collector.

New checks pass on O-/O2/O3: **30/30 Win64 and 63/63 Linux**. They inspect actual
reports for read-only/no-access/unmapped memory, reserved Windows pages, execution
from an NX page, an operand crossing into a no-access page and the enlarged code
window. Linux additionally tests map prefixes split between reads, long paths,
gaps, missing/malformed/truncated input and the read bound. Twelve hardware-fault
scenarios also pass in all three modes on both platforms; their 72 reports retain
the previously required register, operand and code evidence. The two diagnostic-MM
double-free controls still terminate with exit 218, not a Pascal exception.
The complete reporting gate was rerun with this extension: **201/201 Win64 and
214/214 Linux**, including exception lifetime, worker capture and report delivery.

The same separate caught-fault benchmark was repeated: seven processes per
variant, 10,000 faults per process, no report writes. Median microseconds:

| System / actual fault | Before this extension | With regions and 256-byte window |
|---|---:|---:|
| Win64 / invalid read | 6.67 | 8.11 |
| Win64 / integer division | 5.68 | 6.75 |
| Linux / invalid read | 20.18 | 34.68 |
| Linux / integer division | 18.04 | 33.46 |

These are host-specific capture costs, not report-generation costs or a new
Delphi/Eureka comparison. Linux's new invalid-read samples ranged from 33.66 to
37.06 microseconds. A single bounded `/proc/self/maps` scan answers all requested
addresses; ordered VMAs allow stopping when an address is found or passed, without
a stale cache. Software raises and manual samples do not make these OS queries.
Test sources, raw reports and samples remain in the external diagnostic test stand.
