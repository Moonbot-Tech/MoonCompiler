# Platform and runtime API contracts

MoonCompiler supports Win64 and Linux x86-64. The Unicode product profile and
the ordinary FPC profile used by Lazarus are built separately. Rebuild all
application and third-party PPUs when upgrading the toolchain.

## Windows

`Winapi.X` and the supported short name `X` resolve to the same compiled unit
and share types. The product no longer installs or aliases standard APIs to
the Jwa unit family. The direct bindings retain their open-source notices.

| Family | Public units and contract |
| --- | --- |
| Files, directories, environment, version resources | `Winapi.Windows`; generic names take UTF-16 in the product profile; explicit `A` and `W` entry points remain available |
| Processes, threads, waiting and memory counters | `Windows`, `PsAPI`, `TlHelp32`; native handles and pointer-sized fields; pointer form of `GetProcessMemoryInfo` |
| Networking | `WinSock`, `WinSock2`, `IpHlpApi`, `IpTypes`, `IpRtrMib`, `IpExport`, `Qos`; OS socket, adapter and routing declarations |
| Services, access control, credentials and profiles | `WinSvc`, `AccCtrl`, `AclAPI`, `WinCred`, `Winsafer`, `UserEnv`, `WTSApi32` |
| Existing SDK families | `ActiveX`, `Messages`, `CommCtrl`, `CommDlg`, `DwmApi`, `FlatSB`, `ImageHlp`, `Imm`, `MMSystem`, `MultiMon`, `Nb30`, `Ole2`, `RichEdit`, `ShellAPI`, `SHFolder`, `ShlObj`, `ShLwApi`, `UrlMon`, `UxTheme`, `WinHTTP`, `WinInet`, `WinSpool`, `Cpl`, `Dlgs`, `RegStr` |

This is a binding inventory, not a claim to implement every API in the latest
Windows SDK or a GUI framework. The unit-scope gate checks all 42 standard
unit pairs and type identity. Runtime tests exercise Unicode paths, DLL search
directories, disk space, version resources, process counters, thread snapshots,
service-manager access and socket events. Structure assertions are independently
checked against C SDK headers by `platform_abi_oracle.c`.

Use `SyncObjs.TCriticalSection` for the class and `TRTLCriticalSection` for the
low-level record. The Unicode Windows unit does not shadow the class with a
record named `TCriticalSection`. `THandleObject.Handle`, including `TEvent.Handle`,
is a real Windows `THandle` suitable for OS waits; the internal event descriptor
remains owned by the RTL. POSIX events retain their native RTL representation.

## Linux

The following `Posix.*` units expose Linux x86-64 glibc ABI declarations. They
use explicit byte strings (`PAnsiChar`), C widths and `cdecl`. They do not turn
Windows API calls into Linux calls.

| Family | Units | Included operations |
| --- | --- | --- |
| Fundamental types and errors | `SysTypes`, `Errno` | pointer-sized sizes, 64-bit file/time values, thread-local libc errno |
| Time | `Time`, `SysTime` | wall/monotonic clocks, `timeval`, `timespec`, calendar conversion, sleep |
| Files and process identity | `Unistd`, `Fcntl`, `SysStat`, `Stdio` | open/read/write/seek/close, descriptor flags, directories, access/stat, IDs |
| Memory and shared memory | `SysMman` | mmap/munmap, protection, synchronization and shared-memory handles |
| Dynamic loading | `Dlfcn` | dlopen/dlsym/dlclose/dlerror |
| Sockets and names | `SysSocket`, `NetinetIn`, `ArpaInet`, `Netdb`, `Poll` | socket operations, IPv4/IPv6 conversion, DNS/address resolution and poll |
| Threads and signals | `Pthread`, `Signal` | thread creation/join, mutexes, conditions, signal masks and sigaction |

The source declarations define the supported subset; these are not complete
translations of every POSIX header. Epoll, process spawning, terminal control,
directory iterators and other APIs are not added by this set. Existing FPC
`BaseUnix`, `Unix`, `Sockets` and related units remain available. These glibc
records must not be substituted for FPC's kernel-level signal records or used
on another architecture/libc. ABI assertions cover sizes, field offsets and
real file, socket, memory, thread and signal operations.

Pascal names that would hide `System` I/O use Delphi's prefixes:
`__read`, `__write`, `__close`, `__chdir`, `__rmdir` in `Posix.Unistd`,
`__open` in `Posix.Fcntl`, and `__rename` in `Posix.Stdio`. The latter also
provides `remove` and `perror`; it is not a complete buffered C I/O binding.
The unprefixed conflicting declarations from 2.3.0 have been replaced.

On Linux x86-64 glibc, Pascal shared libraries retain their code while the
initializing thread or foreign threads still own RTL thread-local state.
`dlclose` may therefore defer physical unloading until those threads finish;
a `dlopen` before then can reuse the live module. Cleanup runs on the owning
thread, and final library teardown releases its TLS keys. Applications must
still stop library-owned worker threads and finish active calls before unloading.

`TFile.ReadAllBytes` and `ReadAllText` read to EOF when a readable file does not
provide a seekable size, including procfs and FIFOs. A failed read raises an
exception; it is not reported as an empty file. Explicit text encodings write
preambles, while default writes use UTF-8 without a BOM. Default append detects
and preserves an existing BOM encoding. Explicit nil encodings are invalid.

`TFile.Replace` requires existing source/destination and a nonempty backup path.
It replaces an existing backup. Windows uses `ReplaceFileW`; Linux copies the
backup and renames the source over the destination on the same filesystem.
Linux rejects aliased source/destination/backup files, including hard links,
before writing the backup. These are filesystem operations, not a transaction
against concurrent external path changes.

`Now`, `Date`, `Time`, `GetLocalTime`, the current UTC offset and `TTimeZone`
share libc timezone rules. The tests change `TZ` within one process and check
UTC round trips, named zones, POSIX zone strings, DST and non-hour offsets.

## FreeType

`freetypehdyn` remains an explicitly loaded external library binding. It does
not add FreeType to programs that do not use it. Initialization publishes all
22 required entry points together, rejects incomplete libraries, and serializes
loader ownership. Keep an initialization reference for as long as any library,
face, glyph or function pointer is in use; release those objects before the last
`ReleaseFreetype`. Final release clears every function pointer. LP64 metric
widths, bitmap fields, encoding tags and outline callbacks follow FreeType's C ABI.

## Shared runtime contracts

`TDirectory.Copy` merges a source tree into the destination and overwrites existing
regular files. The two-argument form reports failures; `IgnoreErrors=True` skips
failed entries and continues siblings. Invalid roots and unsafe self-copy are
still errors. Symbolic links are copied as links, including relative and dangling
targets. Recursive enumeration/deletion does not traverse directory links.
Windows link creation requires the appropriate OS privilege or Developer Mode.
Native copying of Windows directory links requires Windows 10 build 19041 or
later (including Windows Server 2022); an unsupported OS reports the copy failure.
These operations do not provide atomic snapshots against concurrent path changes.
`TFile.Copy` rejects aliased source/destination files before truncating either.
Missing paths and access failures are not successful empty enumerations.

`TTextReader`, `TStreamReader`, `TStringReader`, `TTextWriter`, `TStreamWriter` and
`TStringWriter` are available from `System.Classes`/`Classes`. `StreamEx` refers
to the same types, so existing JSON readers and FPC consumers can share them.
Stream readers borrow caller streams unless `OwnStream` is requested; filename
constructors own their streams. `DiscardBufferedData` discards read-ahead after an
external seek without changing the selected encoding; `Rewind` seeks to the start
and repeats BOM detection. Ordinary FPC and Unicode product profiles remain separate.
This does not add Delphi binary reader/writer classes or full `System.Messaging`.

`TMBCSEncoding` honors explicit Windows conversion flags through the native API.
On Linux, strict UTF-8 decoding (`MB_ERR_INVALID_CHARS`, 8) and encoding
(`WC_ERR_INVALID_CHARS`, 128) reject invalid byte sequences and unpaired UTF-16
surrogates. Other nonzero Windows-specific flags raise an explicit unsupported
conversion error on Linux. Zero flags retain the ordinary replacement behavior.
Stream readers retain incomplete CP932/936/949/950/1361 and GB18030 characters
between reads, as well as UTF-8 and UTF-16 tails.

`TNetEncoding.Base64URL` defaults to unpadded, unwrapped URL-safe Base64. Its
string, byte-array and stream overloads share the same decoder. URIParser uses
UTF-8 percent-encoded bytes for Unicode URI components.

`TPath.GetTempFileName` creates and closes a new empty file before returning its
name; the caller owns its cleanup. `TFile.Open(..., fmCreateNew, ...)` uses an
exclusive native create operation and never truncates an existing file. Windows
share flags describe which access is allowed to other handles.

`TURLEncoding.EncodePath` preserves path separators and escapes spaces as `%20`.
`URLDecode` preserves literal `+`; `FormDecode` treats it as a space.
`TryISO8601ToDate` returns `False` for malformed/out-of-range timezone offsets;
the throwing conversion reports an error. Moon does not reproduce Delphi versions
whose `Try` entry point throws for that malformed timezone input.

`TJSONIterator.Next` enters root object/array contents automatically; `Recurse`
explicitly enters a nested container. Exhausting that level resumes its parent;
an immediate `Return` after exhaustion does not skip a second level. Serializer
parse errors use `EJsonSerializationException`; application converter exceptions
keep their type. New object cleanup pairs the selected creator's `Invoke` and
`Release`; custom converters retain responsibility for their own ownership policy.

- `IEqualityComparer<T>.GetHashCode`, comparer classes and public hash delegates
  return `Integer`. Dictionaries retain all 32 bits, including negative hashes.
  Internal hash algorithms remain unsigned.
- `ExtractStrings` accepts UTF-16 and ANSI pointers, with lengths in their own
  character units. Unicode input is not truncated to byte characters.
- `TVarData.VUInt64` aliases the existing 64-bit unsigned storage without
  changing Variant layout.
- `TThread.Started` reports that the thread has entered its startup path and
  remains true after termination. It is false for a suspended thread before
  startup; a call to `Start` alone is not a synchronization barrier.
- `System.Threading` uses the `SysUtils.TProc`/`TFunc` callback family in the
  product profile. Typed closures can be passed to `TTask` and `Future`.
- `System.JSON` uses private compiled parser units. An application may have its
  own `JsonReader`, `JsonScanner` or `fpjson`; changing search-path order is not
  required. MoonORMot JSON remains a separate application choice.

## Regular expressions

`System.RegularExpressions` and `System.RegularExpressionsCore` link the pinned
PCRE2-16 engine statically. No PCRE2 DLL or shared object is required on the
deployment machine. Programs which do not use these units do not link the
engine. The low-level optional FPC `libpcre2_8/16/32` dynamic bindings remain
distinct from the Delphi compatibility units.

The default matcher uses UTF-16 code-unit indexes, Unicode case folding and
ASCII `\w`, `\d`, `\s` classes. An explicit `(*UTF)` pattern requests Unicode
scalar matching. `roNotEmpty` excludes empty matches; with an explicit empty
option set the iterator advances even after a zero-length match. Multiline
handling accepts CR, LF and CRLF. Tests cover invalid patterns, NULs, capture
groups, lookaround, replacements, collection lifetimes and allocation balance.

The source archive, native build recipe, binary manifests and notices are in
[`packages/libpcre/native`](../packages/libpcre/native). See [Licensing](LICENSING.md).

## HTTP transport diagnostics

The existing `ENetException` descendants expose Moon-specific `Reason`, `Outcome`
and `NativeError` properties. Classify failures by these fields rather than by
localized `Message` text. `Reason` distinguishes DNS, TLS, timeout, connection
refusal, connection closure, cancellation, invalid parameters, protocol errors
and other connection failures; `Unknown` remains available when no reliable
classification exists. `NativeError` preserves an available OS error number;
zero means none was supplied. It is diagnostic information, not a portable enum.
Async `Await` and `EndAsyncHTTP` preserve these properties and existing exception
families, including repeated retrieval of a failed result.

`Outcome=NotSent` means the request failed before transmission began.
`ResponseReceived` means complete response headers arrived; reading the body
can still fail. `Unknown` means neither guarantee is available. For code-based
application diagnostics, `OutcomeCode=600` marks this unknown outcome; otherwise
it is zero. This is a local marker, never a fabricated HTTP response or a value
inserted into `IHTTPResponse.StatusCode`. Actual HTTP statuses remain unchanged.

HTTPS validates the requested DNS name or IP address as well as certificate trust.
Before reusing a connection, the client checks for peer closure without sending
an HTTP probe or waiting for a TLS record to finish. A stale connection is replaced
before transmitting any method, including POST. If the peer closes during a POST
or PATCH already being sent, the client reports the failure and does not replay
the request automatically. A timeout or cancellation alone does not prove that
the server did not execute it. Applications need an idempotency key or another
application-level confirmation mechanism before retrying such operations.

## Compiler identity

`System.CompilerVersion` and `{$IF CompilerVersion ...}` identify MoonCompiler:
2.4 in release 2.4.1. They do not pretend to be Delphi 36. Use
`MOONCOMPILER_FULLVERSION` for ordered version comparisons: major × 10000 +
minor × 100 + patch, or 20401 for 2.4.1. A real number cannot distinguish
2.10 from 2.1. `FPC_FULLVERSION` and `fpc -iV` continue to report the underlying
FPC ABI version. Existing Delphi feature checks must distinguish the compiler
instead of interpreting the Moon version as a Delphi release number.
