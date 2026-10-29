"""Linux event-wait contracts, instrumenting an isolated copy of cthreads only."""
import argparse
from pathlib import Path
import shutil
import subprocess


def once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"Instrumentation anchor changed: {old!r}")
    return text.replace(old, new)


def instrument_state_futex(text):
    """Keep pthread backend coverage; inject into the actual state-futex path."""
    text = once(text, '\nimplementation\n', '''
const
  EventProbeStateFutex = {$if defined(linux) and defined(cpux86_64) and not defined(android) and not defined(FPC_USE_LIBC)}True{$else}False{$endif};
var
  EventProbeClockReads, EventProbeTimedWaits: LongInt;
  EventProbeFailClock: Boolean;
  EventProbeWaitError, EventProbeSpuriousWaits, EventProbeCondWaits: LongInt;
  EventProbeNotifyTarget, EventProbeWaitTarget: Pointer;
  EventProbeNotifyStage, EventProbeNotifyRelease: LongInt;
  EventProbeWaitStage, EventProbeWaitRelease: LongInt;
  EventProbeFutexCalls, EventProbeFutexRetries, EventProbeFutexRetryError: LongInt;
  EventProbeDeadlineSec, EventProbeDeadlineNs: Int64;
  EventProbeDeadlineChanged: Boolean;
function EventProbeWaiterCount(State: Pointer): LongInt;
implementation
''')
    helpers = '''function EventProbeWaiterCount(State: Pointer): LongInt;
begin
  pthread_mutex_lock(@PLocalEventState(State)^.FEventSection);
  Result:=InterlockedCompareExchange(PLocalEventState(State)^.FWaiters,0,0);
  pthread_mutex_unlock(@PLocalEventState(State)^.FEventSection);
end;

function EventProbeInjectedError: LongInt;
begin
  InterlockedIncrement(EventProbeCondWaits);
  if EventProbeCondWaits>8 then begin
    WriteLn('COND_ERROR_RETRY_LOOP');
    Halt(93);
  end;
  if EventProbeSpuriousWaits>0 then begin
    Dec(EventProbeSpuriousWaits);
    Exit(0);
  end;
  Result:=EventProbeWaitError;
end;

'''
    helpers += '''function EventProbeCondWait(Cond: ppthread_cond_t; Mutex: ppthread_mutex_t): LongInt;
begin
  if EventProbeWaitError<>0 then Exit(EventProbeInjectedError);
  Result:=pthread_cond_wait(Cond,Mutex);
end;

function EventProbeCondTimedWait(Cond: ppthread_cond_t; Mutex: ppthread_mutex_t; Deadline: ptimespec): LongInt;
begin
  InterlockedIncrement(EventProbeTimedWaits);
  if EventProbeWaitError<>0 then Exit(EventProbeInjectedError);
  Result:=pthread_cond_timedwait(Cond,Mutex,Deadline);
end;

'''
    text = once(text, '{$ifdef BASICEVENT_STATE_FUTEX}\nconst', helpers + '{$ifdef BASICEVENT_STATE_FUTEX}\nconst')
    start = text.index('function BasicEventWaitUnlocked(')
    end = text.index('function IntBasicEventCreate(', start)
    body = text[start:end]
    raw = '''  Result:=futex(@PLocalEventState(State)^.FWaitState,BasicEventWaitBitsetPrivate,
    0,Deadline,nil,-1);
  { Linux.futex uses Do_SysCall: -1 plus RTL fpGetErrno, not -errno. }
  if Result<0 then Result:=fpGetErrno;'''
    injected = '''  if (State=EventProbeWaitTarget) and
    (InterlockedCompareExchange(EventProbeWaitStage,1,0)=0) then
    while InterlockedCompareExchange(EventProbeWaitRelease,0,0)=0 do CThreadSwitch;
  InterlockedIncrement(EventProbeFutexCalls);
  if Assigned(Deadline) then
    begin
      InterlockedIncrement(EventProbeTimedWaits);
      if EventProbeFutexCalls=1 then
        begin
          EventProbeDeadlineSec:=Deadline^.tv_sec;
          EventProbeDeadlineNs:=Deadline^.tv_nsec;
        end
      else if (EventProbeDeadlineSec<>Deadline^.tv_sec) or
        (EventProbeDeadlineNs<>Deadline^.tv_nsec) then EventProbeDeadlineChanged:=True;
    end;
  if EventProbeFutexRetries>0 then
    begin
      Dec(EventProbeFutexRetries);
      Result:=EventProbeFutexRetryError;
    end
  else if EventProbeWaitError<>0 then Result:=EventProbeInjectedError
  else begin
''' + raw + '''
  end;'''
    body = once(body, raw, injected)
    text = text[:start] + body + text[end:]
    start = text.index('function IntbasiceventWaitFor(')
    end = text.index('function intRTLEventCreate:', start)
    body = text[start:end]
    body = body.replace('pthread_cond_wait(', 'EventProbeCondWait(').replace('pthread_cond_timedwait(', 'EventProbeCondTimedWait(')
    native = 'if EventClock(CLOCK_MONOTONIC, @timespec) <> 0 then'
    legacy = 'if EventClock(plocaleventstate(state)^.FClockID, @timespec) <> 0 then'
    for anchor in (native, legacy):
        body = once(body, anchor, 'InterlockedIncrement(EventProbeClockReads);\n      if EventProbeFailClock or (' + anchor[3:-5] + ') then')
    text = text[:start] + body + text[end:]
    start = text.index('procedure intRTLEventWaitForTimeout(')
    text = text[:start] + once(text[start:], '      if EventClock(CLOCK_REALTIME,@Deadline)<>0 then',
        '      InterlockedIncrement(EventProbeClockReads);\n      if EventProbeFailClock or (EventClock(CLOCK_REALTIME,@Deadline)<>0) then')
    return once(text, '  if Notify then\n    begin\n{$ifdef BASICEVENT_STATE_FUTEX}',
        '  if Notify then\n    begin\n      if State=EventProbeNotifyTarget then\n'
        '        if InterlockedCompareExchange(EventProbeNotifyStage,1,0)=0 then\n'
        '          while InterlockedCompareExchange(EventProbeNotifyRelease,0,0)=0 do CThreadSwitch;\n'
        '{$ifdef BASICEVENT_STATE_FUTEX}')


def instrument(text):
    if "{$define BASICEVENT_STATE_FUTEX}" in text:
        return instrument_state_futex(text)
    text = once(text, "\nimplementation\n", """
var
  EventProbeClockReads, EventProbeTimedWaits: LongInt;
  EventProbeFailClock: Boolean;
  EventProbeWaitError, EventProbeSpuriousWaits, EventProbeCondWaits: LongInt;
  EventProbeNotifyTarget: Pointer;
  EventProbeNotifyStage, EventProbeNotifyRelease: LongInt;
function EventProbeWaiterCount(State: Pointer): LongInt;

implementation
""")
    anchor = "function IntBasicEventCreate("
    text = once(text, anchor, """function EventProbeWaiterCount(State: Pointer): LongInt;
begin
  pthread_mutex_lock(@plocaleventstate(State)^.FEventSection);
  Result := InterlockedCompareExchange(plocaleventstate(State)^.FWaiters, 0, 0);
  pthread_mutex_unlock(@plocaleventstate(State)^.FEventSection);
end;

""" + anchor)
    start = text.index("function IntbasiceventWaitFor(")
    end = text.index("function intRTLEventCreate:", start)
    body = text[start:end]
    body = once(body,
        "if EventClock(plocaleventstate(state)^.FClockID, @timespec) <> 0 then",
        "InterlockedIncrement(EventProbeClockReads);\n      if EventProbeFailClock or (EventClock(plocaleventstate(state)^.FClockID, @timespec) <> 0) then")
    body = once(body, "        errres := pthread_cond_timedwait(",
        "        begin\n          InterlockedIncrement(EventProbeTimedWaits);\n          errres := pthread_cond_timedwait(")
    body = once(body, "                                         @timespec);",
        "                                         @timespec);\n        end;")
    helpers = """function EventProbeInjectedError: LongInt;
begin
  InterlockedIncrement(EventProbeCondWaits);
  if EventProbeCondWaits>8 then begin
    WriteLn('COND_ERROR_RETRY_LOOP');
    Halt(93);
  end;
  if EventProbeSpuriousWaits>0 then begin
    Dec(EventProbeSpuriousWaits);
    Exit(0);
  end;
  Result:=EventProbeWaitError;
end;

function EventProbeCondWait(Cond: ppthread_cond_t; Mutex: ppthread_mutex_t): LongInt;
begin
  if EventProbeWaitError<>0 then Exit(EventProbeInjectedError);
  Result:=pthread_cond_wait(Cond,Mutex);
end;

function EventProbeCondTimedWait(Cond: ppthread_cond_t; Mutex: ppthread_mutex_t; Deadline: ptimespec): LongInt;
begin
  if EventProbeWaitError<>0 then Exit(EventProbeInjectedError);
  Result:=pthread_cond_timedwait(Cond,Mutex,Deadline);
end;

"""
    body = body.replace('pthread_cond_timedwait(', 'EventProbeCondTimedWait(').replace('pthread_cond_wait(', 'EventProbeCondWait(')
    text = text[:start] + helpers + body + text[end:]
    start = text.index('procedure intRTLEventWaitForTimeout(')
    tail = once(text[start:], '      if EventClock(CLOCK_REALTIME,@Deadline)<>0 then',
                '      InterlockedIncrement(EventProbeClockReads);\n      if EventProbeFailClock or (EventClock(CLOCK_REALTIME,@Deadline)<>0) then')
    text = text[:start] + tail
    return once(text, '      if Manual then pthread_cond_broadcast',
        '      if State=EventProbeNotifyTarget then\n'
        '        if InterlockedCompareExchange(EventProbeNotifyStage,1,0)=0 then\n'
        '          while InterlockedCompareExchange(EventProbeNotifyRelease,0,0)=0 do CThreadSwitch;\n'
        '      if Manual then pthread_cond_broadcast')


def run(args, cwd, log):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=45)
    with log.open("a", encoding="utf-8") as stream:
        stream.write("COMMAND " + repr(args) + "\n" + result.stdout + "\n")
    if result.returncode:
        raise RuntimeError(f"Exit {result.returncode}: {args}; see {log}\n{result.stdout[-4000:]}")
    return result.stdout


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=str(root / "toolchain/bin/fpc"))
    parser.add_argument("--source", type=Path, default=root / "rtl/unix/cthreads.pp")
    parser.add_argument("--pthread", type=Path, default=root / "rtl/linux/pthread.inc")
    parser.add_argument("--test", type=Path, default=root / "RTL-test/semantic/event_wait_contract_semantic.dpr")
    parser.add_argument("--output", type=Path, default=root / ".qualification/event-wait")
    parser.add_argument("--compiler-option", action="append", default=[])
    parser.add_argument("--profiles", nargs="+", default=["O-", "O2", "O3"])
    parser.add_argument("--cases", nargs="+", default=["contract", "ready", "poll", "clock", "destroy", "internal", "condition-error", "notifier-lifetime", "state-futex"])
    args = parser.parse_args()
    compiler = str(Path(args.compiler).resolve())
    raw_source = args.source.read_text(encoding="utf-8")
    state_futex_source = "{$define BASICEVENT_STATE_FUTEX}" in raw_source
    source = instrument(raw_source)
    for profile in args.profiles:
        out = (args.output / profile).resolve()
        out.mkdir(parents=True, exist_ok=True)
        log = out / "gate.log"
        log.write_text("", encoding="utf-8")
        (out / "cthreads.pp").write_text(source, encoding="utf-8")
        shutil.copyfile(args.pthread, out / "pthread.inc")
        shutil.copyfile(args.test, out / args.test.name)
        flags = [compiler, *args.compiler_option, "-" + profile, "-Fi" + str(out), "-Fu" + str(out), "-FU" + str(out), "-FE" + str(out)]
        run(flags + ["cthreads.pp"], out, log)
        run(flags + ["-dEVENT_PROBE", args.test.name], out, log)
        for name in ['internal_event_probe', 'condition_error_probe', 'notification_lifetime_probe']:
            shutil.copyfile(root / 'qualification/event-wait' / (name + '.dpr'), out / (name + '.dpr'))
            run(flags + [name + '.dpr'], out, log)
        if state_futex_source:
            shutil.copyfile(root / "qualification/event-wait/state_futex_probe.dpr", out / "state_futex_probe.dpr")
            run(flags + ["state_futex_probe.dpr"], out, log)
        for case in args.cases:
            if case == "state-futex":
                if not state_futex_source:
                    print(f"SKIP {profile} state-futex (pthread backend)", flush=True)
                    continue
                output = run([str(out / "state_futex_probe")], out, log).strip()
                if output not in ("STATE_FUTEX_PASS", "STATE_FUTEX_SKIPPED"):
                    raise RuntimeError(output)
                status = "PASS" if output == "STATE_FUTEX_PASS" else "SKIP"
                print(f"{status} {profile} state-futex", flush=True)
                continue
            if case == 'notifier-lifetime':
                for mode in ['auto', 'manual']:
                    output = run([str(out / 'notification_lifetime_probe'), mode], out, log)
                    if output.strip() != 'NOTIFICATION_LIFETIME_PASS':
                        raise RuntimeError(output)
                print(f"PASS {profile} {case}", flush=True)
                continue
            if case == 'internal':
                output = run([str(out / 'internal_event_probe')], out, log)
                if output.strip() != 'INTERNAL_EVENT_PASS':
                    raise RuntimeError(output)
                print(f"PASS {profile} {case}", flush=True)
                continue
            if case == 'condition-error':
                for mode in ['finite', 'infinite']:
                    output = run([str(out / 'condition_error_probe'), mode], out, log)
                    if output.strip() != 'COND_ERROR_CLEANUP_PASS ' + mode:
                        raise RuntimeError(output)
                print(f"PASS {profile} {case}", flush=True)
                continue
            output = run([str(out / args.test.stem)] + ([] if case == "contract" else [case]), out, log)
            if output.strip() != "EVENT_WAIT_CONTRACT_PASS":
                raise RuntimeError(f"Missing contract completion: {case}; see {log}")
            print(f"PASS {profile} {case}", flush=True)
    print("EVENT_WAIT_GATE_PASS", flush=True)


if __name__ == "__main__":
    main()
