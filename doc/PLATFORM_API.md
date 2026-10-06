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
| Files and process identity | `Unistd`, `Fcntl`, `SysStat` | open/read/write/seek/close, descriptor flags, directories, access/stat, IDs |
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

`Now`, `Date`, `Time`, `GetLocalTime`, the current UTC offset and `TTimeZone`
share libc timezone rules. The tests change `TZ` within one process and check
UTC round trips, named zones, POSIX zone strings, DST and non-hour offsets.

## Shared runtime contracts

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

## Compiler identity

`System.CompilerVersion` and `{$IF CompilerVersion ...}` identify MoonCompiler:
2.3 in release 2.3.0. They do not pretend to be Delphi 36. Use
`MOONCOMPILER_FULLVERSION` for ordered version comparisons: major × 10000 +
minor × 100 + patch, or 20300 for 2.3.0. A real number cannot distinguish
2.10 from 2.1. `FPC_FULLVERSION` and `fpc -iV` continue to report the underlying
FPC ABI version. Existing Delphi feature checks must distinguish the compiler
instead of interpreting the Moon version as a Delphi release number.
