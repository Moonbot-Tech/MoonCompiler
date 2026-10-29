use std::sync::{Condvar, Mutex};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering::SeqCst};
use std::thread;
use std::time::{Duration, Instant};

// Linux x86_64 libc ABI. No crate or alternative async runtime is involved.
#[repr(C)] struct Timespec { sec: i64, nsec: i64 }
#[repr(C)] struct Timeval { sec: i64, usec: i64 }
#[repr(C)] struct Rusage { user: Timeval, kernel: Timeval, rest: [i64; 14] }
#[repr(C)] struct Tm { fields: [i32; 9], offset: i64, zone: *const u8 }
unsafe extern "C" {
    fn clock_gettime(id: i32, stamp: *mut Timespec) -> i32;
    fn localtime_r(seconds: *const i64, result: *mut Tm) -> *mut Tm;
    fn getrusage(who: i32, usage: *mut Rusage) -> i32;
}
fn clock(id: i32) -> Timespec {
    let mut t = Timespec { sec: 0, nsec: 0 };
    assert_eq!(unsafe { clock_gettime(id, &mut t) }, 0);
    t
}
fn ns() -> u64 { let t = clock(1); (t.sec as u64) * 1_000_000_000 + t.nsec as u64 }
fn calendar_ms() -> u64 {
    let t = clock(0);
    let mut local: Tm = unsafe { std::mem::zeroed() };
    assert!(!unsafe { localtime_r(&t.sec, &mut local) }.is_null());
    t.sec as u64 * 1000 + t.nsec as u64 / 1_000_000 + local.fields[7] as u64
}
fn cpu() -> (u64, u64) {
    let mut r: Rusage = unsafe { std::mem::zeroed() };
    assert_eq!(unsafe { getrusage(0, &mut r) }, 0);
    (r.user.sec as u64 * 1_000_000_000 + r.user.usec as u64 * 1000,
     r.kernel.sec as u64 * 1_000_000_000 + r.kernel.usec as u64 * 1000)
}
struct Event { state: Mutex<bool>, cond: Condvar, manual: bool }
impl Event {
    fn new(manual: bool) -> Self { Self { state: Mutex::new(false), cond: Condvar::new(), manual } }
    fn set(&self) {
        *self.state.lock().unwrap() = true;
        if self.manual { self.cond.notify_all(); } else { self.cond.notify_one(); }
    }
    fn wait(&self, milliseconds: Option<u64>) -> bool {
        let lock = self.state.lock().unwrap();
        let mut state = match milliseconds {
            None => self.cond.wait_while(lock, |v| !*v).unwrap(),
            Some(ms) => self.cond.wait_timeout_while(lock, Duration::from_millis(ms), |v| !*v).unwrap().0,
        };
        let result = *state;
        if result && !self.manual { *state = false; }
        result
    }
}
struct Worker { wake: Event, issued: AtomicUsize, sent: AtomicU64, log: Mutex<Vec<String>> }
#[derive(Default)]
struct Row { received: usize, timeouts: u64, minimum: u64, generated: u64, bytes: u64,
             digest: u64, checksum: u64, log_sum: u64, latencies: Vec<u64> }
#[derive(Clone, Default)]
struct Delivered { count: u64, bytes: u64, sum: u64 }
fn text_sum(text: &str) -> u64 { text.bytes().fold(0u64, |sum, byte| sum.wrapping_mul(131).wrapping_add(byte as u64)) }
fn drain(queue: &Mutex<Vec<usize>>, workers: &[Worker], delivered: &mut [Delivered]) {
    let calls = std::mem::take(&mut *queue.lock().unwrap());
    for id in calls {
        for text in workers[id].log.lock().unwrap().drain(..) {
            delivered[id].count += 1;
            delivered[id].bytes += text.len() as u64;
            delivered[id].sum = delivered[id].sum.wrapping_add(text_sum(&text));
        }
    }
}
fn main() {
    assert!(cfg!(all(target_os = "linux", target_arch = "x86_64")), "Linux x86_64 ABI required");
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 6, "orders|wait|selected WORKERS ROUNDS PERIOD_MS SIGNALS_PER_WORKER");
    let mode = args[1].as_str();
    assert!(["orders", "wait", "selected"].contains(&mode));
    let count: usize = args[2].parse().unwrap();
    let rounds: usize = args[3].parse().unwrap();
    let period: u64 = args[4].parse().unwrap();
    let signals: usize = args[5].parse().unwrap();
    assert!((1..=256).contains(&count) && (1..=10000).contains(&rounds) && (2..=1000).contains(&period) && (1..=100).contains(&signals));
    assert!(mode == "selected" || rounds > count * signals + 32);
    let workers: Vec<_> = (0..count).map(|_| Worker { wake: Event::new(false), issued: AtomicUsize::new(0),
        sent: AtomicU64::new(0), log: Mutex::new(Vec::new()) }).collect();
    let gate = Event::new(true);
    let ack = Event::new(false);
    let main_wake = Event::new(false);
    let ready = AtomicUsize::new(0);
    let completed = AtomicUsize::new(0);
    let queue = Mutex::new(Vec::new());
    let mut delivered = vec![Delivered::default(); count];
    let n = if mode == "selected" { signals } else { rounds };
    let (rows, elapsed, usage) = thread::scope(|scope| {
        let mut handles = Vec::new();
        for (id, w) in workers.iter().enumerate() {
            let (gate, ack, main_wake, ready, completed, queue) = (&gate, &ack, &main_wake, &ready, &completed, &queue);
            handles.push(scope.spawn(move || {
                let mut row = Row { minimum: u64::MAX, latencies: Vec::with_capacity(signals), ..Row::default() };
                ready.fetch_add(1, SeqCst);
                assert!(gate.wait(None));
                for step in 1..=n {
                    let began = ns();
                    let timeout = if mode == "selected" || row.timeouts == (rounds - signals) as u64 { None } else { Some(period) };
                    let ok = w.wake.wait(timeout);
                    let ended = ns();
                    if ok {
                        assert_eq!(w.issued.load(SeqCst), row.received + 1, "recipient/sequence");
                        assert!(row.received < signals);
                        row.latencies.push(ended - w.sent.load(SeqCst));
                        row.received += 1;
                        ack.set();
                    } else {
                        assert!(mode != "selected" && ended - began + 1_000_000 >= period * 1_000_000, "early timeout");
                        row.timeouts += 1;
                        row.minimum = row.minimum.min(ended - began);
                    }
                    row.checksum += (id as u64 + 1) * 1000003 + step as u64;
                    if mode == "orders" {
                        row.digest ^= ns() / 1_000_000;
                        row.digest ^= ns() / 1_000_000;
                        row.digest ^= calendar_ms();
                        if step % 8 == 0 {
                            let text = format!("order={} step={}", id, step);
                            row.generated += 1;
                            row.bytes += text.len() as u64;
                            row.log_sum = row.log_sum.wrapping_add(text_sum(&text));
                            w.log.lock().unwrap().push(text);
                            queue.lock().unwrap().push(id);
                            main_wake.set();
                        }
                    }
                }
                assert_eq!(row.received, signals, "recipient lifetime");
                completed.fetch_add(1, SeqCst);
                main_wake.set();
                row
            }));
        }
        let (workers, gate, ack) = (&workers, &gate, &ack);
        let producer = scope.spawn(move || {
            assert!(gate.wait(None));
            for round in 1..=signals { for w in workers {
                thread::sleep(Duration::from_millis(period));
                w.sent.store(ns(), SeqCst);
                w.issued.store(round, SeqCst);
                w.wake.set();
                assert!(ack.wait(Some(5000)), "recipient acknowledgement");
            }}
        });
        let startup = Instant::now();
        while ready.load(SeqCst) < count {
            thread::sleep(Duration::from_millis(1));
            assert!(startup.elapsed() < Duration::from_secs(10));
        }
        thread::sleep(Duration::from_millis(20));
        let before = cpu();
        let start = ns();
        gate.set();
        while completed.load(SeqCst) < count {
            drain(&queue, workers, &mut delivered);
            if completed.load(SeqCst) < count { main_wake.wait(Some(100)); }
            assert!(ns() - start < rounds as u64 * period * 4_000_000 + 10_000_000_000, "workload timeout");
        }
        drain(&queue, workers, &mut delivered);
        let elapsed = ns() - start;
        let after = cpu();
        producer.join().unwrap();
        let rows: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        (rows, elapsed, (after.0 - before.0, after.1 - before.1))
    });
    let mut latencies = Vec::with_capacity(count * signals);
    let (mut timeouts, mut minimum, mut logs, mut bytes, mut digest, mut checksum, mut log_sum) = (0, u64::MAX, 0, 0, 0, 0, 0u64);
    for (id, row) in rows.into_iter().enumerate() {
        assert_eq!(row.received, signals);
        assert_eq!(row.checksum, n as u64 * (id as u64 + 1) * 1000003 + (n * (n + 1) / 2) as u64);
        assert_eq!(row.generated, if mode == "orders" { (rounds / 8) as u64 } else { 0 });
        assert_eq!(row.generated, delivered[id].count);
        assert_eq!(row.bytes, delivered[id].bytes);
        assert_eq!(row.log_sum, delivered[id].sum);
        assert!(workers[id].log.lock().unwrap().is_empty());
        timeouts += row.timeouts; minimum = minimum.min(row.minimum);
        logs += row.generated; bytes += row.bytes; digest ^= row.digest; checksum += row.checksum;
        log_sum = log_sum.wrapping_add(row.log_sum);
        latencies.extend(row.latencies);
    }
    assert_eq!(timeouts, if mode == "selected" { 0 } else { (count * (rounds - signals)) as u64 });
    assert!(queue.lock().unwrap().is_empty());
    latencies.sort_unstable();
    let q = |p: usize| latencies[(latencies.len() - 1) * p / 100];
    println!("PULSE_ORDER mode={} workers={} rounds={} period_ms={} wall_ns={} user_ns={} kernel_ns={} cycles=0 signals={} timeouts={} min_timeout_ns={} timeout_slack_ns=1000000 logs={} digest={} checksum={} log_bytes={} log_checksum={} latency_p50_ns={} latency_p95_ns={} latency_p99_ns={} latency_max_ns={} verified=1",
        mode, count, rounds, period, elapsed, usage.0, usage.1, count * signals, timeouts, if timeouts == 0 { 0 } else { minimum },
        logs, digest, checksum, bytes, log_sum, q(50), q(95), q(99), q(100));
}
