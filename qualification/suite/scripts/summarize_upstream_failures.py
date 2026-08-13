#!/usr/bin/env python3
"""Build a per-test matrix from unchanged FPC testsuite longlogs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from runner import (
    normalize_upstream_detail,
    parse_upstream_log,
    upstream_test_ids_sha256,
)


SEPARATOR = ">" * 75
HEADINGS = (
    (re.compile(r"^Failed to run (.+?\.pp) .+ \((-?\d+)\)$"), "run_fail"),
    (re.compile(r"^Failed to compile (.+?\.pp) .+$"), "compile_fail"),
    (
        re.compile(r"^Failed, compilation successful (.+?\.pp) .+$"),
        "unexpected_compile_pass",
    ),
)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def classify(outcome: str, detail: str) -> str:
    if outcome == "run_fail":
        return "runtime_failure"
    if outcome == "unexpected_compile_pass":
        return "unexpected_compile_success"
    if re.search(r"error code:\s*-139\b", detail):
        return "compiler_crash"
    if "Can't find unit" in detail:
        return "missing_unit"
    if "Compilation raised exception internally" in detail or "EAccessViolation" in detail:
        return "compiler_exception"
    if "Internal error" in detail:
        return "compiler_internal_error"
    if "treated as error" in detail:
        return "warning_as_error"
    return "compile_error"


def parse_longlog(option: str, path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    rows: list[dict[str, Any]] = []
    for block in text.split(SEPARATOR):
        lines = [line.rstrip() for line in block.strip().splitlines()]
        if not lines:
            continue
        outcome = None
        test_id = None
        exit_code = None
        for pattern, candidate in HEADINGS:
            match = pattern.match(lines[0])
            if match:
                outcome = candidate
                test_id = match.group(1)
                if candidate == "run_fail":
                    exit_code = int(match.group(2))
                break
        if outcome is None or test_id is None:
            continue
        detail = "\n".join(lines[1:]).strip()
        normalized_detail = normalize_upstream_detail(detail)
        first_diagnostic = next(
            (
                normalize_upstream_detail(line.strip())
                for line in lines[1:] if line.strip()
            ),
            "",
        )
        rows.append({
            "test_id": test_id,
            "option": option,
            "outcome": outcome,
            "class": classify(outcome, detail),
            "exit_code": exit_code,
            "first_diagnostic": first_diagnostic,
            "detail_sha256": hashlib.sha256(normalized_detail.encode()).hexdigest(),
            "raw_detail_sha256": hashlib.sha256(detail.encode()).hexdigest(),
            "longlog": str(path),
            "longlog_sha256": file_sha256(path),
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input", action="append", required=True, metavar="OPTION=LONGLOG"
    )
    parser.add_argument(
        "--log", action="append", required=True, metavar="OPTION=LOG"
    )
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--tsv", type=Path, required=True)
    parser.add_argument("--expectations", type=Path)
    parser.add_argument("--source-commit")
    args = parser.parse_args()
    if bool(args.expectations) != bool(args.source_commit):
        parser.error("--expectations and --source-commit must be given together")

    rows: list[dict[str, Any]] = []
    inputs: dict[str, str] = {}
    parsed_failures: dict[str, dict[str, dict[str, Any]]] = {}
    for spec in args.input:
        option, separator, raw_path = spec.partition("=")
        if not separator or not option or not raw_path:
            parser.error(f"invalid --input {spec!r}; expected OPTION=LONGLOG")
        if option in inputs:
            parser.error(f"duplicate --input option {option!r}")
        path = Path(raw_path)
        inputs[option] = str(path)
        option_rows = parse_longlog(option, path)
        rows.extend(option_rows)
        parsed_failures[option] = {
            row["test_id"]: {
                "observed_result": row["outcome"],
                "failure_class": row["class"],
                "exit_code": row["exit_code"],
                "first_diagnostic": row["first_diagnostic"],
                "detail_sha256": row["detail_sha256"],
                "raw_detail_sha256": row["raw_detail_sha256"],
            }
            for row in option_rows
        }

    logs: dict[str, str] = {}
    coverage: dict[str, dict[str, Any]] = {}
    skipped: dict[str, list[str]] = {}
    for spec in args.log:
        option, separator, raw_path = spec.partition("=")
        if not separator or not option or not raw_path:
            parser.error(f"invalid --log {spec!r}; expected OPTION=LOG")
        if option in logs:
            parser.error(f"duplicate --log option {option!r}")
        if option not in parsed_failures:
            parser.error(f"--log option has no matching --input: {option!r}")
        path = Path(raw_path)
        logs[option] = str(path)
        tests, phase_records = parse_upstream_log(path, parsed_failures[option])
        coverage[option] = {
            "unique_tests": len(tests),
            "phase_records": phase_records,
            "test_ids_sha256": upstream_test_ids_sha256(tests),
        }
        skipped[option] = sorted(
            test_id for test_id, detail in tests.items()
            if detail["observed_result"] == "skip"
        )

    if set(logs) != set(parsed_failures):
        parser.error(
            "--input/--log options differ: "
            f"inputs={sorted(parsed_failures)}, logs={sorted(logs)}"
        )
    modes = {option: "full" for option in inputs}

    calibration = {
        option: {
            "log_sha256": file_sha256(Path(logs[option])),
            "longlog_sha256": file_sha256(Path(inputs[option])),
        }
        for option in inputs
    }

    tests: dict[str, dict[str, Any]] = {}
    for row in rows:
        test = tests.setdefault(row["test_id"], {"test_id": row["test_id"]})
        if row["option"] in test:
            raise RuntimeError(
                f"duplicate upstream failure for {row['option']}/{row['test_id']}"
            )
        test[row["option"]] = {
            key: row[key]
            for key in (
                "outcome", "class", "exit_code", "first_diagnostic",
                "detail_sha256", "raw_detail_sha256",
            )
        }

    option_order = [spec.partition("=")[0] for spec in args.input]
    payload = {
        "schema": 1,
        "inputs": inputs,
        "logs": logs,
        "coverage": coverage,
        "calibration": calibration,
        "modes": modes,
        "failure_records": len(rows),
        "unique_tests": len(tests),
        "tests": [tests[key] for key in sorted(tests)],
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    if args.expectations:
        outcomes: dict[str, dict[str, Any]] = {option: {} for option in option_order}
        for row in rows:
            outcomes[row["option"]][row["test_id"]] = {
                "observed_result": row["outcome"],
                "failure_class": row["class"],
                "exit_code": row["exit_code"],
                "first_diagnostic": row["first_diagnostic"],
                "detail_sha256": row["detail_sha256"],
            }
        for option in option_order:
            outcomes[option].update({test_id: "skip" for test_id in skipped[option]})
        args.expectations.parent.mkdir(parents=True, exist_ok=True)
        args.expectations.write_text(
            json.dumps({
                "schema": 2,
                "source_commit": args.source_commit,
                "note": (
                    "Exact failures, skips, and coverage from the unchanged full "
                    "upstream suite; passing tests are omitted."
                ),
                "coverage": coverage,
                "calibration": calibration,
                "modes": modes,
                "outcomes": outcomes,
            }, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    args.tsv.parent.mkdir(parents=True, exist_ok=True)
    with args.tsv.open("w", encoding="utf-8", newline="") as stream:
        fields = ["test_id"] + [
            field
            for option in option_order
            for field in (f"{option}_outcome", f"{option}_class")
        ]
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for test_id in sorted(tests):
            record: dict[str, Any] = {"test_id": test_id}
            for option in option_order:
                outcome = tests[test_id].get(option, {})
                record[f"{option}_outcome"] = outcome.get("outcome", "pass")
                record[f"{option}_class"] = outcome.get("class", "")
            writer.writerow(record)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
