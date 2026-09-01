# Coverage of RTL fixes

Below is the executable coverage of changed code. It is not replaced by a count
of source files. Run the complete matrix with `RTL-test/run.py`.

| Area | Required boundaries |
|---|---|
| `TList.GetItem/SetItem` | empty/full, low/high error, scalar, string, interface, managed lifetime, notifications |
| `TDictionary.DoRemove` | scalar and managed value, collision cluster, wraparound backward-shift, key/value notifications, exact interface lifetime |
| concrete list/queue/stack enumerators | empty, order, nonzero queue low, managed values, base-typed virtual control, O3 no-call assembly |
| `TQueue.MoveToFront` | managed/unmanaged, overlap in both geometries, string/array/interface/custom managed record, COW, exact finalize |
| queue/stack `Peek` | empty exception, scalar/record/string/interface, count/order unchanged, lifetime |
| AVL `ExtractPair` | key/node overloads, missing key, dispose/detach, two-child removal, notification, interface lifetime |
| semaphore/mutex wait | zero/finite/infinite, success/timeout/error, `EAGAIN/EBUSY/EINTR`, absolute deadline, contention, release/reacquire |
| `TStream.CopyFrom` | EOF, repeated short positive reads, exact count, zero count, empty source, positions/content, exception propagation |
| `TStringStream.ReadUnicodeString` | UTF-8/UTF-16, zero/partial/oversize/EOF, byte positions, decode failure adjacency |
| buffered `SetSize64` | grow/shrink/no-op, dirty page flush, cached/physical size, zero extension, seek/position, reopen |
| integer formatting/parsing | zero, signs, Low/High Int32/Int64, High QWord, decimal boundaries, overflow, invalid, plus/hex/whitespace fallback, Delphi-compatible embedded-NUL termination, random corpus |
| floating text | zero and signed zero, fixed/scientific boundary, NaN/Inf, locale separators, exponent normalization, deterministic bit-pattern corpus |
| trigonometric argument reduction | both sides of `Pi/4` and `Pi/2`, signs, ordinary and large arguments, the exact Cody/Waite → Payne/Hanek boundary, `Sin`, `Cos`, and the `sin²+cos²` identity in Debug/O2/O3 and Delphi 12.2 |
| Unicode string core | nil/constant/shared/unique assign, self-assign, single- and multi-thread refcounts, COW, concat, `Pos`, case and comparisons |
| empty-string equality domains | `=`/`<>` in both operand orders for empty/non-empty RawByteString, UTF8String, UnicodeString, WideString and ShortString; embedded NUL/high bytes; Delphi 12.2 semantic oracle; O3 forbids Ansi/Short/Wide -> Unicode conversion calls |
| Delphi byte-string domains | raw `#$xx`/pair/named/PPU bytes, `Chr`/`WideChar` codepage conversion, Ansi/Raw/UTF-8 concat, compare/`Pos`/replace, overload result type |
| UTF-8 conversion | empty, all ASCII bytes including NUL, codepage metadata, BMP, surrogate pairs, unpaired/invalid input, boundary lengths, random Unicode |
| dynamic-array finalization and `Copy` | unmanaged widths, packed records, managed/nested elements, nil holes, alias/self-copy, clamped/negative ranges, normal/Exit/exception lifetime |
| `Default(T)` for static arrays with management operators | exact fresh-value transfer without `Assign` (100, not 101), direct/indexed/generic PPU, single-evaluation destination, Initialize-prefix unwind before touching the destination, valid replaced/untouched elements after an exception from the old `Finalize`, 32-byte alignment, and a 2 MiB heap temporary with a 1 MiB stack |
| `resourcestring` in typed string constants | local/PPU enum arrays, standalone Unicode/Ansi/Wide destinations, Format, native-width `SetResourceStrings` retranslation, static cross-width values, and clean process termination |
| MM lifetime during unit finalization | a translated resourcestring remains valid; late ObjPas managed decref goes through the still-installed allocator; normal exit does not read freed heap |
| product runtime auto-prefix | a bare program without `uses`, MM/monitor before `SysUtils`, `TThread`/`TMonitor` runtime, a legacy explicit prefix as a no-op, vanilla opt-out, and `-gh` on top of the bundled MM |
| Linux x86-64 stack contract | actual `pthread_getattr_np` size/guard for main, `TThread`, `BeginThread`, and raw pthread; product threads are exactly 1 MiB, main/raw retain Linux/glibc policy |
| `TList<T>` hot paths | growth boundaries, indexed read/write, default/custom comparer search, `ToArray`, copy construction, `AddRange/InsertRange/DeleteRange`, `Pack/Clear`, reorder/sort including `TList<array of interface>`, bounds, exact-class/descendant split, virtual notifications, managed lifetime |
| `TDictionary<TKey,TValue>` hot paths | collisions, grow/explicit rehash, duplicate reject, `Clear`, add/remove notifications, pair/key/value enumeration, managed key/value lifetime, `TryGetValue` hit/miss replacement, aliased managed key/output and non-linear custom probe lookup |
| `TQueue<T>/TStack<T>` hot paths | empty/steady state, wrap-around, scalar/string/128-byte record, `Clear`, enumeration order, managed lifetime |
| `TStringList` name/value search | empty/missing keys, duplicates, separators, embedded NUL, case-sensitive/insensitive and Unicode names |
| compiler loop strength reduction | enum/subrange bounds, guarded out-of-slice cursors, forward/backward traversal, checked-path preservation, procvar-element storage address, mutable UnicodeString/AnsiString/dynamic-array bases, non-address-taken local dynamic array across unrelated calls |
| compiler function-result loop counters | enum/integer/signed-subrange results, forward/backward traversal, early exit, miss fallback, table/string indexing under O3, stack-check instrumentation |
| compiler fixed-array address folding | signed sentinel `J = -1`, `J + 1`/`1 + J`/`J - (-1)`, negative declared bounds, scalar and managed elements |
| WideChar membership in byte-character sets | four/five disjoint ranges, dense mixed ranges, `#$80..#$FF`, variable sets, out-of-range Unicode and single evaluation |
| Variant integer boundaries | direct/byref signed and unsigned carriers, real/currency/string sources, exact overflow/type-cast exception class, Delphi truncation domains |
| x87/SSE defaults | startup masks, mutable process defaults, `SysResetFPU`, worker thread inheritance, Inf/NaN/comparison/overflow/`Trunc` behavior |
| x86-64 peephole `ADD`/`LEA` folding | byte/word array scaling, constant on both sides, negative subtraction, nonzero base offset, 32-bit wrap before 64-bit address use |
| Delphi implicit whole-ASM frame | exact `var`-parameter comparison with two manual early `ret`; unequal/equal paths in Debug/O2/O3; neighbouring ASM routines with a real 32-byte local array or a used seventh stack parameter must retain their compiler frame |
| URL encoding with UTF-8 default code page | Current-tree `System.NetEncoding` (not an installed stale PPU): UnicodeString, raw UTF-8 and arbitrary high bytes, Delphi-compatible ASCII allowed/reserved bytes, FPC length-aware embedded NUL, and empty input before and after `SetMultiByteConversionCodePage(CP_UTF8)` |
| `TTask.WaitForAll/WaitForAny` | empty/nil/already complete, mixed completion, finite/infinite timeout, winning index, exception, cancellation, interactive wait, mixed interactive/non-interactive pools in both orders, and `Synchronize` callback dependencies |
| thread-pool worker lifecycle | immediate shutdown before first time slice, startup publication order, repeated create/run/destroy and clean process exit |
| `System.IOUtils` public API | directory root, file/directory timestamps, missing paths, Delphi enumerator overloads, platform boundaries and error results |
| product RTL API surface | `TTask.Create/Start/Wait`, `TParallel.For`, SHA-256/SHA-512 HMAC, SHA-512/224/256 digest+HMAC, Base64 and URL UTF-8 |
| Linux RTTI Invoke | serializer-owned call-manager registration, class/record constructors and methods, Unicode managed arguments/return and exception propagation |
| C-003 construction ownership | phased `InitializeRecord` (standalone local field/outer throw, class field, happy pairing), holistic open-array copy helper (content+buffer on Assign/Initialize raise, MM-census loop), scalar and inline pre-call guards (a later copy's Assign raise finalizes earlier copies), inlined custom-Initialize locals, updated `aggregate_init_unwind` custom-record-op and `record_management_operators` open-array raise contracts |
| C-001 container spans (`TArray`/`TList`) | DCC64-measured `Move/Exchange/Copy/Sort/BinarySearch` matrix: source→destination check order through indexed message markers, same-index `Move` no-op, state after an exception, negative/past-end/zero-count/`Index=Length`, comparer-call count (no calls for trivial/zero-count cases), insertion point instead of −1 for an empty search, `TBinarySearchResult` candidate, the first `Add` to an empty `TSortedList` and insertion order, and fixed `ListIndexErrorMsg` (the exception class is no longer replaced by the message builder's EConvertError) |
| R-006 memory-stream state machine | negative count/position/size/capacity, Seek overflow with position retained (stricter than DCC wrap), zero-count Write as a pure no-op (the boundary recorded from DCC), write past end growing size, shrink with position clamped, data round-trip after every rejected transition, `Clear`, and the `TBytesStream` twin symmetrically (`Length(Bytes)`>=Size) |
| R-007 `TJSONByteReader` | first AddChar on an empty buffer, exact growth boundary of 16, character-width flush (non-ASCII + surrogate pair), double flush/reset, `aCache` interning for input >1 MiB (same instance) versus small input and `aCache=False`, ASCII parse end-to-end |
| R-015 HTML Span8/Span16 | raw/Unicode no-op alias, raw codepage preservation, exact encoded length, embedded NUL, non-ASCII, the DCC set `& < > "` without apostrophe, known/unknown/unfinished entities, decimal/hex/uppercase-hex, `apos`, numeric NUL, astral surrogate pairs, and invalid numeric entities |
| F-030/A-004 Unicode text streams | `TStringStream` and `TStrings` decode with the selected encoding, `TStringReader` without a byte round trip, UTF-8/UTF-16LE/BE, BOM on/off and BOM override, a multibyte/CRLF chunk boundary after an already-read line, embedded NUL, nonzero/negative/past-end position, repeated short reads, short writes, writer preamble and exact output bytes, `TFile.ReadAllText` BOM/default UTF-8/ANSI fallback |
| R-003 transactional `TStringBuilder` | item and insertion ranges, invalid/overflow state preservation, empty/end insertion, MaxCapacity, `negative/zero/many` repeat, ANSI/Wide, exact-capacity self-alias before/after/across the insertion point, append alias, protected spare-capacity alias, descendant virtual-call counts, safe empty enumeration/equality/replace |
| A-003 direct text sinks | Unicode/Ansi integer append at Low/High signed/unsigned values, exact descendant virtual calls, UTF-8 direct span with a BMP/surrogate-pair boundary at a 128-byte buffer, array subspan, UTF-16BE, preamble/nonzero stream position and short-write exception; `TUTF8Encoding` uses a bounded System span kernel without a managed conversion temporary |
| R-004/R-011/R-012 text spans | full/ranged compare and search, embedded NUL as data, equal-prefix tie-break, quoted/unquoted final separator, empty needle, forward/reverse windows with negative/`Low`/`High(SizeInt)` and oversized count, Unicode/Ansi/Short `EndsText`, `TextPos` nil/empty/hit, and the `System.AnsiStrings` twin |

## Verified major RTL layers without a new fix

Separate programs additionally execute:

- dynamic/static/open arrays and managed records;
- interfaces, Variants, exceptions, and initialization/finalization;
- `TDictionary`, object dictionaries, sets, sorted sets, `TArray` sort/search,
  legacy `TList/TObjectList/TStringList/TThreadList`;
- memory/file/resource/buffered streams, `Move`, `FillChar`;
- critical sections, events, monitors, atomics, thread/TLS lifecycle;
- hashes/comparers, the supported TypInfo/RTTI contract, math/date/string helpers.

The full upstream RTL-ObjPas RTTI differential is retained separately in
`deferred/rtlobjpas_core_deferred.dpr`. Extended member tables and the exact
Delphi semantics of `{$RTTI EXPLICIT ...}` are already covered by a separate
runtime gate; only raw Boolean `PTypeInfo.Kind = tkBool` is deferred, for which
the public `Rtti` facade is compatible and no product raw consumer was found.

| Layer | Result of the current pass |
|---|---|
| strings and managed values | x86-64 Unicode assign/refcount, `Pos`, ASCII case/compare, and UTF-8 paths are optimized; non-ASCII conversion follows the previous shared Unicode path |
| generic collections | concrete access/enumeration, native scalar/Unicode default search, `ToArray`, same-type bulk copy, range growth/delete/move, one-pass `Pack`, callback-free exact-class `Clear`, reordering, and dictionary rehash are fixed; descendant, virtual notification, custom comparer, and owning contracts are retained |
| legacy collections | `TStringList.IndexOf/IndexOfName` gained a direct Unicode path; `TList/TObjectList/TThreadList` remain ownership, ordering, bounds, and threading controls |
| streams and buffers | short-read EOF, Unicode byte position, and buffered 64-bit resize are fixed; memory/file/resource paths remain controls |
| synchronization | POSIX errno/EINTR/deadline paths are fixed; events, monitors, critical sections, atomics, and thread/TLS lifecycle remain controls |
| numeric/formatting | decimal integers, float parsing/format normalization, and `Format` are checked separately; 50,000 deterministic Double bit patterns showed that all 83 changed `FloatToStr` forms moved closer to the Delphi oracle and none moved away; the discrepancy between `FormatFloat` and the shared `Str` decimal core is explicitly recorded in `KNOWN_ISSUES.md` |
| compiler-coupled runtime | unmanaged dynamic-array `Copy` and direct dynamic-array finalization received dedicated lowering; exceptions, RTTI, Variant/interface ABI, and closures remain controls |
| memory manager | is not part of this diff; its separate pinned profile and MM gates remain mandatory |

Without separate evidence, the allocator, exception machinery, Variant/interface
ABI, OS scheduler, and public collection virtuality were not changed. The
experimental first AVX `Move`, cached notification method, and load factor 0.5
were discarded: the first lacked a complete A/B matrix, the second lacked an
honest A/B, and the third bought speed by doubling memory. mORMot `MoveFast`
also did not prove a universal advantage and was not ported.

`System.Move` was later reopened with a separate 297-case matrix and replaced
by a different, independently verified implementation: scalar/SSE fixed-size
blocks, AVX register copies up to 192 bytes, aligned temporal/NT loops, and
preserved memmove overlap semantics. The permanent semantic gate passes
Debug/O2/O3; the full Win64 RTL gate is 240/240 and Linux x86-64 is 237/237.
The exact Win64 medium run is 297/297 MATCH, geomean Moon/Delphi `0.936`; Linux
medium is 297/297 MATCH on another CPU. Evidence and decision boundaries are in
`qualification/performance/evidence/system-move-20260824/`.

## Honest boundary

All changed methods are covered by direct semantic/edge/lifetime tests. It
cannot be claimed that “the entire RTL is fully optimized forever”: that would
require a method/API matrix for tens of thousands of routines and new
performance cases. The collection portion of Pulse has been extended to
48 independent cases; the specific already-proven but deliberately deferred
tails are listed in the public
[`BACKLOG.md`](../doc/BACKLOG.md).
