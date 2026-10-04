# Thread-pool delivery gate

`python qualification/thread-pool/run_gate.py --output <scratch-directory>`
builds an O3 private copy of `System.Threading`, adds semaphore barriers, and
disables the pool monitor in that copy. Product units contain no test hooks.
Use the affinity required by the current qualification package for this command
and its children. Only one build should run at a time.

Each case uses `Min=0, Max=1` and repeats 1000 times:

| Point | Forced ordering | Required result |
| --- | --- | --- |
| 1 | Worker found no work; enqueue before it waits | The retained permit wakes it |
| 2 | Two producers incremented requests while one worker is idle | Pending demand must not suppress wakeup |
| 3 | Worker left idle and its final queue check was empty; enqueue before its slot is released | Releasing the slot starts a replacement |
| 4 | Enqueue before the worker's queue check | The check finds the requests |

For point 3 only, the copy shortens the wait and advances the idle timeout
counter to reach the real exit branch without waiting minutes. Each request
must complete within 5 seconds after the barrier is released and run exactly once.
The deadline tolerates a busy qualification host; the logged completion interval
is diagnostic, not a benchmark.

`--source <system.threading.pp>` builds the same probe against an earlier
implementation. The pre-fix implementation stalls at points 1, 2 and 3.
`--rounds` selects the repetition count. Changed instrumentation anchors fail
explicitly rather than silently testing another interleaving. Logs and the
instrumented sources remain in the output directory for review.

Ordinary, uninstrumented RTL tests cover delivery between private pools,
local work behind a busy worker, cancellation, waits, lifecycle and Windows
handle counts. This gate does not promise progress while every permitted
worker remains blocked inside a user callback, or after pool shutdown begins:
threads added past the maximum for blocked workers come from the monitor,
which the copy disables (`thread_pool_blocked_growth_semantic` covers them).

`python qualification/thread-pool/monitor_exit_gate.py --output <scratch-directory>`
builds a private copy with a two-round monitor idle limit and a controlled CPU
sample. It checks that the monitor stays alive first with only a busy worker,
then with work queued behind that worker while the CPU is busy; after the CPU
becomes free, the queued task must start. It also checks that an idle monitor
exits and that a pool with a live monitor and extra worker can be destroyed.
The same test runs in debug, O2 and O3. `--source <system.threading.pp>` runs
the negative control against an earlier unit without changing the product.
