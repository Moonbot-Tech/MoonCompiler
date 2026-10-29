# Event-wait fast-path contract

Run on Linux with the built product toolchain:

```sh
python3 qualification/event-wait/run_gate.py
```

The gate compiles a private copy of the current `cthreads` in O-/O2/O3.
Test-only counters prove that an already signalled finite wait and an empty
zero-timeout poll do not calculate a deadline or enter a kernel wait.
A clock-failure injection checks the real timed-wait error path and verifies
that ready events and polls remain independent of clocks. No instrumentation
is included in the delivered RTL.

The same gate now covers internal RTLEvent ready/zero/infinite paths, injected
condition-wait errors after spurious successful returns, and the lifetime of a
notifier paused after releasing the event mutex. Destruction must wait for that
notifier even after the actual waiter has returned. Finite and infinite condition
errors must return `wrError`, release the mutex and unregister the waiter.

The clock interposer `tick_clock_fault.c` is local to a test process. With
`TZ=UTC0`, `monotonic_tick_semantic` accepts `fixed`/`fallback` for
`MOON_TICK_TEST=fixed`/`fail`, and `calendar-fixed`/`calendar-fallback` for
`MOON_CALENDAR_TEST=fixed`/`fail`. Run with the compiled shared object in
`LD_PRELOAD`; never adjust the host's clock. This checks 64-bit tick conversion,
Stopwatch units and existing raw-clock fallbacks, not only a positive timestamp.

`multiwait_ready_semantic` and `semaphore_wake_work_semantic` run as ordinary
semantic tests on both platforms. On Linux, `-dWAIT_WORK_PROBE` additionally
requires zero ready/poll allocations and one notification for one permit while
16 consumers wait. The old implementation fails those work-removal oracles.

The same semantic program also runs uninstrumented in the Windows/Linux
`RTL-test` matrix. It covers auto/manual reset, initial state, coalesced signals,
zero/finite/infinite waits, multiple blocked waiters and competing polls.
The Linux probe additionally destroys events with four **registered** waiters
and checks `wrAbandoned`, mutex release and waiter accounting. It does not claim
to support new calls racing destruction of an object whose lifetime has ended.

The baseline before the repair passes the signal/lifetime checks but fails the
ready, poll and clock-independence probes. This is a work-removal oracle, not a
timing threshold; CPU speed and scheduler load do not decide PASS.

## Linux x86-64 state-futex candidate validation

The isolated BasicEvent/TEvent candidate uses a private futex word for signal and destruction
predicates, protected by the existing event mutex. Waiting compares against zero
atomically in the kernel; reacquisition uses an ordinary pthread mutex lock.
This avoids the extra empty mutex wake caused by pthread condition-wait
reacquisition. The obsolete condition object and attributes are absent from this
backend. It is **not enabled in the product**: CPU improved, but sparse-event p99
varied in both directions across controlled comparisons, including adverse pairs.
A combined CPU/response improvement has not been demonstrated. Other targets and
the `FPC_USE_LIBC` configuration retain pthread conditions; the internal RTLEvent
backend is also unchanged by this substitution.

With `--source` pointing to that candidate, the gate includes
`state_futex_probe.dpr`; it reports a skip for the current pthread backend.
The probe pauses a registered waiter
between unlocking and entering futex, then publishes a signal, destroys the event,
or sets and resets it. It checks both reset modes, coalescing, waiter lifetime,
EAGAIN/EINTR retry with one unchanged absolute deadline, timeout and permanent
errors. The irreversible destruction bit survives signal consumption. Existing
after-unlock notifier and multi-waiter tests remain active. Test hooks are injected
into a private source copy and do not enter the shipped RTL.

Cooperative thread termination remains the supported path. This change does not
claim pthread-cancel equivalence: direct futex is not a POSIX cancellation point.
The existing Pascal forced-cancellation probe already terminates the baseline
process with runtime error 217. No new forced-cancellation support is claimed.
