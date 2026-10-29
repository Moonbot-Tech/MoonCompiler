# Order-book JSON to market-buy execution estimate

This example reads a Binance Spot depth snapshot, constructs numeric bid/ask
arrays, and estimates buying with three quote-currency budgets. It reports
acquired base quantity, quote spent, average price, last consumed price,
slippage relative to the best ask, and unspent budget. It is a calculation over
a snapshot; fees, lot rounding and later changes at the exchange are outside
this workload.

The [Binance depth schema](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market)
uses `lastUpdateId`, `bids` and `asks`; each level contains two decimal strings.
[bench.py](bench.py) deterministically generates nine **synthetic** snapshots:
100, 1000 and 5000 levels per side, at three price scales. Both sides are ordered.
The budgets consume half the first level, 55% of available ask notional, and
more than the available liquidity. No exchange requests occur during preparation
or measurement.

## Equivalent useful work

- [Moon](orderbook_moon.dpr): MoonORMot `RecordLoadJson` directly populates numeric
  arrays. `ReadLevel` maps a two-element JSON array into a named price/quantity
  record. Ordinary decimal strings go directly through the library's ASM
  `GetNextExtended` up to the closing quote; escaped strings use the JSON decoder.
  This is the numeric primitive also used by the production `JsonReaderScan` helper.
- [Rust](orderbook.rs): typed serde_json deserialization directly populates
  `Vec<Level>`. A small decimal-string visitor converts to `f64`, including escaped
  strings, without allocating a `String` per number. No `serde_json::Value` tree.
- Both allocate and release the numeric arrays inside the timer, read all levels,
  run all three purchases and produce checksums. Floating-point arithmetic is
  binary64 with the same accumulation order; no fast-math or SIMD-specific flags.
- File loading and one-time schema registration are outside the timer. The Moon
  parser's required mutable input copy is **inside** it. Input files are unchanged.
- No locks, worker threads, explicit exception blocks or owned string loop
  variables occur in the calculation. Exceptions/panics invalidate the invocation.

Each measured process handles 288 snapshots, 1,171,200 levels and 864 purchases
(32 passes). Five alternating pairs follow one discarded warm-up per program.
CPU and elapsed wall time are measured separately; RSS is the peak for the
**whole process**, including inputs, linked libraries and allocator retention.
It is not a parser-only allocation measurement.

## Results, 29 October 2026

| Host | Moon CPU ms | Rust CPU ms | Moon compared with Rust |
|---|---:|---:|---|
| Intel Xeon W-2295, Hel1 | 104.48 | 157.34 | 33.6% less CPU time |
| AMD EPYC Rome VPS | 80.27 | 112.65 | 28.7% less CPU time |

| Host | Moon / Rust wall ms | Moon / Rust peak process RSS MiB |
|---|---:|---:|
| Intel | 104.55 / 157.36 | 8.44 / 3.25 |
| AMD | 91.35 / 130.21 | 8.92 / 3.62 |

The AMD host also runs MoonBot. Programs run sequentially at nice 10 on its
single vCPU. Intel runs on CPU 4. The executable hashes are identical across
hosts. Both hosts favour Moon for this declared workload. These results compare
the two complete application/library stacks, not compilers independently of libraries.

The preceding typed-loader version used `GetExtended` after JSON tokenization.
It consumed 146.37 / 135.52 ms on Intel / AMD and lost to Rust on AMD by 16.3%.
Tokenization scanned the number and wrote a NUL terminator immediately before
the ASM converter read that region with SIMD. Direct conversion avoids that
write/read dependency and the redundant scan, while preserving escaped strings
and validation. The old [source and paired results](controls/tokenized-number/)
are retained. The compiler, RTL, input workload and Rust implementation did not change.

Peak RSS remains higher. A separate staged measurement on AMD found about
7.0 MiB Moon / 2.5 MiB Rust **before** reading JSON. Much of the difference is
resident executable code/tables and initialized allocator metadata, not parsed
book objects. The largest useful bid/ask arrays contain 160000 bytes. Total
process RSS must not be described as parser-only allocation or as a memory win.

The initial Moon version built a complete indexed JSON document before filling
the numeric arrays: 246.96 ms on Intel versus Rust's 157.42 ms. Typed loading
removed that unnecessary intermediate representation. The initial result and
source are retained under `controls/`; it is not substituted for the final
direct-loading comparison or presented as a compiler optimization.

Raw paired runs: [Intel](results-intel.json), [AMD](results-amd.json).
[Build identity](build-identity.txt) records the compiler, config, MoonORMot
revision and binaries. Moon uses the same development compiler and published
2.5.2 RTL as the parent comparison. Rust is 1.97.1; dependencies are pinned by
[Cargo.lock](Cargo.lock). No compiler or RTL source was changed for this case.

## Verification and reproduction

`verify` compares **every** level and all purchase fields with an independent
Python Decimal calculation. It also checks empty books, zero budgets/quantity,
exact first-level exhaustion, insufficient depth, exponent notation, long
mantissas, whitespace, reordered fields and escaped decimal strings. Fourteen
additional numeric cases exercise both direct and escaped decoding. Eight malformed/type/value cases
must fail; a deliberately corrupted level must be rejected by the verifier.
This is application-output validation on a declared schema, not a claim of full
JSON parser conformance or identical handling of all invalid documents.

```sh
python3 bench.py prepare
# Set MOON_COMPILER, MOON_CONFIG and MORMOT_ROOT to a matching SDK/build.
# Optional MOON_UNITS points to compatible, already compiled MoonORMot units.
bash build.sh
python3 bench.py verify
python3 bench.py run --cpu 2 --nice 10 --label my-linux-host --output results.json
```

The build uses existing offline Cargo dependencies. For another host, copy the
same binaries and data, restore executable permissions, verify, then run with
that host's CPU number. [verification.json](verification.json) records the
completed checks. The same check list passed on both measured hosts.
