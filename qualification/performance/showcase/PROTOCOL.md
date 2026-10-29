# Native Linux application comparisons

Frozen choices, 29 October 2026. No Python benchmark implementation.

- Published MoonCompiler 2.5.2 and the identified development compiler, both using the published RTL, product Release profile, production Common JSON helpers and MoonORMot.
- Rust/serde_json: typed Binance trade parsing and accumulation, full exchangeInfo document, JSON generation.
- A later standalone order-book case adds direct typed numeric-array parsing and
  three market-buy estimates per snapshot. Its frozen workload, verification and
  separate build/results are in [orderbook/README.md](orderbook/README.md).
- C++20/libstdc++: numeric windows, string/integer dictionary operations, timer heap, 1000-thread timed-event ring.
- Both sides run sequentially on the same pinned logical CPUs. No service is stopped.
- Repeat on Intel Hel1 and an available AMD host. Ratios belong to each host; no GHz normalization.
- Use fixed identical inputs, independent Decimal trade oracle, all-symbol checks and per-operation checksums.
- Trade input is explicitly synthetic Binance-format data using the entire frozen real symbol list.
- Current trade projection is only `s/p/q`: symbol, price and quantity. Moon's
  symbol is a pointer/byte-length view into the packet; Rust uses borrowed `&str`.
  Unknown values are syntax-checked and skipped. No per-trade symbol allocation,
  UTF-16 conversion or copied query buffer is part of either implementation.
  Selected symbol strings with JSON escapes are rejected by these borrowed
  interfaces; direct UTF-8 including non-ASCII is supported.
- The current `trades` program uses the actual RTL `TDictionary<RawUtf8,TMarket>`
  with `TryGetValueUtf8`, against the same Rust trade program. Both create all
  market objects/maps inside timing. Stored keys are owned; query symbols are
  borrowed only for the lookup call. The dedicated `run_trades_utf8.py` runner
  checks every market after every run. Earlier byte-view/arena/hybrid results
  in UTF8_DICTIONARY.md are archived experiments, not measurements of this API.
- File reads, input-string arrays and reusable parser configuration are outside workload timers.
  Trade timing includes creation of every market object and its map, parsing, lookup and accumulation.
  Dictionary/analytics/serialization fixtures are prepared before their operation timers.
  Memory reports retain required input/storage costs.
- Three or more alternating measured pairs per case, same work and binary hashes; retain all observations.
- Ring: 1000 OS threads, Wait(16), one baton, each recipient increments exactly once per valid signal.
  Timeouts never advance the baton. Report wall time, process CPU, timeout count and total transfers.
- Memory: full readable document, input plus representation, process baseline, peak RSS and retained RSS.
  These OS measurements are not allocator requested bytes. All fields remain accessible to both sides.
- All gains and losses will be reported. Do not change counterpart selection after observing a loss.
- Integer dictionary primary case is pure update; a separate update-then-read control is retained.
  All final entries and the final dictionary size are verified outside the timer.
- String lookup passes an array element directly as a const argument in Moon;
  C++ iterates by const reference. Neither acquires ownership of a per-query string.
  The 15-character ASCII keys use normal UnicodeString in Moon and std::string
  in C++; their different encodings and short-string storage are part of the
  named stacks. Query text is independent of stored keys on both sides.
- Intel Hel1 uses logical CPU 2 (SMT sibling 20); AMD EPYC VPS uses its sole CPU 0.
  AMD runs at nice 10 to preserve the running MoonBot (nice 5). This is a loaded VPS check,
  not a dedicated CPU claim. Process CPU and wall time are reported separately.
- Final workload sizes: 239488 generated trades x 4 passes; one 17.0 MiB exchangeInfo;
  3742 output rows x 500; 524288 analytics windows; 3.2 million timer updates;
  5 million dictionary operations; 1000 threads x 100 signals = 100000 baton transfers.
- Independent review corrected CRLF loading, integer-map final-state verification
  and serialization setup symmetry. The former trade timestamp/side witness was
  subsequently removed from both contestants because those fields are not used
  for turnover; historical five-field results remain labelled as such. The timer oracle
  sums arithmetic progressions without reproducing the tested heap algorithm.

Public schema references:
- https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams
- https://developers.binance.com/docs/binance-spot-api-docs/rest-api/general-endpoints
- https://bybit-exchange.github.io/docs/v5/websocket/public/trade

The Bybit message was examined but is not used: the requested universe is Binance Spot.
Benchmark code does not alter RTL, allocator or production helpers. Compiler-only repairs are measured separately from source cleanup; RESULTS.md identifies the development compiler.
