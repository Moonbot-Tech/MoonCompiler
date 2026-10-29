#!/usr/bin/env python3
"""Linux-only paired scheduler/RTL control. No RTL changes, no throughput calibration."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--moon", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=15)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Linux" or args.cpu not in os.sched_getaffinity(0):
        parser.error("Linux and an available CPU are required")
    if not 0.1 <= args.seconds <= 60 or not 1 <= args.repeats <= 10:
        parser.error("seconds must be 0.1..60; repeats 1..10")
    args.output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    rounds = math.ceil(args.seconds * 1000 / 16)
    commands = {
        "c-normal": [str(args.native.resolve()), "normal", "92", str(rounds), "16"],
        "c-recursive": [str(args.native.resolve()), "recursive", "92", str(rounds), "16"],
        "moon": [str(args.moon.resolve()), "paced-event", "92", str(rounds), "16"],
    }
    manifest = dict(machine=platform.uname()._asdict(), libc=platform.libc_ver(), cpu=args.cpu,
                    seconds=args.seconds, repeats=args.repeats, commands=commands,
                    timer_slack_ns=Path("/proc/self/timerslack_ns").read_text().strip(),
                    native_sha256=sha(args.native), moon_sha256=sha(args.moon),
                    c_source_sha256=sha(root / "threads/pulse_thread_wakeups_native.c"),
                    pascal_source_sha256=sha(root / "threads/pulse_thread_wakeups.dpr"),
                    runner_sha256=sha(Path(__file__)))
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    rows = []
    for repeat in range(args.repeats):
        order = list(commands)
        order = order[repeat % len(order):] + order[:repeat % len(order)]
        for name in order:
            command = ["taskset", "-c", str(args.cpu), *commands[name]]
            started = time.time()
            process = subprocess.run(command, check=True, text=True, capture_output=True,
                                     timeout=args.seconds * 4 + 20)
            (args.output / f"{repeat}-{name}.log").write_text(process.stdout + process.stderr)
            lines = [line for line in process.stdout.splitlines()
                     if line.startswith(("NATIVE_WAKE ", "PULSE_WAKE "))]
            if len(lines) != 1:
                raise RuntimeError("missing measurement: " + process.stdout)
            row = {key: value if key == "mode" else int(value)
                   for key, value in (part.split("=", 1) for part in lines[0].split()[1:])}
            if row["verified"] != 1 or row["wakes"] != 92 * rounds:
                raise RuntimeError("different work or failed contract")
            row.update(implementation=name, repeat=repeat, started_unix=started)
            row["cpu_percent"] = (row["user_ns"] + row["kernel_ns"]) * 100 / row["wall_ns"]
            row["kernel_percent"] = row["kernel_ns"] * 100 / row["wall_ns"]
            rows.append(row)
            (args.output / "samples.json").write_text(json.dumps(rows, indent=2))
            print(f'{name}: CPU={row["cpu_percent"]:.3f}% kernel={row["kernel_percent"]:.3f}% '
                  f'wall={row["wall_ns"]/1e9:.3f}s wakes={row["wakes"]}', flush=True)
    summary = []
    for name in commands:
        selected = [row for row in rows if row["implementation"] == name]
        summary.append(dict(implementation=name, **{
            key: dict(median=statistics.median(row[key] for row in selected),
                      minimum=min(row[key] for row in selected), maximum=max(row[key] for row in selected))
            for key in ("cpu_percent", "kernel_percent", "wall_ns", "dispatch_late_ns")
        }))
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
