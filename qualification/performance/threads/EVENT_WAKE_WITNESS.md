# Native event wake witness

`event_wake_witness.c` isolates OS-thread event delivery from Pascal, Delphi,
calendar conversion, logging and application allocation. It is a latency
experiment, not a complete RTL implementation or an equal-work CPU benchmark.

Build in an x64 Visual Studio developer prompt:

```bat
cl /O2 /TC /std:c11 /MT event_wake_witness.c
event_wake_witness.exe cond 2 91 256 16 16 256
```

Build on Linux:

```sh
gcc -O2 -std=c11 -Wall -Wextra -Werror -pthread event_wake_witness.c -o event_wake_witness
./event_wake_witness cond 2 91 256 31 31 256
./event_wake_witness futex 2 91 256 31 31 256
```

Arguments are backend, CPU, background-thread count, measured samples, sender
period in ms, empty-wait timeout in ms, and integer work per timeout. Choose an
available CPU; use zero background threads to isolate a single waiting recipient.
Windows uses native auto-reset events. Linux offers a pthread condition variable
or a direct futex binary event. All threads share the selected CPU. These event
wrappers support only the single-consumer, joined-lifetime protocol used here.

Each input has a sequence and its own acknowledgement. The producer sleeps
between inputs and never catches up in bursts. Measure from before publishing
and signalling to the first timestamp after the recipient wait. Sixteen warm-up
inputs are excluded. With background threads, the recipient also performs timed
waits and the same integer work. No event, priority, timer slack or system-wide
setting is modified outside the child process.

Use an external 30-second timeout for these commands. Repeat in reverse order;
keep every result, including maxima. Windows requested 16 ms produced roughly
31 ms waits on the measured host. This is observed behaviour, not an API promise.
Wall time and timeout counts disclose differences in actual cadence. Do not use
these variable counts to compare CPU consumption; use `pulse_order_workers` and
the language controls for fixed useful work.

## Measured result, 28 October 2026

Two reverse-order repeats, 256 measured inputs each:

| Machine / implementation | Background workers | p50 us | p99 us |
|---|---:|---:|---:|
| Local Windows, Ryzen 5800X, native event | 0 | 3.0–3.4 | 14.5–17.8 |
| Hel1 Linux, Xeon W-2295, pthread | 0 | 18.16–18.29 | 40.42–41.57 |
| Hel1 Linux, Xeon W-2295, direct futex | 0 | 15.71–15.80 | 35.66–35.78 |
| Local Windows, native event | 91 | 3.5–4.1 | 83.3–113.0 |
| Hel1 Linux, pthread | 91 | 27.49–32.20 | 407.56–420.42 |
| Hel1 Linux, direct futex | 91 | 25.13–27.49 | 275.17–351.39 |

This reproduces the Windows advantage on these machines without either Pascal
compiler. It does **not** prove that every Linux kernel or machine is slower.
Hel1 runs the custom `6.8.12-damon-damon` kernel. CPU-frequency or arithmetic
calibration cannot cancel scheduler, cache, idle-state and hardware differences.
The largest Windows outlier without background workers was 3.74 ms, despite its
better p99; none of these samples is a worst-case guarantee.

Two diagnostic controls explain why a universal conclusion would be wrong:

* Disabling only the Windows recipient's dynamic priority boosts increased p50
  from 3.8–4.1 to 5.6–6.4 us. Its p99 ranges were 87.5–182.5 versus
  189.0–215.2 us. This supports a contribution from scheduling policy; it does
  not explain the entire cross-host gap. A default-boost run had a 15.21 ms max.
* On the same Linux host, a direct-futex continuous ping-pong with no periodic
  sleep produced p50 2.20 and p99 2.53 us over 10,000 inputs. Linux can switch
  this quickly. That continuously active pair is not a substitute for the
  sparse, competing order-worker workload and its CPU cost.

Raw runs, exact source variants and hashes:
[`native-witness`](../../../doc-int/performance/evidence/rtl-wakeups-20261028/native-witness/).
The baseline source in this directory is exactly the source used for the first
six rows; the diagnostic controls retain their own sources in that evidence.

## Additional VPS controls, 29 October 2026

The same C source was run on two Windows and three Linux VPSs. Each test pinned
all its own threads to one logical CPU; existing services were left running.
Two reverse-order repetitions, 256 measured signals each. No system timer,
priority or scheduler setting was changed. With 91 periodic competitors:

| Host | Backend | p50 us | p99 us |
|---|---|---:|---:|
| Win-TEST, Broadwell, Server 2016 | Win32 Event | 3.60–4.00 | 109.80–190.30 |
| Stat-Server, Xeon 8259CL, Server 2016 | Win32 Event | 2.87–3.28 | 175.72–394.45 |
| MoonBot VPS, EPYC Rome, Linux 7.3.0-9-generic | pthread | 5.86–5.87 | 81.83–102.75 |
| Same MoonBot VPS | direct futex | 5.19–5.50 | 102.35–149.85 |
| News VPS, EPYC Rome, Linux 7.0.0-38-generic | pthread | 10.89–12.38 | 171.61–234.39 |
| Same News VPS | direct futex | 9.67–9.77 | 165.22–302.06 |
| Alena VPS, Haswell, Linux 6.17.0-5-generic | pthread | 11.73–11.85 | 178.57–255.41 |
| Same Alena VPS | direct futex | 11.59–13.74 | 210.20–265.85 |

Windows requested 16 ms and Linux 31 ms, as above. Actual work wall was
9.08–9.15 seconds on Win-TEST, 8.50–8.53 on Stat-Server and 8.46–8.51 on Linux;
this is similar cadence, not an identical schedule or fixed timeout count.
All 32 native runs, including zero-background controls, passed their sequence
and acknowledgement checks. The source SHA and per-host build/CPU/kernel
manifests are retained with the raw runs.

The original MoonBot Linux VPS has the better observed p99 than Win-TEST here.
Windows has a better p50, approximately 4 versus 6 us on that pair. This
contradicts any universal Windows/Linux p99 ranking inferred from the earlier
Hel1 measurement. Direct futex also fails to beat pthread uniformly. Maxima
with competitors reached 5.684 ms on Win-TEST and 2.056 ms on Stat-Server;
none of these short samples establishes a worst-case guarantee.
