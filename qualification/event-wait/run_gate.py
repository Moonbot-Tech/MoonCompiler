"""Linux event-wait contracts, instrumenting an isolated copy of cthreads only."""
import argparse
from pathlib import Path
import shutil
import subprocess


def once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"Instrumentation anchor changed: {old!r}")
    return text.replace(old, new)


def instrument(text):
    text = once(text, "\nimplementation\n", """
var
  EventProbeClockReads, EventProbeTimedWaits: LongInt;
  EventProbeFailClock: Boolean;
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
        "if clock_gettime(plocaleventstate(state)^.FClockID, @timespec) <> 0 then",
        "InterlockedIncrement(EventProbeClockReads);\n      if EventProbeFailClock or (clock_gettime(plocaleventstate(state)^.FClockID, @timespec) <> 0) then")
    body = once(body, "        errres := pthread_cond_timedwait(",
        "        begin\n          InterlockedIncrement(EventProbeTimedWaits);\n          errres := pthread_cond_timedwait(")
    body = once(body, "                                         @timespec);",
        "                                         @timespec);\n        end;")
    return text[:start] + body + text[end:]


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
    parser.add_argument("--profiles", nargs="+", default=["O-", "O2", "O3"])
    parser.add_argument("--cases", nargs="+", default=["contract", "ready", "poll", "clock", "destroy"])
    args = parser.parse_args()
    compiler = str(Path(args.compiler).resolve())
    source = instrument(args.source.read_text(encoding="utf-8"))
    for profile in args.profiles:
        out = (args.output / profile).resolve()
        out.mkdir(parents=True, exist_ok=True)
        log = out / "gate.log"
        log.write_text("", encoding="utf-8")
        (out / "cthreads.pp").write_text(source, encoding="utf-8")
        shutil.copyfile(args.pthread, out / "pthread.inc")
        shutil.copyfile(args.test, out / args.test.name)
        flags = [compiler, "-" + profile, "-Fi" + str(out), "-Fu" + str(out), "-FU" + str(out), "-FE" + str(out)]
        run(flags + ["cthreads.pp"], out, log)
        run(flags + ["-dEVENT_PROBE", args.test.name], out, log)
        for case in args.cases:
            output = run([str(out / args.test.stem)] + ([] if case == "contract" else [case]), out, log)
            if output.strip() != "EVENT_WAIT_CONTRACT_PASS":
                raise RuntimeError(f"Missing contract completion: {case}; see {log}")
            print(f"PASS {profile} {case}", flush=True)
    print("EVENT_WAIT_GATE_PASS", flush=True)


if __name__ == "__main__":
    main()
