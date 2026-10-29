use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashMap,
    fs,
    io::{BufRead, BufReader, Write},
    path::Path,
    time::Instant,
};

fn cpu_ns() -> u64 {
    // CLOCK_PROCESS_CPUTIME_ID includes the CPU time of all process threads.
    unsafe {
        let mut time = std::mem::zeroed();
        assert_eq!(
            libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut time),
            0
        );
        time.tv_sec as u64 * 1_000_000_000 + time.tv_nsec as u64
    }
}

struct Stopwatch {
    cpu_start: u64,
    wall_start: Instant,
}

impl Stopwatch {
    fn start() -> Self {
        Self {
            cpu_start: cpu_ns(),
            wall_start: Instant::now(),
        }
    }

    fn elapsed(&self) -> (u128, u64) {
        let wall = self.wall_start.elapsed().as_nanos();
        let cpu = cpu_ns() - self.cpu_start;
        (wall, cpu)
    }
}

fn rss(field: &str) -> u64 {
    fs::read_to_string("/proc/self/status")
        .expect("read process memory statistics")
        .lines()
        .find(|line| line.starts_with(field))
        .expect("memory statistic is present")
        .split_whitespace()
        .nth(1)
        .expect("memory statistic has a value")
        .parse::<u64>()
        .expect("memory statistic is numeric")
        * 1024
}

#[derive(Deserialize)]
struct Packet<'a> {
    #[serde(borrow)]
    data: Trade<'a>,
}

#[derive(Deserialize)]
struct Trade<'a> {
    #[serde(borrow, rename = "s")]
    symbol: &'a str,
    #[serde(borrow, rename = "p")]
    price: &'a str,
    #[serde(borrow, rename = "q")]
    quantity: &'a str,
}

#[derive(Default)]
struct Market {
    price: f64,
    volume: f64,
    count: u64,
}

#[derive(Serialize)]
struct Reply<'a> {
    symbol: &'a str,
    status: &'a str,
    price: f64,
    volume: f64,
    note: &'a str,
}

fn load_symbols(directory: &Path) -> Vec<String> {
    fs::read_to_string(directory.join("symbols.txt"))
        .expect("read symbols")
        .lines()
        .map(str::to_owned)
        .collect()
}

fn run_exchange(directory: &Path, output: Option<&Path>, baseline_rss: u64) {
    let input = fs::read(directory.join("exchangeInfo.json")).expect("read exchangeInfo");
    let input_bytes = input.len();
    let input_rss = rss("VmRSS:");

    let timer = Stopwatch::start();
    let document: Value = serde_json::from_slice(&input).expect("parse exchangeInfo");
    let symbols = document["symbols"].as_array().expect("symbols array");
    let mut names = 0usize;
    let mut filters = 0usize;
    for symbol in symbols {
        names += symbol["symbol"].as_str().expect("symbol name").len();
        filters += symbol["filters"].as_array().expect("symbol filters").len();
    }
    let (wall_ns, cpu_ns) = timer.elapsed();
    let count = symbols.len();

    // Value owns its strings, so the source buffer is no longer required.
    drop(input);
    let retained_rss = rss("VmRSS:");
    let peak_rss = rss("VmHWM:");
    println!(
        "{}",
        serde_json::json!({
            "case": "exchange", "wall_ns": wall_ns, "cpu_ns": cpu_ns,
            "count": count, "names": names, "filters": filters,
            "input_bytes": input_bytes, "baseline_rss": baseline_rss,
            "input_rss": input_rss, "retained_rss": retained_rss, "peak_rss": peak_rss
        })
    );
    if let Some(path) = output {
        let file = fs::File::create(path).expect("create document output");
        serde_json::to_writer(file, &document).expect("write complete document");
    }
    std::hint::black_box(&document);
}

fn run_trades(directory: &Path, symbols: &[String], passes: usize, output: Option<&Path>) {
    let file = fs::File::open(directory.join("trades.jsonl")).expect("open trades");
    let input: Vec<String> = BufReader::new(file)
        .lines()
        .map(|line| line.expect("read trade line"))
        .collect();

    let timer = Stopwatch::start();
    // Each market is an independently owned object, matching the Pascal workload.
    let mut markets: HashMap<String, Box<Market>> = symbols
        .iter()
        .map(|symbol| (symbol.clone(), Box::new(Market::default())))
        .collect();
    for _ in 0..passes {
        for line in &input {
            let packet: Packet = serde_json::from_str(line).expect("parse trade");
            let trade = packet.data;
            let price: f64 = trade.price.parse().expect("numeric trade price");
            let quantity: f64 = trade.quantity.parse().expect("numeric trade quantity");
            assert!(price > 0.0 && quantity > 0.0);
            let market = markets.get_mut(trade.symbol).expect("known market");
            market.price = price;
            market.volume += price * quantity;
            market.count += 1;
        }
    }
    let (wall_ns, cpu_ns) = timer.elapsed();

    if let Some(path) = output {
        let mut file = fs::File::create(path).expect("create market output");
        for symbol in symbols {
            let market = &markets[symbol];
            writeln!(
                file,
                "{}\t{}\t{:.17}\t{:.17}",
                symbol, market.count, market.price, market.volume
            )
            .expect("write market state");
        }
    }
    println!(
        "{}",
        serde_json::json!({
            "case": "trades", "wall_ns": wall_ns, "cpu_ns": cpu_ns,
            "operations": input.len() * passes, "count": markets.len(),
            "peak_rss": rss("VmHWM:")
        })
    );
}

fn run_serialization(symbols: &[String], passes: usize, output: Option<&Path>) {
    let rows: Vec<_> = symbols
        .iter()
        .enumerate()
        .map(|(index, symbol)| Reply {
            symbol,
            status: "TRADING",
            price: (index + 1) as f64 / 64.0,
            volume: (index + 1) as f64 / 128.0,
            note: "market \"ready\"\n",
        })
        .collect();

    let timer = Stopwatch::start();
    let mut total_bytes = 0;
    let mut last_document = Vec::new();
    for _ in 0..passes {
        last_document = serde_json::to_vec(&rows).expect("serialize market rows");
        total_bytes += last_document.len();
        std::hint::black_box(&last_document);
    }
    let (wall_ns, cpu_ns) = timer.elapsed();

    if let Some(path) = output {
        fs::write(path, &last_document).expect("write serialized document");
    }
    println!(
        "{}",
        serde_json::json!({
            "case": "serialize", "wall_ns": wall_ns, "cpu_ns": cpu_ns,
            "operations": symbols.len() * passes, "bytes": total_bytes,
            "peak_rss": rss("VmHWM:")
        })
    );
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    assert!(
        (3..=5).contains(&arguments.len()),
        "usage: showcase_rust CASE DATA_DIR [PASSES [OUTPUT]]"
    );
    let mode = arguments[1].as_str();
    let directory = Path::new(&arguments[2]);
    let passes: usize = arguments
        .get(3)
        .map(|s| s.parse().expect("positive pass count"))
        .unwrap_or(1);
    assert!(passes > 0, "pass count must be positive");
    let output = arguments.get(4).map(Path::new);
    let baseline_rss = rss("VmRSS:");
    match mode {
        "exchange" => run_exchange(directory, output, baseline_rss),
        "trades" => run_trades(directory, &load_symbols(directory), passes, output),
        "serialize" => run_serialization(&load_symbols(directory), passes, output),
        _ => panic!("unknown case: {mode}"),
    }
}
