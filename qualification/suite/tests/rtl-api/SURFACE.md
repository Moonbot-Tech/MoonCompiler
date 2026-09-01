# RTL API surface gate

This gate checks not the breadth of the generated AST, but the presence and
basic semantics of the public Delphi RTL API. A missing constructor, overload,
property, or default argument cannot be found by Mega/Omni until a source
explicitly names it.

## Selection rule

An API belongs in the matrix only if all three conditions hold:

1. the family is actually used in current MoonBot or Arbitrage;
2. it is a shared Win64/Linux application contract rather than a GUI,
   design-time, or platform wrapper;
3. a stable compile/runtime oracle can be defined for the call.

The source inventory on 2026-08-25 showed the main families: `TMemoryStream` —
905 references, `TThread` — 761, `TList` — 715, `TArray` — 491, `TStringList`
— 379, `TDictionary` — 350, `TMonitor` — 143, `TFileStream` — 137,
`TCriticalSection` — 79, `TEvent` — 50, `TBytesStream` — 23,
`TObjectList` — 21, `TStringBuilder` — 14, `TStack` — 3. `TStopwatch` has
83 references, including production WebSocket rather than only benchmarks.
The counts serve only as the selection boundary and are not a coverage metric.

The matrix checks:

- ordinary and suspended `TThread.Create`, anonymous thread, `Start`,
  `WaitFor`, `Queue/ForceQueue/Synchronize`, monotonic ticks, `TEvent`,
  `TCriticalSection`, and the base `TMonitor`;
- unmanaged and managed `TList<T>`, `TArray`, comparer, enumeration, and object
  ownership;
- string/numeric `TDictionary`, `IsEmpty`, ownership, and stack;
- `TStringList`, `TStringBuilder`, virtual `TMemoryStream.SetCapacity`, Integer/
  Int64 `SetSize`, memory/bytes/string/file streams, and UTF-8;
- `TFile.GetSize` for existing and missing files;
- ANSI/Wide `TextPos` while preserving the original pointer offset;
- the most common conversion/string/date helpers, `TStopwatch`, enum TypInfo,
  `TRttiContext.GetType`, `TValue`, and `FreeAndNil`.

VCL/FMX, COM, database/XML, design-time streaming, deprecated thread APIs, rare
encodings, platform handles, and methods absent from every product are
intentionally excluded. They do not become a supported contract merely because
they are present in the Delphi RTL.

The same source is built in Debug and Release by the real product build driver.
The product compiler injects the bundled MM before its `uses`, then Linux
`cthreads`, `cwstring`, `fpmonitor`, or Win64 `fpwinmonitor`. The FPC-only
prefix retained in the source is a compatibility oracle for legacy entry points
and is a no-op; it is conditionally excluded under Delphi 12.2, so the same
file remains a DCC oracle without a separately rewritten copy.

The main `rtl_api_surface.dpr` is confirmed by running one exact source in
three environments:

- Delphi 12.2 Win64 compiler 36.0;
- MoonCompiler Win64 Debug/Release;
- MoonCompiler Linux x86-64 Debug/Release.

`rtl_api_array_copy.dpr` is separate so the absence of one API cannot hide the
rest of the matrix. Delphi 12.2 executes both overloads, including a managed
destination. Moon RTL exports the same two overloads through one existing
generic helper; Win64/Linux Debug/Release pass the same oracle.

`rtl_api_fphttp_nodelay.dpr` creates a real loopback TCP connection and applies
`TFPHTTPConnection.SetupSocket` to its accepted keep-alive socket. It then
reads `TCP_NODELAY` back from the kernel. This pins the latency contract which
prevents Nagle/delayed-ACK stalls on persistent FCL HTTP connections on both
Win64 and Linux.
