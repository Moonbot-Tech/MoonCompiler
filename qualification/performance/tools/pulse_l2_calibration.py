#!/usr/bin/env python3
"""Measure L2 misses per 1000 cycles of every Pulse case that shares the machine.

pulse_full.py runs a case alone when this rate says a neighbour on the shared
L3 can move its cost (pulse_full.L2_EXCLUSIVE_PER_KCYCLE).  One process per
case, built by the given toolchain, under Pulse's machine settings, the cases
spread over the single-CPU cores of pulse_full as each core frees: a case's
own L2 misses do not depend on what runs on another core (the L2 is the
core's), and every process is judged by its core and its SMT sibling as in a
Pulse pass.  Windows reads xperf PMC TotalCycles and --event (run from an
elevated shell); Linux reads the harness's cycle group with raw perf events.
An event may be a sum, `a+b+c`: the requests of a core to L3 are one event on
Intel and three on AMD.  Only this machine's section of the table, keyed by
its host name, is rewritten only when the event passed both controls: every
discovered workloads/stream-* case measured clean and over the threshold,
each of the two register-only cases measured clean and under it.  Other cases
rejected after three processes stay absent from the table and run exclusively
in Pulse; only clean rates are written, unrounded.  After a run on a remote host,
copy the table back into the repository; pulse_both.py synchronizes it from there.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import pulse  # noqa: E402
import pulse_full  # noqa: E402
import qualify_measurement_method as method  # noqa: E402


DURATION_MS = 100
# Intel's architectural LLC reference (event 2EH, umask 4FH) as a raw perf
# config: core requests to L3, hardware prefetches from L1 and L2 included, not
# every L3 access (Intel perfmon).  On HEL1 it saw 74-87 per 1000 cycles on the
# 48 MB DRAM streams, where MEM_LOAD_RETIRED.L2_MISS (0x10d1) saw 0.18.  Other
# PMUs encode their events differently.
INTEL_L3_REFERENCES = "0x4f2e"
# The same requests on AMD Zen 2 to Zen 5, which have no one event for them
# (Linux pmu-events amdzen2..amdzen5, the same codes on all four): demand misses
# of the instruction and data caches in L2 (PMCx064 umask 0x09,
# l2_cache_req_stat.ic_dc_miss_in_l2) plus L2 prefetches that miss L2 and hit L3
# (PMCx071, l2_pf_miss_l2_hit_l3) or miss L3 too (PMCx072, l2_pf_miss_l2_l3).
AMD_L3_REQUESTS = "0x964+0xff71+0xff72"
# The controls an event must pass before its section is written: streaming
# over DRAM is heavy, a chain of dependent register adds is not.
REGISTER_CONTROLS = ("calibration/asm-dependent-add", "codegen/dep-add")
STREAM_CONTROL_PREFIX = "workloads/stream-"


def counted_event(event: str | None, cpuinfo: str | None) -> str:
    """--event, or on a Linux Intel or AMD PMU the core's requests to L3; Windows
    names its xperf source."""
    if event:
        return event
    if cpuinfo is not None and "GenuineIntel" in cpuinfo:
        return INTEL_L3_REFERENCES
    if cpuinfo is not None and "AuthenticAMD" in cpuinfo:
        return AMD_L3_REQUESTS
    raise SystemExit(
        f"pulse_l2_calibration: --event is required here: {INTEL_L3_REFERENCES} (Intel) and "
        f"{AMD_L3_REQUESTS} (AMD) are raw perf configs of Linux.  Name this machine's event "
        "that counts the core's L2 misses (raw perf config on Linux, xperf PMC source on "
        "Windows; a+b sums several).  The table is written "
        "only if every workloads/stream-* case comes out over "
        f"{pulse_full.L2_EXCLUSIVE_PER_KCYCLE} per 1000 cycles and the register-only "
        f"controls ({', '.join(REGISTER_CONTROLS)}) under it; the event is written into it."
    )


def event_parts(event: str) -> list[str]:
    """The events a sum names, in the order the harness numbers them raw0, raw1..."""
    parts = [part.strip() for part in event.split("+")]
    if not all(parts) or len(parts) > 4:
        raise SystemExit(f"pulse_l2_calibration: --event {event!r} is not one to four events joined by +")
    return parts


def control_failures(rates: dict[str, float], expected_streams: set[str]) -> list[str]:
    """Why these rates cannot be published: the event must see every stream over
    the threshold and count each register-only chain under it, all measured.
    The rates are the ones written, as measured: a rounded rate can cross it."""
    threshold = pulse_full.L2_EXCLUSIVE_PER_KCYCLE
    failures = [f"register-only control {name} not measured" for name in REGISTER_CONTROLS if name not in rates]
    failures += [f"register-only control {name} = {rates[name]} is not under {threshold}"
                 for name in REGISTER_CONTROLS if name in rates and not rates[name] < threshold]
    failures += [f"stream control {name} not measured" for name in sorted(expected_streams - rates.keys())]
    streams = {name: rates[name] for name in expected_streams if name in rates}
    failures += [f"stream control {name} = {rate} is not over {threshold}"
                 for name, rate in sorted(streams.items()) if not rate > threshold]
    if not expected_streams:
        failures.append(f"no {STREAM_CONTROL_PREFIX}* control measured")
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=Path, required=True)
    parser.add_argument("--mm-source", type=Path)
    parser.add_argument("--programs", default=",".join(pulse.stand_programs(True)))
    parser.add_argument(
        "--event",
        help="xperf PMC source (Windows) or raw perf config (Linux) counting L2 misses; "
        f"only an Intel PMU has a default, {INTEL_L3_REFERENCES}",
    )
    parser.add_argument("--output", type=Path, required=True, help="new directory for the logs")
    parser.add_argument("--table", type=Path, default=pulse_full.L2_CALIBRATION)
    parser.add_argument(
        "--cpu",
        default="",
        help="comma-separated logical CPUs to measure on; default: the single-CPU cores of pulse_full",
    )
    parser.add_argument("--windows-profile-interval", type=int, default=1221,
                        help="xperf sampling interval in 100 ns units during Windows L2 calibration (default: 1221)")
    args = parser.parse_args()
    if args.windows_profile_interval <= 0:
        parser.error("--windows-profile-interval must be positive")
    args.event = counted_event(
        args.event,
        None if os.name == "nt" else Path("/proc/cpuinfo").read_text(encoding="utf-8"),
    )
    return args


def spread_over_cores(cases: list, cpus: list[int], measure, attempts: int) -> tuple[dict, list[str]]:
    """measure(index, case, cpu) for every case, a record or None when the runner
    rejected the process, each core taking the next case as it frees.  A rejected
    case is repeated on a core it has not run on yet (any core once it has run on
    all): a core whose sibling stays busy does not decide a case three times.
    ({case: record}, the cases rejected `attempts` times)."""
    condition = threading.Condition()
    pending = list(cases)
    tried: dict[object, set[int]] = {case: set() for case in cases}
    runs: dict[object, int] = {case: 0 for case in cases}
    measured: dict[object, dict[str, object]] = {}
    unclean: list[str] = []
    running = 0
    failure: list[BaseException] = []

    def eligible(cpu: int):
        return next((case for case in pending if cpu not in tried[case] or len(tried[case]) >= len(cpus)), None)

    def work(cpu: int) -> None:
        nonlocal running
        while True:
            with condition:
                while True:
                    case = eligible(cpu)
                    if case is not None or failure or (not pending and running == 0):
                        break
                    if running == 0:
                        return
                    condition.wait()
                if case is None or failure:
                    condition.notify_all()
                    return
                pending.remove(case)
                tried[case].add(cpu)
                runs[case] += 1
                running += 1
            try:
                record = measure(cases.index(case), case, cpu)
            except BaseException as error:
                with condition:
                    failure.append(error)
                    running -= 1
                    condition.notify_all()
                return
            with condition:
                running -= 1
                if record is not None:
                    measured[case] = record
                elif runs[case] < attempts:
                    pending.append(case)
                else:
                    unclean.append(f"{case[0]}/{case[1]}")
                condition.notify_all()

    threads = [threading.Thread(target=work, args=(cpu,), name=f"pulse-l2-{cpu}") for cpu in cpus]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    if failure:
        raise failure[0]
    return measured, unclean


def l2_rate(record: dict[str, object], misses_of) -> float:
    """Median L2 misses per 1000 cycles over the samples of one process."""
    rates = []
    for sample in record["samples"]:
        cycles = int(sample["core_cycles"])
        if cycles <= 0:
            raise RuntimeError(f"no core cycles: {record['program']}/{record['case']}")
        rates.append(1000.0 * int(misses_of(sample)) / cycles)
    return statistics.median(rates)


def run() -> int:
    args = parse_args()
    toolchain = args.toolchain.resolve()
    mm_source = (
        args.mm_source or toolchain / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
    ).resolve()
    output = args.output.resolve()
    (output / "logs").mkdir(parents=True, exist_ok=False)
    programs = [name.strip() for name in args.programs.split(",") if name.strip()]

    def build(program: str) -> Path:
        return pulse.build_moon(
            program, False, system="pulse-l2-calibration", toolchain=toolchain, mm_source=mm_source
        )

    with ThreadPoolExecutor(max_workers=4) as executor:
        built = dict(zip(programs, executor.map(build, programs)))
    cases = []
    for program in programs:
        for name, row in pulse_full.discover(built[program]).items():
            category = pulse_full.classify(program, name, row.get("layer", ""))
            if not pulse_full.POLICIES[category].exclusive:
                cases.append((program, name, category))
    cpus = (
        [int(cpu) for cpu in args.cpu.split(",") if cpu.strip()]
        if args.cpu
        else list(pulse_full.benchmark_cpu_sets()[0])
    )
    parts = event_parts(args.event)
    for cpu in cpus:
        method.keep_runner_off(cpu)
    windows = os.name == "nt"
    settings = method.windows_machine_settings if windows else method.linux_machine_settings
    etl = output / "l2.etl"
    max_attempts = 3

    def calibrate(index: int, case: tuple[str, str, str], cpu: int) -> dict[str, object] | None:
        """One process of one case on `cpu`, None when the runner rejected it."""
        program, name, category = case
        record = method.run_one(
            built[program], program, name, "l2", 0, DURATION_MS, category, (cpu,),
            output / "logs", raw_configs="" if windows else ",".join(parts),
        )
        # Judged as pulse_full judges a single-CPU process: its counters, the core
        # before it and the sibling over its life.  The harness's own sibling check
        # sums five 20 ms samples of 10 ms clock ticks against one tick of
        # tolerance and rejects an idle sibling (8 ticks of 9.7 in a sample of
        # json/parse-large-custom-double on HEL1, 28.09).
        metrics = method.record_metrics(record, category == "multithread", work_only=category != "multithread")
        if metrics["valid"]:
            return record
        print(
            f"PULSE_L2_RETRY case={program}/{name} cpu={cpu} "
            f"reason={method.rejection_reason(metrics)} runner={json.dumps(record.get('runner'))}",
            flush=True,
        )
        return None

    with settings():
        if windows:
            method.xperf_start(etl, ("TotalCycles", *parts))
        try:
            if windows and args.windows_profile_interval != 1221:
                method.command([str(method.XPERF), "-SetProfInt", str(args.windows_profile_interval)])
            measured, unclean = spread_over_cores(cases, cpus, calibrate, max_attempts)
        finally:
            if windows:
                dump = method.xperf_stop(etl)
        records = [measured[case] for case in cases if case in measured]
        if windows:
            method.attach_windows_core_cycles(dump, records)

    def misses_of(sample: dict[str, object]) -> int:
        if windows:
            return sum(int(sample["pmc"][part]) for part in parts)
        return sum(int(sample[f"raw{index}"]) for index in range(len(parts)))

    section = {
        "event": args.event,
        "toolchain_sha256": pulse.moon_toolchain_identity(toolchain)["backend_sha256"],
        "created_unix": time.time(),
        "cases": {f"{record['program']}/{record['case']}": l2_rate(record, misses_of) for record in records},
        "unclean": sorted(unclean),
    }
    if windows:
        section["profile_interval_100ns"] = args.windows_profile_interval
    alone = sorted(
        name
        for name, rate in section["cases"].items()
        if rate > pulse_full.L2_EXCLUSIVE_PER_KCYCLE
    )
    expected_streams = {f"{program}/{name}" for program, name, _ in cases
                        if f"{program}/{name}".startswith(STREAM_CONTROL_PREFIX)}
    failures = control_failures(section["cases"], expected_streams)
    print(
        f"PULSE_L2 machine={platform.node()} cases={len(section['cases'])} "
        f"alone={len(alone)} unclean_exclusive={len(unclean)} refused={int(bool(failures))} table={args.table}",
        flush=True,
    )
    for name in alone:
        print(f"PULSE_EXCLUSIVE case={name} l2_misses_per_kcycle={section['cases'][name]:.4f}", flush=True)
    if failures:
        # An unproven event cannot decide which cases share the machine.
        for failure in failures:
            print(f"PULSE_L2_REFUSED {failure}", file=sys.stderr, flush=True)
        return 1
    for name in sorted(unclean):
        print(f"PULSE_L2_UNMEASURED case={name} remains exclusive", flush=True)
    table = (
        json.loads(args.table.read_text(encoding="utf-8"))
        if args.table.is_file()
        else {"schema": 2}
    )
    table[platform.node()] = section
    temporary = args.table.with_name(args.table.name + ".tmp")
    temporary.write_text(
        json.dumps(table, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(args.table)
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
