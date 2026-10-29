# Sparse order-worker controls in C, C++ and Rust

These Linux x86_64 programs reproduce the protocol of `pulse_order_workers.dpr`:
92 worker OS threads, a separate producer and main thread; 256 iterations per
worker; 31 ms timeouts; two individually acknowledged inputs per recipient.
There are exactly 23,368 timeouts and 184 inputs. Each worker switches to an
infinite wait after spending its timeout budget, so slow production cannot
change useful work or signal a destroyed recipient. All threads join before
their events and log buffers are destroyed.

`orders` performs two monotonic millisecond reads and one local-calendar read
per iteration, and queues `order=ID step=N` every eight iterations. Main-thread
delivery must preserve all 2,944 lines, their byte counts and a string checksum.
Every mode validates a deterministic iteration checksum. Latency starts before
the producer publishes the issued sequence and sets the recipient event; it
ends at the recipient's first clock read after waiting, before acknowledgement
or other work. The producer sleeps between individual signals and does not
catch up in bursts. Quantiles use the same `(N-1)*percent/100` index as Pascal.

`wait` removes calendar, tick and log work and is the closest common mechanism
control. `selected` leaves all other recipients sleeping indefinitely.

## Scope of the comparison

- C uses pthread mutex/condition variables with monotonic timed waits.
- C++ uses `std::mutex`/`std::condition_variable`. It shares the C workload,
  pthread thread startup, libc calendar conversion and malloc logger, so this
  pair isolates the event wrapper rather than the entire language runtime.
- Rust uses scoped standard OS threads, `Mutex`/`Condvar`, `Vec<String>` and a
  callback-ID vector. It calls the same libc clocks and `localtime_r` as C/C++.
- Pascal uses `Now`, `TStringList` and `TThread.Queue`. Native calendar and
  allocation/queue algorithms differ. Equal useful-work counts do not make an
  orders CPU difference a language-only or event-only effect. Native checksums
  add a small amount of work absent from the frozen Pascal harness.

These reference events cover binary auto-reset use with one outstanding input
and one waiter. They are not replacement implementations of the full RTL event
API or its concurrent-destruction contract. No priorities, spinning, timer
slack or system timer settings are changed.

## Run

From the repository, with GCC, G++ and rustc on PATH:

```sh
python3 qualification/performance/tools/check_order_language_oracles.py --output /tmp/order-negative
python3 qualification/performance/tools/compare_order_languages.py --cpu 2 --cases orders,wait --repeats 3 --output /tmp/order-languages --executable moon-base=/absolute/frozen/baseline --executable moon-final=/absolute/frozen/candidate
```

Build separately with `--build-only` and later run with `--no-build` against
the same output directory when build CPU affinity must differ from measurement
affinity. The runner rotates executable order, retains every raw run and records
binary/source hashes, build commands, compiler versions, machine and timer slack.
Whole-child `getrusage` CPU includes startup, verification, joins and teardown;
the narrower in-program CPU interval and work wall time are retained separately.
Only sequential test children run during each accounting delta. Compare Windows
whole-process ETW with whole-child CPU, not the narrower interval.

Negative controls independently break recipient sequence, timeout duration, log
delivery and worker lifetime in all three implementations; each must terminate
with an error and no success result. They use a one-worker short workload.
184 latency samples per full run are not a production worst-case bound.

Sources of the wait contracts: [POSIX condition wait](https://pubs.opengroup.org/onlinepubs/9799919799/functions/pthread_cond_clockwait.html),
[C++ condition variable](https://eel.is/c++draft/thread.condition.condvar),
[Rust Condvar](https://doc.rust-lang.org/std/sync/struct.Condvar.html).

## Hel1 result, 28 October 2026

Three rotated runs of each implementation and mode on CPU2, normal 50 us timer
slack; GCC/G++ 13.3.0 `-O2`, rustc 1.97.1 `-O`. All 30 full runs passed.
The twelve negative controls above were rejected. Raw data, build logs, hashes
and native binaries are in
[`order-languages/final-measured`](../../../doc-int/performance/evidence/rtl-wakeups-20261028/order-languages/final-measured/).

Whole-child CPU, work wall and latency quantiles below are medians of the three
runs. CPU brackets retain the complete range; max is the median per-run maximum,
not the largest sample from the entire series.

| orders | CPU ms [range] | Work wall s | p50 us | p95 us | p99 us | max us |
|---|---:|---:|---:|---:|---:|---:|
| C / pthread cond | 176.80 [171.77-177.06] | 7.994 | 28.26 | 229.17 | 327.32 | 479.76 |
| C++ / std condvar | 174.84 [174.38-176.79] | 7.993 | 26.99 | 184.15 | 366.01 | 578.01 |
| Rust / Mutex+Condvar | 141.82 [141.39-169.86] | 7.988 | 25.09 | 185.96 | 320.70 | 453.46 |
| Moon / frozen base | 191.67 [156.29-227.18] | 7.963 | 31.86 | 208.62 | 336.39 | 487.03 |
| Moon / frozen final | 189.20 [178.48-196.77] | 7.993 | 27.88 | 224.08 | 374.62 | 626.99 |

| wait | CPU ms [range] | Work wall s | p50 us | p95 us | p99 us | max us |
|---|---:|---:|---:|---:|---:|---:|
| C / pthread cond | 154.26 [148.84-158.29] | 7.989 | 27.90 | 192.90 | 344.60 | 453.49 |
| C++ / std condvar | 164.57 [150.91-167.26] | 7.992 | 28.32 | 206.30 | 356.40 | 412.51 |
| Rust / Mutex+Condvar | 155.09 [134.64-157.33] | 7.993 | 31.16 | 211.73 | 355.49 | 401.82 |
| Moon / frozen base | 176.57 [134.09-184.61] | 7.993 | 34.30 | 198.60 | 335.31 | 552.07 |
| Moon / frozen final | 169.89 [113.37-171.26] | 7.993 | 27.02 | 221.92 | 344.91 | 400.61 |

The shared wait-only mechanism puts the native controls and Moon in the same
latency range here. Orders adds library-specific calendar/allocation work; its
CPU ranking cannot identify the cost of a language or of the event alone.
Pascal CPU varies substantially across the three runs, so this series does not
replace the earlier repair-specific paired measurements with a precise speedup.
None of these native controls demonstrates both lower CPU and lower median/tail
latency than the retained Delphi/Windows measurement (162.26 ms CPU, 8.22 s work
wall, p50 3.10 us, p99 278.60 us). Different machines and measurement overhead
remain part of that cross-host comparison.

### Causal follow-up

The 141.82 ms Rust orders result above is not a demonstrated 47 ms event-only
advantage over Moon. Two later reverse-order runs measured 169.77 ms for Rust
and 192.36 ms for Moon. Replacing only the Rust event with pthread condition
waits raised its CPU to 179.88 ms. A syscall trace found the concrete difference:
glibc's condition-wait mutex reacquisition causes one empty futex wake after
each otherwise uncontended event wait; Rust's direct futex path avoids it.

The separate [native event witness](EVENT_WAKE_WITNESS.md) reproduces the
Windows/Linux sparse-latency difference without Pascal and includes a hot Linux
counterexample. It is a latency experiment with variable timeout counts, not a
replacement for this fixed-work CPU model. The detailed attribution, scheduler
trace and tested policy tradeoffs are in the internal
[repair report](../../../doc-int/performance/RTL_WAKE_REPAIR_20261028.md).
