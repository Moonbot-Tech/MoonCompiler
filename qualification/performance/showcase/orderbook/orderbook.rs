use serde::{Deserialize, Deserializer};
use std::{env, fs, time::Instant};

// Binance encodes decimals as JSON strings. Decode straight into numeric levels,
// without allocating a String or constructing serde_json::Value for each field.
#[derive(Deserialize)]
struct Level(
    #[serde(deserialize_with = "decimal")] f64,
    #[serde(deserialize_with = "decimal")] f64,
);

fn decimal<'de, D: Deserializer<'de>>(deserializer: D) -> Result<f64, D::Error> {
    struct DecimalVisitor;
    impl<'de> serde::de::Visitor<'de> for DecimalVisitor {
        type Value = f64;
        fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
            f.write_str("a finite decimal string")
        }
        fn visit_str<E: serde::de::Error>(self, value: &str) -> Result<f64, E> {
            let number = value.parse::<f64>().map_err(E::custom)?;
            if !number.is_finite() {
                return Err(E::custom("non-finite decimal"));
            }
            Ok(number)
        }
    }
    deserializer.deserialize_str(DecimalVisitor)
}

#[derive(Deserialize)]
struct Book {
    #[serde(rename = "lastUpdateId")]
    last_update_id: i64,
    bids: Vec<Level>,
    asks: Vec<Level>,
}

struct Input {
    json: Vec<u8>,
    budgets: [f64; 3],
}

#[derive(Default)]
struct Fill {
    quantity: f64,
    spent: f64,
    average_price: f64,
    last_price: f64,
    slippage: f64,
    unspent: f64,
}

fn parse_book(json: &[u8]) -> Book {
    let book: Book = serde_json::from_slice(json).expect("invalid book JSON");
    for level in book.bids.iter().chain(&book.asks) {
        assert!(level.0 > 0.0 && level.1 >= 0.0, "invalid price or quantity");
    }
    book
}

fn buy(asks: &[Level], budget: f64) -> Fill {
    let mut fill = Fill::default();
    let mut remaining = budget;
    for level in asks {
        if remaining <= 0.0 {
            break;
        }
        if level.1 == 0.0 {
            continue;
        }
        let full_cost = level.0 * level.1;
        let (cost, taken) = if full_cost <= remaining {
            (full_cost, level.1)
        } else {
            (remaining, remaining / level.0)
        };
        fill.quantity += taken;
        fill.spent += cost;
        fill.last_price = level.0;
        remaining -= cost;
    }
    fill.unspent = remaining;
    if fill.quantity > 0.0 {
        fill.average_price = fill.spent / fill.quantity;
        fill.slippage = fill.average_price / asks[0].0 - 1.0;
    }
    fill
}

fn cpu_ns() -> i64 {
    let mut time = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    assert_eq!(unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut time) }, 0);
    time.tv_sec * 1_000_000_000 + time.tv_nsec
}

fn peak_rss() -> u64 {
    let status = fs::read_to_string("/proc/self/status").unwrap();
    let line = status.lines().find(|line| line.starts_with("VmHWM:")).unwrap();
    line.split_whitespace().nth(1).unwrap().parse::<u64>().unwrap() * 1024
}

fn dump(path: &str, inputs: &[Input]) {
    use std::io::Write;
    let mut output = std::io::BufWriter::new(fs::File::create(path).unwrap());
    for (index, input) in inputs.iter().enumerate() {
        let book = parse_book(&input.json);
        writeln!(output, "book\t{index}\t{}", book.last_update_id).unwrap();
        for level in &book.bids {
            writeln!(output, "bid\t{:.17e}\t{:.17e}", level.0, level.1).unwrap();
        }
        for level in &book.asks {
            writeln!(output, "ask\t{:.17e}\t{:.17e}", level.0, level.1).unwrap();
        }
        for budget in input.budgets {
            let fill = buy(&book.asks, budget);
            writeln!(output, "fill\t{:.17e}\t{:.17e}\t{:.17e}\t{:.17e}\t{:.17e}\t{:.17e}",
                fill.quantity, fill.spent, fill.average_price, fill.last_price, fill.slippage, fill.unspent).unwrap();
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    assert!(args.len() == 3 || args.len() == 4, "usage: orderbook_rust DATA PASSES [DUMP]");
    let passes: usize = args[2].parse().unwrap();
    assert!(passes > 0);
    let manifest = fs::read_to_string(format!("{}/manifest.tsv", args[1])).unwrap();
    let inputs: Vec<Input> = manifest.lines().map(|line| {
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 4);
        Input {
            json: fs::read(format!("{}/{}", args[1], fields[0])).unwrap(),
            budgets: std::array::from_fn(|index| fields[index + 1].parse().unwrap()),
        }
    }).collect();
    let mut checksum = 0.0;
    let mut level_sum = 0.0;
    let mut levels = 0usize;
    let mut id_sum = 0i64;
    let cpu_start = cpu_ns();
    let wall_start = Instant::now();
    for _ in 0..passes {
        for input in &inputs {
            let book = parse_book(&input.json);
            id_sum += book.last_update_id;
            levels += book.bids.len() + book.asks.len();
            for level in book.bids.iter().chain(&book.asks) {
                level_sum = level_sum + level.0 + level.1;
            }
            for budget in input.budgets {
                let fill = buy(&book.asks, budget);
                checksum = checksum + fill.quantity + fill.spent + fill.average_price
                    + fill.last_price + fill.slippage + fill.unspent;
            }
        }
    }
    let wall = wall_start.elapsed().as_nanos();
    let cpu = cpu_ns() - cpu_start;
    println!("{}", serde_json::json!({
        "language": "Rust", "cpu_ns": cpu, "wall_ns": wall,
        "snapshots": inputs.len() * passes, "levels": levels, "id_sum": id_sum,
        "level_sum": level_sum, "checksum": checksum, "peak_rss": peak_rss(),
    }));
    if args.len() == 4 {
        dump(&args[3], &inputs);
    }
}
