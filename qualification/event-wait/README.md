# Event-wait fast-path contract

Run on Linux with the built product toolchain:

```sh
python3 qualification/event-wait/run_gate.py
```

The gate compiles a private copy of the current `cthreads` in O-/O2/O3.
Test-only counters prove that an already signalled finite wait and an empty
zero-timeout poll do not calculate a deadline or enter `pthread_cond_timedwait`.
A clock-failure injection checks the real timed-wait error path and verifies
that ready events and polls remain independent of clocks. No instrumentation
is included in the delivered RTL.

The same semantic program also runs uninstrumented in the Windows/Linux
`RTL-test` matrix. It covers auto/manual reset, initial state, coalesced signals,
zero/finite/infinite waits, multiple blocked waiters and competing polls.
The Linux probe additionally destroys events with four **registered** waiters
and checks `wrAbandoned`, mutex release and waiter accounting. It does not claim
to support new calls racing destruction of an object whose lifetime has ended.

The baseline before the repair passes the signal/lifetime checks but fails the
ready, poll and clock-independence probes. This is a work-removal oracle, not a
timing threshold; CPU speed and scheduler load do not decide PASS.
