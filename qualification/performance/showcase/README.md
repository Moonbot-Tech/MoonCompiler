# Trading workloads: Moon and Rust on Linux

Three standalone tasks from a trading terminal, using MoonCompiler with Moonbot's
JSON helpers and MoonORMot, compared with ordinary Rust/serde_json implementations.
Each pair receives the same data and must produce the same useful result.

| Task | What both programs do | Sources |
|---|---|---|
| Trades | Parse 957,952 messages, find one of 3,742 markets, accumulate price × quantity | [Moon](showcase_moon.dpr), [Rust](showcase.rs) |
| Exchange information | Parse the complete 17 MiB Binance instrument document and retain access to every field | [Moon](showcase_moon.dpr), [Rust](showcase.rs) |
| Order book | Read numeric levels and calculate quantity, average execution price and slippage for three purchase budgets | [Moon](orderbook/orderbook_moon.dpr), [Rust](orderbook/orderbook.rs) |

The trade case uses the current RTL `TDictionary.TryGetValueUtf8`. The JSON helpers
are included in [common/](common/); no private source repository is required.

Recorded runs: [Intel](results-20261031-intel.json) · [AMD](results-20261031-amd.json),
with all five pairs, build identities and correctness checks.

## Run the ready-made programs

Requires Linux x86-64, glibc 2.34 or newer and `libgcc_s.so.1`, plus Python 3.11
or newer, `bash`, `tar`, `sha256sum` and `taskset`:

```sh
./reproduce.sh run
```

The four [Linux executables](bin/linux-x86_64/) include **both Moon and Rust**.
No compiler is needed. The command verifies their hashes, unpacks the fixed inputs,
checks the full results and runs five alternating pairs for each task. It prints
CPU time, peak process memory and the relative difference. Individual observations
are saved under `results/reader-*`; build and verification logs are in `.reproduce/`.

The default uses the first CPU available to the process. To choose CPUs explicitly:

```sh
SHOWCASE_CPU=2 SHOWCASE_BOOK_CPU=4 ./reproduce.sh run
```

## Build from source

Install Rust 1.97.1, Git, curl and a C toolchain/linker. Then:

```sh
./reproduce.sh build
./reproduce.sh run
```

The build downloads the public MoonCompiler 2.5.3 Linux SDK and MoonORMot revision
`f62a8f24ba6f05b8289adf938fc5199395db3cf9` into `.reproduce/`. Cargo downloads the
versions in the two `Cargo.lock` files. It builds both contestants and replaces the
four local executables. Nothing is installed system-wide.

## Inputs and checks

[inputs/data-20261029.tar.gz](inputs/data-20261029.tar.gz) contains the fixed Binance
`exchangeInfo` response, synthetic `aggTrade` messages, symbol list, per-market
Decimal oracle and checksums. The run does not download a fresh exchange response.
The nine order-book snapshots are generated deterministically by
[orderbook/bench.py](orderbook/bench.py).

The checks compare every field of the exchange document, every market's trade
count/last price/turnover, and every order-book level and purchase result. Broken
or incomplete results fail the run. Network waits and file loading are outside
CPU timing; parsing, market lookup and the calculations are inside it.

Memory is the peak RSS of the whole process, including input buffers and loaded
libraries. In the trade case, input preparation is outside CPU timing but still
contributes to peak RSS. It is not a parser-only allocation measurement.

[Full test protocol](PROTOCOL.md) · [Order-book calculation](orderbook/README.md)
