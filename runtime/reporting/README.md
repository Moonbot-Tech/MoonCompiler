# Moon.Diagnostics

In-process exception and thread reports for MoonCompiler applications on Win64
and Linux x86-64. Start with the [short usage and settings guide](../../doc/DIAGNOSTICS.md#start);
this README covers dependencies, callbacks, delivery and capture limits.

## Dependencies

The product toolchain's `fpc.cfg` already includes the unit and its static
instruction decoder. If building the toolchain from this checkout, build the
compiler and matching RTL first as described in the repository [README](../../README.md).
The module requires the matching RTL exception hooks and must not be mixed with
older PPUs.

Its ZIP and HTTP units use mORMot even when upload is disabled. The compiler
uses the project's own mORMot when present, otherwise the `mormot` clone beside
the toolchain; without either, the application cannot compile this module.
`MoonORMot.Need` rejects a MoonORMot older than the required version in
`runtime/moonormot.need.inc`. Normal application builds need no qualification
checkout or Python.

For the current backend on Ubuntu 24.04:

```sh
sudo apt-get update
sudo apt-get install libunwind8 zlib1g libssl3t64 ca-certificates
```

`libunwind8` supplies stack unwinding; mORMot uses native zlib for ZIP and OpenSSL
for HTTPS. Other distributions may name the OpenSSL runtime package differently
(for example `libssl3`). The package manager resolves dependencies, including
`liblzma5`. The module does not install packages or request privileges at runtime.
Win64 uses OS unwind APIs, mORMot's existing static compressor and SChannel TLS;
no curl/archive DLL is needed.

## File names and application data

```pascal
function ReportName(const Kind, Title: string): string;
begin
  Result := 'MyService_U_42';
  If Kind = 'manual' then Result := Result + '_XR';
  Result := Result + '_V123';
end;

procedure ApplicationData(Report: TDiagnosticReport);
begin
  Report.Add('operation', 'loading market history');
  Report.AttachFile('application.log');
end;

var Options: TDiagnosticOptions;
begin
  Options := Default(TDiagnosticOptions);
  Options.Directory := 'BugReports';
  Options.FileName := ReportName;
  InitializeReports(Options, ApplicationData, '1.2.3');
end.
```

The name callback supplies a **prefix**, not a path or extension, at report time.
The module appends `-PID-TID-yyyymmdd-hhnnss-zzz-sequence.txt` and creates the file
exclusively: existing reports are never overwritten. Unicode, spaces, underscores,
brackets and other valid filename characters are retained. Portable filesystem
forbidden characters (`<>:"/\|?*` and control characters) become `_`. The prefix
is limited to 48 UTF-16 code units without splitting a surrogate pair, leaving
room for the suffix within Linux's filename limit. An empty prefix uses `report`.
A failing callback uses the default name and records `filename_error`.

Callbacks must not depend on GUI queues or locks held by a failing/sampled thread.
They run while a report is being written, not on every exception capture.

`WriteExceptionReport('description')` inside `except` uses the original context;
`WriteManualReport('description')` samples all enumerated OS threads. Both return
the saved path. Files are UTF-8; attachments are streamed as hexadecimal data.
Linux report files are mode 0600. On Windows restrict the directory's ACL.

## Limit repeated reports

By default, the module permits **10 report attempts per process run**, shared by
all threads and by automatic, explicit exception and manual reports. Set the
limit before initialization:

```pascal
Options := Default(TDiagnosticOptions);
Options.MaxReportsPerRun := 10;
InitializeReports(Options, ApplicationData, '1.2.3');
```

Zero selects the default 10; negative values are rejected. To disable reporting,
use the switches below. The quota does not reset when capture is disabled and
re-enabled, nor when a manual report is requested. Only a new process starts
with a fresh quota; repeated initialization is not allowed.

Each permitted attempt reserves one slot under the existing report lock, before
callbacks, manual thread enumeration/sampling or file creation. Failed/partial
writes and failed uploads still consume that slot, so a broken disk or endpoint
cannot cause unlimited attempts. Once exhausted, writers return `''` without
creating files, sampling threads, invoking callbacks, packing or sending POSTs.
Already admitted reports may finish, but concurrent failures cannot exceed the
quota. There is no extra overflow report and no automatic retry.

This limits report production, not ordinary exception handling or early context
capture. A caught exception that is not explicitly reported consumes no slot.
Automatic unhandled-exception reporting may therefore be suppressed after the
quota is exhausted; the application's original termination behaviour is unchanged.

## Disable capture on expected-error paths

`SetThreadReportsEnabled(False)` disables this module in the current thread;
`SetReportsEnabled(False)` disables it process-wide. Both return their own
previous state, and both default to enabled. `ReportsEnabled` queries the
combined state of the calling thread.

```pascal
var Saved: Boolean;
begin
  Saved := SetThreadReportsEnabled(False);
  try
    // Work whose expected exceptions need no diagnostic snapshots.
  finally
    SetThreadReportsEnabled(Saved);
  end;
end;
```

Restore the saved state, not an unconditional `True`: nested suppression must
not enable its outer block. For a worker that never needs exception reports,
disable once at the start of `Execute`; new threads start enabled independently.
The process-wide switch is for process-wide policy, not a temporary local block.

Disabling bypasses early stack/context capture, snapshot allocation and report
writing/upload. Writers return an empty string; normal RTL raise/except,
backtraces, worker termination and other installed hooks remain intact. The
already installed hook checks and the RTL's own exception cost still exist.
Initialization also retains the module's 127-frame RTL limit while disabled;
deep-stack costs therefore need not equal an uninitialized RTL's shorter limit.
Switches do not destroy snapshots owned by existing exceptions or cancel a
report in progress. Re-enabling cannot reconstruct exceptions missed while off.

To request a manual report from a disabled worker, temporarily enable that
thread (and ensure global reporting is enabled). A manual report initiated in
an enabled thread still samples **all** OS threads, including workers whose
automatic exception capture is disabled.

## Optional ZIP and HTTP(S) POST

Delivery uses `TZipWrite`, `THttpMultiPartStream` and `THttpClientSocket` from
mORMot. No private ZIP encoder, multipart encoder, HTTP client or TLS bindings
are implemented here. No libcurl or libarchive is used by this backend.

Configure before `InitializeReports`:

```pascal
Options.PostURL := 'https://reports.example.org/upload';
Options.PostFieldName := 'el_upload_file_0'; // default; compatible with Eureka's HTTP field
Options.PostTimeoutMS := 10000;             // default, socket connection/I/O timeout
Options.PostSuccessText := '<EurekaLogStatus>0</EurekaLogStatus>'; // optional receiver acknowledgement
```

Each finished report is flushed and closed, then packed into a sibling `.zip`
with one deflated `report.txt` entry containing the report and its attached data.
The ZIP is sent as one `application/zip` file in `multipart/form-data`.
Compression and upload are streamed without a second whole-report buffer.
An existing ZIP is never overwritten. A failed new archive is removed; the
original report remains. Other threads are resumed and the report-writing lock
is released before packing or network I/O.

Sending is synchronous in the requesting thread. The socket timeout is not an
end-to-end deadline covering DNS and a peer that continues making progress.
There is no background queue, automatic retry or deletion after success.
Ordinary handled exceptions still perform no network work. TLS peer/hostname
verification stays enabled and redirects are not followed. HTTP 2xx is required;
if `PostSuccessText` is set, the UTF-8 response must also contain that exact text
(responses over 64 KiB are rejected).

The report survives every delivery outcome. A sibling `.txt.delivery` file
records `sent`, `http_status` and an error, never credentials or the server body.
Missing delivery status is **not** evidence of successful delivery. Failure to
write that status does not discard the report or replace the original exception.
An empty `PostURL` is the default: no packing or upload is performed. This does
not remove the compile-time mORMot dependency from the current module.

Reports may contain secrets from application data, stack memory and attachments.
Only configure an endpoint authorised to receive them. This is an ordinary ZIP
upload; the receiver must accept it. No production endpoint or credential is
embedded in this module.

## Hardware-fault evidence

Alongside the original general registers and stack, hardware-fault reports save:

- XMM0–XMM15, x87 ST0–ST7 and control/status/tag/opcode fields, MXCSR, directly
  from the OS context; values are raw bits, not guesses about Pascal types;
- up to 128 bytes before RIP and 128 from RIP (256 total), captured before exception unwinding;
- up to two ordinary memory operands of the failing instruction, their access
  widths/read-write flags and up to 64 readable bytes at each address; a distinct
  base-register address also gets at most 64 bytes;
- Linux's trap/error code and, for a page fault, the OS fault address.

Reports also retain the OS memory-region state at capture time for RIP, the two
decoded operand addresses and Linux's page-fault address. They distinguish
`mapped`, `unmapped`, Windows `reserved`, and `unavailable` when querying failed.
Mapped/reserved regions include their base, size and `rwx` access flags; Windows
also includes the native protection flags and guard status. These are virtual
memory mappings, not physical residency or proof that a particular object is alive.
An unmapped address need not have been freed: it may never have been valid.

Windows uses [VirtualQuery](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualquery).
Linux scans [/proc/self/maps](https://man7.org/linux/man-pages/man5/proc_pid_maps.5.html)
once for all addresses, with fixed buffers and a 1 MiB read bound, without heap
allocation or a stale shared cache. An I/O error, malformed/truncated data or
exhausted bound leaves unresolved addresses `unavailable`, not falsely `unmapped`.
The ordered kernel map permits stopping once every address is found or passed.
No new library is required. OS queries add cost on hardware faults; ordinary
software raises and manual thread samples do not perform these queries.
The measured addition for region metadata and the larger code window was about
1–1.5 microseconds per caught hardware fault on the Win64 test machine and
14–15 microseconds on the Linux test machine, without writing a report. See
[the dated measurements](../../doc/DIAGNOSTICS.md#memory-regions-and-the-256-byte-code-window);
these are separate hosts, not a Windows/Linux compiler comparison.

The queries precede `except`, so a page released or reprotected by the handler
does not overwrite its saved state. Other threads can still change mappings
concurrently: this is not an atomic process snapshot. OS-dispatched guard faults
may already have cleared Windows' guard bit before capture. Operand regions
describe the starting address; operand width and region size show crossings.
Linux additionally identifies the actual failing byte/page from the OS context.

Saved code is printed as readable Intel ASM using a
[private static MIT decoder](native/README.md). No EurekaLog source was copied.
The instruction at RIP is decoded from that exact address. Earlier bytes are
decoded only when a nearby unwind-table function start provides a boundary and
decoding reaches RIP exactly; otherwise they remain explicitly labelled raw bytes.
These instructions are nearby code, **not a record of which branches executed**.
The forward window stops at a known function end. Without unwind bounds it is
only linear decoding of the saved window, which can include padding or data.

Only one instruction is decoded during early capture, without formatting or new
allocations. FP capture copies the OS's saved 512-byte area, not live registers
after entry into `except`. Memory reads use OS self-process read APIs; inaccessible
or partial regions are labelled by the actual captured byte count. This is neither
a whole-heap dump nor a globally atomic snapshot. AVX upper halves/AVX-512 state,
FS/GS bases and historical memory contents are not captured. x87 pointer fields
are raw OS FXSAVE fields; their layout is platform-specific.

Ordinary software `raise` and manual thread sampling do not collect these extra
hardware fields. A stale pointer can explain an invalid access, but its current
value alone cannot prove who freed an allocation. A `double free` intercepted by
the diagnostic MM exits directly with its own first-violation message, **not** a
Pascal exception: Moon.Diagnostics does not fabricate an exception report for it.

## Scope and tests

See [the diagnostic guide](../../doc/DIAGNOSTICS.md) for capture timing, lifecycle
limits, partial reports, cost and [test instructions](../../doc/TESTING.md#diagnostic-reports).
The supported lifecycle is a static executable; workers must stop before unit
finalization. Full reports after arbitrary heap corruption or stack exhaustion
are not guaranteed. Optimisation and inlining remain enabled.

[License](LICENSE.md): LGPL with the FPC static-linking exception. External
libraries retain their own licences and distribution notices.
