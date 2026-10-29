# Native Linux application results - 29 October 2026

All nine cases were rerun after removing explicit try/finally/catch from the examples. Each invocation runs one case; errors abort the process and invalidate its result. Successful runs still free resources and join workers. Compiler exception tests remain in a separate correctness gate. C++ ring workers now use std::thread without cancellation polling; the timed-wait workload is unchanged.

String lookup was subsequently corrected and rerun separately on both hosts:
Moon passes each array element directly to TryGetValue instead of assigning an
owned string iteration variable. The string-lookup rows below use this newer
build; the other eight cases retain the preceding measurements and build hashes.

Trades were then corrected to select only `s/p/q` and to look up the UTF-8 symbol
directly by pointer/length. The trade rows below now use this later five-pair run
with the existing generic byte-view dictionary and, in a separate row, the
shared-buffer application prototype; Rust selects the same three fields.
[UTF-8 results](UTF8_DICTIONARY.md) identify the arena/hybrid implementations,
all trade alternatives and the new build hashes. Earlier five-field trade
rows remain in the original JSON as historical evidence.

Wins and losses are retained. Each host uses five alternating pairs on the same pinned CPU, with identical inputs and executable hashes across hosts. These compare the named application stacks, not entire programming languages.

The development compiler is based on `1c7f927e2` with two repairs in three audited tree-optimizer files; it is not a new published SDK. Linux compiler SHA256: `3954232bdc31a67c818213f75306d8e8c48ba28b84b645351a1b5573113f5a68`. It uses the unchanged published 2.5.2 RTL. GCC is 13.3 (`-O3 -std=c++20`); Rust is 1.97.1 (release, checked-in Cargo.lock). No fast-math flags are used.

## Process CPU time

Medians in milliseconds. Competitor / Moon above 1 favours Moon. AMD is a one-vCPU EPYC Rome VPS with a running MoonBot; it is a production-load check, not an isolated microarchitecture comparison. No GHz normalization is used.

### Intel Xeon W-2295 Hel1

| Workload | Comparison implementation | Moon, ms | Other, ms | Other / Moon |
|---|---|---:|---:|---:|
| Trades and market turnover: generic byte-view map | Rust serde_json + HashMap | 275.37 | 605.18 | 2.20x |
| Trades and market turnover: shared-buffer map prototype | Same Rust program | 234.82 | 605.18 | 2.58x |
| Full exchangeInfo parsing | Rust serde_json::Value | 37.24 | 148.11 | 3.98x |
| Order-book JSON and market-buy estimate | Rust typed serde_json | 104.48 | 157.34 | 1.51x |
| Market JSON serialization | Rust serde_json::to_vec | 476.31 | 397.53 | 0.83x |
| Window turnover, maximum and VWAP | C++ vector + numeric loops | 233.77 | 224.58 | 0.96x |
| Timer heap rescheduling | C++ binary heap | 215.07 | 316.81 | 1.47x |
| String dictionary lookup | C++ unordered_map | 243.22 | 346.51 | 1.42x |
| Integer dictionary update | C++ insert_or_assign | 94.00 | 83.09 | 0.88x |
| Integer update then lookup | C++ insert_or_assign + at | 338.66 | 140.64 | 0.42x |
| 1000-thread timed event ring | C++ thread + binary_semaphore | 424.94 | 679.77 | 1.60x |

### AMD EPYC Rome VPS

| Workload | Comparison implementation | Moon, ms | Other, ms | Other / Moon |
|---|---|---:|---:|---:|
| Trades and market turnover: generic byte-view map | Rust serde_json + HashMap | 204.18 | 436.71 | 2.14x |
| Trades and market turnover: shared-buffer map prototype | Same Rust program | 190.41 | 436.71 | 2.29x |
| Full exchangeInfo parsing | Rust serde_json::Value | 32.94 | 122.62 | 3.72x |
| Order-book JSON and market-buy estimate | Rust typed serde_json | 80.27 | 112.65 | 1.40x |
| Market JSON serialization | Rust serde_json::to_vec | 394.35 | 310.82 | 0.79x |
| Window turnover, maximum and VWAP | C++ vector + numeric loops | 180.33 | 170.34 | 0.94x |
| Timer heap rescheduling | C++ binary heap | 154.13 | 204.89 | 1.33x |
| String dictionary lookup | C++ unordered_map | 458.39 | 343.42 | 0.75x |
| Integer dictionary update | C++ insert_or_assign | 79.02 | 37.68 | 0.48x |
| Integer update then lookup | C++ insert_or_assign + at | 313.34 | 67.80 | 0.22x |
| 1000-thread timed event ring | C++ thread + binary_semaphore | 873.77 | 790.01 | 0.90x |

The two trade rows perform the same complete operation: create 3742 markets,
parse 957952 trades, look up the market and accumulate `price * quantity`.
Both borrow each query symbol without a temporary string. Shared storage saves
14.7% / 6.7% CPU versus the generic byte-view map on Intel / AMD. This is an
application-container comparison, not a claim that the prototype implements
the complete RTL dictionary contract. [Source, scope and all alternatives](UTF8_DICTIONARY.md)
and [raw runs](utf8-results-20261029.json) are included for reproduction.

The three Rust cases are in [showcase.rs](showcase.rs): typed borrowed trade
deserialization, a complete exchangeInfo document, and market serialization.
The C++ cases are in [showcase_cpp.cpp](showcase_cpp.cpp). The language/library
column identifies which implementation was actually measured for every row.

The later [order-book case](orderbook/README.md) has separate source/build/input
identities and paired results. It parses both numeric sides and performs three
market-buy estimates for each snapshot; file loading is outside timing. Its
numeric adapter now uses GetNextExtended directly, avoiding tokenization's
NUL write immediately before SIMD conversion. This source correction was rerun
on both hosts; the earlier AMD loss and source remain in its controls directory.
Whole-process RSS is still higher than Rust, as detailed in the case README.
The arithmetic-window case remains here as historical/control evidence.

## String lookup and storage

The workload is five million lookups over 100000 stored keys and one million
prepared queries, with the same hit/miss sequence and checksum on both sides.
No string assignment or allocation is required by the timed Moon loop. On the
loaded AMD VPS Moon CPU samples range from 431.93 to 478.37 ms and C++ from
313.84 to 368.04 ms. Do not interpret changes between separate AMD series as a
precise compiler-patch gain.

These 15-character ASCII keys occupy 30 UTF-16 bytes in separately allocated
Moon string buffers. libstdc++ stores their 15 bytes inside each std::string
object, including the dictionary node. A controlled experiment using one C++
binary, unchanged key bytes/hash/bucket count, moved only stored keys into
separate buffers before timing: CPU rose from 351.82 to 406.30 ms on Intel and
328.27 to 486.47 ms on AMD. This establishes a material data-storage cost without
moving the lookup instructions. That diagnostic variant does not replace the
ordinary C++ implementation in the comparison table. It is not an exact
decomposition of the difference between two different containers.

## Memory and event-ring boundaries

| Host | exchangeInfo Moon peak / retained MiB | Rust peak / retained MiB | Ring Moon / C++ wall ms |
|---|---:|---:|---:|
| Intel Xeon W-2295 Hel1 | 43.50 / 43.50 | 123.71 / 107.27 | 429.85 / 683.26 |
| AMD EPYC Rome VPS | 41.89 / 41.89 | 124.72 / 107.77 | 974.54 / 887.33 |

Moon retains an in-place indexed document; Rust retains serde_json::Value. Every field remains accessible and the full document was independently compared. RSS includes required input buffers, runtime and allocator retention. Trade-process peak RSS is not parser-only memory: input preparation differs and is excluded from processing time.

The ring transfers one baton 100000 times among 1000 OS threads, with 16 ms waits. Timeouts never advance the counter. It measures this chain including empty wakeups, not isolated wakeup p99 or idle trading workers. C++ uses std::thread and std::binary_semaphore.

## Analytics: source improvement versus compiler repair

The calculation is a separate function with local accumulators and no explicit exception block. Both languages name price, quantity and their product once per sample, stating the intended snapshot of immutable input. Window definitions, accumulation order and checksums are unchanged. Both compilers measured the same final source.

| Host | Published 2.5.2, ms | Development compiler, ms | C++ paired with development compiler, ms |
|---|---:|---:|---:|
| Intel Xeon W-2295 Hel1 | 233.95 | 233.77 | 224.58 |
| AMD EPYC Rome VPS | 192.69 | 180.33 | 170.34 |

These full baseline and candidate series ran separately. Their difference, particularly on the loaded AMD VPS, is not proof of a compiler-patch gain. The earlier explicit-value source cleanup already improved published 2.5.2. The current paired analytics result still favours C++; it is not presented as a Moon win.

The compiler repair addresses separate unchanged-source cases where unrelated exception handling disabled useful optimization: accumulators in the original large main block now stay in registers; stable local-array base loads can move out of the loop. Repeated base loads for the original global array remain. The published example's local function and explicit values must not be mistaken for a complete compiler repair of that original shape.

Experimental general heap-read reuse and scalar-prefix hoisting were rejected: the former lacked an ownership proof; the latter could change exception order, and its corrected form slowed a neighbouring kernel by breaking compare/branch fusion. Neither is in the final compiler.

## Reproduction and evidence

[PROTOCOL.md](PROTOCOL.md) defines the workloads; [README.md](README.md) gives commands. [Raw measurements and hashes](results-20261029.json) include both compilers and both hosts. There are 3742 Binance symbols, 239488 generated complete combined aggTrade messages and a 17817633-byte exchangeInfo. Trades are synthetic, 64 messages per symbol, including inactive symbols. A later download changes the fixture: compare hashes before calling it the same experiment.

All original 360 measured outputs passed independent checks; all 20 outputs
from the subsequent string-lookup rerun passed as well. Its measurements and
exact build identities are under `string_lookup_indexed` in the JSON; original
rows are retained as historical evidence. Mutation tests rejected 768 deliberately corrupted outputs. Trade totals use a Decimal oracle for every symbol; document and serialization checks inspect contents. The separate iterator-return control was rebuilt and rerun five times per host; its source hash, binary hash and results are also in the JSON.

Moon JSON uses production Common JsonReader/JsonReaderScan/JsonHelpers and MoonORMot, not only compiler RTL. Reproduction requires those dependencies; the private Common snapshot is not redistributed here. build.sh records its hashes. This is not a dependency-free compiler benchmark or evidence that every Moon program beats C++ or Rust.
