# Quiet order polling

`pulse_moonshot_idle.dpr` is a separate, source-derived Pulse workload for
mostly sleeping order workers. It does not replace the generic event or
producer/consumer programs.

The fixture comes from a checked application window with 92 MoonShot workers:
four enabled strategies on 23 altcoins, three short/ASK groups and one long/BID
group. Both hosts had the same strategy fields. The 90-second reference log
contained no order replacements, fills, or worker log records. The fixture has
**no network requests, file logging, Queue traffic, or exchange integration**.

Each worker performs a fixed number of quiet checks, then waits on its own
auto-reset event. The checks retain calendar/tick reads, corridor arithmetic,
local order-status checks every fourth iteration, and the diagnostic text
preparation that the application executes even without writing a log record.
That preparation contains six floating-point conversions and two `Format`
calls per iteration, plus conversion of the strategy's fixed character-array
name. These are temporary strings, not emitted messages.

The configured 10-second price interval is **not** a ten-second trade-history
scan here. ASK/BID uses current/previous quotes for these altcoins; their special
quote-history buffer is empty. `history_rows=0` is part of the oracle.

The four strategy coefficients and 23 price magnitudes are frozen in
`pulse_moonshot_fixture.inc`. The market samples are stable and kept inside the
no-replacement corridor. Model 2 preserves the source-derived filter prefix
through `IgnoreFilters`, managed list getters, runtime zero-weight arithmetic,
partial-fill calculations, the full scalar state-difference checker, and the
periodic full state comparison after nine seconds. Four shared strategy objects
and 23 shared markets serve 92 workers. The default is 320 checks per worker,
approximately ten seconds at the selected coarse timeout profile.

`MoonShotFilters.pas`, `MoonShotOrderPath.pas` and `MoonShotOrderState.pas`
retain these paths. Unsupported active trading, history and filter paths fail
explicitly. The complete application object layout and instruction layout are
not reproduced. Exchange status replies are an explicit fixture boundary:
unchanged local state replaces network requests and response parsing. Market
data producers, charts and network maintenance are outside this program.
`api_status_replays` counts each expired request interval; this boundary does
not reproduce pending request waits or TLS setup. The managed message record
contains the two separately constructed strings present in the application.

## Cases

| Case | Purpose |
|---|---|
| `quiet` | Ordinary polling with the unconditional diagnostic strings |
| `no-format` | Same checks, omitting the discarded corridor strings; a cost attribution control |
| `no-filter` | Same checks, bypassing the three strategy-filter calls; a cost attribution control |
| `wait` | Event wait and the Linux application's two uncontended wrapper locks |
| `response` | Quiet checks plus 184 addressed signals, with sequence checks and acknowledgements |
| `cpu` | The quiet check body without sleeping; not application CPU utilization |
| `cpu-no-format` | Body without sleeping or diagnostic formatting |
| `cpu-no-filter` | Body without sleeping or strategy-filter calls |

An optional compile-time control, `MOONSHOT_BORROWED_CONTENT`, changes only
the extracted read-only `HasStrategy` argument from a by-value record to `const`.
Its result is labelled `borrowed_content=1`; the faithful default is `0`.
Do not pool the two binaries or describe this control as a compiler repair.
It measures avoidable managed-record copies in the application's inline helper.

`response` deliberately adds artificial probes; they are not claimed to be
observed exchange events. Each recipient is signalled twice and must acknowledge
each sequence exactly once. The producer uses the same timed-event pacing policy
as the workers. A recipient that has consumed its timeout budget waits for its
remaining probes rather than dropping work. The benchmark measures direct
SetEvent-to-worker continuation; it does not measure a socket send or apply the
separate urgent-send priority policy.

## Run

```powershell
python qualification/performance/tools/pulse_moonshot.py --cpu 4 --cases quiet,response,no-format,wait --repeats 3 --output <results>
```

```sh
python3 qualification/performance/tools/pulse_moonshot.py --toolchain <sdk> --cpu 2 --wait-granularity-us 15625 --cases quiet,response,no-format,wait --repeats 3 --output <results>
```

The Linux application profile rounds WaitFor(16) up to 31.25 ms. Windows uses
its native timeout without requesting a finer timer. An entire process is
pinned to one CPU. Record other running work; on a live application VPS it can
change response tails. Never stop the application to improve a benchmark score.

Compare **CPU time for equal work and actual wall time/wake frequency together**.
CPU/wall can look lower merely because a host schedules fewer checks per second.
The response cases additionally report p50/p95/p99/max; p95 is the primary tail
indicator for this investigation. It is a short sample, not a latency guarantee.

Before measurement it checks whitelist/blacklist rejection, market penalties,
runtime arithmetic coefficients, hot-state changes and periodic slow-state
changes. This prevents simplification from silently erasing the tested work.
The program verifies UTF-16 strings, check/timeout/signal/format counts, zero
logs/requests/history scans, no replacement/cancellation and every worker's
successful completion. The runner rejects mismatched observations and saves
all samples, hashes and machine metadata. Negative oracle tests are in
`tools/test_pulse_moonshot.py`.

Windows GetProcessTimes can return zero for this sparse workload. Do not turn
that zero into a speedup. For an authoritative CPU comparison, collect context
switch events with WPR and calculate process execution time with xperf, excluding
DPC/ISR. `phase_start_filetime` and `wall_ns` identify the measured interval, so
thread creation/destruction are excluded. Check trace loss. Keep the original
counter readings and cycle counts as controls; do not divide cycles by nominal
GHz to normalize different VPSs.
