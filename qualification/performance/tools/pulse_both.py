#!/usr/bin/env python3
"""Run one bounded Pulse comparison on Windows and HEL1 and merge the reports."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import pulse_assessment

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[2]
DEFAULT_CONFIG = ROOT / ".qualification" / "pulse_both.json"
SYNC_FILES = (
    "qualification/performance/common/pulse_harness.pas",
    "qualification/performance/common/pulse_process_metrics.pas",
    "qualification/performance/repairs/pulse_repairs.dpr",
    "qualification/performance/threads/pulse_threads.dpr",
    "qualification/performance/move/pulse_move.dpr",
    "qualification/performance/pulse_l2_misses.json",
    "qualification/performance/tools/pulse.py",
    "qualification/performance/tools/pulse_full.py",
    "qualification/performance/tools/pulse_assessment.py",
    "qualification/performance/tools/qualify_measurement_method.py",
    "qualification/performance/tools/code_placement.py",
    "qualification/performance/tools/pulse_reanalyze.py",
    "qualification/performance/tools/pulse_l2_calibration.py",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cases", default="")
    parser.add_argument("--programs", default="")
    parser.add_argument("--pairs", type=int, default=12)
    parser.add_argument("--build-jobs", type=int, default=4)
    parser.add_argument("--skip-sync", action="store_true")
    parser.add_argument("--skip-preflight", action="store_true")
    return parser.parse_args()


def load_config(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(
            f"Pulse host config is missing: {path}. Copy pulse_both.example.json "
            "or pass --config."
        )
    config = json.loads(path.read_text(encoding="utf-8"))
    for section in ("windows", "linux"):
        if section not in config:
            raise ValueError(f"missing config section: {section}")
    return config


def run_logged(command: list[str], cwd: Path, log: Path) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8", errors="replace") as stream:
        completed = subprocess.run(
            command,
            cwd=cwd,
            stdout=stream,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    return completed.returncode


def ssh_prefix(config: dict[str, Any]) -> list[str]:
    return [
        str(config["plink"]),
        "-batch",
        "-hostkey",
        str(config["hostkey"]),
        "-i",
        str(config["key"]),
        str(config["target"]),
    ]


def pscp_prefix(config: dict[str, Any]) -> list[str]:
    return [
        str(config["pscp"]),
        "-batch",
        "-hostkey",
        str(config["hostkey"]),
        "-i",
        str(config["key"]),
    ]


def remote_command(config: dict[str, Any], arguments: list[str]) -> list[str]:
    command = f"cd {shlex.quote(str(config['repo']))} && {shlex.join(arguments)}"
    return ssh_prefix(config) + [command]


def sync_runner(config: dict[str, Any]) -> None:
    repo = str(config["repo"]).rstrip("/")
    directories = sorted({str(Path(name).parent).replace("\\", "/") for name in SYNC_FILES})
    mkdir = "mkdir -p " + " ".join(shlex.quote(f"{repo}/{name}") for name in directories)
    subprocess.run(ssh_prefix(config) + [mkdir], cwd=ROOT, check=True)
    for relative in SYNC_FILES:
        source = ROOT / relative
        destination = f"{config['target']}:{repo}/{relative.replace('\\', '/')}"
        subprocess.run(pscp_prefix(config) + [str(source), destination], cwd=ROOT, check=True)


def runner_arguments(
    python: str,
    host: dict[str, Any],
    output: str,
    args: argparse.Namespace,
) -> list[str]:
    command = [
        python,
        "qualification/performance/tools/pulse_full.py",
        "--baseline-toolchain",
        str(host["baseline_toolchain"]),
        "--candidate-toolchain",
        str(host["candidate_toolchain"]),
        "--baseline-mm-source",
        str(host["baseline_mm_source"]),
        "--candidate-mm-source",
        str(host["candidate_mm_source"]),
        "--output",
        output,
        "--pairs",
        str(args.pairs),
        "--build-jobs",
        str(args.build_jobs),
    ]
    if args.cases:
        command.extend(("--cases", args.cases))
    if args.programs:
        command.extend(("--programs", args.programs))
    if args.skip_preflight:
        command.append("--skip-preflight")
    return command


def compact_machine(result: dict[str, Any] | None, returncode: int) -> dict[str, Any]:
    if result is None:
        return {"returncode": returncode, "verdict": "INCOMPLETE"}
    return {
        "returncode": returncode,
        "verdict": result.get("overall_verdict", "INCOMPLETE"),
        "elapsed_seconds": result.get("elapsed_seconds"),
        "measurement_seconds": result.get("measurement_seconds"),
        "preflight_passed": (result.get("preflight") or {}).get("passed"),
        "case_count": len(result.get("cases", {})),
    }


def combined_case_verdict(verdicts: list[str]) -> str:
    applicable = [value for value in verdicts if value != "N/A"]
    if not applicable:
        return "N/A"
    if "INCOMPLETE" in applicable:
        return "INCOMPLETE"
    if len(applicable) == 1:
        return applicable[0]
    if "SEMANTIC_MISMATCH" in applicable:
        return "SEMANTIC_MISMATCH"
    return pulse_assessment.directions(applicable)


def merge_results(
    windows: dict[str, Any] | None,
    linux: dict[str, Any] | None,
    windows_code: int,
    linux_code: int,
) -> dict[str, Any]:
    machine_results = {"windows": windows, "linux": linux}
    names = sorted(
        set().union(
            *(set(value.get("cases", {})) for value in machine_results.values() if value)
        )
    )
    cases: dict[str, Any] = {}
    for name in names:
        per_machine = {}
        decisions = []
        reference = next(value["cases"][name] for value in machine_results.values() if value and name in value["cases"])
        for machine, result in machine_results.items():
            if result is None:
                per_machine[machine] = "INCOMPLETE"
                decisions.append("INCOMPLETE")
            else:
                row = result.get("cases", {}).get(name)
                missing = "N/A" if pulse_assessment.context(name, reference)[0] == "control" else "INCOMPLETE"
                values = pulse_assessment.metric_decisions(row) if row else [missing]
                decisions.extend(values)
                per_machine[machine] = combined_case_verdict(values)
        cases[name] = {
            "verdict": combined_case_verdict(list(per_machine.values())),
            "complete": all(value in {"BETTER", "WORSE", "SAME", "TRADEOFF", "N/A"} for value in decisions),
            "machines": per_machine,
        }
    assessment = pulse_assessment.assess(machine_results)
    return {
        "schema": 2,
        "overall_verdict": assessment["outcome"],
        "assessment": assessment,
        "passed": assessment["complete"] and assessment["outcome"] in ("BETTER", "SAME"),
        "measurement_completed": all(pulse_assessment.measurement_completed(result) for result in machine_results.values()),
        "machines": {
            "windows": compact_machine(windows, windows_code),
            "linux": compact_machine(linux, linux_code),
        },
        "cases": cases,
        "measurements": {
            machine: {
                "machine": result.get("machine", {}),
                "scope": result.get("scope", {}),
                "confirmation_required": result.get("confirmation_required", False),
                "confirmation_preflight_passed": (result.get("confirmation_preflight") or {}).get("passed"),
                "baseline_toolchain": result.get("baseline_toolchain", {}),
                "candidate_toolchain": result.get("candidate_toolchain", {}),
                "stand_preflight_failed": result.get("stand_preflight_failed", False),
                "cases": {
                    name: {
                        "layer": row.get("layer", ""),
                        "verdict": row["verdict"],
                        "final": {key: value for key, value in row.get("final", {}).items() if key != "records"},
                        **({"confirmation": row["confirmation"]} if "confirmation" in row else {}),
                    }
                    for name, row in result.get("cases", {}).items()
                },
            } if result else None
            for machine, result in machine_results.items()
        },
    }


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_report(output: Path, result: dict[str, Any]) -> None:
    pulse_assessment.write_report(output, result["measurements"])


def run() -> int:
    args = parse_args()
    config = load_config(args.config.resolve())
    run_id = time.strftime("pulse-both-%Y%m%d-%H%M%S")
    output = (args.output or ROOT / ".qualification" / run_id).resolve()
    output.mkdir(parents=True, exist_ok=False)
    windows_output = output / "windows"
    linux_output = f"{str(config['linux']['output_root']).rstrip('/')}/{run_id}"

    if not args.skip_sync:
        print("PULSE_BOTH sync=HEL1", flush=True)
        sync_runner(config["linux"])

    windows_args = runner_arguments(
        sys.executable,
        config["windows"],
        str(windows_output),
        args,
    )
    linux_args = runner_arguments("python3", config["linux"], linux_output, args)
    print(f"PULSE_BOTH start output={output}", flush=True)
    with ThreadPoolExecutor(max_workers=2) as executor:
        windows_future = executor.submit(
            run_logged, windows_args, ROOT, output / "windows.log"
        )
        linux_future = executor.submit(
            run_logged,
            remote_command(config["linux"], linux_args),
            ROOT,
            output / "linux.log",
        )
        windows_code = windows_future.result()
        linux_code = linux_future.result()

    linux_local = output / "linux"
    linux_local.mkdir(parents=True, exist_ok=True)
    for name in (
        "result.json",
        "result.raw.json.gz",
        "result.partial.json",
        "REPORT.md",
        "CASES.md",
        "MEASUREMENTS.md",
    ):
        remote = f"{config['linux']['target']}:{linux_output}/{name}"
        subprocess.run(
            pscp_prefix(config["linux"]) + [remote, str(linux_local / name)],
            cwd=ROOT,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    windows_result = read_json(windows_output / "result.json")
    linux_result = read_json(linux_local / "result.json")
    merged = merge_results(windows_result, linux_result, windows_code, linux_code)
    (output / "result.json").write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    write_report(output, merged)
    print(
        f"PULSE_REPORT_READY measurement_completed={merged['measurement_completed']} "
        f"report={output / 'REPORT.md'}",
        flush=True,
    )
    return 0 if merged["measurement_completed"] else 2


if __name__ == "__main__":
    raise SystemExit(run())
