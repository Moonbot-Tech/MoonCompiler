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

## Bounded thread completion

MoonCompiler 2.4.6 adds `TThread.WaitFor(TimeoutMs: Cardinal): Boolean` on
Windows and Linux. It returns `True` after the OS thread has actually exited,
including native thread-local cleanup; `False` means the timeout expired.
Zero polls without waiting, and `High(Cardinal)` waits indefinitely. Native
wait errors raise `EThread`; thread exit codes remain available from the
parameterless `WaitFor` and are never interpreted as timeout/error codes.

```pascal
Worker.Terminate; // Cooperative request; it does not force the thread to stop.
If Worker.WaitFor(1000) then
  FreeAndNil(Worker);
// On timeout, retain Worker and its dependencies for a later join.
```

The timed overload does not execute `Synchronize`, `OnTerminate` callbacks or
window messages. A callback could itself block beyond the requested deadline.
Use the ordinary parameterless `WaitFor` when main-thread callback dispatch is
needed; its existing behavior and integer result are preserved. If a worker
is waiting in `Synchronize`, the timed overload can time out until the main
thread services that callback elsewhere.

The object must have one owner, `FreeOnTerminate=False`, and must not represent
the calling thread or a borrowed external thread. Do not call `WaitFor` and
`Free` concurrently or join a `TThread.Handle` through another API. Successful
Linux joins are recorded in the object: subsequent waits and destruction do
not join a recycled pthread ID. Timeout neither terminates the worker nor makes
it safe to free; destruction of a running thread still waits for completion.

Linux uses a monotonic native join deadline. Older libc versions without that
entry use a bounded try-join poll at intervals of at most one millisecond.
Scheduler delays can postpone return; this is not a real-time scheduling API.
No per-thread event, watcher thread or allocation is added by this API.

For separately owned `BeginThread` handles, `System.WaitForThreadTerminateEx`
returns `twrSignaled`, `twrTimeout` or `twrError` and separate `ExitCode` and
`NativeError` outputs. It uses the same zero/infinite conventions as the timed
overload. A successful Unix join consumes the native handle: do not join it
again. Custom thread managers may provide the appended callback; if absent,
the extended API returns `twrError` with error zero, while ordinary `WaitFor`
retains their legacy implementation. Rebuild external PPUs with this release.

The legacy low-level `WaitForThreadTerminate` keeps its historical conventions:
zero is infinite; Linux nonpositive values are infinite, positive values now
honor the timeout. On Linux it returns the exit code on success and clears
errno; timeout/error returns `High(DWord)` and sets errno. Prefer the extended
API because `High(DWord)` is also a valid successful exit code. Windows keeps
the legacy native wait-status result.

## Windows current-thread handles

The wrapper returned by `TThread.CurrentThread` for a native Windows thread owns
a duplicated OS handle. A priority getter or setter through that wrapper targets
the represented thread even when called by another thread. Releasing the wrapper
closes this duplicate without terminating the native thread. The wrapper itself
belongs to the RTL; callers should not free the borrowed object.

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
an appropriate `RLIMIT_NICE`. Assignment is best effort: an OS refusal does not
raise, so cleanup and subsequent application code can still run. The getter
reports the actual native state, using the nearest enum level after an external
renice; it does not report a refused request as successful. Assignment to a
terminated or joined ordinary `TThread` is ignored; reading its priority raises
`EThread` because no live native state remains. For explicit success/failure and
errno diagnostics, use the low-level `ThreadSetPriority` Boolean result.
For an externally created native thread, the `CurrentThread` wrapper borrows its
native identity and is valid only while that thread is alive. Do not retain and
use that wrapper after native exit/join: the OS may reuse its handle.

Thread handles are resolved to live kernel thread IDs without depending on a
private libc layout. Single-threaded fork children establish their own identity;
as with the rest of the RTL, arbitrary Pascal work after a multithreaded fork is
not supported before exec. Windows priority behavior is unchanged.

### Explicit Linux scheduling attributes

`CThreads.TryGetCThreadScheduling(ThreadID, out Attributes)` and
`TrySetCThreadScheduling(ThreadID, const Attributes)` expose `Linux.TSchedAttr`
for a live Pascal thread. Both return `False` with `BaseUnix.fpGetErrno` on
failure; they do not raise exceptions or change an event's scheduling policy.
Pass `Worker.ThreadID` or `GetCurrentThreadID`. These are pthread handles, not
kernel TIDs; do not cast them to the PID argument of a native Linux syscall.

The caller owns the thread's lifetime and serializes changes to its scheduling
profile. The RTL resolves and pins the native TID during each call; it does not
retain the object or validate a handle after its lifetime ends. A finished
registered thread returns `ESRCH`. The typed setter rejects sizes larger than
`SizeOf(TSchedAttr)` with `E2BIG` and preserves its const argument on errors.
The lower-level `Linux.sched_getattr` / `sched_setattr` bindings take a native
TID and a pointer, with the Linux ABI and `-1`/errno convention.

`TSchedAttr` contains Size, Policy, Flags, Nice, Priority, Runtime, Deadline,
Period, UtilMin and UtilMax. Time fields are nanoseconds. Keep unrelated fields
when modifying a profile. For ordinary `SCHED_OTHER` threads, supporting kernels
allow an explicit fair-scheduler slice in Runtime. This is not a nonpreemptible
time reservation. Older kernels may accept the setter but ignore that field:
read back the profile during setup before enabling an optimization.

`sched_getattr` returns the effective slice, not its automatic/custom mode.
To restore a **known automatic** original mode, set Runtime to zero. Restoring
the effective numeric value instead installs a custom slice. An application
that already owns a custom profile must retain that profile itself. Increasing
priority may require privileges; check both applying and restoring a profile.
Do not let a denied scheduling request discard otherwise valid application work.

### Optional timeout granularity on Linux

`Unix.SetWaitGranularityUS(15625)` opts the process into rounding positive
relative `SysUtils.Sleep`, direct `TEvent` and internal `RTLEvent` timeout
durations up to multiples of 15.625 ms.
For example, 16 ms becomes 31.25 ms and 80 ms becomes 93.75 ms. The default is
zero (no rounding). This is explicit duration rounding, not emulation of the
Windows scheduler or synchronization of all deadlines to a common clock phase.

Set the policy once before starting worker threads. Zero-time polls, infinite
waits and ready events retain their meaning. Signaling an event still releases
its waiter immediately, subject to OS scheduling; it does not wait for the
rounded timeout. The setting also affects short sleeps: `Sleep(1)` becomes
15.625 ms. Review retry/backoff code before opting in. `TSemaphore`, `TMutex`
and timed thread joins use other primitives and are not changed. Higher-level
wrappers retain their outer elapsed-time budget: another notification can make
a MultiWait/Lightweight wait finish before the rounded leaf deadline. This
switch does not make every higher-level `WaitFor(16)` last exactly 31.25 ms.

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
