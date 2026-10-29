# Thread and clock Pulse programs

- `pulse_threads.dpr`: busy parallel workers, shared data, allocation and handoff.
- `pulse_thread_lifecycle.dpr`: thread creation and joining.
- `pulse_clocks.dpr`: ticks, `Now`, Stopwatch, ready/poll events and queued callbacks; ordinary
  Pulse program `clocks`. On Delphi the first case uses the Windows API, since
  Delphi does not declare this function in SysUtils. The clock remains live;
  the checksum counts valid observations instead of comparing timestamps.
- `pulse_thread_wakeups.dpr`: many mostly idle workers and a main-thread
  callback loop. Use the paced runner below, not throughput calibration.
- `pulse_order_workers.dpr`: fixed work, process CPU and selected-recipient
  latency in the same sparse workload. This is the primary order-worker model.
- `event_wake_witness.c`: standalone Windows/Linux native-event comparison,
  including a selected recipient competing with 91 periodic workers.
  [Commands, results and interpretation](EVENT_WAKE_WITNESS.md).

## Order-worker CPU and response time

```text
python qualification/performance/tools/pulse_orders.py --toolchain <sdk> --cpu 2 --cases orders,wait,selected --repeats 3 --output <results>
```

Defaults: 92 threads, 256 iterations per worker, 31 ms timeout, two individually
acknowledged signals per worker. `orders` performs two tick reads and one `Now`
per iteration, and queues one in-memory log per eight iterations. The oracle
requires exactly 23,368 timeouts, 184 selected signals and 2,944 delivered logs.
Once a worker exhausts its timeout budget, it waits indefinitely for any remaining
selected input; a slow sender cannot change the useful-work count. `wait` removes
clock/log work, while `selected` keeps all other recipients indefinitely asleep.

Latency starts immediately before SetEvent and ends at the recipient's first
timestamp after WaitFor, before acknowledgement and business work. The sender
sleeps between signals and never catches up with a burst. Both CPU and
p50/p95/p99/maximum latency are retained; 184 observations per run do not establish
a production worst case. These are OS threads, not a simulated scheduler.

The 31 ms choice belongs to the native workload: by default the RTL does not round
a requested 16 ms timeout up to 31 ms. Windows may round waits to its system ticks, including
downwards; the oracle reads the system timer increment and records the minimum
observed timeout. Linux retains its deadline semantics. Always show actual wall
time beside CPU per identical work. Do not derive a cross-host scheduler ratio
from clock frequency, an ALU loop or a memory bandwidth calibration.

For the measured Windows Server 2016 VPS, `--period-ms 16` produces approximately
the same cadence as Linux `--period-ms 31`: the default order work takes about
8.2 and 8.0 seconds respectively. This is a measured host setting, not a portable
Windows rule. Select and record the period explicitly, then verify actual wall
time and timeout counts. Requesting 31 ms on that Windows host took 9.0–9.4 seconds
and must not be presented as the same wake rate.

Windows sparse GetProcessTimes samples may alias to zero. Use a scheduler ETW
trace for a cross-host CPU conclusion, and verify trace completeness/lost events.
An ETW whole-process total includes thread creation and teardown; compare it
with Linux whole-child getrusage, not the narrower in-program interval.
The Linux runner retains both intervals, including `whole_cpu_ns` for this comparison.
The runner's `--executable NAME=PATH` accepts frozen baseline/candidate binaries;
the manifest records all hashes. Negative controls for dropped logs, wrong
recipients and immediate false timeouts must fail before accepting new variants.

This model intentionally omits networking and trading logic. It measures the
thread/wait/time/log-delivery mechanism, not an established production call mix.
The busy `pulse_threads` and continuous handoff tests answer different questions.

### Optional Linux wait granularity

Linux applications can call `Unix.SetWaitGranularityUS(15625)` once at startup,
before starting worker threads. This rounds finite **relative** wait durations
up to a multiple of 15,625 microseconds: 16 ms becomes 31.25 ms, 31 ms becomes
31.25 ms, and 80 ms becomes 93.75 ms. Zero (the default) keeps native timing.
The additional empty-wait delay is intentional and must fit the application.
This is an RTL option, not an exact emulation of every Windows timer setting.

The common `SysUtils.Sleep` / `TThread.Sleep`, direct `TEvent.WaitFor`, and internal
`RTLEvent` paths use it. A signal still interrupts the wait; ready events, zero
polls, infinite waits and clock readings remain unchanged. There is no shared
absolute timer grid, priority change, spinning, or OS timer-slack adjustment.
Sleep retries after EINTR use the remaining duration without rounding it again.
Do not change the setting concurrently with active workers.

Higher-level wrappers retain their own timeout budgets: an unrelated notification
can make MultiWait or a lightweight primitive recheck its original deadline.
Thread joins, native mutex/semaphore calls, network deadlines and foreign-library
waits are not globally rewritten. This setting is intended for periodic
Sleep/event loops, not for extending application deadlines.

```text
python qualification/performance/tools/pulse_orders.py --toolchain <updated-linux-sdk> --cpu 2 --period-ms 16 --wait-granularity-us 15625 --cases orders,selected --repeats 3 --output <results>
```

The runner records the requested quantum and rejects binaries that merely report
it while still returning short timeouts. `wait_granularity_semantic.dpr` covers
rounding boundaries, ready/poll/reset modes, signal interruption and zero Sleep.
The C/C++/Rust versions and comparable measurements are described in
[ORDER_LANGUAGE_CONTROLS.md](ORDER_LANGUAGE_CONTROLS.md).

## Mostly waiting workers

For the separately observed quiet MoonShot workload, use
[Quiet order polling](MOONSHOT_IDLE.md). It retains unconditional diagnostic
string preparation but emits no log records and makes no exchange requests.
Its `response` control measures selected-worker wake latency under the polling
load. The older `queue8` and `queue1` cases below are deliberate mechanism
stress tests, not the observed application's logging frequency.

```text
python qualification/performance/tools/pulse_wakeups.py --toolchain <sdk> --cpu 2 --cases idle,paced-event,paced-clock,paced-queue --seconds 15 --repeats 3 --output <results>
```

Windows builds Delphi and Moon; Linux builds Moon. `--systems moon` selects
one compiler. An entire process, including its workers, is pinned to the one
specified logical CPU. Only run on an otherwise free test machine. Programs
perform no network requests, file logging or application activity.

The `paced-*` cases deliver an identical sequence of external rounds to all
92 workers, at a target interval of 16 ms. The producer waits for every worker
to consume the preceding round before publishing the next one. Each worker
checks its own issued sequence, and the producer reports its maximum scheduling delay.
This prevents lost/coalesced signals from masquerading as less expensive work.
Compare actual wall time as well as counts: equal work that takes longer is
not an equal-rate CPU comparison. The producer and acknowledgement costs are
included on both platforms; this is a controlled workload, not 92 independent
application timers.

`short_gaps` counts catch-up rounds separated by less than half the nominal
period; `min_gap_ns` reports the shortest interval. Equal total work and wall
time do not prove identical spacing. Catch-up rounds can consume an already
set event instead of waking a blocked thread. Keep these results for useful-work
CPU accounting, but do not infer blocked-event latency from them. A finer timer
does not guarantee that the operating system schedules the producer on time.

`paced-event` only wakes workers; `paced-clock` also reads ticks twice and
calls `Now` once per round; `paced-queue` adds one log entry per eight rounds.
For a 60-second confirmation use `--cases paced-queue --seconds 60`.

The diagnostic matrix also includes 1 and 92 workers, 16/80 ms timeouts, Sleep, idle
threads, auto-reset event signals, repeated clock reads, Queue and Synchronize.
`queue8` delivers one log entry per eight rounds; `queue1` deliberately stresses
delivery on every round. Log generation, delivery counts and lengths must agree.
The signal case also has timeouts: SetEvent coalescing is allowed and actual
signalled/timed-out counts are reported; it is not an equal-number-of-signals test.

Each worker executes a fixed number of rounds. Report both CPU time per round
and wall time / actual wake frequency. Equal requested timeouts do **not** imply
equal wake rates on different operating systems. `--windows-timer-ms 1` is an
explicit diagnostic control, recorded in the manifest; the default does not
request a different timer resolution. `clock-libc16` is a Linux diagnostic
control for the standard libc clock path (on Windows it uses QPC).

Process user/kernel times come from GetProcessTimes/getrusage. Windows
observations can round to zero or vary substantially for periodic short bursts,
even when the process cycle count is stable. Retain the range, extend the
observation when necessary, and do not call a low sample free execution.
Windows also records QueryProcessCycleTime; compare it on
the same machine and do not interpret it as a portable hardware cycle counter.
No ratio is valid with a zero or unresolved denominator. The runner records all
samples; it does not discard awkward results or normalize scheduler cost using
an unrelated arithmetic benchmark.

Thread startup and resource creation occur before the measured interval;
worker loop completion and final callback draining are included; final joins
and destruction follow the measured interval. The main loop is
`WakeMainThread -> TEvent.SetEvent -> CheckSynchronize(0)`, matching a headless
application structure. This is a mechanism model, not a claim that an application's
business work or actual logging frequency has been reproduced.

`manifest.json`, `samples.json` and `summary.json` retain source/binary/compiler
identity, affinity, requested timer resolution, wall/user/kernel times, wake
counts and delivery counts. The normal throughput runner does not execute paced
families implicitly: waiting wall time must not become a throughput verdict.

## Native Linux control

`pulse_thread_wakeups_native.c` implements the `paced-event` protocol using
pthread mutexes and condition variables. It preserves the 92 per-worker binary
events, numbered rounds, acknowledgement, pacing and measurement boundaries.
It deliberately has no logging or calendar work. Ordinary and recursive mutex
variants separate the choice of mutex from the rest of the RTL wrapper.

```sh
gcc -O2 -std=c11 -Wall -Wextra -Werror -pthread qualification/performance/threads/pulse_thread_wakeups_native.c -o /tmp/native_wakeups
python3 qualification/performance/tools/compare_native_wakeups.py --native /tmp/native_wakeups --moon <published-sdk-built-pulse_thread_wakeups> --cpu 2 --seconds 15 --repeats 3 --output <results>
```

The runner rotates the three implementations, runs them sequentially on the
same logical CPU and retains every sample plus source/binary hashes. This is
a reference workload, not a replacement for TEvent: it does not implement the
RTL concurrent-destruction contract. Its main thread has no empty
CheckSynchronize loop, and some atomic reads differ from the Pascal harness.
Small differences therefore cannot all be assigned to TEvent. Compare CPU and
wall time; the result is not a measurement of signal-to-execution latency or a
proof that pthread is the fastest possible Linux implementation.
