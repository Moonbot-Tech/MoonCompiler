# dvl-0007 — `TMonitor.Enter` on Win64 previously raised a null-address AV

**Status: fixed.** MoonCompiler now installs the platform monitor manager as
part of its product runtime on both Win64 and Linux. The generated
`monitor-counter` form, the standalone platform gates, and the Resident
`rtl-monitor` stage are active.

Found by Devil, `thr` layer, `monitor-counter` form: under `TMonitor`, Delphi's
counter reaches the expected value, while ours remains zero at every
optimization level.

## Repro

`repro.dpr` — twenty lines, the main thread, and no multithreading at all:

```pascal
Lock := TObject.Create;
Counter := 0;
TMonitor.Enter(Lock);
try
  Inc(Counter, 10);
finally
  TMonitor.Exit(Lock);
end;
WriteLn(Counter);
```

| compiler at discovery | result |
|---|---|
| Delphi 12.2 Win64 | prints `10` |
| pre-fix MoonCompiler (`-O-`, `-O2`) | `EAccessViolation` at `$0000000000000000`, exit 217 |

`repro-threads.dpr` performs the same operation in four threads: Delphi gets
`counter=40`, ours gets `counter=0`. In a thread, the exception reaches
`FatalException`, so externally this looks not like a crash but like a silently
skipped body — the worst form of failure.

A separate run confirms that threads themselves work: an ordinary increment
without `TMonitor` from the same threads produces the correct `40`, and the
launch counter shows that all `Execute` methods ran.

## Why this was not visible earlier

The null address is an uncalled monitor callback: the manager is uninitialized.
A similar defect was already fixed in the fallback path, but
`scripts/run_monitor_gate.sh` validates it **only on Linux**. On Win64,
`TMonitor` had still not been checked by anything, while MoonBot uses it on
production locking paths.

## Resolution

The RTL now initializes the fallback monitor manager and supplies the Win64
manager explicitly. The product compiler also inserts `fpwinmonitor` or
`fpmonitor` automatically, so an ordinary project does not depend on a manual
unit prefix. An explicit vanilla-runtime build remains outside that product
contract and may report runtime error 235 when no monitor manager is linked.

Permanent coverage includes the Win64 monitor semantic test, the Linux monitor
gate, the generated multi-threaded `monitor-counter` shape, and the Resident
stage that repeatedly enters, leaves, and probes an object monitor.
