# Native Linux application comparison suite

This suite compares MoonCompiler with ordinary Rust/serde_json
and C++20/libstdc++ implementations on the **same Linux host**. It is a comparison
of the named application stacks, not a claim that every program in one language
is faster than every program in another. Python only prepares inputs, checks
outputs and orchestrates processes; it is not a benchmark contestant.

The frozen workload, measurement boundaries and host policies are in
[PROTOCOL.md](PROTOCOL.md). All wins and losses are retained.

## Programs

| Case | Useful result | Other implementation |
|---|---|---|
| `trades` | Decode Binance aggTrade messages, find market objects, accumulate price × quantity | Rust borrowed typed serde_json + HashMap |
| `exchange` | Parse a complete exchangeInfo document, retaining access to every field | Rust serde_json::Value |
| `orderbook` | Parse bid/ask arrays and estimate market-buy quantity, execution price and slippage | Rust typed serde_json |
| `serialize` | Write market records, numbers and escaped strings to JSON | Rust serde serialization |
| `analytics` | Buy/sell turnover, maximum price and VWAP over changing windows | C++ loops over a vector |
| `timers` | Select and reschedule the earliest of 8192 deadlines | C++ binary heap with root replacement |
| `dict-string` | Five million mixed hit/miss lookups over 100000 independent string keys | C++ std::unordered_map |
| `dict-int-update` | Five million updates/inserts, with complete final-state validation | C++ std::unordered_map::insert_or_assign |
| `dict-int-update-read` | Update a value, then perform a separate lookup | C++ insert_or_assign followed by at |
| `ring` | 1000 OS threads passing one baton 100000 times, with 16 ms waits | C++ std::thread + std::binary_semaphore |

## Rust examples

All three Rust workloads are implemented in [showcase.rs](showcase.rs), built
with [Cargo.toml](Cargo.toml) and the checked-in [Cargo.lock](Cargo.lock).
They are included in the measured results, not proposed future examples:

- `run_trades`: deserialize each trade into a typed borrowed `Packet`, parse
  price and quantity, find the market in `HashMap<String, Box<Market>>`, and
  accumulate `price * quantity`. File loading is outside the timer; creating
  market objects is inside, matching the Moon program.
- `run_exchange`: parse the full document into `serde_json::Value`, retaining
  every field. Both processing time and peak/retained RSS are recorded.
- `run_serialization`: serialize market records with `serde_json::to_vec`,
  including numbers, quotes and a newline in a string field. This case favours
  Rust on both measured hosts; that result is retained.

The C++ workloads are in [showcase_cpp.cpp](showcase_cpp.cpp). Each case has
one declared comparison implementation; this suite does not claim to have
measured every case in every language.

The additional Rust/Moon [order-book example](orderbook/README.md) is isolated
in `orderbook/`, with its own fixed inputs, verification, commands and raw results.
It uses direct typed loading on both sides. After correcting the Moon numeric
adapter, it uses less CPU on both hosts; the previous AMD loss is retained with
its source and results. Whole-process RSS remains higher. Unlike the other Moon JSON examples,
this one needs MoonORMot only, without the private Common units.

`dict-int-update-read` is an additional control with an immediate lookup after
each update. `audit_cpp_int.cpp` uses the iterator returned by insert_or_assign
instead of that unnecessary second lookup. Neither control replaces pure update.

The Moon JSON paths use the production Common `JsonReader`, `JsonReaderScan`
and `JsonHelpers`, together with MoonORMot. These dependencies must be named
in any publication; they are not all part of the compiler's standard RTL.

The current trade workload extracts only symbol, price and quantity (`s/p/q`).
Moon receives the symbol as a bounded UTF-8 slice into the original packet;
Rust receives a borrowed `&str`. Neither creates a query string. Unknown JSON
values are skipped with syntax checking. Selected strings containing JSON
escapes are rejected by both borrowed interfaces; the frozen corpus uses direct
UTF-8 symbols. The older five-field timestamp/side witness is historical only.

The current trade program uses the RTL `TDictionary<RawUtf8, TMarket>` and
`TryGetValueUtf8(pointer, byteLength, market)`. It does not implement its own
dictionary. Stored keys remain ordinary owning strings; query slices are not
copied. See [the RTL API contract](../../../doc/STRING_DICTIONARIES.md).
The [storage experiments](UTF8_DICTIONARY.md) and their results are historical
evidence only; arena/hybrid prototypes are no longer selected by this program.

Each invocation runs one case and exits. The timed application examples contain no explicit
`try`/`finally`/`catch`: errors abort that process and invalidate its result.
Successful runs free their resources and join every worker before freeing
events. Compiler exception-regression fixtures belong to the separate
`qualification/optimizer-core/analytics` gate, not these application comparisons.
Dictionary contract probes catch deliberately requested insertion errors outside
any performance measurement.

## Reproduction

Use an isolated directory with the published Linux SDK extracted into `sdk/`
and the three frozen Common units in `common/`. Set `MORMOT_ROOT` to the matching
MoonORMot checkout. GCC 13.3, Rust 1.97.1 and the Cargo.lock versions were used.
Cargo dependencies must already be available for the offline build command.

```sh
python3 prepare.py data --per-symbol 64
bash build.sh
python3 verify.py
python3 run.py --cpu 2 --label my-host --pairs 5
```

Use an SDK containing `TryGetValueUtf8`, or build the current RTL first. A
dedicated trade run checks the new API against the same Rust workload:

```sh
bash build_utf8.sh
nice -n 10 python3 run_trades_utf8.py --cpu 2 --label my-host-trades-rtl --pairs 5
```

This runner measures the actual RTL and Rust maps in alternating order. It
validates every market's count, last price and accumulated `P * Q` after every
invocation. Use CPU 0 on the AMD VPS. [Archived prototype results and hashes](utf8-results-20261029.json)
describe the old implementations, not the new RTL API. The separate
`dictionary_slice_probe` compares temporary-string lookup with direct slices
in the same RTL dictionary; it checks the complete result checksum.

`prepare.py` downloads the full public Binance Spot exchangeInfo only when the
file is absent. It generates synthetic full combined aggTrade messages covering
every returned symbol, including inactive ones. They are not recorded trades.
Keep the same `data/` directory for every contestant and host; a future download
changes the universe and cannot be compared to the October 29 results directly.

`verify.py` reconstructs and compares the entire parsed document, generates
independent arithmetic/Decimal oracles, and writes `expected.json`. Run it
separately from measurements. The complete verified document check is performed
before copying the identical binaries to the second host. `run.py` checks each
timed process's output and saves raw logs, CPU/wall durations, hashes and host
state. File preparation and verification are outside the operation timers.

To recheck archived results, including deliberately corrupted outputs:

```sh
python3 check_evidence.py /path/to/evidence /path/to/frozen/data
```

RSS is resident process memory, including allocator retention and required input
buffers. It is not requested allocation size. The exchange document's input is
released only where the resulting representation no longer needs it. Do not use
the trade process's lifetime peak RSS as parser-only memory: its input preparation
differs and is deliberately outside the measured processing interval.

Ring time divided by transfer count describes this timed-wait chain. It is not
an isolated wakeup p99, a model of trading logic, or an explanation of idle worker
CPU. Timeouts never increment the counter. All events remain alive until every
worker has joined.

The complete table, including losses and the distinction between source cleanup and compiler changes, is in [RESULTS.md](RESULTS.md). Raw measurements and identities are in [results-20261029.json](results-20261029.json).
