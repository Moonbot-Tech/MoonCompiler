#!/usr/bin/env python3
"""Paced Pulse family: CPU cost of many mostly waiting workers, not sleep throughput."""
import argparse
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import time

import pulse

CASES = {
    "idle": ("idle", 92, 16),
    "one-event": ("event", 1, 16),
    "event80": ("event", 92, 80),
    "sleep16": ("sleep", 92, 16),
    "event16": ("event", 92, 16),
    "signal16": ("signal", 92, 16),
    "clock16": ("clock", 92, 16),
    "clock-libc16": ("clock-libc", 92, 16),
    "queue8": ("queue", 92, 16),
    "sync8": ("synchronize", 92, 16),
    "queue1": ("queue-heavy", 92, 16),
    "paced-event": ("paced-event", 92, 16),
    "paced-clock": ("paced-clock", 92, 16),
    "paced-queue": ("paced-queue", 92, 16),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=Path, default=pulse.ROOT / "toolchain")
    parser.add_argument("--systems", default="delphi,moon" if os.name == "nt" else "moon")
    parser.add_argument("--cases", default=",".join(CASES))
    parser.add_argument("--seconds", type=float, default=3)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--cpu", type=int, required=True, help="one logical CPU for the entire process")
    parser.add_argument("--windows-timer-ms", type=int, choices=(0, 1), default=0,
                        help="optional Windows timer-resolution control; 0 preserves the process default")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()
    systems = args.systems.split(",")
    cases = args.cases.split(",")
    if not set(systems) <= {"delphi", "moon"} or not set(cases) <= CASES.keys():
        parser.error("unknown system or case")
    if not 0.05 <= args.seconds <= 60 or args.repeats < 1:
        parser.error("seconds must be 0.05..60 and repeats positive")
    if args.cpu < 0 or (os.name == "nt" and args.cpu >= 64):
        parser.error("invalid CPU; Windows runner uses the primary processor group")
    if hasattr(os, "sched_getaffinity") and args.cpu not in os.sched_getaffinity(0):
        parser.error("CPU is not in the allowed affinity set")
    args.output.mkdir(parents=True, exist_ok=True)
    program = "thread-wakeups"
    source = pulse.PERF_ROOT / "threads" / "pulse_thread_wakeups.dpr"
    # Reuse the ordinary Pulse build profile and allocator; this family needs
    # its own CPU-time report because elapsed time is intentionally paced.
    pulse.PROGRAMS[program] = source
    executables = {}
    for system in systems:
        if not args.no_build:
            if system == "delphi":
                pulse.build_delphi(program)
            else:
                pulse.build_moon(program, False, toolchain=args.toolchain)
        executables[system] = pulse.executable(program, system)
    provenance = {
        "schema": "pulse-paced-workers-v2",
        "git_head": pulse.git_text("rev-parse", "HEAD"),
        "git_status": pulse.git_text("status", "--short"),
        "source_sha256": pulse.sha256(source),
        "runner_sha256": pulse.sha256(Path(__file__)),
        "machine": pulse.machine_metadata(),
        "cpu": args.cpu,
        "windows_timer_ms": args.windows_timer_ms,
        "seconds": args.seconds,
        "repeats": args.repeats,
        "cases": {case: CASES[case] for case in cases},
        "toolchain": pulse.moon_toolchain_identity(args.toolchain) if "moon" in systems else None,
        "binary_sha256": {name: pulse.sha256(path) for name, path in executables.items()},
        "allocator_sha256": pulse.sha256(pulse.MM_SOURCE),
    }
    (args.output / "manifest.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    if args.build_only:
        return
    rows = []
    for repeat in range(args.repeats):
        # Alternate systems and reverse cases to expose drift; never overlap
        # the two systems on the reserved CPU.
        for case in (cases if repeat % 2 == 0 else cases[::-1]):
            mode, workers, period = CASES[case]
            rounds = max(1, math.ceil(args.seconds * 1000 / period))
            for system in (systems if repeat % 2 == 0 else systems[::-1]):
                command = [str(executables[system]), mode, str(workers), str(rounds), str(period)]
                env = dict(os.environ, PULSE_WAKE_CPU=str(args.cpu), PULSE_WAKE_TIMER_MS=str(args.windows_timer_ms))
                if os.name != "nt":
                    command = ["taskset", "-c", str(args.cpu), *command]
                started = time.time()
                result = subprocess.run(command, capture_output=True, text=True, env=env,
                                        timeout=args.seconds * 4 + 20, check=True)
                lines = [line for line in result.stdout.splitlines() if line.startswith("PULSE_WAKE ")]
                if len(lines) != 1:
                    raise RuntimeError(result.stdout + result.stderr)
                fields = pulse.parse_fields(lines[0])
                row = {key: value if key == "mode" else int(value) for key, value in fields.items()}
                assert row["verified"] == 1
                row.update(system=system, case=case, repeat=repeat, started_unix=started)
                cpu_ns = row["user_ns"] + row["kernel_ns"]
                row["cpu_percent"] = cpu_ns / row["wall_ns"] * 100
                row["kernel_percent"] = row["kernel_ns"] / row["wall_ns"] * 100
                row["cpu_ns_per_wake"] = cpu_ns / row["wakes"] if row["wakes"] else None
                rows.append(row)
                if row.get('short_gaps', 0):
                    print(f"{system}: {row['short_gaps']} catch-up rounds below half the nominal period; "
                          "this is not a clean blocked-wait latency comparison.", flush=True)
                (args.output / "samples.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
                print(f'{system:7s} {case:13s} CPU={row["cpu_percent"]:.3f}% '
                      f'kernel={row["kernel_percent"]:.3f}% wakes={row["wakes"]} '
                      f'wall={row["wall_ns"] / 1e9:.3f}s', flush=True)
    summary = []
    for case in cases:
        for system in systems:
            samples = [row for row in rows if row["case"] == case and row["system"] == system]
            summary.append({"case": case, "system": system, **{
                key: statistics.median([row[key] for row in samples])
                for key in ("cpu_percent", "kernel_percent", "wall_ns", "wakes", "logs", "process_cycles", "dispatch_late_ns")
            }})
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
