# Thread coordination

Use `TThreadedQueue<T>` from `System.Generics.Collections` to transfer work
between existing threads. Use `TCountdownEvent` from `System.SyncObjs` to wait
until a known or growing batch finishes. Neither creates worker threads.

## Bounded queues

`Create(Depth, PushTimeout, PopTimeout)` allocates the ring buffer. Defaults are
ten elements and infinite waits; a zero timeout makes an operation nonblocking.
A full queue waits for space, an empty queue waits for data. `Grow(Delta)` adds
capacity without changing FIFO order and wakes producers that can now proceed.
A negative delta reduces capacity only if all pending elements still fit;
otherwise the call raises without changing the queue.
`QueueSize` is the current element count. The two total counters count successful
insertions/removals, not timeouts or shutdown notifications.

The public overloads accept both `NativeInt` and `Integer` queue-size outputs on
64-bit targets. String, interface and other managed values remain owned by the
queue while stored; removing them clears their slot. Plain object references are
not owned or automatically freed.

`DoShutDown` is permanent and wakes both producers and consumers. Following
Delphi 12.2 behavior, existing elements can be drained, new elements are rejected,
and a closed empty pop returns the default value. Shutdown returns `wrSignaled`,
so that result alone does not prove that a push inserted an element or a pop
returned work. Arrange application shutdown explicitly: stop submitting work,
signal the queue, join its users, then free it. Do not destroy a queue while
another thread is in a queue method, and do not use shutdown as a per-item
acknowledgment protocol. Timeout also resets a pop's output to the default value.

Notifications are directed to waiting readers or writers as data or space becomes
available. A single item does not deliberately broadcast to every consumer.
Ready work is passed to the next waiter even when a managed assignment raises;
rechecking the predicate does not restart the original timeout budget.

## Linux thread priority

`TThread.Priority` changes the target Linux thread's native nice value, including
before `Start`. It also works through `TThread.CurrentThread` for the main thread
and native threads attached to the RTL. The mapping is:

| Priority | nice |
|---|---:|
| `tpIdle` | 19 |
| `tpLowest` | 10 |
| `tpLower` | 5 |
| `tpNormal` | 0 |
| `tpHigher` | -5 |
| `tpHighest` | -10 |
| `tpTimeCritical` | -20 |

This adjusts ordinary scheduling under contention; it does not set a CPU usage
limit or enable a real-time scheduling policy. Increasing scheduling priority,
including returning from `tpLowest` to `tpNormal`, may require `CAP_SYS_NICE` or
an appropriate `RLIMIT_NICE`. A rejected assignment raises `EThread`; the getter
reports the actual native state, using the nearest enum level after an external
renice. Access to a terminated or joined ordinary `TThread` also raises `EThread`.
For an externally created native thread, the `CurrentThread` wrapper borrows its
native identity and is valid only while that thread is alive. Do not retain and
use that wrapper after native exit/join: the OS may reuse its handle.

Thread handles are resolved to live kernel thread IDs without depending on a
private libc layout. Single-threaded fork children establish their own identity;
as with the rest of the RTL, arbitrary Pascal work after a multithreaded fork is
not supported before exec. Windows priority behavior is unchanged.

## Completion counters

Construct `TCountdownEvent` with the number of outstanding operations (default
one). Each completed operation calls `Signal`; the transition to zero releases
every waiter. `WaitFor(Timeout)` returns a `TWaitResult` and an already completed
counter returns immediately. Waiting through `TSynchroObject` and the
`TTimeSpan` overload dispatches to the same implementation.

`AddCount` and `TryAddCount` can increase an active batch. Once zero has been
reached, only `Reset` may reopen it: `TryAddCount` returns False, while `AddCount`
raises. Counts must be positive for adding/signaling, may be zero for creation
or reset, and must not overflow. `Reset(NewCount)` also replaces `InitialCount`;
parameterless `Reset` reuses it. Coordinate reset with the batch's users so that
work from an old batch cannot signal a new one.

The optional spin count bounds an initial wait before using the event. The
default implementation goes directly to the event, avoiding background polling.
Negative spin counts select this default; explicit values range from 0 to 4095.
Free the object only after all signalers and waiters have finished.

## Validation

`qualification/suite/tests/rtl-api/rtl_api_threading_contracts.dpr` runs against
Delphi 12.2 and MoonCompiler. It checks wrapped growth, every queue overload,
timeouts, zero capacity, shutdown wakeups, interface lifetime, multiple producers
and consumers, and concurrent countdown signaling/waiting. The ordinary RTL API
gate runs it in Debug and Release on Windows and Linux. Additional queue tests
exercise single-notification behavior, assignment exceptions and a deterministic
timeout/notification race. Linux priority tests query the OS independently and
cover pre-start changes, native threads, fork, cancellation, lifetime and denied
priority increases in Debug, O2 and O3.

## Lightweight events and semaphores

`TLightweightEvent.Create(InitialState, SpinCount)` creates a manual-reset event.
The default initial state is false. `SetEvent` releases current waiters and keeps
later waits ready until `ResetEvent`. A waiter already released by a signal stays
released if another thread resets the event before that waiter resumes.
`Acquire` waits indefinitely; use `SetEvent` to signal (`Release` is the inherited
base-class method). `SpinCount` is read-only and accepts 0..4095 at construction.

`TLightweightSemaphore.Create(InitialCount, MaximumCount)` maintains a bounded
permit count; the optional maximum is `MaxInt`. A successful `WaitFor` consumes
one permit. `Release(Count)` adds positive permits atomically and returns the
previous count; parameterless `Release` adds one. Exceeding the maximum raises
without changing the count. Use the concrete semaphore type for this operation.

Both types return `TWaitResult`, accept zero/infinite millisecond waits, and expose
`BlockedCount` as a cumulative diagnostic count. Available resources use an atomic
fast path; contention uses a bounded spin followed by a blocking monitor wait.
Free them only after all users have finished. `TTimeSpan` overloads truncate to
whole milliseconds and accept 0..MaxInt; the Cardinal overload retains `INFINITE`.

`TLightweightMREW` records initialize automatically in locals, fields and arrays.
Readers share access; writers are exclusive. Do not copy or reinitialize a lock
while it is in use. The native SRW/pthread primitive determines scheduling;
writer fairness is not promised. Timed `TryBeginRead/TryBeginWrite` are Linux-only.

## Lightweight validation

`RTL-test/semantic/lightweight_boundaries_semantic.dpr` checks record initialization,
tracked recursion, timeout validation, event Set/Reset wakeups and permit accounting.
The same contracts run in Debug, O2 and O3 on both platforms.
