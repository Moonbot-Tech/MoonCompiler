#!/usr/bin/env python3
"""Coordinate both release hosts, advancing only when both finish a stage."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shlex
import subprocess
import sys

HOSTS = ("windows", "linux")
PHASES = (("light", False), ("medium", False), ("full", False), ("light", True))


def command(config: dict, host: str, arguments: list[str]) -> list[str]:
    settings = config[host]
    if host == "windows":
        return arguments
    return settings["ssh"] + [f"cd {shlex.quote(settings['repo'])} && {shlex.join(arguments)}"]


def invoke(config: dict, host: str, arguments: list[str], *, capture: bool = False) -> tuple[int, str]:
    cmd = command(config, host, arguments)
    cwd = config["windows"]["repo"]
    if capture:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)
        return result.returncode, result.stdout.strip()
    process = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, errors="replace")
    output = []
    for line in process.stdout:
        print(f"[{host}] {line.rstrip()}", flush=True)
        output.append(line)
    process.stdout.close()
    return process.wait(), "".join(output)


def arguments(settings: dict, host: str, action: str, mode: str, final: bool, head: str = "",
              skip_pulse: bool = False) -> list[str]:
    result = [settings.get("python", sys.executable if host == "windows" else "python3"),
              "qualification/release/qualify.py", action, "--platform", "win64" if host == "windows" else "linux",
              "--run-dir", settings["run_dir"], "--mode", mode,
              "--jobs", str(settings["jobs"]), "--memory-mb", str(settings["memory_mb"])]
    if skip_pulse:
        result.append("--skip-pulse")
    elif settings.get("baseline_toolchain"):
        result += ["--baseline-toolchain", settings["baseline_toolchain"]]
    if not skip_pulse and settings.get("baseline_mm_source"):
        result += ["--baseline-mm-source", settings["baseline_mm_source"]]
    if head:
        result += ["--expect-head", head]
    if final:
        result.append("--final")
    return result


def run_route(config: dict, skip_pulse: bool = False) -> int:
    heads = {}
    for host in HOSTS:
        code, head = invoke(config, host, ["git", "rev-parse", "HEAD"], capture=True)
        if code or len(head) != 40:
            raise ValueError(f"{host}: cannot identify the source revision")
        code, dirty = invoke(config, host, ["git", "status", "--porcelain", "--untracked-files=no"], capture=True)
        if code or dirty:
            raise ValueError(f"{host}: commit tracked changes before qualification")
        heads[host] = head
    if len(set(heads.values())) != 1:
        raise ValueError("both hosts must have the same committed candidate before starting")
    head = heads["windows"]
    for mode, final in PHASES:
        label = "final Light" if final else mode
        print(f"QUALIFICATION_STAGE {label} head={head}", flush=True)
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = {host: pool.submit(invoke, config, host,
                       arguments(config[host], host, "run", mode, final, head, skip_pulse)) for host in HOSTS}
            results = {host: future.result() for host, future in futures.items()}
        failed = []
        for host, (code, output) in results.items():
            markers = ("FINAL_EXACT_HEAD_PASS",) if final else ("DISCOVERY_PASS", "DISCOVERY_PROVISIONAL")
            if code or not any(f"{marker} {head} " in output for marker in markers):
                failed.append(host)
        if failed:
            print(f"QUALIFICATION_STOP stage={label} hosts={','.join(failed)}; later stages were not started")
            return 1
    if skip_pulse:
        print(f"QUALIFICATION_COMPLETE {head} scope=correctness-without-pulse; Pulse was not run")
    else:
        print(f"QUALIFICATION_COMPLETE {head}; read both Pulse reports before deciding to publish")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "run"))
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--skip-pulse", action="store_true",
                        help="run all correctness and delivery stages without Pulse")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    for host in HOSTS:
        settings = config[host]
        if settings["jobs"] < 1 or settings["memory_mb"] < 1:
            parser.error(f"{host}: worker and memory budgets must be positive")
    if args.action == "plan":
        for mode, final in PHASES:
            print("final Light" if final else mode)
            for host in HOSTS:
                print(host, json.dumps(command(config, host, arguments(config[host], host, "run", mode, final,
                                                                      skip_pulse=args.skip_pulse))))
        print("PLAN_ONLY: no host commands, builds, or tests were executed")
        return 0
    return run_route(config, args.skip_pulse)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"qualification coordination: {error}", file=sys.stderr)
        raise SystemExit(2)
