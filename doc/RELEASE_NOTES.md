# MoonCompiler 2.5.0: smaller applications with complete runtime metadata

Release builds now keep the information deployed applications need for exception
reports: function names, source files, lines and address ranges. Debugger-only
descriptions of local variables, parameters and types are omitted from Release;
Debug retains full information, including the SDK units. Linux compresses the
remaining diagnostic sections automatically. No new runtime dependency is added.

Generic specializations shared by multiple units no longer carry separate copies
of equivalent code and runtime type descriptions. Type identity, reflective
discovery, attributes, virtual dispatch and managed-value lifetime are preserved.
Immutable RTTI names and parameter descriptions are shared without changing the
public RTTI record layout. Runtime RTTI is distinct from debugger metadata and is
retained wherever the language and application require it.

Linux GNU assembler builds (`-Aas`) preserve the same shared generic ownership,
including mixed native/GNU assembler objects and PIE. Canonical symbol names are
quoted where AT&T syntax would otherwise interpret them as immediate operands.

Equivalent diagnostic records are compacted after linking. Linux stack-recovery
tables use shorter standard encodings while retaining the rules for every
instruction address. Interrupted prologues and epilogues, foreign C frames,
exceptions and shared-library calls have dedicated runtime checks. Long function
names and line-table boundaries are also covered by permanent regression tests.

The Release profile uses separate SDK units and `release-compact` application
directories. Build systems that inspect static symbols can retain them with
`-Xs-` before their own packaging or signing step. See [Building Applications](PROJECT_BUILD.md#profiles)
and [Diagnostics](DIAGNOSTICS.md).

Install the complete SDK and rebuild application and third-party PPUs. The PPU
format changed for shared generic ownership; mixing old and new compiled units
is rejected. `MOONCOMPILER_FULLVERSION` is 20500, `CompilerVersion` is 2.5, and the
FPC base version remains 3.3.1. MoonORMot 15 remains required.

---

# MoonCompiler 2.4.17: smaller Linux executables with retained diagnostics

Linux applications can keep runtime function names and source lines while using
zlib-compressed DWARF. Both standard ELF compressed sections and GNU `.zdebug_*`
sections are supported by the RTL reader, so ordinary exception backtraces and
`Moon.Diagnostics` use the same implementation. Compression remains an explicit
application build step; see [Diagnostics](DIAGNOSTICS.md#optional-compression-on-linux).

The reader now bounds section and record reads, rejects damaged compression data
and prevents malformed debug metadata from trapping report generation in a loop.
Cleanup preserves pending I/O state, and concurrent backtraces no longer replace
the process-wide symbol lookup hook. Original exception addresses remain available
when names cannot be recovered.

The existing statically linked zlib engine is shared with `System.ZLib`; no new
runtime DLL/so or application `uses` entry is required. Decompression happens only
when symbols are requested. It trades report-generation CPU and temporary memory
for disk space, and `Moon.Diagnostics` frees decoded buffers after each report.
Windows and uncompressed Linux executables retain their existing deployment form.

Permanent checks transform real binaries, compare names and lines, damage section
headers and compressed streams, and exercise report lifecycle and concurrent lookup.
These checks also run against unpacked release archives.

Install the complete SDK and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20417; `CompilerVersion` remains 2.4 and the FPC base
ABI remains 3.3.1. MoonORMot 15 remains required.

---

# MoonCompiler 2.4.16: shared project profiles

Helper programs and tests can select an existing project profile directly:

```sh
fpc --project-profile=App.mooncompiler tests/ContractTest.dpr
```

The selected profile retains its unit aliases, path order, conditional
directives and early defines. Its paths are relative to its own directory;
command-line settings still take precedence. It replaces the automatic
source-side profile, so build scripts no longer need to parse profile lines
themselves. Ordinary `@file` response/configuration semantics are unchanged.

Relative `#INCLUDE` and `$PROJECTDIR` now work during the early profile pass
as well as the full pass. This also repairs automatic profiles whose included
defines select the toolchain's Debug/Release configuration.

Permanent Windows/Linux checks cover alias collisions, path precedence,
relative outputs, Unicode paths, conditions, early defines, invalid selection,
the `fpc` frontend and repeated embedded compiler invocations. Profile checks
also run against the unpacked SDK. See [Project Build](PROJECT_BUILD.md#large-project-file).

`MOONCOMPILER_FULLVERSION` is 20416; `CompilerVersion` remains 2.4 and the
FPC base ABI remains 3.3.1. MoonORMot 15 remains required.

---

# MoonCompiler 2.4.15: portable RC resource paths

- The bundled `fpcres` accepts Windows path separators in RC file references
  on Linux, including doubled and mixed separators. Delphi-generated RC files
  can embed their existing resource files without rewriting those paths.
  The common repair covers external RCDATA, custom resource types, bitmaps,
  icons and cursors while preserving the RC directory used for relative paths.
- Quoted and search-path `#include` references also accept Windows separators.
  UTF-8 include filenames remain Unicode through filesystem lookup. Missing,
  malformed or excessively nested includes now stop with a parser error instead
  of reading standard input or overrunning the include stack.
- Ordinary resource strings and their escapes retain their existing meaning.
  This repair does not map Windows drive letters to Linux mount points or
  change filename case and search-directory policies.

Permanent Windows/Linux checks verify embedded bytes, path variants, includes,
failure cases and clean Debug/Release compilation through `-FF`. The same
checks run against the unpacked SDK archives. Publication requires successful
qualification of the exact release commit on both platforms, without Pulse.

Install the complete 2.4.15 SDK so its resource compiler is updated as well.
`MOONCOMPILER_FULLVERSION` is 20415; `CompilerVersion` remains 2.4. MoonORMot 15
remains required.

---

# MoonCompiler 2.4.14: Unicode overloads, reliable warnings and faster Linux text conversion

- Calls such as `MatchText(Value, ['instrument_discovered', 'wallet_discovered'])`
  preserve Unicode when choosing between corresponding ANSI and Unicode
  open-array overloads. The repair also covers `MatchStr`, `IndexText`, `IndexStr`
  and application overloads. Previously, an ANSI choice could lose characters
  and produce a false match on a limited codepage. Typed arrays and unrelated
  overload preferences retain their normal rules.
- Warning settings are restored before saving a nested generic replay. A generic
  dependency that disables its own warnings no longer silently disables warnings
  in a subsequently compiled application unit. Explicit warning suppression and
  push/pop remain effective.
- Linux x86-64 UTF-8/UTF-16 conversions use a direct RTL path, avoiding two eager
  iconv converters per thread and their intermediate native buffers. Other
  codepages retain iconv support. Valid text, malformed-sequence replacement,
  terminators, codepage tags and thread cleanup retain their existing contracts.

In deterministic complete-string comparisons on the Hel1 Linux stand, the UTF
path was about 1.7–5.9 times faster. A 120-worker idle-thread comparison used
about 7.9 MiB less native allocated heap. These are conversion and thread-lifecycle
measurements, not a claim of the same gain in whole-application speed or RSS.

Permanent checks include an independently compiled Delphi 12.2 overload oracle,
actual RTL calls under native/CP1251/UTF-8 codepages, warning-state tests with
fresh and reused PPUs, and Linux UTF correctness and converter-allocation checks.
The public calls and UTF checks also run against unpacked release archives.
Publication requires Windows and Linux qualification of the exact release commit;
Pulse is not part of this release's correctness qualification.

Install the complete 2.4.14 SDK and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20414; `CompilerVersion` remains 2.4. MoonORMot 15
remains required.

---

# MoonCompiler 2.4.13: managed-value and exception lifetime repairs

- RTTI writes use normal managed assignment when replacing a live value, releasing
  its previous ownership. The repair covers strings, interfaces, dynamic arrays,
  variants, managed records, field-backed properties and callback var/out
  arguments. Self-assignment, custom record copy operators, failed casts and fresh
  result buffers retain their respective contracts. Ordinary class-variable-backed
  properties now reference their actual static storage, including from a PPU.
- On Linux, leaving an exception handler releases its runtime wrapper and trace
  even when `AcquireExceptionObject` transfers the exception object to the caller.
  The acquired object remains valid until its new owner frees or raises it.
  Completed handlers no longer leave stale records in the exception stack.
- On Windows, an exception replaced by a throwing `finally` releases the old
  pending handler record correctly. Hardware exceptions and normal
  Exit/Break/Continue unwinding remain distinct from pending Pascal exceptions.
- `$R` resource lookup first tries the exact filename. If it is absent, a unique
  ASCII case-insensitive match in the same directory is accepted using its actual
  filename; ambiguous matches produce an error. Existing resource search order
  and PPU source-path handling are preserved.

Permanent ownership checks cover Debug, Release O2 and Release O3 on Windows
and Linux. Acceptance checks object destruction, restored exception stacks and
zero residual memory-manager allocations, as well as returned values. The checks
also run against both unpacked release archives. Publication requires successful
Windows and Linux qualification of the exact release commit. Pulse is not part
of this correctness release.

Install the complete 2.4.13 SDK and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20413; `CompilerVersion` remains 2.4. MoonORMot 15
remains required.

---

# MoonCompiler 2.4.12: fast ready-event waits on Linux

Linux `TEvent.WaitFor` no longer queries the clock when a signal is already
available. An empty `WaitFor(0)` returns through the shared timeout path without
entering an expired kernel wait. Auto/manual-reset behaviour, waiter accounting
and destruction order are preserved under the existing mutex.

On the Hel1 Linux x86-64 stand, median `SetEvent + WaitFor(200)` fell from about
226 ns to 39 ns; an empty zero-timeout poll fell from 55.5 microseconds to
31 ns. These are short event-operation measurements, not an application-wide
speedup or a claim about time spent genuinely waiting for another thread.

The permanent Windows/Linux semantic matrix covers signals, timeouts and
multiple waiters. A Linux O-/O2/O3 probe additionally checks clock independence,
real clock errors and destruction with registered waiters. Release publication
requires successful Windows and Linux qualification of the exact release commit.

Install the complete 2.4.12 SDK and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20412; `CompilerVersion` remains 2.4. MoonORMot 15
remains required.

---

# MoonCompiler 2.4.11: application-defined expected exceptions

`Moon.Diagnostics` can skip additional capture and reporting for exception
classes selected by the application. Register them before initialization with
`Options.AddExpectedException(ExceptionClass)`. Matching is exact by default;
pass `True` as the second argument to include descendants. No classes are
excluded automatically, and the active list is fixed at initialization.

- Expected software exceptions avoid the extra diagnostic stack/context capture
  and snapshot allocation. Their exception reports consume no quota and perform
  no callback, file write or upload. Manual snapshots remain available.
- Normal exception handling, rethrows, acquired exceptions, queued callbacks,
  worker termination and previously installed hooks retain their behaviour.
  Unexpected exceptions keep their original diagnostic evidence.
- Linux hardware faults still save their initial native context before an
  exception class exists; a class filter cannot avoid that first capture.

The reporting suite passed 240 Windows and 253 Linux checks across O-/O2/O3,
including concurrent workers, quota isolation and a filtered hardware fault
followed by an unexpected software exception. This patch reuses the qualified
2.4.10 compiler/RTL baseline and checks the new API from both installed archives.
Full qualification and Pulse are not repeated for this diagnostics-only change.

Install the complete 2.4.11 SDK and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20411; `CompilerVersion` remains 2.4. MoonORMot 15
remains required. See [the expected-exception API](DIAGNOSTICS.md#expected-exception-classes).

---

# MoonCompiler 2.4.10: resources, configuration and runtime diagnostics

- Component resources load safely with numeric resource types. Named and numeric
  resource identifiers remain distinct, inherited components preserve their
  initialization order, and an empty delta-resource list leaves the component alone.
- `TCustomIniFile.ReadBool` uses the integer/default contract. Nonnumeric values
  such as `true`, `false`, `yes` and `no` retain the supplied default. Use `0` and
  `1` in portable INI files, or choose an explicit application text-flag parser.
- SQLite SQLDB preserves Unicode SQL, identifiers, filenames, metadata and errors
  across its UTF-8 API. Binary parameters retain their exact bytes. String and
  memo fields preserve their declared encoding when exposed as Unicode or Variant.
- Windows `TThread.CurrentThread` uses a real handle for the represented thread,
  so priority access also works when another thread uses that wrapper.
- Linux CPU usage includes IRQ, softirq, steal and I/O-wait accounting. Counter
  rollback invalidates the sample instead of producing a false load spike.
- Linux `CaptureBacktrace` uses existing unwind information in optimized builds.
  Symbol lookup retains loaded executable and library identity after a working
  directory change, including relative launches and library loads.
- HTTP connection failures retain immediate native errors, including local port
  exhaustion. Asynchronous delivery preserves the same reason and outcome.
  Interrupted and pending connections continue through the existing wait path.

Regression coverage includes both toolchains, optimized builds, ANSI and Unicode
RTL profiles where applicable, and consumers built from installed SDK archives.
The repair adds no new native runtime dependency or compiler optimization pass.

Install the complete 2.4.10 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20410; `CompilerVersion` remains 2.4. Update MoonORMot
to version 15 or newer for the connection-error repair. Full Pulse is not repeated
for this correctness release.

---

# MoonCompiler 2.4.9: keep the original fault in diagnostic reports

- `Moon.Diagnostics` preserves the first captured context when a queued callback
  exception leaves `CheckSynchronize`, when `Synchronize` delivers an exception
  to a worker, and when an acquired exception is explicitly raised again.
  Reports retain the original faulting instruction, registers and stack instead
  of replacing them with the delivery site.
- New regression tests compare the saved report contents before and after
  transfer. They also cover nested errors, capture switches, reusable out-of-memory
  exceptions, context reset and existing exception hooks on Windows and Linux.

The fix changes diagnostic capture only. Exception handling and `ExceptAddr`,
thread scheduling, compiler optimization and application error policy stay the
same. No new public API or dependency is required.

Install the complete 2.4.9 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20409; `CompilerVersion` remains 2.4. MoonORMot 14
remains required. Full Pulse is not repeated for this diagnostic repair.

---

# MoonCompiler 2.4.8: safe cleanup of unstarted threads

- On Windows, freeing a suspended `TThread` with `FreeOnTerminate=True`
  destroys the object once. Cleanup takes ownership before waking the thread,
  preventing a second destructor and an access violation during finalization.
- If a descendant constructor raises after `Create(False)`, Windows cleanup
  releases the native thread instead of waiting forever. On Linux, the same
  cleanup no longer calls `Execute` on the incompletely constructed object.
- Regression tests cover suspended cancellation, constructor exceptions,
  termination callbacks, ordinary self-freeing threads and the shared callback
  queue. They run in the RTL matrix and against both packaged toolchains.

Install the complete 2.4.8 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20408; `CompilerVersion` remains 2.4. MoonORMot 14
remains required. Compiler optimization and the timed-wait API are unchanged;
full Pulse is not repeated for this patch.

---

# MoonCompiler 2.4.7: safe lifetime of deferred component references

- Destroying a `TPersistent` now cancels its pending global reader references.
  A resource property such as `Ref = Later.Child` can no longer retain a
  destroyed receiver for a later property assignment.
- Cancellation remains safe when lookup callbacks or property setters destroy
  objects, query references, or invoke nested resolution. Other live receivers
  keep their references and can still resolve them. Registration and cancellation
  use the existing registry lock; this does not make application objects
  generally safe for concurrent destruction.
- Regression tests cover the reported resource-loading sequence, multiple
  receivers, nested persistent properties, explicit cancellation, callback
  exceptions, reentrant resolution and concurrent independent registrations.
  Both ordinary and product RTL profiles are checked on Windows and Linux.

There is no public API or `TPersistent` layout change. Compiler optimization is
unchanged; full Pulse is not repeated for this lifetime repair.

Install the complete 2.4.7 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20407; `CompilerVersion` remains 2.4. MoonORMot 14
is required, following the qualified dependency update already on `main`.

---

# MoonCompiler 2.4.6: bounded native thread completion

- `TThread.WaitFor(TimeoutMs): Boolean` provides bounded OS-thread completion on
  Windows and Linux. Zero polls, `High(Cardinal)` waits indefinitely, and the
  result distinguishes completion from timeout without consuming thread exit
  codes. A timeout leaves the thread object alive for a later wait.
- Linux waiting includes native TLS cleanup after `Finished` becomes true.
  Successful joins are recorded so repeated waits and destruction cannot join
  a recycled pthread ID. Native errors no longer mark the thread as reaped.
- Linux `WaitForThreadTerminate` now honors positive timeouts. Its historical
  zero-as-infinite convention remains; the new `WaitForThreadTerminateEx`
  interface separates status, exit code and native error for raw thread owners.

The timed overload deliberately does not dispatch main-thread callbacks or
messages. The parameterless `WaitFor` retains synchronization dispatch and its
integer result. See [thread coordination](THREAD_COORDINATION.md#bounded-thread-completion)
for ownership, shutdown and custom-manager contracts.

Regression tests cover timeouts, native teardown, repeated waits, exit-code
boundaries, synchronized termination, missing native providers and native
errors on both platforms. Linux uses monotonic deadlines and an older-libc
fallback. The release does not introduce a new runtime library dependency or
change compiler optimization. Full Pulse is not repeated for this patch.

Install the complete 2.4.6 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20406; `CompilerVersion` remains 2.4. MoonORMot 13
remains required.

---

# MoonCompiler 2.4.5: faster Linux clocks and best-effort thread priority

- Linux `Now`, `Date`, `Time` and `GetLocalTime` avoid repeated system-zone
  file checks within one UTC second. Every call still reads the current clock
  and its fractional part. Process `TZ` changes, DST transitions and clock
  rollback remain effective immediately. Administrative changes to the default
  system zone are observed within one monotonic second. On the Hel1 focused
  test, `Now` took about 0.315 microseconds instead of 1.58 microseconds in
  2.4.4 (about five times faster); this is not a new full Pulse result.
- Linux `TThread.Priority` assignment is best effort. An OS refusal, including
  restoring normal priority after lowering it, no longer raises `EThread` or
  skips application cleanup. The getter still reports actual native state.
  Assignments to terminated or joined ordinary threads are ignored safely;
  the low-level `ThreadSetPriority` result remains available for diagnostics.

Regression tests cover timezone forms and changes, fresh clock fractions,
DST boundaries, clock rollback, concurrent callers, fork, unavailable monotonic
clocks and local-to-UTC conversion during a system-zone change. Priority tests
check permitted and denied changes and completion of application cleanup.
Windows behavior is unchanged. Full Pulse is not repeated for this patch.

Install the complete 2.4.5 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20405; `CompilerVersion` remains 2.4. MoonORMot 13
remains required. No new runtime dependency is introduced.

---

# MoonCompiler 2.4.4: thread scheduling, queue notifications and diagnostics

- Linux `TThread.Priority` changes the target thread's native nice value, including
  before `Start` and through `TThread.CurrentThread`. The getter reflects the OS
  state; a denied change raises `EThread`. Increasing priority, including restoring
  normal priority after lowering it, can require `CAP_SYS_NICE` or `RLIMIT_NICE`.
- `TThreadedQueue<T>` directs notifications to waiting readers and writers instead
  of broadcasting one item or slot to every waiter. Readiness is preserved through
  assignment exceptions, growth, shutdown and timeout races. The uncontended path
  avoids event signaling when no thread is waiting.
- `Moon.Diagnostics.WriteManualReport` remains available after the exception-report
  quota is exhausted. Manual snapshots neither check nor consume that quota and
  retain unique filenames, enable switches, serialization and recursion protection.
- `Windows` and `Winapi.Windows` expose `CheckRemoteDebuggerPresent` with pointer
  and variable forms of its native `BOOL` output parameter. No JEDI unit is needed.

Regression tests check actual Linux OS priorities, thread identity and lifetime,
native threads, fork and cancellation; queue delivery and notification behavior,
exception recovery and deadlines; diagnostic quotas, concurrent requests and I/O
failure; and the Windows API signature and native calls.

Install the complete 2.4.4 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20404; `CompilerVersion` remains 2.4. MoonORMot 13
remains required. No new runtime dependency is introduced.

---

# MoonCompiler 2.4.3: helper reload safety and Delphi source compatibility

- Incremental builds restore helper and generic lookup indexes after reloading
  a dependency. Suspended source units no longer retain helper pointers into a
  freed symbol table. Repeated class-helper reloads also restore their synthetic
  lookup symbols correctly. Unchanged builds continue to reuse PPUs.
- Delphi inline ASM accepts bare LEA address expressions such as
  `lea rax, rax + 8`, including index registers and scales. It uses the same
  address encoding as the bracketed form and preserves processor flags.
- A uses clause can name several aliases of the same physical unit. All names
  share types and one initialization/finalization; the first physical occurrence
  retains lookup precedence. Qualified names also survive generic specialization
  from source-free PPUs, including implementation uses clauses. The library's
  bindings remain stable when its consumer changes namespace or alias options.
- Windows bindings add `MEMORYSTATUSEX`, both pointer and variable forms of
  `GlobalMemoryStatusEx`, `CancelSynchronousIo`, clipboard format listeners,
  `HWND_MESSAGE` and `ERROR_NOT_FOUND`. Short and `Winapi.*` unit names expose
  the same declarations and types.

Regression tests execute successive retained-PPU edits, reversals, helper and
generic dependency cycles, source-free consumers, alias precedence and negative
visibility cases. ASM tests check instruction bytes and flag preservation;
Windows tests exercise SDK layouts and native API calls.

Install the complete 2.4.3 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20403; `CompilerVersion` remains 2.4. MoonORMot 13
remains required. No new runtime dependency is introduced.

---

# MoonCompiler 2.4.2: incremental compilation and resource streaming

- Incremental compilation resolves indirect source/PPU dependency cycles even
  when several source units change together. The scheduler follows unfinished
  dependency checksums through intermediate units and searches each source
  target independently. Unchanged builds continue to reuse their PPUs.
- `TReader.CopyValue` copies every binary resource value type, including strings,
  binary data, sets, nested lists and collections. Encoded bytes are preserved,
  including floating-point payloads; the reader advances to the next value.
  `SkipValue` uses the same complete grammar. Truncated values, invalid tags and
  invalid lengths raise a read error.
- Resource readers preserve the sign and fractional scale of `Currency` and
  read unsigned 64-bit variants without routing them through a signed tag check.

Regression tests retain PPUs across successive edits and execute the resulting
programs. Resource tests cover all 24 value tags, small fragmented reads, nested
containers, malformed input and semantic scalar copying through custom writers.
The resource test also runs against extracted Windows and Linux release archives.

Install the complete 2.4.2 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20402; `CompilerVersion` remains 2.4. MoonORMot 13
remains required. No new runtime dependency is introduced.

---

# MoonCompiler 2.4.1: reliable HTTP transport and compiler compatibility

This maintenance release fixes compiler and runtime contracts exercised by
desktop applications and long-running services.

- HTTPS on Linux verifies the requested host name or IP address, in addition
  to certificate trust. Reused HTTP connections are checked before sending a
  request, so a connection closed during an idle period is replaced before POST.
  A POST whose delivery becomes uncertain is not automatically replayed.
- Existing HTTP exception classes expose machine-readable failure reason,
  delivery outcome and available native error codes. Async calls preserve those
  fields. Applications can distinguish DNS, TLS, timeout, disconnection,
  cancellation and invalid parameters without parsing exception text. Truncated
  or malformed responses fail instead of becoming successful incomplete bodies.
- Win64 inline ASM uses RIP-relative addressing for unqualified global symbols,
  including images above 4 GB. Explicit absolute/segment addressing, parenthesized
  unary operands and `.noframe` are supported. Frameless routines resolve named
  stack parameters correctly; unrepresentable absolute relocations fail at link
  time instead of silently truncating an address.
- Numeric overload resolution handles integer/real argument combinations such
  as `Max(0, DoubleValue)` without losing `Double` precision.
  Typed character-pointer constants and compiler-generated anonymous cleanup
  routines work across unit and external-class boundaries.
- Incremental generic-unit compilation handles source/PPU dependency cycles and
  discards stale attribute and generated-helper state before reparsing a module.
  PPU and executable paths retain their full names beyond 255 bytes, including
  source-free reuse and ELF postprocessing. Async lowering types its generated calls before optimizer analysis.
- Queued main-thread work remains queued even before the first worker starts.
  Win64 `Classes` supplies object-method callbacks and hidden-window helpers;
  Unicode disk-space calls and `Math.Min/Max` retain their intended public types
  when Windows and SysUtils units are used together.
- The pinned Lazarus IDE build adapts its comparer and event-handle declarations
  to the existing Moon API and uses the direct Toolhelp32 binding for process attachment.

Tests exercise observable values, generated instruction bytes, fresh and warm
PPUs, callbacks, connection reuse, response framing and a shared trusted CA with
both matching and mismatching server certificates. No new runtime dependency
or Pulse performance claim is introduced. See [runtime contracts](PLATFORM_API.md).

Install the complete 2.4.1 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20401; `CompilerVersion` remains 2.4. MoonORMot 13
remains required.

---

# MoonCompiler 2.4.0: runtime boundaries and lightweight synchronization

This minor release completes common runtime contracts used by Delphi applications
and adds lightweight synchronization primitives on Windows and Linux.

- `SyncObjs.TLightweightEvent` supplies manual-reset signaling;
  `TLightweightSemaphore` supplies counted permits and returns the previous count
  when releasing them. Ready waits avoid blocking. `TLightweightMREW` records now
  initialize automatically, including local variables and nested records.
  Tracked spin locks reject recursive acquisition, and `TTimeSpan` waits validate
  their range before acquiring a resource.
- Windows library loading, environment enumeration, configuration-directory
  storage, named events and timezone identifiers preserve Unicode. Native waits
  report abandoned mutex ownership correctly, and the requested COM wait mode
  reaches the backend. Registry keys close after flushing when lazy writes are
  disabled.
- `TFile.Open` honors read/write sharing and creates new files atomically.
  `TPath.GetTempFileName` returns a reserved empty file with a distinct name.
  Root-relative Windows paths keep their meaning when combined.
- Base64URL uses its URL alphabet consistently across strings, bytes and streams,
  without default padding or line breaks. Decoding preserves short reads and
  unpadded tails. Text readers preserve multibyte characters split across reads;
  URI helpers escape Unicode as UTF-8 bytes. Explicit strict UTF-8 conversion
  rejects malformed input instead of silently replacing it.
- JSON deserialization invokes the object's parameterless constructor and
  preserves its initialization and cleanup. Typed readers report failed numeric
  and date conversions, use invariant JSON defaults and respect local/UTC date
  handling. Large unsigned numbers remain positive through DOM, reader,
  serializer and RTTI conversions. Typed integer reads reject fractional tokens,
  and signed 64-bit reads reject overflowing values.
  ISO date parsing validates decimal fields and separators.
  Regex group names are exact and remain accessible beside unnamed captures.
  Updating a finalized hash raises `EHashException`; `Reset` starts a fresh hash.

Tests cover API call forms, invalid inputs, stream partitions, native handle
ownership, constructor failures and concurrent wakeups. No new performance
claims or additional third-party runtime dependencies are introduced.
See [runtime contracts](PLATFORM_API.md) and
[thread coordination](THREAD_COORDINATION.md) for supported behavior.

Install the complete 2.4.0 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20400 and `CompilerVersion` is 2.4. MoonORMot 13
remains required.

---

# MoonCompiler 2.3.2: HTTP privacy and runtime reliability

`System.Net.HttpClient` no longer includes request URLs or raw transport/server
messages in generated exceptions. Tokens in URL paths, query strings and user
credentials therefore do not leak through these messages into application logs.
Exception families and useful failure categories are preserved, including
timeouts, certificate rejection, redirect limits and socket result names.
The same rules apply to synchronous calls and `EndAsyncHTTP`.
Malformed URI ports and unsupported server charsets also produce fixed diagnostic
text without echoing the supplied value.

URI fragments (`#...`) are no longer sent to HTTP servers. The real request path,
query and escaped characters are preserved, as are URI values exposed to callers.
Application callbacks and explicit URL logging still need their own privacy policy.

Tests exercise fake secrets, failed connections and TLS handshakes, response
timeouts, redirects, malformed replies and wrapped stream errors on Windows and
Linux. Dictionary implementation and existing optimizations are unchanged. This
maintenance release makes no new performance claims.

Linux exception tables now remain valid when a handler conditionally reraises an
exception and other branches raise a replacement. The original exception retains
its identity on rethrow; replacement exceptions reach the correct outer handler,
and `finally` blocks and managed locals are cleaned up normally.

Linux `TMonitor.Wait` now creates and destroys the same event type used by its
wait and pulse operations. Timed waits no longer depend on unrelated heap bytes;
tests check elapsed time, allocation boundaries, recursive ownership and pulses.

The Unicode RTL now exposes `GetCurrentDir`, `TSearchRec.Name` and
`TSymLinkRec.TargetName` as Unicode strings. Direct `PChar` consumers and directory
enumeration use the correct character representation. Explicit raw-byte APIs
remain available. Both contracts are also checked against the installed release
archive, outside the source checkout.

Common RTL operations now preserve their public contracts across both platforms:

- `TDirectory.Copy` copies directory trees, with a separate `IgnoreErrors` overload.
  Copying into the source tree is rejected, including destinations reached through
  aliases. Recursive traversal does not follow directory links; deleting a link
  leaves its target intact. Failed file and directory operations report errors.
  Linux creates real symbolic links and honors `XDG_CONFIG_HOME` without requiring
  a trailing slash.
- URL path encoding preserves repeated and trailing slashes and uses `%20` for
  spaces. The URL, form, query and authentication helpers retain their distinct
  escaping rules. ISO 8601 parsing rejects invalid timezone syntax and ranges;
  `TryISO8601ToDate` returns `False` for those inputs.
- `System.Classes` exposes the text reader/writer classes. Readers support
  character, block, line and whole-text reads, peeking, rewind and enumeration.
  Short stream reads and split UTF-8/BOM sequences are handled without forcing
  a ready line to wait for a full buffer. `StreamEx` retains aliases to the same
  types; the existing buffered writer implementation is preserved.
- JSON iteration starts at the root's contents and maintains consistent nested
  navigation. Serializer syntax failures use `EJsonSerializationException`.
  Failed construction releases objects through their creator, including completed
  elements of an incomplete array; custom converter ownership remains explicit.
- A failed Linux event clock query releases its mutex and waiter registration.

The tests use independent values, actual filesystem state, short-read streams,
custom ownership callbacks and injected failures. New public API programs also
run against unpacked release archives in Debug and Release. See
[runtime contracts](PLATFORM_API.md) for the precise boundaries.

Install the complete 2.3.2 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20302; `CompilerVersion` remains 2.3. MoonORMot 13
remains required.

---

# MoonCompiler 2.3.1: file I/O and native-library reliability

This maintenance release completes common Windows and POSIX call forms and
fixes runtime failures found while porting server applications.

- Windows socket-event enumeration accepts both a record and a pointer.
  Disk-space APIs support signed and unsigned 64-bit outputs, generic/A/W
  names and optional pointer outputs.
- POSIX file operations use Delphi's `__read`, `__write`, `__close`, `__open`,
  `__chdir`, `__rmdir` and `__rename` names. Importing these units preserves
  ordinary Pascal file I/O. `Posix.Stdio` supplies file rename/removal and
  error reporting; the documented POSIX surface remains a supported subset.
- `TFile` reads readable pseudo-files and FIFOs without trusting their reported
  size. Text writes honor explicit encoding preambles, while default UTF-8
  writes and appends omit a BOM. Appending to a BOM-marked UTF-16 file preserves
  its encoding. Line and text APIs share the same decoding path. Copy and replace
  operations report failures; Windows replacement uses the Unicode native API.
- The optional FreeType binding resolves and clears every required function,
  rejects incomplete libraries, and protects concurrent loader ownership.
  Its scalar widths, bitmap structures, encoding tags and callbacks follow
  the C ABI on Win64 and Linux x86-64.
- Linux turns failed indirect calls into catchable access violations without
  recursively faulting inside the unwinder. Tests exercise cleanup, rethrow,
  managed locals, stack arguments and worker threads alongside ordinary data faults.
  Diagnostic reports retain raw fault registers and mark an unavailable Linux
  trace as incomplete instead of claiming a complete empty stack.
- Linux shared-library cleanup keeps code alive until its thread-local cleanup
  callbacks finish. Native C host tests cover cross-thread unload, explicit
  thread cleanup, real reload and TLS-key recovery.

The runtime API gates now include these consumer scenarios in Debug and Release,
loader failure/reload fixtures, and a real FreeType rendering cycle on Linux.
No additional library is linked into applications that do not use FreeType.
This release introduces no new Pulse performance claims.

Install the complete 2.3.1 toolchain and rebuild application and third-party PPUs.
`MOONCOMPILER_FULLVERSION` is 20301; `CompilerVersion` remains 2.3. MoonORMot 13
remains the required runtime version.

---

# MoonCompiler 2.3: consistent runtime and platform APIs

Release 2.3 makes standard units work together without application workarounds
for conflicting names, string widths, callback types or missing runtime libraries.
It supports Win64 and Linux x86-64 and retains the performance work from 2.0.

## Platform APIs

Windows API units now use direct bindings and canonical Windows types. Standard
`Winapi.*` names no longer redirect to Jwa units. Generic string functions use
UTF-16 in the product profile; explicit ANSI and wide entry points remain
available. The bindings correct pointer depth, native-sized outputs, callbacks
and record layout in process, service, credential and access-control APIs.

Linux gains a documented `Posix.*` surface for time, files, memory mapping,
sockets, DNS, loading libraries, threads and signals. These declarations follow
the Linux x86-64 glibc ABI. See the exact supported families and boundaries in
[Platform and runtime API contracts](PLATFORM_API.md).

## Standard units used together

`TCriticalSection` remains the synchronization class even when `Windows` appears
later in `uses`; the low-level record is `TRTLCriticalSection`. Task and future
APIs accept the common `SysUtils.TProc`/`TFunc` family. `TThread.Started` exposes
the thread startup state, and Windows event handles can be passed to OS waits.

Public equality comparers return signed `Integer` hashes, while dictionaries
retain all 32 hash bits. `ExtractStrings` supports both UTF-16 and ANSI inputs
without corrupting character lengths. `TVarData.VUInt64` names the existing
unsigned storage. Linux local clocks and timezone conversion now share libc
rules, including changes to `TZ` during a process's lifetime.

The standard JSON units isolate their internal parsers. A project can contain
its own `JsonReader`, `JsonScanner` or `fpjson` without breaking the installed
`System.JSON` units or changing the order of search paths.

## Regular expressions without deployment dependencies

`System.RegularExpressions` links a pinned PCRE2-16 engine into programs that
use it. No PCRE2 DLL/shared library or additional compiler-runtime DLL is needed;
programs without regular expressions do not link the engine. Unicode case
folding, UTF-16 indexes, groups, lookaround, replacement callbacks and empty
matches have explicit tests. Reusing a matcher after a replacement or an error
preserves its valid state. Native sources, build manifests and license notices
ship with the repository and applicable notices with the toolchain.

## Upgrade and validation

Install the complete 2.3 toolchain and rebuild application and third-party PPUs.
`CompilerVersion` identifies MoonCompiler 2.3, not a Delphi version number.
Use `MOONCOMPILER_FULLVERSION` (20300) for ordered version checks. The required
MoonORMot runtime version is 13; [Setup](SETUP.md) describes its location.

The added tests cover mixed unit names, high-bit hashes with range/overflow
checks, Unicode paths, C ABI layouts, actual OS calls, matcher reuse and installed
package isolation on both platforms. Separate audits cover correctness and
source provenance. This release makes no new Pulse performance claims; the
dated 2.0 measurements remain unchanged below.

---

# MoonCompiler 2.1: Delphi runtime compatibility

Release 2.1 extends the standard libraries used by server applications on Win64
and Linux x86-64. It closes missing API and behavioral contracts while keeping
the direct `fpc` build and the performance work from 2.0.

## HTTP clients and streamed data

The Delphi-compatible HTTP client over MoonORMot now provides the standard
asynchronous request family, shared URL/client/request/response types, response
metadata and file, string, stream and multipart uploads. Cancellation interrupts
DNS waiting, TCP connection and TLS setup; the connection deadline covers all
three. Resolver work that the OS cannot cancel is independently owned and bounded.

Cookies retain domain, path, security and expiration rules across redirects and
asynchronous requests. Basic authentication supports credentials and challenge
callbacks; proxy credentials remain separate from server credentials. MIME parts
can carry custom headers and borrowed or owned streams, with repeatable body reads.
ZIP entry streams report read progress and retain CRC validation.

Brotli decoding is optional. Add `Moon.HttpClient.Brotli` to `uses` when an
application needs HTTP `br` content. Other HTTP applications do not link the
decoder or its dictionary. The optional static decoder requires no Brotli DLL.
See the [HTTP/runtime contracts](../runtime/mormot/README.md) and
[third-party licensing](LICENSING.md).

## Queues, completion and time

`TThreadedQueue<T>` provides a bounded FIFO between producer and consumer threads,
with push/pop timeouts, explicit capacity growth, shutdown and operation counters.
`TCountdownEvent` waits for a batch of concurrent operations to finish without
creating a thread pool. Both use existing synchronization primitives and are
available on both targets. Their lifetime and shutdown rules are described in
[Thread coordination](THREAD_COORDINATION.md).

Time-zone conversion uses historical OS rules on Windows and Linux, including
ambiguous autumn times, missing spring times and non-hour transitions. The RTL
also completes Unicode custom-Variant dispatch, identifier customization and the
collection-growth callback used by standard containers.

## Source compatibility

Win64 supports delayed DLL imports, including named and ordinal imports,
notification/failure hooks and concurrent first calls. Record helpers resolve
implicit and explicit `Self` while retaining local-variable precedence.

The existing JSON builder and iterator API now handles nested values, raw JSON,
typed values, snapshots, resetting and exact paths through quoted property names.
These are the standard compatibility units; applications using MoonORMot JSON
continue to use it directly.

## Upgrade and validation

Install the complete 2.1 toolchain and rebuild application and third-party units.
The PPU payload version changes for delayed-import metadata; mixing old compiled
units with the new compiler is unsupported. Keep MoonORMot next to the toolchain
as described in [Setup](SETUP.md).

The release checks cover the added contracts on Windows and Linux, Delphi
behavioral comparisons for thread coordination, managed lifetimes, HTTP/TLS,
archive installation and the normal GitHub qualification workflow. The 2.0
performance results below belong to their original measured version; 2.1 does
not claim a new Pulse campaign or new performance ratios.

---

# MoonCompiler 2.0: the second release

This release makes ordinary Delphi code cheaper to execute and easier to build
and diagnose on Win64 and Linux x86-64. The changes cover the compiler, Unicode
RTL, collections, memory manager and the installed toolchain as one product.
Applications keep their Pascal source, managed types and normal library calls.

## Text and message processing

Substring search, case-insensitive name checks and UTF-8 decoding now do less
work in the common path. `Pos` uses a shared, bounded x86-64 UTF-16 search;
`SameText` checks equality directly and can reject a different short name early.
UTF-8 decoding handles adjacent two-byte characters together, while retaining
validation of malformed input. Converting an integer `Variant` to Unicode text
avoids intermediate ANSI and BSTR strings.

Searching ordinary ASCII keys in `TStringList` no longer creates uppercase
copies or invokes the full locale machinery for every candidate. Non-ASCII
inputs and user-defined comparison behavior keep their appropriate general
paths. This matters in configuration lookup, message dispatch and protocol
field processing, where comparison is repeated many times.

## Dictionaries, lists and buffers

Dictionary work improved across lookup, updates, enumeration and growth. Flat
lookup avoids repeated searches, and rehashing can transfer ownership of plain
managed values without incrementing and then decrementing their references.
Custom comparison and managed-record operations retain their contracts.

Measured Linux examples against the first release include 60% less CPU cost for
numeric-key lookup, 44% for string-key lookup, 68% for `AddOrSetValue`, and 18–55%
for enumeration. Growing dictionaries with numeric keys and string values use
31–39% less CPU in the measured sizes. These are improvements to indexes,
caches and state tables, rather than just faster construction of an empty object.

An ordinary list with reserved capacity can insert a simple element without
the general notification setup when no observer or override needs it. An exact
`TMemoryStream` can change its logical length without a buffer transaction when
the existing capacity can be retained under its normal shrink policy. A uniquely
owned string result of the required size can reuse its allocation for repeated
`Copy` operations.

## Loops and resource management

The compiler retains more useful pointers and intermediate values in registers
and removes redundant index copies. Eligible loops with a runtime bound use a
remaining-iteration counter. Ordinal `case` labels sharing the same action can
be combined into membership tests, which helps mixed byte-oriented scanners.

Short `try/finally` blocks perform normal cleanup directly while preserving the
exception path. Small implicit cleanup sequences on Win64 avoid unnecessary
dispatch on an ordinary return. Passing an already owned aggregate result to a
`const` consumer avoids technical copies without dropping user-defined
`Initialize`, `Assign` or `Finalize` operations.

These changes benefit operations such as scanning messages, walking arrays of
records, calculating a recent weighted price, and releasing local resources.
They preserve floating-point evaluation order, exception behavior and ownership.

## Selected measurements

The table shows **CPU cost removed for the same work**, rounded to whole
percentages. A 25% reduction means that the operation takes three quarters of
its former cost; it is not a 25% whole-application speedup.

| Operation | Versus Delphi 12.2, Win64 | Versus first Moon release, Win64 | Versus first Moon release, Linux |
|---|---:|---:|---:|
| Find a substring in a 64-character UTF-16 string | 24% | 52% | 56% |
| Decode 32 Cyrillic characters with `TEncoding.UTF8.GetString` | 60% | 83% | 79% |
| Decode the same text family with `UTF8ToString` | 48% | 62% | 61% |
| Convert an integer `Variant` to text | 17% | — | 74% |
| Find an ASCII key in a 128-entry `TStringList` | 91% | 91% | 93% |
| Add or update a numeric dictionary entry | 70% | 70% | 68% |
| Fill a reserved dictionary with 100 numeric keys and string values | 13% | 51% | 50% |
| Resize `TMemoryStream` within its existing capacity | 69% | 74% | 70% |
| Scan mixed JSON bytes, medium input | 32% | 36% | 34% |
| Loop with a short `try/finally` | 37% | 29% | 63% |

These selected examples were measured on 5 October 2026 using the release 2.0
product. The workloads were built at
`83315fe3b92b2bafc478c9a16ec9424fa8a62382`. Each published runtime comparison has
twelve accepted pairs; a dash means that no refreshed numerical claim is made.
The first-release baseline is
`ccaa5fbaf5ec5bfeef09a3f3f049ffe603d9509c`. Windows comparisons use Ryzen 7
5800X; Linux comparisons use Intel Xeon W-2295. Each comparison builds the same
workload with each side's complete Release profile and requires matching
semantic digests and an accepted identical-program control. The
[measurement record](evidence/release2/README.md) gives exact case identifiers,
ratios and provenance. This is a selection of confirmed improvements, not a
complete benchmark average, a full Windows Pulse qualification, or a prediction
for an entire application.

The bundled memory manager also remains useful independently of compiler
optimizations. In the separate 4 October allocator comparison using the same
Windows compiler, the measured live-block ring,
fragmented mixture and `ReallocMem` growth workloads require 64%, 41% and 36%
less CPU respectively than the standard FPC memory manager. That comparison
changes the allocator, not the compiler, and is separate from the release-to-
release columns above.

## Exact decimal rounding

`RoundTo` now rounds the actual binary floating-point input to the requested
decimal position under nearest/even rounding. The ordinary path uses hardware
arithmetic; difficult half-boundaries use an exact fallback. This avoids a
slightly inaccurate decimal scale changing which side of a rounding boundary
the value lands on. The supported floating-point environment is described in
[Known Deviations](KNOWN_ISSUES.md#floating-point-edge-cases).

## Faster compilation

Large programs with many generated classes no longer repeatedly register an
already active symbol table while building virtual method tables. In the
controlled large-program experiment, a full source rebuild fell from 81.5 to
21.6 seconds. The paired executables without user debug information were byte
identical. A subsequent uninstrumented build with the original debug settings
took 23.7 seconds. This is a measured large-program example, not a universal
compiler-speed ratio; the number and structure of classes determine the benefit.

## A portable product build

The installed `fpc` owns the product profile. A normal project builds directly:

```text
fpc hello.dpr
fpc -dRELEASE hello.dpr
```

These select Debug and Release. Both use the same Unicode and runtime contract;
Release enables the product optimizations. There is no Python build driver in
the application build path. A larger project puts source paths, aliases and
defines in its adjacent `.mooncompiler` option file. Compiler-unit output is
separated by platform and profile.

The release archive contains the compiler, RTL, packages, tools and runtime
units. MoonORMot remains a separate clone next to `toolchain`. Lazarus uses an
isolated ordinary FPC ABI for the IDE and LCL, leaving the application Unicode
profile separate. See [installation](SETUP.md) and [project builds](PROJECT_BUILD.md).

## Libraries and diagnostics

The Delphi-compatible surface now includes buffered file streams, lightweight
reader/writer locks, mask matching, socket address storage, and URL/header
types. `System.ZLib` supplies one native zlib on each target. `System.Zip`,
multipart MIME and `System.Net.HttpClient` build over the project's MoonORMot,
including archive integrity checks, streamed request bodies, redirects,
cancellation and TLS validation.

`Moon.Diagnostics` provides optional local exception and all-thread reports.
It keeps the original exception context, uses embedded names and source lines,
and can attach application data or upload a saved report. Expected-error paths
can disable capture per thread or for the process. See the
[diagnostics guide](DIAGNOSTICS.md) for initialization and deployment requirements.

## Qualification and upgrading

The release route covers Windows and Linux, language and RTL contracts, the
complete generated Devil corpus, managed lifetime, threading, compiler
self-builds, mORMot, archive consumers and installation, Lazarus and Pulse.
Independent correctness tests share a bounded worker budget. Cold-build and
determinism checks still rebuild; later reuse consumes only validated PPUs.
Final Light tests the same artifact that passed Full and verifies its complete
identity. [Testing](TESTING.md) describes the reproducible route.

Install the new toolchain as a complete unit, then cleanly rebuild application
and third-party units with it. Do not mix PPUs from different compiler versions
or from the IDE and Unicode application profiles. Keep the required MoonORMot
version next to the toolchain and retain embedded debug information when using
diagnostic reports. The [supported boundaries](KNOWN_ISSUES.md) remain the
reference for compatibility.
