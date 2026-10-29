# UTF-8 dictionary storage experiment — 29 October 2026

This is archived experimental evidence. The current `showcase_moon trades`
program uses the actual RTL `TDictionary.TryGetValueUtf8` instead of these
prototype containers. The old percentages below must not be attributed to the
new API. Prototype sources and raw results remain available for investigation;
`trades-arena` and `trades-hybrid` are no longer current showcase commands.

All lookups use independent query text. Five implementations accept an immutable pointer and byte length; the sixth control is the existing optimized `TDictionary<RawUtf8, UInt64>` using prepared string queries. Its strings are created before timing. No fake Pascal string headers are used.

Five rotating repetitions on each host; one million approximately 90% hit lookups per process. CPU time is separate from wall time. Both hosts use identical executables and datasets. Intel: Xeon W-2295 Hel1, CPU 2. AMD: EPYC Rome VPS, CPU 0, nice 10 with the live service untouched. AMD ranges are in the raw data; small differences on this loaded VPS are not precision claims.

## Containers

- `generic-owned`: existing optimized RawUtf8 dictionary; prepared owned query strings. Different API/hash path from byte-view variants.
- `generic-view`: existing generic dictionary with a pointer/length comparer; copies keys at insertion, never at lookup.
- `external`: flat 24-byte slots, with keys in separately owned string buffers.
- `arena`: 8-byte hash/offset slots; a shared growing byte buffer stores a 16-byte length/value header and the variable-length key, rounded to 8-byte boundaries.
- `inline16`: 40-byte slots with up to 16 key bytes inline, separately owned long keys.
- `hybrid32`: 32-byte slots with a union of 16 inline bytes or an offset into a shared long-key buffer. No separate long-string objects.

All four custom containers use the same CRC32C hash and linear probing, at most 50% occupancy. They reserve a maximum entry count and implement insertion/lookup/destruction, not the full public TDictionary contract. Remove, iterator invalidation, managed values, custom comparers and notifications are outside this prototype. Keys compare byte-exactly, including embedded NUL, without Unicode normalization.

## Lookup and construction

Profiles: `ASCII15` = 15 bytes; `UTF8` = 29 bytes including Cyrillic and emoji; `mixed` = 15–128 bytes with shared prefixes. CPU milliseconds are medians. Live MiB are allocator-reported usable bytes of table-owned allocations after construction, including size-class rounding; they exclude fixture/query arrays. They are not RSS. Build allocation count includes realloc calls. `peak_live_bytes` in raw data only sees MM call boundaries, not transient memory inside realloc.

### Intel Hel1

| Entries | Keys | Container | Lookup CPU ms | Build CPU ms | Live MiB | Build allocations |
|---:|---|---|---:|---:|---:|---:|
| 3742 | ASCII15 | arena | 27.60 | 0.08 | 0.19 | 12 |
| 3742 | ASCII15 | external | 27.95 | 0.15 | 0.36 | 3745 |
| 3742 | ASCII15 | generic-owned | 28.62 | 0.27 | 0.33 | 3744 |
| 3742 | ASCII15 | generic-view | 45.01 | 0.25 | 0.42 | 3747 |
| 3742 | ASCII15 | hybrid32 | 28.65 | 0.07 | 0.25 | 2 |
| 3742 | ASCII15 | inline16 | 27.05 | 0.25 | 0.40 | 3 |
| 3742 | UTF8 | arena | 28.61 | 0.10 | 0.31 | 13 |
| 3742 | UTF8 | external | 29.12 | 0.16 | 0.42 | 3745 |
| 3742 | UTF8 | generic-owned | 34.47 | 0.28 | 0.39 | 3744 |
| 3742 | UTF8 | generic-view | 46.29 | 0.26 | 0.48 | 3747 |
| 3742 | UTF8 | hybrid32 | 30.44 | 0.11 | 0.38 | 12 |
| 3742 | UTF8 | inline16 | 31.63 | 0.36 | 0.60 | 3745 |
| 3742 | mixed | arena | 67.17 | 0.39 | 0.63 | 14 |
| 3742 | mixed | external | 69.69 | 0.25 | 0.56 | 3745 |
| 3742 | mixed | generic-owned | 65.77 | 0.33 | 0.53 | 3744 |
| 3742 | mixed | generic-view | 88.90 | 0.36 | 0.62 | 3747 |
| 3742 | mixed | hybrid32 | 73.61 | 0.42 | 0.81 | 14 |
| 3742 | mixed | inline16 | 71.92 | 0.47 | 0.74 | 3679 |
| 100000 | ASCII15 | arena | 48.59 | 5.35 | 8.06 | 17 |
| 100000 | ASCII15 | external | 47.09 | 7.91 | 12.63 | 100003 |
| 100000 | ASCII15 | generic-owned | 45.54 | 10.67 | 11.81 | 100002 |
| 100000 | ASCII15 | generic-view | 69.28 | 11.98 | 14.63 | 100005 |
| 100000 | ASCII15 | hybrid32 | 35.90 | 5.29 | 10.00 | 2 |
| 100000 | ASCII15 | inline16 | 37.03 | 6.35 | 12.81 | 3 |
| 100000 | UTF8 | arena | 50.34 | 6.46 | 12.06 | 18 |
| 100000 | UTF8 | external | 48.01 | 9.27 | 14.15 | 100003 |
| 100000 | UTF8 | generic-owned | 52.19 | 12.52 | 13.34 | 100002 |
| 100000 | UTF8 | generic-view | 71.68 | 13.87 | 16.15 | 100005 |
| 100000 | UTF8 | hybrid32 | 48.04 | 8.16 | 16.00 | 17 |
| 100000 | UTF8 | inline16 | 52.09 | 11.51 | 18.15 | 100003 |
| 100000 | mixed | arena | 108.73 | 9.43 | 20.06 | 19 |
| 100000 | mixed | external | 91.06 | 10.24 | 17.97 | 100003 |
| 100000 | mixed | generic-owned | 89.92 | 12.65 | 17.15 | 100002 |
| 100000 | mixed | generic-view | 124.14 | 14.21 | 19.97 | 100005 |
| 100000 | mixed | hybrid32 | 92.73 | 10.34 | 20.00 | 18 |
| 100000 | mixed | inline16 | 97.16 | 12.64 | 21.90 | 98247 |

### AMD VPS

| Entries | Keys | Container | Lookup CPU ms | Build CPU ms | Live MiB | Build allocations |
|---:|---|---|---:|---:|---:|---:|
| 3742 | ASCII15 | arena | 20.68 | 0.07 | 0.19 | 12 |
| 3742 | ASCII15 | external | 24.25 | 0.14 | 0.36 | 3745 |
| 3742 | ASCII15 | generic-owned | 24.70 | 0.19 | 0.33 | 3744 |
| 3742 | ASCII15 | generic-view | 41.41 | 0.18 | 0.42 | 3747 |
| 3742 | ASCII15 | hybrid32 | 22.88 | 0.07 | 0.25 | 2 |
| 3742 | ASCII15 | inline16 | 23.09 | 0.24 | 0.40 | 3 |
| 3742 | UTF8 | arena | 21.81 | 0.10 | 0.31 | 13 |
| 3742 | UTF8 | external | 25.09 | 0.14 | 0.42 | 3745 |
| 3742 | UTF8 | generic-owned | 29.41 | 0.19 | 0.39 | 3744 |
| 3742 | UTF8 | generic-view | 46.15 | 0.19 | 0.48 | 3747 |
| 3742 | UTF8 | hybrid32 | 27.09 | 0.12 | 0.38 | 12 |
| 3742 | UTF8 | inline16 | 27.47 | 0.31 | 0.60 | 3745 |
| 3742 | mixed | arena | 57.65 | 0.34 | 0.63 | 14 |
| 3742 | mixed | external | 61.68 | 0.23 | 0.56 | 3745 |
| 3742 | mixed | generic-owned | 51.06 | 0.24 | 0.53 | 3744 |
| 3742 | mixed | generic-view | 76.26 | 0.25 | 0.62 | 3747 |
| 3742 | mixed | hybrid32 | 62.81 | 0.34 | 0.81 | 14 |
| 3742 | mixed | inline16 | 65.44 | 0.41 | 0.74 | 3679 |
| 100000 | ASCII15 | arena | 34.43 | 4.95 | 8.06 | 17 |
| 100000 | ASCII15 | external | 75.61 | 12.19 | 12.63 | 100003 |
| 100000 | ASCII15 | generic-owned | 76.81 | 13.84 | 11.81 | 100002 |
| 100000 | ASCII15 | generic-view | 180.42 | 18.94 | 14.63 | 100005 |
| 100000 | ASCII15 | hybrid32 | 42.14 | 8.39 | 10.00 | 2 |
| 100000 | ASCII15 | inline16 | 49.89 | 10.37 | 12.81 | 3 |
| 100000 | UTF8 | arena | 55.22 | 7.51 | 12.06 | 18 |
| 100000 | UTF8 | external | 87.14 | 14.88 | 14.15 | 100003 |
| 100000 | UTF8 | generic-owned | 87.25 | 13.78 | 13.34 | 100002 |
| 100000 | UTF8 | generic-view | 168.74 | 18.26 | 16.15 | 100005 |
| 100000 | UTF8 | hybrid32 | 72.09 | 11.69 | 16.00 | 17 |
| 100000 | UTF8 | inline16 | 106.31 | 20.45 | 18.15 | 100003 |
| 100000 | mixed | arena | 115.57 | 12.41 | 20.06 | 19 |
| 100000 | mixed | external | 139.43 | 14.37 | 17.97 | 100003 |
| 100000 | mixed | generic-owned | 134.53 | 13.70 | 17.15 | 100002 |
| 100000 | mixed | generic-view | 219.09 | 19.13 | 19.97 | 100005 |
| 100000 | mixed | hybrid32 | 134.85 | 16.73 | 20.00 | 18 |
| 100000 | mixed | inline16 | 165.42 | 22.13 | 21.90 | 98247 |

## Full trade parsing and market turnover

239488 complete synthetic Binance combined aggTrade messages × 4 passes = 957952 trades. All 3742 frozen real symbols are covered, including seven non-ASCII symbols; the longest UTF-8 name is 30 bytes. Input files/string arrays are prepared before the timer. Creating market objects and their dictionary, parsing, lookup and accumulating `price * quantity` are timed.

Both Moon and Rust select only `s/p/q`, skip other values with syntax checks, and borrow the symbol directly from the input. Moon uses Common JsonReader/JsonReaderScan and MoonORMot; Rust uses serde_json and HashMap<String, Box<Market>>. These named libraries are part of the comparison. Selected JSON-escaped symbol strings are rejected by both borrowed interfaces; the input uses direct UTF-8.

| Host | Existing generic byte-view map | Arena prototype | Hybrid prototype | Rust |
|---|---:|---:|---:|---:|
| hel1 | 275.37 ms | 234.82 ms | 251.29 ms | 605.18 ms |
| amd | 204.18 ms | 190.41 ms | 190.03 ms | 436.71 ms |

In that archived experiment the arena reduced full-workload CPU time by 14.7% on Intel and 6.7% on AMD versus the generic view map. Rust took 2.58× and 2.29× the arena time, respectively. Those were prototype results, not measurements of the current RTL slice API.

## What this does and does not establish

Variable-length storage is practical: a slot can contain a fixed-size offset while its key has arbitrary length in a separate shared buffer. No short-key size is required for that design. Inline storage instead buys one fewer dependent access for short keys, at the cost of larger table cells.

No universal winner: hybrid helps large short-key maps on both hosts, but arena wins the actual trade workload on Intel and is effectively tied with hybrid on the loaded AMD VPS. For small mixed-length maps, the optimized existing RawUtf8 map beats the prototypes; arena reserve space can also exceed separately allocated key storage. Construction, lookup and memory must be considered together. These measurements do not justify replacing every RTL dictionary.

## Correctness and reproduction

Windows and Linux pass empty/nil-zero, embedded NUL, non-ASCII, inline boundaries, source mutation/lifetime, duplicate insertion, capacity limits, arena growth, bucket-wrap and full-hash collisions. Read-only query pages ending at an inaccessible guard page test no writes and no overreads for lengths 0–96. Every measured lookup has zero allocations and frees, and destruction returns counted live storage to zero. The trade slice probe checks pointer ownership, unmodified input, skipped irrelevant fields and rejected missing/truncated/escaped selected inputs.

400 final measured outputs passed independent validation; 120 deliberately corrupted trade summaries/turnovers were rejected. Every market count, last price and P×Q total is checked against the frozen Decimal oracle. Windows additionally passed 18 allocation/lookup combinations; Windows timings are not used as cross-platform performance evidence.

Use the archived source/build identities when reproducing these prototype
measurements. Current build/run commands in README.md test the RTL API instead.
[Raw final measurements and source/build identities](utf8-results-20261029.json)
retain all observations. `verify_utf8_results.py` rechecks archived per-market
outputs and deliberately damaged controls. Prototype memory metering was disabled
during timing. Compiler/RTL product sources were not changed for that experiment.
