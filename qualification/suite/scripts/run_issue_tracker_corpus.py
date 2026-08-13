#!/usr/bin/env python3
"""Compile every issue-tracker fixture independently and record observations.

This is a discovery runner: the manifest describes the intended oracle, while
the result file records what Delphi 12.2 and MoonBot Compiler actually do.  A
single compiler crash, hang, or unsupported construct cannot hide other cases.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fixtures" / "tracker" / "manifest.json"


def run(command: list[str], cwd: Path, timeout: int) -> dict[str, object]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return {
            "exit_code": result.returncode,
            "timeout": False,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "output": result.stdout.decode("utf-8", errors="replace"),
        }
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or b""
        return {
            "exit_code": None,
            "timeout": True,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "output": output.decode("utf-8", errors="replace"),
        }


def classify_compile(observation: dict[str, object]) -> str:
    if observation["timeout"]:
        return "compile_timeout"
    output = str(observation["output"])
    code = observation["exit_code"]
    if code == 0:
        return "compile_pass"
    if ("Internal error" in output or "F2084" in output or
            "Compilation raised exception internally" in output or
            "compiler AV" in output):
        return "compiler_internal_error"
    if code is not None and int(code) < 0:
        return "compiler_crash"
    return "compile_error"


def classify_run(observation: dict[str, object]) -> str:
    if observation["timeout"]:
        return "run_timeout"
    if observation["exit_code"] != 0:
        return "run_fail"
    return "pass" if "PASS " in str(observation["output"]) else "run_no_pass_marker"


def compiler_run(
    compiler: str,
    compiler_path: Path,
    config: Path | None,
    option: str,
    case: dict[str, object],
    output_root: Path,
    timeout: int,
) -> dict[str, object]:
    case_id = str(case["id"])
    source = ROOT / str(case["source"])
    case_dir = source.parent
    out_dir = (output_root / compiler / option / case_id).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    exe_suffix = ".exe" if os.name == "nt" else ""
    exe = out_dir / (source.stem + exe_suffix)
    if compiler == "delphi":
        studio = compiler_path.parent.parent
        lib = studio / "lib" / "win64" / "release"
        command = [
            str(compiler_path), "-B", "-Q", "-$O+",
            "-U" + str(lib), "-NSSystem",
            "-E" + str(out_dir), "-N0" + str(out_dir), "-NU" + str(out_dir), str(source),
        ]
    else:
        command = [str(compiler_path), "-n"]
        if config is not None:
            command.append("@" + str(config))
        command += ["-B", "-" + option, "-FE" + str(out_dir), "-FU" + str(out_dir), str(source)]
    compiled = run(command, case_dir, timeout)
    result: dict[str, object] = {
        "id": case_id,
        "compiler": compiler,
        "option": option,
        "source": str(source.relative_to(ROOT)).replace(os.sep, "/"),
        "compile": compiled,
        "observed": classify_compile(compiled),
    }
    if compiled["exit_code"] == 0 and not bool(case.get("compile_only")):
        executed = run([str(exe)], case_dir, timeout)
        result["run"] = executed
        result["observed"] = classify_run(executed)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fpc", type=Path, required=True)
    parser.add_argument("--fpc-config", type=Path, required=True)
    parser.add_argument("--delphi", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument(
        "--enforce",
        action="store_true",
        help="fail unless every MoonBot Compiler observation matches the manifest",
    )
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    selected = set(args.case)
    cases = [case for case in manifest["cases"] if not selected or case["id"] in selected]
    jobs: list[tuple[str, Path, Path | None, str, dict[str, object]]] = []
    for case in cases:
        if args.delphi is not None:
            jobs.append(("delphi", args.delphi, None, "optimized", case))
        for option in ("O2", "O3"):
            jobs.append(("fpc", args.fpc, args.fpc_config, option, case))
    def execute(job: tuple[str, Path, Path | None, str, dict[str, object]]) -> dict[str, object]:
        compiler, compiler_path, config, option, case = job
        return compiler_run(
            compiler, compiler_path, config, option, case, args.output, args.timeout
        )
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(execute, jobs))
    summary: dict[str, int] = {}
    mismatches: list[str] = []
    for row in rows:
        key = f"{row['compiler']}/{row['option']}/{row['observed']}"
        summary[key] = summary.get(key, 0) + 1
        if args.enforce and row["compiler"] == "fpc":
            case = next(item for item in cases if item["id"] == row["id"])
            expected = str(case.get(
                "fpc_expected",
                "compile_pass" if case.get("compile_only") else "pass",
            ))
            diagnostic = case.get("expected_diagnostic")
            if row["observed"] != expected:
                mismatches.append(
                    f"{row['id']}/{row['option']}: expected {expected}, "
                    f"observed {row['observed']}"
                )
            elif diagnostic and str(diagnostic) not in str(row["compile"]["output"]):
                mismatches.append(
                    f"{row['id']}/{row['option']}: expected diagnostic missing: "
                    f"{diagnostic}"
                )
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "results.json").write_text(
        json.dumps({"schema": 1, "summary": summary, "rows": rows}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, sort_keys=True))
    if mismatches:
        raise SystemExit("tracker contract mismatch:\n" + "\n".join(mismatches))


if __name__ == "__main__":
    main()
