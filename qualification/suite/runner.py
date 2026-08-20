#!/usr/bin/env python3
"""Bounded, low-priority runner for the FPC/Unleashed qualification lab."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import signal
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
MANIFEST_PATH = ROOT / "runner_manifest.json"
COMPILER_PROVENANCE: dict[str, str] = {}


def load_manifest() -> dict[str, Any]:
    with MANIFEST_PATH.open(encoding="utf-8") as stream:
        return json.load(stream)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_clean_git_source(source_root: Path, expected_commit: str | None) -> None:
    """Reject a versioned source checkout whose tree no longer matches HEAD."""
    if expected_commit is None:
        return
    actual = subprocess.run(
        ["git", "-C", str(source_root), "rev-parse", "HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    dirty = subprocess.run(
        ["git", "-C", str(source_root), "status", "--porcelain"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    if actual != expected_commit or dirty:
        raise RuntimeError(
            f"mORMot source is not clean commit {expected_commit}: {source_root}"
        )


def mormot_static_inputs(
    source_root: Path, source: dict[str, Any],
) -> tuple[Path, Path, str]:
    """Resolve the current vendored or historical mORMot static inputs."""
    static_dir = ROOT / source["static_dir"]
    manifest_name = source.get("static_manifest")
    if manifest_name:
        manifest = ROOT / manifest_name
        return static_dir, manifest, sha256(manifest)

    archive = ROOT / source["static_archive"]
    source_static_link = source_root / "static/x86_64-linux"
    if not source_static_link.is_symlink() or source_static_link.resolve() != static_dir.resolve():
        raise RuntimeError(
            f"mORMot static link mismatch: {source_static_link} must resolve to {static_dir}"
        )
    return static_dir, archive, sha256(archive)


def mormot_test_inputs(
    source_root: Path, source: dict[str, Any], work: Path,
) -> tuple[Path, Path]:
    """Stage the matching test tree beside the exact product source tree."""
    configured = source.get("test_path")
    test_root = ROOT / configured if configured else source_root / "test"
    rtsp_ports = source.get("rtsp_ports")
    provenance_source = test_root / "mormot2tests.dpr"
    if not provenance_source.is_file():
        raise RuntimeError(f"mORMot test program is missing: {provenance_source}")
    if not configured and not rtsp_ports:
        return provenance_source, provenance_source

    staged_root = work / "source"
    if staged_root.exists():
        shutil.rmtree(staged_root)
    staged_root.mkdir(parents=True)
    shutil.copytree(test_root, staged_root / "test")
    (staged_root / "src").symlink_to(
        source_root / "src", target_is_directory=True,
    )
    (staged_root / "static").symlink_to(
        source_root / "static", target_is_directory=True,
    )
    if rtsp_ports:
        rtsp_source = staged_root / "test/test.net.proto.pas"
        text = rtsp_source.read_text(encoding="utf-8")
        old = "'3999', '3998'"
        if text.count(old) != 1:
            raise RuntimeError(f"unexpected mORMot RTSP port declaration: {rtsp_source}")
        rtsp_source.write_text(
            text.replace(old, f"'{rtsp_ports[0]}', '{rtsp_ports[1]}'"),
            encoding="utf-8",
        )
    return staged_root / "test/mormot2tests.dpr", provenance_source


def compiler_provenance(compiler: dict[str, Any]) -> str:
    key = compiler["driver"]
    if key in COMPILER_PROVENANCE:
        return COMPILER_PROVENANCE[key]
    driver = Path(key)
    if not driver.is_absolute():
        driver = ROOT / driver
    if not driver.is_file():
        raise RuntimeError(f"compiler driver is missing: {driver}")
    actual = sha256(driver)
    COMPILER_PROVENANCE[key] = actual
    return actual


def compiler_command(compiler: dict[str, Any]) -> list[str]:
    compiler_provenance(compiler)
    driver = Path(compiler["driver"])
    if not driver.is_absolute():
        driver = ROOT / driver
    command = [str(driver)]
    if compiler.get("config"):
        config = Path(compiler["config"])
        if not config.is_absolute():
            config = ROOT / config
        command.extend(["-n", f"@{config}"])
    for arg in compiler.get("base_args", []):
        if arg.startswith("-Fu") and not Path(arg[3:]).is_absolute():
            arg = "-Fu" + str(ROOT / arg[3:])
        command.append(arg)
    return command


def compiler_info(compiler: dict[str, Any]) -> str:
    result = subprocess.run(
        compiler_command(compiler) + ["-iVSPTPSOTODW"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
        check=False,
    )
    return result.stdout.strip()


def expectation_keys(
    compiler_id: str, option: str, fallback_compiler_id: str | None = None,
) -> tuple[str, ...]:
    compiler_ids = (compiler_id, fallback_compiler_id)
    return tuple(
        key for candidate in compiler_ids if candidate
        for key in (f"{candidate}/{option}", f"{candidate}/*")
    ) + (f"*/{option}", "*/*")


def expected_observed(
    test: dict[str, Any], compiler_id: str, option: str,
    fallback_compiler_id: str | None = None,
) -> str:
    table = test.get("expected_observed", {})
    for key in expectation_keys(compiler_id, option, fallback_compiler_id):
        if key in table:
            return table[key]
    return "pass"


def expected_failure_class(
    test: dict[str, Any], compiler_id: str, option: str,
    fallback_compiler_id: str | None = None,
) -> str | None:
    table = test.get("expected_failure_class", {})
    for key in expectation_keys(compiler_id, option, fallback_compiler_id):
        if key in table:
            return table[key]
    return None


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def fixture_case_key(test_id: str, compiler_id: str, option_id: str) -> str:
    return f"{test_id}/{compiler_id}/{option_id}"


def fixture_exact_expectation_compiler(
    manifest: dict[str, Any], compiler_id: str,
) -> str:
    return manifest["compilers"][compiler_id].get(
        "fixture_exact_expectation_alias", compiler_id,
    )


def fixture_compatibility_compiler(
    manifest: dict[str, Any], compiler_id: str,
) -> str:
    compiler = manifest["compilers"][compiler_id]
    return compiler.get("fixture_compatibility_alias", compiler_id)


def fixture_compilers(manifest: dict[str, Any], test: dict[str, Any]) -> list[str]:
    result = list(test.get("compiler_allow", manifest["primary_compilers"]))
    for compiler_id in manifest.get("fixture_qualification_compilers", []):
        if fixture_compatibility_compiler(manifest, compiler_id) in result:
            result.append(compiler_id)
    return result


def fixture_test_provenance(test: dict[str, Any]) -> dict[str, Any]:
    record: dict[str, Any] = {
        "spec_sha256": canonical_sha256(test),
        "source_sha256": sha256(ROOT / test["source"]),
    }
    producer = test.get("producer_source")
    if producer:
        record["producer_source_sha256"] = sha256(ROOT / producer)
    dependencies = test.get("dependencies", [])
    if dependencies:
        record["dependency_sha256"] = {
            dependency: sha256(ROOT / dependency) for dependency in dependencies
        }
    return record


def normalize_fixture_text(text: str, run_dir: Path) -> str:
    text = text.replace(str(ROOT), "<ROOT>")
    run_prefix = "<ROOT>/" + run_dir.relative_to(ROOT).as_posix()
    text = text.replace(run_prefix, "<ROOT>/results/runs/<RUN>")
    text = re.sub(
        r"<ROOT>/toolchains/[^/\s\"']+", "<ROOT>/toolchains/<COMPILER>", text,
    )
    text = re.sub(
        r"(<ROOT>/results/runs/<RUN>/build/[^/\s\"']+/)[^/\s\"']+",
        r"\1<COMPILER>",
        text,
    )
    text = re.sub(
        r"(?m)^((?:Free|Unleashed) Pascal Compiler version "
        r"[^\r\n]*?)\[\d{4}/\d{2}/\d{2}\]",
        r"\1[<BUILD-DATE>]",
        text,
    )
    text = re.sub(
        r"(?m)(An unhandled exception occurred at )\$[0-9A-Fa-f]+:",
        r"\1$<ADDRESS>:",
        text,
    )
    text = re.sub(
        r"(?m)^(\s*)\$[0-9A-Fa-f]+", r"\1$<ADDRESS>", text,
    )
    return text


def normalize_fixture_log(path: Path, run_dir: Path) -> str:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if lines and lines[0].startswith("COMMAND "):
        lines = lines[1:]
    text = "\n".join(lines)
    if lines:
        text += "\n"
    return normalize_fixture_text(text, run_dir)


def normalized_fixture_log_sha256(path: Path | None, run_dir: Path) -> str | None:
    if path is None or not path.is_file():
        return None
    return hashlib.sha256(normalize_fixture_log(path, run_dir).encode()).hexdigest()


def fixture_observation(row: dict[str, Any], run_dir: Path) -> dict[str, Any]:
    compile_failure_log: Path | None = None
    if row["observed_result"].startswith("compile_"):
        if "producer_source" in row:
            key = (
                "producer_compile_log"
                if row.get("failure_phase") == "producer"
                else "consumer_compile_log"
            )
        else:
            key = "compile_log"
        relative = row.get(key)
        if relative:
            compile_failure_log = ROOT / relative
    run_log = ROOT / row["run_log"] if row.get("run_log") else None
    diagnostic = row.get("first_compile_diagnostic")
    if diagnostic:
        diagnostic = normalize_fixture_text(diagnostic, run_dir)
    return {
        "observed_result": row["observed_result"],
        "compile_failure_class": row.get("compile_failure_class"),
        "first_compile_diagnostic": diagnostic,
        "compile_exit_code": row.get("compile_exit_code"),
        "producer_compile_exit_code": row.get("producer_compile_exit_code"),
        "consumer_compile_exit_code": row.get("consumer_compile_exit_code"),
        "run_exit_code": row.get("run_exit_code"),
        "failure_phase": row.get("failure_phase"),
        "options": row["options"],
        "compile_failure_detail_sha256": normalized_fixture_log_sha256(
            compile_failure_log, run_dir,
        ),
        "run_output_sha256": normalized_fixture_log_sha256(run_log, run_dir),
    }


def load_fixture_expectations(
    manifest: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    config = manifest.get("fixture_expectations")
    if not config:
        raise RuntimeError("fixture exact expectations are not configured")
    path = ROOT / config["path"]
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != 1:
        raise RuntimeError(f"invalid fixture expectation schema: {path}")
    return payload["tests"], payload["outcomes"]


def load_fixture_oracles(manifest: dict[str, Any]) -> dict[str, Any]:
    config = manifest.get("fixture_oracles")
    if not config:
        raise RuntimeError("fixture semantic oracles are not configured")
    path = ROOT / config["path"]
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != 1:
        raise RuntimeError(f"invalid fixture oracle schema: {path}")
    return payload["tests"]


def fixture_matrix(manifest: dict[str, Any]) -> set[str]:
    keys: set[str] = set()
    qualification_compilers = set(
        manifest.get("fixture_qualification_compilers", [])
    )
    qualification_exclusions = manifest.get("fixture_qualification_exclusions", {})
    for test in manifest["fixtures"]:
        for compiler_id in fixture_compilers(manifest, test):
            if (
                compiler_id in qualification_compilers
                and test["id"] in qualification_exclusions
            ):
                continue
            for option_id in manifest["option_sets"]:
                if test.get("option_allow") and option_id not in test["option_allow"]:
                    continue
                key = fixture_case_key(
                    test["id"],
                    fixture_exact_expectation_compiler(manifest, compiler_id),
                    option_id,
                )
                if key in keys:
                    raise RuntimeError(f"duplicate fixture matrix key: {key}")
                keys.add(key)
    return keys


def verify_fixture_expectation_contract(
    manifest: dict[str, Any], expected_tests: dict[str, Any],
    expected_outcomes: dict[str, Any],
) -> None:
    tests = {test["id"]: test for test in manifest["fixtures"]}
    if set(expected_tests) != set(tests):
        raise RuntimeError(
            "fixture expectation test inventory differs from the manifest: "
            f"expected={len(expected_tests)} actual={len(tests)}"
        )
    matrix = fixture_matrix(manifest)
    if set(expected_outcomes) != matrix:
        missing = sorted(matrix - set(expected_outcomes))[:20]
        obsolete = sorted(set(expected_outcomes) - matrix)[:20]
        raise RuntimeError(
            "fixture expectation matrix differs from the manifest: "
            f"expected={len(expected_outcomes)} actual={len(matrix)} "
            f"missing={missing} obsolete={obsolete}"
        )


def verify_fixture_oracle_contract(
    manifest: dict[str, Any], oracles: dict[str, Any],
) -> None:
    tests = {test["id"]: test for test in manifest["fixtures"]}
    if set(oracles) != set(tests):
        raise RuntimeError(
            "fixture oracle inventory differs from the manifest: "
            f"expected={len(oracles)} actual={len(tests)}"
        )
    for test_id, test in tests.items():
        oracle = oracles[test_id]
        acceptance = oracle.get("acceptance", {})
        accepted = acceptance.get("observed_result")
        if accepted not in {"pass", "compile_fail"}:
            raise RuntimeError(f"invalid fixture acceptance for {test_id}: {accepted}")
        if not oracle.get("oracle_kind") or not oracle.get("evidence"):
            raise RuntimeError(f"incomplete fixture oracle for {test_id}")
        references = oracle["evidence"].get("independent_references", [])
        if not isinstance(references, list):
            raise RuntimeError(f"invalid fixture references for {test_id}")


def apply_fixture_oracle(row: dict[str, Any], oracle: dict[str, Any]) -> None:
    acceptance = oracle["acceptance"]
    accepted = acceptance["observed_result"]
    accepted_class = acceptance.get("failure_class")
    accepted_diagnostic = acceptance.get("diagnostic_contains")
    semantic_met = row["observed_result"] == accepted
    if accepted_class is not None:
        semantic_met = semantic_met and row.get("compile_failure_class") == accepted_class
    if accepted_diagnostic is not None:
        semantic_met = semantic_met and accepted_diagnostic in (
            row.get("first_compile_diagnostic") or ""
        )
    row.update({
        "expected_result": accepted,
        "expected_semantic_failure_class": accepted_class,
        "expected_semantic_diagnostic_contains": accepted_diagnostic,
        "fixture_oracle_kind": oracle["oracle_kind"],
        "fixture_oracle_evidence": oracle["evidence"],
        "semantic_oracle_met": semantic_met,
        "known_deviation": (
            not semantic_met and row.get("fixture_exact_expectation_met", False)
        ),
    })


def apply_fixture_exact_expectation(
    row: dict[str, Any], run_dir: Path, expected: dict[str, Any],
) -> None:
    observed = fixture_observation(row, run_dir)
    # The exception log contains the resolved ppcx64 path.  Its hash remains
    # evidence, but relocating an editable worktree must not change the gate.
    compared = set(observed) - {"compile_failure_detail_sha256"}
    exact_met = all(observed[key] == expected.get(key) for key in compared)
    row["fixture_observation"] = observed
    row["expected_fixture_observation"] = expected
    row["fixture_exact_expectation_met"] = exact_met
    row["expected_observed_result"] = expected["observed_result"]
    row["expected_failure_class"] = expected["compile_failure_class"]
    row["expected_compile_diagnostic"] = expected["first_compile_diagnostic"]
    row["expectation_met"] = exact_met


def expected_mega_failures(
    test: dict[str, Any], compiler_id: str, option: str,
) -> list[str]:
    table = test.get("expected_failures", {})
    for key in (f"{compiler_id}/{option}", f"{compiler_id}/*", f"*/{option}", "*/*"):
        if key in table:
            return sorted(table[key])
    return []


def expected_mega_fact_failures(
    test: dict[str, Any], compiler_id: str, option: str,
) -> list[str]:
    table = test.get("expected_fact_failures", {})
    for key in (f"{compiler_id}/{option}", f"{compiler_id}/*", f"*/{option}", "*/*"):
        if key in table:
            return sorted(table[key])
    return []


def expected_mega_checks(
    test: dict[str, Any], compiler_id: str, option: str, seed: int,
) -> int:
    table = test["expected_checks"]
    for key in (f"{compiler_id}/{option}", f"{compiler_id}/*", f"*/{option}", "*/*"):
        if key in table:
            return int(table[key][str(seed)])
    raise RuntimeError(
        f"missing mega check-count expectation for {compiler_id}/{option}/{seed}"
    )


def classify_compile_log(path: Path) -> tuple[str | None, str | None]:
    if not path.is_file():
        return None, None
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    text = "\n".join(lines)
    if re.search(r"error code:\s*-139\b", text):
        failure_class = "compiler_crash"
    elif "Compilation raised exception internally" in text or re.search(
        r"\bE(?:AccessViolation|ListError|RangeError)\b", text
    ):
        failure_class = "compiler_exception"
    elif re.search(r"\bInternal error\b", text, re.IGNORECASE):
        failure_class = "compiler_internal_error"
    elif "TIMEOUT after" in text:
        failure_class = "compile_timeout"
    else:
        failure_class = "compile_error"
    # Prefer the diagnostic that identifies an exception/internal error, then
    # the first actionable compiler error over generic terminal lines.
    diagnostic = None
    if failure_class == "compiler_crash":
        diagnostic = next(
            (line.strip() for line in lines if re.search(r"error code:\s*-139\b", line)),
            None,
        )
    elif failure_class == "compiler_exception":
        diagnostic = next(
            (line.strip() for line in lines if "Compilation raised exception internally" in line),
            None,
        )
    elif failure_class == "compiler_internal_error":
        diagnostic = next(
            (line.strip() for line in lines if re.search(r"\bInternal error\b", line, re.IGNORECASE)),
            None,
        )
    if diagnostic is None:
        diagnostic = next(
            (
                line.strip() for line in lines
                if re.search(
                    r"\.(?:pas|pp|p|lpr|dpr)\(\d+(?:,\d+)?\)\s+(?:Error|Fatal):",
                    line,
                    re.IGNORECASE,
                )
            ),
            None,
        )
    if diagnostic is None:
        diagnostic = next(
            (
                line.strip() for line in lines
                if re.search(r"(?:^|\s)Error:", line)
                and "returned an error exitcode" not in line
            ),
            None,
        )
    if diagnostic is None:
        diagnostic = next(
            (line.strip() for line in lines if re.search(r"(?:^|\s)Fatal:", line)),
            None,
        )
    if diagnostic is None:
        diagnostic = next(
            (line.strip() for line in lines if re.search(r"(?:^|\s)Warning:", line)),
            None,
        )
    return failure_class, diagnostic


MEGA_CHECK_RE = re.compile(r"\bcheck=([a-z0-9-]+)")
MEGA_SUMMARY_RE = re.compile(
    r"\bMEGA_(?:SUMMARY|PASS)\s+seed=(\d+)\s+checks=(\d+)\s+"
    r"visits=(\d+)\s+cross=(\d+)\s+peak=(\d+)\s+managed=(\d+)/(\d+)\s+"
    r"portable_checks=(\d+)\s+portable_digest=([0-9A-Fa-f]{16})\b"
)
MEGA_DIRECT_FAILURE_RE = re.compile(
    r"^MEGA_FAIL (phase-(?:ready|copy|done)-timeout|managed-lifetime|"
    r"deterministic-interleave|cross-thread|no-concurrent-overlap)\b",
    re.MULTILINE,
)
MEGA_PORTABLE_FAILURE_RE = re.compile(r"\bEPortableFailure: ([a-z0-9-]+)")
MEGA_EXCEPTION_RE = re.compile(r"\b(E[A-Z]\w+):")
MEGA_FACT_RE = re.compile(r"^MEGA_FACT ([a-z0-9-]+)=(.*)$", re.MULTILINE)


def parse_mega_run(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    failures = set(MEGA_CHECK_RE.findall(text))
    failures.update(MEGA_DIRECT_FAILURE_RE.findall(text))
    failures.update(MEGA_PORTABLE_FAILURE_RE.findall(text))
    for exception_class in MEGA_EXCEPTION_RE.findall(text):
        if exception_class not in {"EMegaFailure", "EPortableFailure"}:
            failures.add("exception:" + exception_class)
    facts: dict[str, str] = {}
    duplicate_facts: list[str] = []
    for name, value in MEGA_FACT_RE.findall(text):
        if name in facts:
            duplicate_facts.append(name)
        facts[name] = value
    summary = MEGA_SUMMARY_RE.search(text)
    return {
        "failures": sorted(failures),
        "completed": summary is not None,
        "seed": int(summary.group(1)) if summary else None,
        "checks": int(summary.group(2)) if summary else None,
        "visits": int(summary.group(3)) if summary else None,
        "cross": int(summary.group(4)) if summary else None,
        "peak": int(summary.group(5)) if summary else None,
        "managed_initializes": int(summary.group(6)) if summary else None,
        "managed_finalizes": int(summary.group(7)) if summary else None,
        "portable_checks": int(summary.group(8)) if summary else None,
        "portable_digest": summary.group(9).upper() if summary else None,
        "facts": dict(sorted(facts.items())),
        "duplicate_facts": sorted(set(duplicate_facts)),
    }


class ResultWriter:
    def __init__(self, run_dir: Path, run_id: str) -> None:
        self.run_dir = run_dir
        self.run_id = run_id
        self.path = run_dir / "results.jsonl"
        self.path.touch()
        self.rows: list[dict[str, Any]] = []

    def add(self, row: dict[str, Any], announce: bool = True) -> None:
        if row.get("semantic_oracle_met") is False:
            row["semantic_result"] = "defect"
        elif row["observed_result"] == row["expected_result"]:
            row["semantic_result"] = "pass"
        elif row["observed_result"] in ("skip", "blocked_by_suite_failure"):
            row["semantic_result"] = "unproven"
        else:
            row["semantic_result"] = "defect"
        row = {"schema": 1, "run_id": self.run_id, **row}
        self.rows.append(row)
        with self.path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, sort_keys=True) + "\n")
        if announce:
            print(
                f"{row['test_id']}: {row['compiler_id']} {row['options_id']} "
                f"observed={row['observed_result']} "
                f"expected={row['expected_observed_result']}"
            )

    def finish(self) -> None:
        counts: dict[str, int] = {}
        measurement_counts: dict[str, int] = {}
        for row in self.rows:
            key = row["observed_result"]
            counts[key] = counts.get(key, 0) + 1
            quality = row.get("measurement_quality")
            if quality is not None:
                measurement_counts[quality] = measurement_counts.get(quality, 0) + 1
        summary = {
            "schema": 1,
            "run_id": self.run_id,
            "rows": len(self.rows),
            "observed_counts": dict(sorted(counts.items())),
            "measurement_quality_counts": dict(sorted(measurement_counts.items())),
            "expectation_mismatches": sum(
                not row["expectation_met"] for row in self.rows
            ),
            "semantic_defects": sum(
                row["semantic_result"] == "defect" for row in self.rows
            ),
            "semantic_passes": sum(
                row["semantic_result"] == "pass" for row in self.rows
            ),
            "unproven": sum(
                row["semantic_result"] == "unproven" for row in self.rows
            ),
            "result_table_sha256": sha256(self.path),
        }
        with (self.run_dir / "summary.json").open("w", encoding="utf-8") as stream:
            json.dump(summary, stream, indent=2, sort_keys=True)
            stream.write("\n")
        print(json.dumps(summary, sort_keys=True))


def run_process(
    command: list[str], cwd: Path, timeout: int, log_path: Path,
    env: dict[str, str] | None = None,
) -> tuple[int | None, bool, float]:
    start = time.monotonic()
    full_command = ["nice", "-n", "15", "ionice", "-c2", "-n7", *command]
    with log_path.open("w", encoding="utf-8") as log:
        log.write("COMMAND " + shlex.join(full_command) + "\n")
        log.flush()
        process = subprocess.Popen(
            full_command,
            cwd=cwd,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            return process.wait(timeout=timeout), False, time.monotonic() - start
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            log.write(f"TIMEOUT after {timeout}s\n")
            return None, True, time.monotonic() - start


def compile_and_run(
    writer: ResultWriter,
    compiler_id: str,
    compiler: dict[str, Any],
    option_id: str,
    options: list[str],
    test: dict[str, Any],
    build_root: Path,
    run_args: list[str] | None = None,
    row_extra: dict[str, Any] | None = None,
    fixture_expected: dict[str, Any] | None = None,
    fixture_oracle: dict[str, Any] | None = None,
    fallback_compiler_id: str | None = None,
) -> None:
    source = ROOT / test["source"]
    test_id = test["id"]
    work = build_root / test_id / compiler_id / option_id
    if run_args:
        suffix = hashlib.sha256("\0".join(run_args).encode()).hexdigest()[:12]
        work = work / suffix
    work.mkdir(parents=True, exist_ok=True)
    compile_log = work / "compile.log"
    run_log = work / "run.log"
    command = compiler_command(compiler)
    command.extend(options)
    command.extend(test.get("extra_options", []))
    command.extend([f"-FE{work}", f"-FU{work}", str(source)])
    compile_rc, compile_timeout, compile_seconds = run_process(
        command, ROOT, test.get("compile_timeout_seconds", 90), compile_log
    )
    run_rc: int | None = None
    run_timeout = False
    run_seconds = 0.0
    if compile_timeout:
        observed = "compile_timeout"
    elif compile_rc != 0:
        observed = "compile_fail"
    elif test.get("compile_only", False):
        observed = "pass"
    else:
        executable = work / source.stem
        run_rc, run_timeout, run_seconds = run_process(
            [str(executable), *(run_args or [])], ROOT,
            test.get("run_timeout_seconds", 90), run_log,
        )
        if run_timeout:
            observed = "run_timeout"
        elif run_rc == 0:
            observed = "pass"
        else:
            observed = "run_fail"
    if fixture_expected is None:
        expected = expected_observed(
            test, compiler_id, option_id, fallback_compiler_id,
        )
        expected_class = expected_failure_class(
            test, compiler_id, option_id, fallback_compiler_id,
        )
    else:
        expected = fixture_expected["observed_result"]
        expected_class = fixture_expected["compile_failure_class"]
    compile_failure_class, first_compile_diagnostic = (
        classify_compile_log(compile_log) if observed.startswith("compile_")
        else (None, None)
    )
    expectation_met = observed == expected and (
        expected_class is None or compile_failure_class == expected_class
    )
    row: dict[str, Any] = {
        "stage": test.get("stage", "fixture"),
        "test_id": test_id,
        "source": str(source.relative_to(ROOT)),
        "source_sha256": sha256(source),
        "compiler_id": compiler_id,
        "compiler_commit": compiler.get("commit", "worktree"),
        "compiler_artifact_sha256": compiler_provenance(compiler),
        "compiler_kind": compiler["kind"],
        "compiler_info": compiler_info(compiler),
        "options_id": option_id,
        "options": options + test.get("extra_options", []),
        "expected_result": "pass",
        "expected_observed_result": expected,
        "observed_result": observed,
        "expectation_met": expectation_met,
        "compile_failure_class": compile_failure_class,
        "expected_failure_class": expected_class,
        "first_compile_diagnostic": first_compile_diagnostic,
        "compile_exit_code": compile_rc,
        "run_exit_code": run_rc,
        "compile_seconds": round(compile_seconds, 6),
        "run_seconds": round(run_seconds, 6),
        "compile_log": str(compile_log.relative_to(ROOT)),
        "run_log": str(run_log.relative_to(ROOT)) if run_log.exists() else None,
    }
    if run_args:
        row["run_args"] = run_args
    if row_extra:
        row.update(row_extra)
    dependencies = test.get("dependencies", [])
    if dependencies:
        row["dependency_sha256"] = {
            dependency: sha256(ROOT / dependency) for dependency in dependencies
        }
    if test.get("stage") == "mega":
        mega_run = parse_mega_run(run_log)
        expectation_compiler = fallback_compiler_id or compiler_id
        expected_failures = expected_mega_failures(
            test, expectation_compiler, option_id,
        )
        row["mega_completed"] = mega_run["completed"]
        row["mega_failures"] = mega_run["failures"]
        row["expected_mega_failures"] = expected_failures
        row["mega_failures_met"] = (
            mega_run["completed"] and mega_run["failures"] == expected_failures
        )
        execution = {
            key: mega_run[key] for key in (
                "visits", "cross", "peak", "managed_initializes", "managed_finalizes"
            )
        }
        row["mega_seed_reported"] = mega_run["seed"]
        row["mega_checks"] = mega_run["checks"]
        expected_checks = expected_mega_checks(
            test, expectation_compiler, option_id, int(row["seed"])
        )
        row["expected_mega_checks"] = expected_checks
        row["mega_checks_met"] = mega_run["checks"] == expected_checks
        row["mega_execution"] = execution
        row["expected_mega_execution"] = test["expected_execution"]
        row["mega_execution_met"] = (
            mega_run["seed"] == int(row["seed"])
            and execution == test["expected_execution"]
        )
        row["portable_checks"] = mega_run["portable_checks"]
        row["portable_digest"] = mega_run["portable_digest"]
        row["mega_facts"] = mega_run["facts"]
        row["mega_duplicate_facts"] = mega_run["duplicate_facts"]
        row["expected_mega_facts"] = test["expected_facts"]
        row["mega_fact_failures"] = sorted(
            key for key in set(mega_run["facts"]) | set(test["expected_facts"])
            if mega_run["facts"].get(key) != test["expected_facts"].get(key)
        )
        row["expected_mega_fact_failures"] = expected_mega_fact_failures(
            test, expectation_compiler, option_id,
        )
        row["mega_fact_failures_met"] = (
            not mega_run["duplicate_facts"]
            and row["mega_fact_failures"] == row["expected_mega_fact_failures"]
        )
        row["mega_facts_met"] = (
            not mega_run["duplicate_facts"]
            and mega_run["facts"] == test["expected_facts"]
        )
        reference = test.get("portable_reference", {}).get(str(row.get("seed")))
        if reference:
            reference_meta = test["portable_reference_meta"]
            row["portable_reference_compiler"] = reference_meta["compiler"]
            row["portable_reference_source_sha256"] = sha256(
                ROOT / reference_meta["source"]
            )
            row["portable_reference_unit_sha256"] = sha256(
                ROOT / reference_meta["unit"]
            )
            row["expected_portable_checks"] = reference["checks"]
            row["expected_portable_digest"] = reference["digest"]
            row["portable_reference_met"] = (
                mega_run["portable_checks"] == reference["checks"]
                and mega_run["portable_digest"] == reference["digest"]
            )
        else:
            row["portable_reference_met"] = False
        row["expectation_met"] = (
            row["expectation_met"] and row["mega_failures_met"]
            and row["mega_checks_met"] and row["mega_execution_met"]
            and row["portable_reference_met"] and row["mega_fact_failures_met"]
        )
        row["semantic_oracle_met"] = (
            mega_run["completed"] and not mega_run["failures"]
            and row["mega_checks_met"] and row["mega_execution_met"]
            and row["portable_reference_met"] and row["mega_facts_met"]
        )
    if fixture_expected is not None:
        apply_fixture_exact_expectation(row, writer.run_dir, fixture_expected)
    if fixture_oracle is not None:
        apply_fixture_oracle(row, fixture_oracle)
    writer.add(row)


def compile_ppu_and_consumer(
    writer: ResultWriter,
    compiler_id: str,
    compiler: dict[str, Any],
    option_id: str,
    options: list[str],
    test: dict[str, Any],
    build_root: Path,
    fixture_expected: dict[str, Any],
    fixture_oracle: dict[str, Any],
) -> None:
    """Compile an optimized producer unit, then consume only its emitted PPU."""
    producer = ROOT / test["producer_source"]
    consumer = ROOT / test["source"]
    test_id = test["id"]
    work = build_root / test_id / compiler_id / option_id
    producer_work = work / "producer"
    consumer_work = work / "consumer"
    producer_work.mkdir(parents=True, exist_ok=True)
    consumer_work.mkdir(parents=True, exist_ok=True)
    producer_log = producer_work / "compile.log"
    consumer_log = consumer_work / "compile.log"
    run_log = consumer_work / "run.log"

    producer_command = compiler_command(compiler)
    producer_command.extend(options)
    producer_command.extend(test.get("producer_extra_options", []))
    producer_command.extend([f"-FU{producer_work}", str(producer)])
    producer_rc, producer_timeout, producer_seconds = run_process(
        producer_command, ROOT, 90, producer_log
    )

    consumer_rc: int | None = None
    consumer_timeout = False
    consumer_seconds = 0.0
    run_rc: int | None = None
    run_timeout = False
    run_seconds = 0.0
    if producer_timeout:
        observed = "compile_timeout"
        failure_phase: str | None = "producer"
    elif producer_rc != 0:
        observed = "compile_fail"
        failure_phase = "producer"
    else:
        consumer_command = compiler_command(compiler)
        consumer_command.extend(options)
        consumer_command.extend(test.get("consumer_extra_options", []))
        consumer_command.extend([
            f"-Fu{producer_work}", f"-FU{consumer_work}",
            f"-FE{consumer_work}", str(consumer),
        ])
        consumer_rc, consumer_timeout, consumer_seconds = run_process(
            consumer_command, ROOT, 90, consumer_log
        )
        if consumer_timeout:
            observed = "compile_timeout"
            failure_phase = "consumer"
        elif consumer_rc != 0:
            observed = "compile_fail"
            failure_phase = "consumer"
        elif test.get("compile_only", False):
            observed = "pass"
            failure_phase = None
        else:
            executable = consumer_work / consumer.stem
            run_rc, run_timeout, run_seconds = run_process(
                [str(executable)], ROOT, 90, run_log
            )
            if run_timeout:
                observed = "run_timeout"
                failure_phase = "run"
            elif run_rc == 0:
                observed = "pass"
                failure_phase = None
            else:
                observed = "run_fail"
                failure_phase = "run"

    expected = fixture_expected["observed_result"]
    failed_compile_log = (
        producer_log if failure_phase == "producer" else consumer_log
    )
    compile_failure_class, first_compile_diagnostic = (
        classify_compile_log(failed_compile_log)
        if observed.startswith("compile_") else (None, None)
    )
    expected_class = fixture_expected["compile_failure_class"]
    expectation_met = observed == expected and (
        expected_class is None or compile_failure_class == expected_class
    )
    row = {
        "stage": test.get("stage", "fixture"),
        "test_id": test_id,
        "source": str(consumer.relative_to(ROOT)),
        "source_sha256": sha256(consumer),
        "producer_source": str(producer.relative_to(ROOT)),
        "producer_source_sha256": sha256(producer),
        "compiler_id": compiler_id,
        "compiler_commit": compiler.get("commit", "worktree"),
        "compiler_artifact_sha256": compiler_provenance(compiler),
        "compiler_kind": compiler["kind"],
        "compiler_info": compiler_info(compiler),
        "options_id": option_id,
        "options": options,
        "expected_result": "pass",
        "expected_observed_result": expected,
        "observed_result": observed,
        "expectation_met": expectation_met,
        "compile_failure_class": compile_failure_class,
        "expected_failure_class": expected_class,
        "first_compile_diagnostic": first_compile_diagnostic,
        "failure_phase": failure_phase,
        "producer_compile_exit_code": producer_rc,
        "consumer_compile_exit_code": consumer_rc,
        "run_exit_code": run_rc,
        "producer_compile_seconds": round(producer_seconds, 6),
        "consumer_compile_seconds": round(consumer_seconds, 6),
        "run_seconds": round(run_seconds, 6),
        "producer_compile_log": str(producer_log.relative_to(ROOT)),
        "consumer_compile_log": (
            str(consumer_log.relative_to(ROOT)) if consumer_log.exists() else None
        ),
        "run_log": str(run_log.relative_to(ROOT)) if run_log.exists() else None,
    }
    apply_fixture_exact_expectation(row, writer.run_dir, fixture_expected)
    apply_fixture_oracle(row, fixture_oracle)
    writer.add(row)


def run_fixtures(
    writer: ResultWriter, manifest: dict[str, Any], compiler_filter: set[str] | None,
    option_filter: set[str] | None, test_filter: set[str] | None,
) -> None:
    expected_tests, expected_outcomes = load_fixture_expectations(manifest)
    oracles = load_fixture_oracles(manifest)
    verify_fixture_expectation_contract(
        manifest, expected_tests, expected_outcomes,
    )
    verify_fixture_oracle_contract(manifest, oracles)
    build_root = writer.run_dir / "build"
    for test in manifest["fixtures"]:
        if test_filter:
            if test["id"] not in test_filter:
                continue
        elif test["id"] in manifest.get("fixture_qualification_exclusions", {}):
            continue
        compiler_ids = fixture_compilers(manifest, test)
        for compiler_id in compiler_ids:
            if compiler_filter and compiler_id not in compiler_filter:
                continue
            compiler = manifest["compilers"][compiler_id]
            for option_id, options in manifest["option_sets"].items():
                if option_filter and option_id not in option_filter:
                    continue
                if test.get("option_allow") and option_id not in test["option_allow"]:
                    continue
                fixture_expected = expected_outcomes[
                    fixture_case_key(
                        test["id"],
                        fixture_exact_expectation_compiler(manifest, compiler_id),
                        option_id,
                    )
                ]
                if test.get("kind") == "ppu_consumer":
                    compile_ppu_and_consumer(
                        writer, compiler_id, compiler, option_id, options,
                        test, build_root, fixture_expected, oracles[test["id"]],
                    )
                else:
                    compile_and_run(
                        writer, compiler_id, compiler, option_id, options,
                        test, build_root, test.get("run_args"),
                        fixture_expected=fixture_expected,
                        fixture_oracle=oracles[test["id"]],
                    )


def run_mega(
    writer: ResultWriter, manifest: dict[str, Any], compiler_filter: set[str] | None,
    option_filter: set[str] | None,
) -> None:
    base = dict(manifest["mega"])
    base["stage"] = "mega"
    reference_meta = base["portable_reference_meta"]
    seeds = base.pop("seeds")
    compiler_ids = base.pop("compiler_ids", manifest["primary_compilers"])
    expectation_aliases = base.pop("expectation_aliases", {})
    option_sets = base.pop("option_sets", manifest["option_sets"])
    build_root = writer.run_dir / "build"
    for compiler_id in compiler_ids:
        if compiler_filter and compiler_id not in compiler_filter:
            continue
        compiler = manifest["compilers"][compiler_id]
        for option_id, options in option_sets.items():
            if option_filter and option_id not in option_filter:
                continue
            for seed in seeds:
                compile_and_run(
                    writer, compiler_id, compiler, option_id, options, base,
                    build_root, [str(seed)], {"seed": seed},
                    fallback_compiler_id=expectation_aliases.get(compiler_id),
                )


BENCH_ORACLE_RE = re.compile(
    r"^ORACLE name=(\S+) iterations=(\d+) digest=([0-9A-F]{16})$",
    re.MULTILINE,
)
BENCH_WARMUP_RE = re.compile(
    r"^BENCH_WARMUP name=(\S+) iterations=(\d+) digest=([0-9A-F]{16})$",
    re.MULTILINE,
)
BENCH_SAMPLE_RE = re.compile(
    r"^BENCH_SAMPLE name=(\S+) sample=(\d+) iterations=(\d+) "
    r"elapsed_ns=(\d+) cpu_ns=(\d+) digest=([0-9A-F]{16})$",
    re.MULTILINE,
)
BENCH_DONE_RE = re.compile(
    r"^BENCH_DONE name=(\S+) samples=(\d+)$", re.MULTILINE,
)


def read_optional_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def benchmark_host_info(affinity_cpu: int) -> dict[str, Any]:
    cpu_model = None
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.is_file():
        for line in cpuinfo.read_text(errors="replace").splitlines():
            if line.lower().startswith("model name") and ":" in line:
                cpu_model = line.split(":", 1)[1].strip()
                break
    uname = platform.uname()
    cpu_root = Path(f"/sys/devices/system/cpu/cpu{affinity_cpu}")
    return {
        "system": uname.system,
        "release": uname.release,
        "machine": uname.machine,
        "node": uname.node,
        "processor": uname.processor,
        "cpu_model": cpu_model,
        "logical_cpu_count": os.cpu_count(),
        "performance_affinity_cpu": affinity_cpu,
        "process_allowed_cpus": sorted(os.sched_getaffinity(0)),
        "thread_siblings": read_optional_text(
            cpu_root / "topology" / "thread_siblings_list"
        ),
        "smt_active": read_optional_text(Path("/sys/devices/system/cpu/smt/active")),
        "cpufreq_driver": read_optional_text(
            cpu_root / "cpufreq" / "scaling_driver"
        ),
        "cpufreq_governor": read_optional_text(
            cpu_root / "cpufreq" / "scaling_governor"
        ),
        "cpufreq_min_khz": read_optional_text(
            cpu_root / "cpufreq" / "scaling_min_freq"
        ),
        "cpufreq_max_khz": read_optional_text(
            cpu_root / "cpufreq" / "scaling_max_freq"
        ),
    }


def load_benchmark_oracle_proof(
    test: dict[str, Any],
) -> tuple[Path, dict[tuple[str, int], str]]:
    proof = ROOT / test["long_oracle_proof"]
    with proof.open(encoding="utf-8") as stream:
        payload = json.load(stream)
    if (
        payload.get("schema") != 1
        or payload.get("oracle_source") != test["oracle"]
    ):
        raise RuntimeError(f"invalid benchmark oracle proof provenance: {proof}")
    digests: dict[tuple[str, int], str] = {}
    for result in payload.get("results", []):
        key = (result["name"], int(result["iterations"]))
        if key in digests:
            raise RuntimeError(f"duplicate benchmark oracle proof row: {key}")
        digests[key] = result["digest"]
    return proof, digests


def parse_benchmark_run(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    warmups = [
        {"name": name, "iterations": int(iterations), "digest": digest}
        for name, iterations, digest in BENCH_WARMUP_RE.findall(text)
    ]
    samples = [
        {
            "name": name,
            "sample": int(sample),
            "iterations": int(iterations),
            "elapsed_ns": int(elapsed_ns),
            "cpu_ns": int(cpu_ns),
            "digest": digest,
        }
        for name, sample, iterations, elapsed_ns, cpu_ns, digest
        in BENCH_SAMPLE_RE.findall(text)
    ]
    dones = [
        {"name": name, "samples": int(sample_count)}
        for name, sample_count in BENCH_DONE_RE.findall(text)
    ]
    return {"warmups": warmups, "samples": samples, "dones": dones}


def benchmark_run_met(
    parsed: dict[str, Any], name: str, iterations: int, samples: int,
    warmup_digest: str, digest: str,
) -> bool:
    warmup_iterations = max(1, iterations // 16)
    return (
        parsed["warmups"] == [{
            "name": name,
            "iterations": warmup_iterations,
            "digest": warmup_digest,
        }]
        and parsed["dones"] == [{"name": name, "samples": samples}]
        and len(parsed["samples"]) == samples
        and all(
            sample["name"] == name
            and sample["sample"] == index
            and sample["iterations"] == iterations
            and sample["elapsed_ns"] > 0
            and sample["cpu_ns"] > 0
            and sample["digest"] == digest
            for index, sample in enumerate(parsed["samples"], 1)
        )
    )


def run_benchmark_oracle(
    oracle: Path, name: str, iterations: int, log: Path, timeout: int,
) -> str:
    rc, timed_out, _ = run_process(
        [sys.executable, str(oracle), name, str(iterations)], ROOT, timeout, log,
    )
    if timed_out or rc != 0:
        raise RuntimeError(
            f"benchmark oracle failed for {name}/{iterations}: "
            f"exit={rc} timeout={timed_out} log={log}"
        )
    text = log.read_text(encoding="utf-8", errors="replace")
    matches = BENCH_ORACLE_RE.findall(text)
    if len(matches) != 1 or matches[0][:2] != (name, str(iterations)):
        raise RuntimeError(
            f"invalid benchmark oracle output for {name}/{iterations}: {matches}"
        )
    return matches[0][2]


def run_benchmark(
    writer: ResultWriter, manifest: dict[str, Any], compiler_filter: set[str] | None,
    option_filter: set[str] | None, test_filter: set[str] | None,
) -> None:
    test = manifest["benchmark"]
    source = ROOT / test["source"]
    oracle = ROOT / test["oracle"]

    affinity_cpu = int(test["performance_affinity_cpu"])
    if shutil.which("taskset") is None:
        raise RuntimeError("taskset is required for pinned benchmark runs")
    if affinity_cpu not in os.sched_getaffinity(0):
        raise RuntimeError(f"benchmark CPU {affinity_cpu} is outside process affinity")
    oracle_proof, oracle_proof_digests = load_benchmark_oracle_proof(test)

    workloads = {
        name: workload for name, workload in test["workloads"].items()
        if not test_filter or f"benchmark-{name}" in test_filter
    }
    if not workloads:
        return

    oracle_dir = writer.run_dir / "benchmark-oracle"
    oracle_dir.mkdir(parents=True, exist_ok=True)
    oracle_results: dict[tuple[str, int], tuple[str, Path]] = {}
    for name, workload in workloads.items():
        iterations = int(workload["iterations"])
        for count in sorted({
            max(1, test["oracle_iterations"] // 16),
            test["oracle_iterations"],
        }):
            key = (name, count)
            if key in oracle_results:
                continue
            log = oracle_dir / f"{name}-{count}.log"
            oracle_results[key] = (
                run_benchmark_oracle(
                    oracle, name, count, log, test["run_timeout_seconds"] * 4,
                ),
                log,
            )
        if oracle_results[(name, test["oracle_iterations"])][0] != workload[
            "oracle_digest"
        ]:
            raise RuntimeError(f"benchmark oracle digest mismatch: {name}")
        for count in (max(1, iterations // 16), iterations):
            if (name, count) not in oracle_proof_digests:
                raise RuntimeError(
                    f"benchmark oracle proof row missing: {name}/{count}"
                )

    host = benchmark_host_info(affinity_cpu)
    build_root = writer.run_dir / "benchmark-build"
    option_sets = test.get("option_sets", manifest["option_sets"])
    for compiler_id in test["compiler_ids"]:
        if compiler_filter and compiler_id not in compiler_filter:
            continue
        compiler = manifest["compilers"][compiler_id]
        for option_id, options in option_sets.items():
            if option_filter and option_id not in option_filter:
                continue
            work = build_root / compiler_id / option_id
            units = work / "units"
            units.mkdir(parents=True, exist_ok=True)
            executable = work / source.stem
            compile_log = work / "compile.log"
            command = compiler_command(compiler)
            command.extend(options)
            command.extend(test["extra_options"])
            command.extend([
                f"-Fu{source.parent}", f"-FU{units}", f"-FE{work}",
                f"-o{executable}", str(source),
            ])
            compile_rc, compile_timeout, compile_seconds = run_process(
                command, ROOT, test["compile_timeout_seconds"], compile_log,
            )
            if compile_timeout:
                compile_observed = "compile_timeout"
            elif compile_rc != 0:
                compile_observed = "compile_fail"
            else:
                compile_observed = "pass"
            compile_failure_class, first_compile_diagnostic = (
                classify_compile_log(compile_log)
                if compile_observed.startswith("compile_") else (None, None)
            )
            info = compiler_info(compiler)
            artifact_hash = compiler_provenance(compiler)
            executable_hash = sha256(executable) if executable.is_file() else None

            for name, workload in workloads.items():
                test_id = f"benchmark-{name}"
                iterations = int(workload["iterations"])
                samples = int(test["samples"])
                warmup_digest = oracle_proof_digests[
                    (name, max(1, iterations // 16))
                ]
                performance_digest = oracle_proof_digests[(name, iterations)]
                oracle_iterations = int(test["oracle_iterations"])
                oracle_run_log = work / f"{name}-oracle.log"
                performance_log = work / f"{name}-performance.log"
                run_rc: int | None = None
                run_timeout = False
                run_seconds = 0.0
                oracle_run_rc: int | None = None
                oracle_run_timeout = False
                oracle_run_seconds = 0.0
                oracle_parsed = {"warmups": [], "samples": [], "dones": []}
                performance_parsed = {"warmups": [], "samples": [], "dones": []}
                if compile_observed != "pass":
                    observed = compile_observed
                else:
                    oracle_run_rc, oracle_run_timeout, oracle_run_seconds = run_process(
                        [str(executable), name, str(oracle_iterations), "1"],
                        ROOT, test["run_timeout_seconds"], oracle_run_log,
                    )
                    if oracle_run_timeout:
                        observed = "run_timeout"
                    elif oracle_run_rc != 0:
                        observed = "run_fail"
                    else:
                        run_rc, run_timeout, run_seconds = run_process(
                            [
                                "taskset", "-c", str(affinity_cpu),
                                str(executable), name, str(iterations), str(samples),
                            ],
                            ROOT, test["run_timeout_seconds"], performance_log,
                        )
                        if run_timeout:
                            observed = "run_timeout"
                        elif run_rc != 0:
                            observed = "run_fail"
                        else:
                            observed = "pass"
                    oracle_parsed = parse_benchmark_run(oracle_run_log)
                    performance_parsed = parse_benchmark_run(performance_log)

                oracle_met = benchmark_run_met(
                    oracle_parsed, name, oracle_iterations, 1,
                    oracle_results[(name, max(1, oracle_iterations // 16))][0],
                    workload["oracle_digest"],
                )
                performance_met = benchmark_run_met(
                    performance_parsed, name, iterations, samples,
                    warmup_digest, performance_digest,
                )
                semantic_met = (
                    observed == "pass" and oracle_met and performance_met
                )
                elapsed = [
                    sample["elapsed_ns"] for sample in performance_parsed["samples"]
                ]
                cpu = [
                    sample["cpu_ns"] for sample in performance_parsed["samples"]
                ]
                median_ns = int(statistics.median(elapsed)) if elapsed else None
                median_cpu_ns = int(statistics.median(cpu)) if cpu else None
                sorted_cpu = sorted(cpu)
                best3_elapsed_ns = (
                    int(statistics.median(sorted(elapsed)[:3])) if elapsed else None
                )
                best3_cpu_ns = (
                    int(statistics.median(sorted_cpu[:3])) if cpu else None
                )
                cpu_spread_ratio = (
                    round(max(cpu) / min(cpu), 6) if cpu else None
                )
                best3_stability_ratio = (
                    round(sorted_cpu[2] / sorted_cpu[1], 6)
                    if len(sorted_cpu) >= 3 else None
                )
                if not semantic_met or best3_stability_ratio is None:
                    measurement_quality = "unavailable"
                elif best3_stability_ratio <= test["max_best3_stability_ratio"]:
                    measurement_quality = "pass"
                else:
                    measurement_quality = "noisy"
                expected = expected_observed(test, compiler_id, option_id)
                writer.add({
                    "stage": "benchmark",
                    "test_id": test_id,
                    "benchmark_kind": workload["kind"],
                    "source": str(source.relative_to(ROOT)),
                    "source_sha256": sha256(source),
                    "dependency_sha256": {
                        path: sha256(ROOT / path) for path in test["dependencies"]
                    },
                    "oracle_source": str(oracle.relative_to(ROOT)),
                    "oracle_source_sha256": sha256(oracle),
                    "long_oracle_proof": str(oracle_proof.relative_to(ROOT)),
                    "long_oracle_proof_sha256": sha256(oracle_proof),
                    "independent_oracle_logs": {
                        str(count): str(log.relative_to(ROOT))
                        for (oracle_name, count), (_, log) in oracle_results.items()
                        if oracle_name == name
                    },
                    "compiler_id": compiler_id,
                    "compiler_commit": compiler.get("commit", "worktree"),
                    "compiler_artifact_sha256": artifact_hash,
                    "compiler_kind": compiler["kind"],
                    "compiler_info": info,
                    "executable_sha256": executable_hash,
                    "options_id": option_id,
                    "options": options + test["extra_options"],
                    "expected_result": "pass",
                    "expected_observed_result": expected,
                    "observed_result": observed,
                    "expectation_met": observed == expected and semantic_met,
                    "semantic_oracle_met": semantic_met,
                    "compile_failure_class": compile_failure_class,
                    "first_compile_diagnostic": first_compile_diagnostic,
                    "compile_exit_code": compile_rc,
                    "oracle_run_exit_code": oracle_run_rc,
                    "run_exit_code": run_rc,
                    "compile_seconds": round(compile_seconds, 6),
                    "oracle_run_seconds": round(oracle_run_seconds, 6),
                    "run_seconds": round(run_seconds, 6),
                    "compile_log": str(compile_log.relative_to(ROOT)),
                    "oracle_run_log": (
                        str(oracle_run_log.relative_to(ROOT))
                        if oracle_run_log.exists() else None
                    ),
                    "run_log": (
                        str(performance_log.relative_to(ROOT))
                        if performance_log.exists() else None
                    ),
                    "benchmark_host": host,
                    "performance_affinity_cpu": affinity_cpu,
                    "oracle_iterations": oracle_iterations,
                    "oracle_digest": workload["oracle_digest"],
                    "oracle_run_met": oracle_met,
                    "iterations": iterations,
                    "samples": samples,
                    "warmup_digest": warmup_digest,
                    "performance_digest": performance_digest,
                    "performance_run_met": performance_met,
                    "measurement_quality": measurement_quality,
                    "cpu_spread_ratio": cpu_spread_ratio,
                    "best3_stability_ratio": best3_stability_ratio,
                    "max_best3_stability_ratio": test[
                        "max_best3_stability_ratio"
                    ],
                    "elapsed_samples_ns": elapsed,
                    "cpu_samples_ns": cpu,
                    "median_elapsed_ns": median_ns,
                    "median_cpu_ns": median_cpu_ns,
                    "min_elapsed_ns": min(elapsed) if elapsed else None,
                    "max_elapsed_ns": max(elapsed) if elapsed else None,
                    "min_cpu_ns": min(cpu) if cpu else None,
                    "max_cpu_ns": max(cpu) if cpu else None,
                    "primary_performance_metric": (
                        "best3_median_cpu_ns_per_iteration"
                    ),
                    "min_elapsed_ns_per_iteration": (
                        round(min(elapsed) / iterations, 9) if elapsed else None
                    ),
                    "min_cpu_ns_per_iteration": (
                        round(min(cpu) / iterations, 9) if cpu else None
                    ),
                    "median_ns_per_iteration": (
                        round(median_ns / iterations, 9) if median_ns else None
                    ),
                    "median_iterations_per_second": (
                        round(iterations * 1_000_000_000 / median_ns, 3)
                        if median_ns else None
                    ),
                    "median_cpu_ns_per_iteration": (
                        round(median_cpu_ns / iterations, 9)
                        if median_cpu_ns else None
                    ),
                    "median_cpu_iterations_per_second": (
                        round(iterations * 1_000_000_000 / median_cpu_ns, 3)
                        if median_cpu_ns else None
                    ),
                    "best3_median_elapsed_ns": best3_elapsed_ns,
                    "best3_median_cpu_ns": best3_cpu_ns,
                    "best3_median_ns_per_iteration": (
                        round(best3_elapsed_ns / iterations, 9)
                        if best3_elapsed_ns else None
                    ),
                    "best3_median_cpu_ns_per_iteration": (
                        round(best3_cpu_ns / iterations, 9)
                        if best3_cpu_ns else None
                    ),
                })


UPSTREAM_SEPARATOR = ">" * 75
UPSTREAM_FAILURE_HEADINGS = (
    (re.compile(r"^Failed to run (.+?\.pp) .+ \((-?\d+)\)$"), "run_fail"),
    (re.compile(r"^Failed to compile (.+?\.pp) .+$"), "compile_fail"),
    (
        re.compile(r"^Failed, compilation successful (.+?\.pp) .+$"),
        "unexpected_compile_pass",
    ),
)
UPSTREAM_LOG_LINE = re.compile(
    r"^(.*?) (\S+\.pp) [0-9]{4}/[0-9]{2}/[0-9]{2}"
)


def normalize_upstream_detail(text: str) -> str:
    text = text.replace(str(ROOT), "<ROOT>")
    text = re.sub(
        r"<ROOT>/toolchains/[^/\s\"']+", "<ROOT>/toolchains/<COMPILER>", text,
    )
    text = re.sub(r"\bTime:\d+\.\d+(?=\s+N:)", "Time:<elapsed>", text)
    text = re.sub(r"(?m)^(\s*)\d+\.\d{3}(\s+)", r"\1<elapsed>\2", text)
    text = re.sub(
        r"(?i)(\b(?:at|block)\s+)\$[0-9a-f]+", r"\1$<address>", text,
    )
    text = re.sub(r"(?m)^(\s*)\$[0-9A-Fa-f]+", r"\1$<address>", text)
    runtime_error_216 = "Runtime error 216 at $<address>\n  $<address>\n"
    offset = 0
    while text.startswith(runtime_error_216, offset):
        offset += len(runtime_error_216)
    tail = text[offset:]
    if tail == runtime_error_216.rstrip("\n"):
        offset += len(runtime_error_216)
        tail = ""
    if offset >= 2 * len(runtime_error_216) and runtime_error_216.startswith(tail):
        text = runtime_error_216 + "<repeated>\n"
    text = re.sub(
        r"\bThread \d+(?=\s+Released lock\b)", "Thread <id>", text,
    )
    text = re.sub(
        r"(?m)^\d+(?=: Thread <id> Released lock$)", "<tick>", text,
    )
    text = re.sub(r"\bchunk[0-9A-Za-z]+\b", "chunk<id>", text)
    return re.sub(r"\bfpc_[0-9A-Fa-f]+\.tmp\b", "fpc_<id>.tmp", text)


def parse_upstream_longlog(path: Path) -> dict[str, dict[str, Any]]:
    failures: dict[str, dict[str, Any]] = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    for block in text.split(UPSTREAM_SEPARATOR):
        lines = [line.rstrip() for line in block.strip().splitlines()]
        if not lines:
            continue
        for pattern, outcome in UPSTREAM_FAILURE_HEADINGS:
            match = pattern.match(lines[0])
            if not match:
                continue
            detail = "\n".join(lines[1:]).strip()
            if outcome == "run_fail":
                failure_class = "runtime_failure"
                exit_code: int | None = int(match.group(2))
            elif outcome == "unexpected_compile_pass":
                failure_class = "unexpected_compile_success"
                exit_code = None
            elif re.search(r"error code:\s*-139\b", detail):
                failure_class = "compiler_crash"
                exit_code = None
            elif "Can't find unit" in detail:
                failure_class = "missing_unit"
                exit_code = None
            elif (
                "Compilation raised exception internally" in detail
                or "EAccessViolation" in detail
            ):
                failure_class = "compiler_exception"
                exit_code = None
            elif "Internal error" in detail:
                failure_class = "compiler_internal_error"
                exit_code = None
            elif "treated as error" in detail:
                failure_class = "warning_as_error"
                exit_code = None
            else:
                failure_class = "compile_error"
                exit_code = None
            normalized_detail = normalize_upstream_detail(detail)
            test_id = match.group(1)
            if test_id in failures:
                raise RuntimeError(f"duplicate upstream failure for {test_id} in {path}")
            failures[test_id] = {
                "observed_result": outcome,
                "failure_class": failure_class,
                "exit_code": exit_code,
                "first_diagnostic": next(
                    (
                        normalize_upstream_detail(line.strip())
                        for line in lines[1:] if line.strip()
                    ),
                    "",
                ),
                "detail_sha256": hashlib.sha256(normalized_detail.encode()).hexdigest(),
                "raw_detail_sha256": hashlib.sha256(detail.encode()).hexdigest(),
            }
            break
    return failures


def parse_upstream_log(
    path: Path, failures: dict[str, dict[str, Any]],
) -> tuple[dict[str, dict[str, Any]], int]:
    tests: dict[str, dict[str, Any]] = {}
    phase_records = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = UPSTREAM_LOG_LINE.match(line)
        if not match:
            continue
        phase_records += 1
        status, test_id = match.groups()
        if status.startswith("Skipping test"):
            detail = {"observed_result": "skip"}
        elif status.startswith("Success, compilation failed"):
            detail = {"observed_result": "pass"}
        elif status.startswith("Successfully compiled"):
            detail = {"observed_result": "pass"}
        elif status.startswith("Successfully run"):
            detail = {"observed_result": "pass"}
        elif status.startswith("Failed to compile"):
            detail = failures.get(
                test_id, {"observed_result": "compile_fail"}
            )
        elif status.startswith("Failed to run"):
            detail = failures.get(test_id, {"observed_result": "run_fail"})
        elif status.startswith("Failed, compilation successful"):
            detail = failures.get(
                test_id, {"observed_result": "unexpected_compile_pass"}
            )
        else:
            continue
        previous = tests.get(test_id)
        if (
            previous is None or previous["observed_result"] == "skip"
            or detail["observed_result"] not in ("pass", "skip")
        ):
            tests[test_id] = detail
    missing_failures = sorted(set(failures) - set(tests))
    missing_details = sorted(
        test_id for test_id, detail in tests.items()
        if detail["observed_result"] not in ("pass", "skip")
        and test_id not in failures
    )
    if missing_failures or missing_details:
        raise RuntimeError(
            f"upstream short/long log mismatch in {path}: "
            f"missing failures={missing_failures}, missing details={missing_details}"
        )
    return tests, phase_records


def upstream_test_ids_sha256(tests: dict[str, dict[str, Any]]) -> str:
    payload = "".join(test_id + "\n" for test_id in sorted(tests))
    return hashlib.sha256(payload.encode()).hexdigest()


def require_same_upstream_test_set(
    reference: dict[str, Any], current: dict[str, Any], compiler_id: str,
) -> None:
    fields = ("unique_tests", "test_ids_sha256")
    if any(reference[key] != current[key] for key in fields):
        raise RuntimeError(
            f"upstream test-set mismatch between options for {compiler_id}: "
            f"first {reference}, current {current}"
        )


def exact_upstream_failure(
    detail: dict[str, Any], observed: str, expected: Any,
) -> bool:
    return (
        isinstance(expected, dict)
        and expected.get("observed_result") == observed
        and all(
            detail.get(key) == expected.get(key)
            for key in ("failure_class", "exit_code", "first_diagnostic")
        )
    )


def upstream_expected_record(
    upstream: dict[str, Any], expected_map: dict[str, Any], option_id: str,
    test_id: str, observed: str,
) -> tuple[str | dict[str, Any], bool]:
    known = upstream.get("known_deviations", {}).get(option_id, {}).get(test_id)
    if known is not None:
        return known, True
    if observed == "pass":
        return "pass", False
    return expected_map.get(test_id, "pass"), False


def upstream_delphi_contract(source: Path) -> bool:
    text = source.read_text(encoding="utf-8", errors="replace")
    if re.search(r"\{\$\s*modeswitch\s+nestedprocvars\b", text, re.IGNORECASE):
        return False
    mode = re.search(r"\{\$\s*mode\s+([a-z0-9_]+)", text, re.IGNORECASE)
    if mode:
        return mode.group(1).lower() in {"delphi", "delphiunicode"}
    return bool(re.search(
        r"%\s*opt[^\r\n]*(?:-Mdelphi\b|-Sd\b)", text, re.IGNORECASE,
    ))


def upstream_target_exclusion(source: Path, target: str) -> str | None:
    text = source.read_text(encoding="utf-8", errors="replace")

    def targets(directive: str) -> set[str]:
        match = re.search(
            rf"%\s*{directive}\s*=\s*([^}}\r\n]+)", text, re.IGNORECASE,
        )
        if not match:
            return set()
        return {
            item.strip().lower()
            for item in match.group(1).split(",")
            if item.strip()
        }

    normalized = target.lower()
    only_targets = targets("TARGET")
    if only_targets and normalized not in only_targets:
        return f"upstream target directive excludes {target}"
    if normalized in targets("SKIPTARGET"):
        return f"upstream skip-target directive excludes {target}"
    return None


def run_upstream_case(
    writer: ResultWriter, manifest: dict[str, Any], compiler_id: str,
    option_id: str, options: list[str],
) -> dict[str, Any]:
    upstream = manifest["upstream"]
    compiler = manifest["compilers"][compiler_id]
    source_root = ROOT / upstream["path"]
    compiler_artifact_sha256 = compiler_provenance(compiler)
    expected_path = ROOT / upstream["expected_outcomes"]
    expected_payload = json.loads(expected_path.read_text(encoding="utf-8"))
    if expected_payload.get("schema") != 2:
        raise RuntimeError(f"invalid upstream expectations: {expected_path}")
    expected_map = expected_payload["outcomes"][option_id]

    snapshot = writer.run_dir / "upstream" / compiler_id / option_id
    snapshot.mkdir(parents=True, exist_ok=True)
    temp_dir = snapshot / "tmp"
    temp_dir.mkdir()
    clean_log = snapshot / "source-clean.log"
    full_log = snapshot / "full.log"
    driver = str(ROOT / compiler["driver"])
    test_options = [*options, *upstream.get("test_support_options", [])]
    jobs = int(upstream.get("jobs", 1))
    if jobs < 1 or jobs > len(os.sched_getaffinity(0)):
        raise RuntimeError(f"invalid upstream job count: {jobs}")
    clean_command = [
        "make", "-C", str(source_root), "-j1", "clean", f"FPC={driver}",
    ]
    command = [
        "make", "-C", str(source_root / "tests"), f"-j{jobs}", "full",
        f"FPC={driver}", f"TEST_FPC={driver}",
        f"NATIVE_FPC={driver}", "TEST_OPT=" + " ".join(test_options),
        "OPT=" + " ".join(upstream.get("host_support_options", [])),
        "TEST_DELTEMP=1",
    ]
    env = os.environ.copy()
    env["QUICKTEST"] = "1"
    env["TMPDIR"] = str(temp_dir)
    env["PATH"] = str((ROOT / compiler["driver"]).parent) + os.pathsep + env["PATH"]
    if compiler.get("config"):
        env["PPC_CONFIG_PATH"] = str((ROOT / compiler["config"]).parent)
    clean_rc, clean_timeout, clean_seconds = run_process(
        clean_command, ROOT, upstream.get("clean_timeout_seconds", 600), clean_log, env,
    )
    if clean_timeout or clean_rc != 0:
        reason = "timed out" if clean_timeout else f"failed with exit {clean_rc}"
        raise RuntimeError(
            f"upstream source cleanup {reason}: {compiler_id}/{option_id}"
        )
    make_rc, make_timeout, make_seconds = run_process(
        command, ROOT, upstream.get("timeout_seconds", 1800), full_log, env,
    )
    if make_timeout:
        raise RuntimeError(f"upstream suite timed out: {compiler_id}/{option_id}")
    if make_rc != 0:
        raise RuntimeError(
            f"upstream core suite failed with exit {make_rc}: "
            f"{compiler_id}/{option_id}"
        )
    output = source_root / "tests/output/x86_64-linux"
    for name in ("log", "longlog", "faillist"):
        source = output / name
        if not source.is_file():
            raise RuntimeError(
                f"upstream suite produced no {name}: {compiler_id}/{option_id}; "
                f"make exit {make_rc}"
            )
        shutil.copy2(source, snapshot / name)

    log_path = snapshot / "log"
    longlog_path = snapshot / "longlog"
    failures = parse_upstream_longlog(longlog_path)
    tests, phase_records = parse_upstream_log(log_path, failures)
    coverage = {
        "unique_tests": len(tests),
        "phase_records": phase_records,
        "test_ids_sha256": upstream_test_ids_sha256(tests),
    }
    if not tests or phase_records < len(tests):
        raise RuntimeError(
            f"incomplete upstream log for {compiler_id}/{option_id}: {coverage}"
        )
    compiler_version = compiler_info(compiler)
    suite_source = source_root / "tests/Makefile"
    writer.add({
        "stage": "upstream-suite",
        "test_id": "upstream:suite-build",
        "source": str(suite_source.relative_to(ROOT)),
        "source_sha256": sha256(suite_source),
        "source_commit": "worktree",
        "compiler_id": compiler_id,
        "compiler_commit": compiler.get("commit", "worktree"),
        "compiler_artifact_sha256": compiler_artifact_sha256,
        "compiler_kind": compiler["kind"],
        "compiler_info": compiler_version,
        "options_id": option_id,
        "options": test_options,
        "expected_result": "pass",
        "expected_observed_result": "pass",
        "observed_result": "pass",
        "expectation_met": True,
        "compile_failure_class": None,
        "expected_failure_class": None,
        "first_compile_diagnostic": None,
        "compile_exit_code": make_rc,
        "run_exit_code": None,
        "compile_seconds": round(make_seconds, 6),
        "run_seconds": 0.0,
        "compile_log": str(full_log.relative_to(ROOT)),
        "run_log": None,
        "suite_mode": "core",
    })
    counts: dict[str, int] = {}
    mismatches = 0
    for test_id in sorted(tests):
        detail = tests[test_id]
        observed = detail["observed_result"]
        source_link = source_root / "tests" / test_id
        source = source_link.resolve()
        if not source.is_file():
            raise RuntimeError(f"upstream log references missing source: {source}")
        core_profile_exclusion = upstream.get("core_profile_exclusions", {}).get(
            test_id
        )
        contract_exclusion = upstream.get("delphi_contract_exclusions", {}).get(
            test_id
        )
        missing_package_unit = detail.get("failure_class") == "missing_unit"
        warning_as_error = detail.get("failure_class") == "warning_as_error"
        outside_contract = not upstream_delphi_contract(source)
        target_exclusion = upstream_target_exclusion(source, "linux")
        expected_failure = expected_map.get(test_id)
        exact_policy_failure = exact_upstream_failure(
            detail, observed, expected_failure,
        )
        excluded_reason: str | None = None
        if core_profile_exclusion:
            excluded_reason = core_profile_exclusion
        elif contract_exclusion:
            excluded_reason = contract_exclusion
        elif target_exclusion:
            excluded_reason = target_exclusion
        elif outside_contract:
            excluded_reason = "outside the Delphi application contract"
        elif exact_policy_failure and missing_package_unit:
            excluded_reason = "exact expected missing-package failure"
        elif exact_policy_failure and warning_as_error:
            excluded_reason = "exact expected warning-as-error failure"
        if excluded_reason:
            observed = "skip"
            expected_record: str | dict[str, Any] = "skip"
            known_deviation = False
        else:
            expected_record, known_deviation = upstream_expected_record(
                upstream, expected_map, option_id, test_id, observed,
            )
        if isinstance(expected_record, str):
            expected = expected_record
            expected_detail: dict[str, Any] = {}
        else:
            expected = expected_record["observed_result"]
            expected_detail = expected_record
        detail_fields = ("failure_class", "exit_code", "first_diagnostic")
        detail_met = (
            all(detail.get(key) == expected_detail.get(key) for key in detail_fields)
            if observed == expected and expected_detail else True
        )
        expectation_met = observed == expected and detail_met
        mismatches += not expectation_met
        counts[observed] = counts.get(observed, 0) + 1
        writer.add({
            "stage": "upstream",
            "test_id": "upstream:" + test_id,
            "source": str(source_link.relative_to(ROOT)),
            "source_sha256": sha256(source),
            "source_commit": "worktree",
            "compiler_id": compiler_id,
            "compiler_commit": compiler.get("commit", "worktree"),
            "compiler_artifact_sha256": compiler_artifact_sha256,
            "compiler_kind": compiler["kind"],
            "compiler_info": compiler_version,
            "options_id": option_id,
            "options": test_options,
            "expected_result": "pass",
            "expected_observed_result": expected,
            "observed_result": observed,
            "expectation_met": expectation_met,
            "expected_failure_class": expected_detail.get("failure_class"),
            "expected_exit_code": expected_detail.get("exit_code"),
            "expected_first_diagnostic": expected_detail.get("first_diagnostic"),
            "expected_detail_sha256": expected_detail.get("detail_sha256"),
            "failure_detail_met": detail_met,
            "upstream_failure_class": detail.get("failure_class"),
            "upstream_exit_code": detail.get("exit_code"),
            "first_diagnostic": detail.get("first_diagnostic"),
            "detail_sha256": detail.get("detail_sha256"),
            "raw_detail_sha256": detail.get("raw_detail_sha256"),
            "excluded_reason": excluded_reason,
            "known_deviation": known_deviation,
            "suite_mode": "core",
            "suite_make_exit_code": make_rc,
            "suite_phase_records": phase_records,
            "suite_unique_tests": len(tests),
            "suite_test_ids_sha256": coverage["test_ids_sha256"],
            "source_clean_exit_code": clean_rc,
            "source_clean_seconds": round(clean_seconds, 6),
            "suite_seconds": round(make_seconds, 6),
            "source_clean_log": str(clean_log.relative_to(ROOT)),
            "suite_log": str(full_log.relative_to(ROOT)),
            "upstream_log": str(log_path.relative_to(ROOT)),
            "upstream_longlog": str(longlog_path.relative_to(ROOT)),
        }, announce=False)
    print(
        f"upstream-suite: {compiler_id} {option_id} tests={len(tests)} "
        f"mode=core exit={make_rc} "
        f"phase-records={phase_records} "
        f"counts={json.dumps(dict(sorted(counts.items())), sort_keys=True)} "
        f"mismatches={mismatches}"
    )
    return coverage


def run_upstream(
    writer: ResultWriter, manifest: dict[str, Any], compiler_filter: set[str] | None,
    option_filter: set[str] | None, test_filter: set[str] | None,
) -> None:
    if test_filter and "upstream-suite" not in test_filter:
        return
    compiler_ids = manifest["upstream"].get("compiler_allow", ["unleashed-latest"])
    for compiler_id in compiler_ids:
        if compiler_filter and compiler_id not in compiler_filter:
            continue
        coverage_reference: dict[str, Any] | None = None
        for option_id, options in manifest["option_sets"].items():
            if option_filter and option_id not in option_filter:
                continue
            coverage = run_upstream_case(
                writer, manifest, compiler_id, option_id, options,
            )
            if coverage_reference is None:
                coverage_reference = coverage
            else:
                require_same_upstream_test_set(
                    coverage_reference, coverage, compiler_id,
                )


MORMOT_ENVIRONMENT_METHODS = {
    "ip dns ldap",
    "dns and ldap",
    "rtsp over http",
    "rtsp over http buffered write",
}


def parse_mormot_report(report: Path) -> dict[str, Any]:
    text = report.read_text(encoding="utf-8", errors="replace")
    total_match = re.search(
        r"Total assertions failed for all test suits:\s*([0-9,]+)\s*/\s*([0-9,]+)",
        text,
        re.IGNORECASE,
    )
    if not total_match:
        raise RuntimeError(f"mORMot report has no final assertion total: {report}")
    total_failed = int(total_match.group(1).replace(",", ""))
    total_assertions = int(total_match.group(2).replace(",", ""))
    failures: list[dict[str, Any]] = []
    leaf_pattern = re.compile(
        r"!\s+-\s+(.+?):\s+([0-9,]+)\s*/\s*([0-9,]+)\s+FAILED",
        re.IGNORECASE,
    )
    for line in text.splitlines():
        # Some mORMot revisions emit a socket diagnostic before the failure
        # marker on the same line (e.g. "#1 ENetSock ! - RTSP ...").
        match = leaf_pattern.search(line)
        if not match:
            continue
        method = match.group(1).strip()
        failed = int(match.group(2).replace(",", ""))
        assertions = int(match.group(3).replace(",", ""))
        category = (
            "environment"
            if method.casefold() in MORMOT_ENVIRONMENT_METHODS
            else "qualification"
        )
        failures.append({
            "method": method,
            "failed": failed,
            "assertions": assertions,
            "category": category,
        })
    parsed_failed = sum(item["failed"] for item in failures)
    if parsed_failed != total_failed:
        raise RuntimeError(
            f"mORMot failure accounting mismatch in {report}: "
            f"report={total_failed}, parsed={parsed_failed}"
        )
    environment_failed = sum(
        item["failed"] for item in failures if item["category"] == "environment"
    )
    qualification_failed = sum(
        item["failed"] for item in failures if item["category"] == "qualification"
    )
    return {
        "total_assertions": total_assertions,
        "total_failed": total_failed,
        "environment_failed": environment_failed,
        "qualification_failed": qualification_failed,
        "failed_methods": failures,
    }


def mormot_suite_result(
    run_rc: int,
    total_failed: int,
    environment_failed: int,
    qualification_failed: int,
) -> str:
    environment_only_exit = (
        run_rc == 1
        and environment_failed > 0
        and total_failed == environment_failed
    )
    return (
        "pass"
        if qualification_failed == 0 and (run_rc == 0 or environment_only_exit)
        else "run_fail"
    )


def mormot_qualification_signature(failures: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        (
            {
                "method": item["method"].casefold(),
                "failed": item["failed"],
                "assertions": item["assertions"],
            }
            for item in failures if item["category"] == "qualification"
        ),
        key=lambda item: (item["method"], item["failed"], item["assertions"]),
    )


def expected_mormot_qualification_signature(
    source: dict[str, Any], compiler_id: str, option_id: str,
) -> list[dict[str, Any]]:
    table = source["expected_qualification_failures"]
    for key in (
        f"{compiler_id}/{option_id}", f"{compiler_id}/*",
        f"*/{option_id}", "*/*",
    ):
        if key in table:
            return sorted(
                table[key],
                key=lambda item: (item["method"], item["failed"], item["assertions"]),
            )
    raise RuntimeError(
        f"missing mORMot qualification expectation for {compiler_id}/{option_id}"
    )


def expected_mormot_compile_diagnostic(
    source: dict[str, Any], compiler_id: str, option_id: str,
) -> str | None:
    table = source.get("expected_compile_diagnostic", {})
    for key in (
        f"{compiler_id}/{option_id}", f"{compiler_id}/*",
        f"*/{option_id}", "*/*",
    ):
        if key in table:
            return table[key]
    return None


def mormot_run_timeout(
    source: dict[str, Any], compiler_id: str, option_id: str,
) -> int:
    table = source.get("run_timeout_seconds", {})
    for key in (
        f"{compiler_id}/{option_id}", f"{compiler_id}/*",
        f"*/{option_id}", "*/*",
    ):
        if key in table:
            return int(table[key])
    return 1200


def mormot_compile_command(
    compiler: dict[str, Any], options: list[str], source_root: Path,
    static_dir: Path, work: Path, program_source: Path | None = None,
    output_name: str = "mormot2tests", unit_override: Path | None = None,
    pinned_memory_manager: Path | None = None,
) -> list[str]:
    source_dirs = [
        "app", "core", "crypt", "db", "lib", "net", "orm", "rest",
        "soa", "script", "misc", "tools/mget", "tools/ecc",
    ]
    include_dirs = [source_root / "src", source_root / "src/core", source_root / "src/net"]
    unit_dirs = [source_root / "src" / name for name in source_dirs]
    if unit_override is not None:
        unit_dirs.insert(0, unit_override)
    suppress = (
        "-vm11047,6058,6018,5093,5092,5091,5060,5058,5057,5044,5028,"
        "5024,5023,4082,4081,4079,4056,4055,3175,3177,3187,3124,3123,"
        "5059,5033,5036,5043,5037,5089,5090"
    )
    command = compiler_command(compiler)
    if pinned_memory_manager is not None:
        command.append(
            "--pinned-unit=mormot.core.fpcx64mm="
            + str(pinned_memory_manager.resolve())
        )
        command.append("--required-first-unit=mormot.core.fpcx64mm")
    command.extend([
        "-MDelphi", "-Sci", "-Ci", "-g", "-gl", "-gw2", "-Xg",
        "-k-rpath=$ORIGIN", f"-k-L{work}", "-Tlinux", "-Px86_64",
        *options,
        "-dFPC_NO_DEFAULT_MEMORYMANAGER", "-dFPC_X64MM", "-dFPCMM_SERVER",
        "-dMOONBOT_MM_PROFILE_REQUIRED", "-dFPCMM_BOOSTER",
        "-dFPCMM_MOONSHARD",
        "-dFPCMM_REPORTMEMORYLEAKS", "-CX", "-XX", "-veiq", "-v-n-h-",
        suppress,
        "-Fi" + ";".join(str(path) for path in include_dirs),
        "-Fu" + ";".join(str(path) for path in unit_dirs),
        f"-Fl{static_dir}", f"-FU{work / 'lib'}", f"-FE{work}",
        f"-o{work / output_name}", "-B", "-Se1",
        str(program_source or source_root / "test/mormot2tests.dpr"),
    ])
    return command


def mormot_work_dir(writer: ResultWriter, identity: str) -> Path:
    work_key = hashlib.sha256(
        f"{writer.run_id}\0{identity}".encode()
    ).hexdigest()[:16]
    return ROOT / ".m" / work_key


def mormot_suite_work_dirs(
    writer: ResultWriter, identity: str,
) -> tuple[Path, Path]:
    artifacts = mormot_work_dir(writer, identity)
    if os.name != "posix":
        return artifacts, artifacts
    runtime = Path(tempfile.mkdtemp(prefix=f"mbc-{artifacts.name}-", dir="/tmp"))
    socket_path = runtime / "mormot2tests.sock:"
    if len(os.fsencode(socket_path)) >= 108:
        shutil.rmtree(runtime)
        raise RuntimeError(f"mORMot Unix socket path is too long: {socket_path}")
    return runtime, artifacts


def run_mormot_probe_case(
    writer: ResultWriter, probe_id: str, probe: dict[str, Any],
    source: dict[str, Any], compiler_id: str, compiler: dict[str, Any],
    option_id: str, options: list[str],
) -> None:
    source_root = ROOT / source["path"]
    require_clean_git_source(source_root, source.get("commit"))
    static_dir, static_input, static_input_sha256 = mormot_static_inputs(
        source_root, source,
    )
    memory_manager = source.get("memory_manager")
    memory_manager_source = ROOT / memory_manager if memory_manager else None
    if memory_manager_source is not None and not memory_manager_source.is_file():
        raise RuntimeError(f"mORMot memory manager is missing: {memory_manager_source}")
    program_source = ROOT / probe["source"]

    test_id = f"mormot-probe-{probe_id}"
    work = mormot_work_dir(
        writer, f"probe\0{probe_id}\0{compiler_id}\0{option_id}",
    )
    (work / "lib").mkdir(parents=True, exist_ok=True)
    compile_log = work / "compile.log"
    run_log = work / "run.log"
    compile_rc, compile_timeout, compile_seconds = run_process(
        mormot_compile_command(
            compiler, options, source_root, static_dir, work,
            program_source, "probe",
            pinned_memory_manager=memory_manager_source,
        ),
        ROOT, probe.get("compile_timeout_seconds", 300), compile_log,
    )
    run_rc: int | None = None
    run_timeout = False
    run_seconds = 0.0
    marker_count = 0
    if compile_timeout:
        observed = "compile_timeout"
    elif compile_rc != 0:
        observed = "compile_fail"
    else:
        run_rc, run_timeout, run_seconds = run_process(
            [str(work / "probe")], work,
            probe.get("run_timeout_seconds", 5), run_log,
        )
        if run_timeout:
            observed = "run_timeout"
        elif run_rc == 0:
            observed = "pass"
        else:
            observed = "run_fail"
        if run_log.is_file():
            marker_count = len(re.findall(
                rf"^{re.escape(probe['expected_marker'])}$",
                run_log.read_text(encoding="utf-8", errors="replace"),
                re.MULTILINE,
            ))

    expected = expected_observed(probe, compiler_id, option_id)
    marker_met = marker_count == 1
    compile_failure_class, first_compile_diagnostic = (
        classify_compile_log(compile_log) if observed.startswith("compile_")
        else (None, None)
    )
    writer.add({
        "stage": "mormot-probe",
        "test_id": test_id,
        "source": str(program_source.relative_to(ROOT)),
        "source_sha256": sha256(program_source),
        "mormot_source_commit": source.get("commit", "worktree"),
        "static_input": str(static_input.relative_to(ROOT)),
        "static_input_sha256": static_input_sha256,
        "compiler_id": compiler_id,
        "compiler_commit": compiler.get("commit", "worktree"),
        "compiler_artifact_sha256": compiler_provenance(compiler),
        "compiler_kind": compiler["kind"],
        "compiler_info": compiler_info(compiler),
        "options_id": option_id,
        "options": options,
        "expected_result": "pass",
        "expected_observed_result": expected,
        "observed_result": observed,
        "expectation_met": observed == expected and (
            expected != "pass" or marker_met
        ),
        "semantic_oracle_met": observed == "pass" and marker_met,
        "expected_marker": probe["expected_marker"],
        "marker_count": marker_count,
        "compile_failure_class": compile_failure_class,
        "first_compile_diagnostic": first_compile_diagnostic,
        "compile_exit_code": compile_rc,
        "run_exit_code": run_rc,
        "compile_seconds": round(compile_seconds, 6),
        "run_seconds": round(run_seconds, 6),
        "compile_log": str(compile_log.relative_to(ROOT)),
        "run_log": str(run_log.relative_to(ROOT)) if run_log.exists() else None,
    })


def _run_mormot_case_in_workspace(
    writer: ResultWriter, source_id: str, source: dict[str, Any],
    compiler_id: str, compiler: dict[str, Any], option_id: str,
    options: list[str], work: Path, artifacts: Path,
) -> None:
    source_root = ROOT / source["path"]
    require_clean_git_source(source_root, source.get("commit"))
    static_dir, static_input, static_input_sha256 = mormot_static_inputs(
        source_root, source,
    )

    test_id = f"mormot-{source_id}"
    (work / "lib").mkdir(parents=True, exist_ok=True)
    program_source, provenance_source = mormot_test_inputs(
        source_root, source, work,
    )
    memory_manager = source.get("memory_manager")
    memory_manager_source = ROOT / memory_manager if memory_manager else None
    if memory_manager:
        assert memory_manager_source is not None
        if not memory_manager_source.is_file():
            raise RuntimeError(f"mORMot memory manager is missing: {memory_manager_source}")
    compile_log = work / "compile.log"
    run_log = work / "run.log"
    compile_rc, compile_timeout, compile_seconds = run_process(
        mormot_compile_command(
            compiler, options, source_root, static_dir, work, program_source,
            pinned_memory_manager=memory_manager_source,
        ),
        program_source.parent, 600, compile_log,
    )
    run_rc: int | None = None
    run_timeout = False
    run_seconds = 0.0
    report: Path | None = None
    parsed: dict[str, Any] = {
        "total_assertions": None,
        "total_failed": None,
        "environment_failed": None,
        "qualification_failed": None,
        "failed_methods": [],
    }
    if compile_timeout:
        observed = "compile_timeout"
    elif compile_rc != 0:
        observed = "compile_fail"
    else:
        prefix = work / "report-prefix"
        prefix.touch()
        run_rc, run_timeout, run_seconds = run_process(
            [str(work / "mormot2tests"), prefix.name, "--nontp"],
            work, mormot_run_timeout(source, compiler_id, option_id), run_log,
        )
        if run_timeout:
            observed = "run_timeout"
        else:
            reports = [
                path for path in work.glob("report-prefix*mORMot2 Regression Tests.txt")
                if path.stat().st_size > 0
            ]
            if len(reports) != 1:
                observed = "run_fail"
            else:
                report = reports[0]
                parsed = parse_mormot_report(report)
                observed = mormot_suite_result(
                    run_rc,
                    parsed["total_failed"],
                    parsed["environment_failed"],
                    parsed["qualification_failed"],
                )

    expected = expected_observed(source, compiler_id, option_id)
    artifacts.mkdir(parents=True, exist_ok=True)
    for path in (compile_log, run_log):
        if path.is_file() and path.parent != artifacts:
            shutil.copy2(path, artifacts / path.name)
    if report is not None and report.parent != artifacts:
        shutil.copy2(report, artifacts / report.name)
        report = artifacts / report.name
    compile_log = artifacts / compile_log.name
    run_log = artifacts / run_log.name
    compile_failure_class, first_compile_diagnostic = (
        classify_compile_log(compile_log) if observed.startswith("compile_")
        else (None, None)
    )
    expected_class = expected_failure_class(source, compiler_id, option_id)
    expected_diagnostic = expected_mormot_compile_diagnostic(
        source, compiler_id, option_id,
    )
    qualification_signature = mormot_qualification_signature(parsed["failed_methods"])
    expected_signature = expected_mormot_qualification_signature(
        source, compiler_id, option_id,
    )
    if expected in ("pass", "run_fail"):
        qualification_signature_met = (
            report is not None and qualification_signature == expected_signature
        )
    else:
        qualification_signature_met = None
    expectation_met = observed == expected and (
        expected_class is None or compile_failure_class == expected_class
    ) and (
        expected_diagnostic is None or first_compile_diagnostic == expected_diagnostic
    ) and (
        qualification_signature_met is not False
    )
    writer.add({
        "stage": "mormot",
        "test_id": test_id,
        "source": str(provenance_source.relative_to(ROOT)),
        "source_sha256": sha256(provenance_source),
        "source_commit": source.get("commit", "worktree"),
        "test_source_commit": source.get("test_commit"),
        "memory_manager": memory_manager,
        "memory_manager_sha256": (
            sha256(memory_manager_source) if memory_manager_source else None
        ),
        "static_input": str(static_input.relative_to(ROOT)),
        "static_input_sha256": static_input_sha256,
        "compiler_id": compiler_id,
        "compiler_commit": compiler.get("commit", "worktree"),
        "compiler_artifact_sha256": compiler_provenance(compiler),
        "compiler_kind": compiler["kind"],
        "compiler_info": compiler_info(compiler),
        "options_id": option_id,
        "options": options,
        "expected_result": "pass",
        "expected_observed_result": expected,
        "observed_result": observed,
        "expectation_met": expectation_met,
        "compile_failure_class": compile_failure_class,
        "expected_failure_class": expected_class,
        "first_compile_diagnostic": first_compile_diagnostic,
        "expected_compile_diagnostic": expected_diagnostic,
        "compile_exit_code": compile_rc,
        "run_exit_code": run_rc,
        "compile_seconds": round(compile_seconds, 6),
        "run_seconds": round(run_seconds, 6),
        "compile_log": str(compile_log.relative_to(ROOT)),
        "run_log": str(run_log.relative_to(ROOT)) if run_log.exists() else None,
        "report": str(report.relative_to(ROOT)) if report else None,
        "qualification_signature": qualification_signature,
        "expected_qualification_signature": expected_signature,
        "qualification_signature_met": qualification_signature_met,
        **parsed,
    })


def collect_mormot_suite_artifacts(work: Path, artifacts: Path) -> None:
    if work == artifacts:
        return
    artifacts.mkdir(parents=True, exist_ok=True)
    for path in (work / "compile.log", work / "run.log"):
        if path.is_file():
            shutil.copy2(path, artifacts / path.name)
    for path in work.glob("report-prefix*mORMot2 Regression Tests.txt"):
        if path.is_file():
            shutil.copy2(path, artifacts / path.name)
    shutil.rmtree(work)


def run_mormot_case(
    writer: ResultWriter, source_id: str, source: dict[str, Any],
    compiler_id: str, compiler: dict[str, Any], option_id: str,
    options: list[str],
) -> None:
    # mORMot derives a Unix-domain socket name from ProgramFilePath. Keep the
    # executable path well below sockaddr_un.sun_path's 108-byte Linux limit.
    work, artifacts = mormot_suite_work_dirs(
        writer, f"suite\0{source_id}\0{compiler_id}\0{option_id}",
    )
    try:
        _run_mormot_case_in_workspace(
            writer, source_id, source, compiler_id, compiler, option_id,
            options, work, artifacts,
        )
    finally:
        collect_mormot_suite_artifacts(work, artifacts)


def run_mormot(
    writer: ResultWriter, manifest: dict[str, Any], compiler_filter: set[str] | None,
    option_filter: set[str] | None, test_filter: set[str] | None,
) -> None:
    if sys.platform != "linux" or os.uname().machine != "x86_64":
        raise RuntimeError(
            "mORMot qualification requires native Linux x86-64: its exact "
            "corpus includes Linux static inputs and POSIX boundary probes"
        )
    sources = manifest["mormot"]["sources"]
    for probe_id, probe in manifest["mormot"].get("probes", {}).items():
        test_id = f"mormot-probe-{probe_id}"
        if test_filter and test_id not in test_filter:
            continue
        source = sources[probe["mormot_source"]]
        for compiler_id in probe["compiler_allow"]:
            if compiler_filter and compiler_id not in compiler_filter:
                continue
            compiler = manifest["compilers"][compiler_id]
            for option_id, options in probe["option_sets"].items():
                if option_filter and option_id not in option_filter:
                    continue
                run_mormot_probe_case(
                    writer, probe_id, probe, source, compiler_id, compiler,
                    option_id, options,
                )
    for source_id, source in sources.items():
        test_id = f"mormot-{source_id}"
        if test_filter and test_id not in test_filter:
            continue
        compiler_ids = source.get("compiler_allow", manifest["primary_compilers"])
        for compiler_id in compiler_ids:
            if compiler_filter and compiler_id not in compiler_filter:
                continue
            compiler = manifest["compilers"][compiler_id]
            for option_id, options in manifest["option_sets"].items():
                if option_filter and option_id not in option_filter:
                    continue
                run_mormot_case(
                    writer, source_id, source, compiler_id, compiler,
                    option_id, options,
                )


def parse_set(values: list[str] | None) -> set[str] | None:
    return set(values) if values else None


def create_run_directory(
    runs_root: Path,
    stage: str,
    requested_run_id: str | None,
) -> tuple[str, Path]:
    runs_root.mkdir(parents=True, exist_ok=True)
    if requested_run_id:
        run_dir = runs_root / requested_run_id
        run_dir.mkdir(exist_ok=False)
    else:
        timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run_dir = Path(tempfile.mkdtemp(prefix=f"{timestamp}-{stage}-", dir=runs_root))
    return run_dir.name, run_dir


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "stage",
        choices=["fixtures", "mega", "benchmark", "upstream", "mormot", "all"],
    )
    parser.add_argument("--compiler", action="append")
    parser.add_argument("--option", action="append")
    parser.add_argument("--test", action="append")
    parser.add_argument("--run-id")
    args = parser.parse_args()
    manifest = load_manifest()
    run_id, run_dir = create_run_directory(
        ROOT / "results" / "runs", args.stage, args.run_id,
    )
    runner_snapshot = run_dir / "runner.py"
    shutil.copy2(ROOT / "runner.py", runner_snapshot)
    run_manifest = dict(manifest)
    run_manifest["_run"] = {
        "argv": sys.argv[1:],
        "input_manifest_sha256": sha256(MANIFEST_PATH),
        "python_version": sys.version,
        "runner_sha256": sha256(runner_snapshot),
    }
    with (run_dir / "manifest.json").open("w", encoding="utf-8") as stream:
        json.dump(run_manifest, stream, indent=2, sort_keys=True)
        stream.write("\n")
    writer = ResultWriter(run_dir, run_id)
    compiler_filter = parse_set(args.compiler)
    option_filter = parse_set(args.option)
    test_filter = parse_set(args.test)
    if args.stage in ("fixtures", "all"):
        run_fixtures(writer, manifest, compiler_filter, option_filter, test_filter)
    if args.stage in ("mega", "all"):
        run_mega(writer, manifest, compiler_filter, option_filter)
    if args.stage in ("benchmark", "all"):
        run_benchmark(
            writer, manifest, compiler_filter, option_filter, test_filter,
        )
    if args.stage in ("upstream", "all"):
        run_upstream(writer, manifest, compiler_filter, option_filter, test_filter)
    if args.stage in ("mormot", "all"):
        run_mormot(writer, manifest, compiler_filter, option_filter, test_filter)
    writer.finish()
    return 1 if any(
        not row["expectation_met"]
        or (row["semantic_result"] == "defect" and not row.get("known_deviation"))
        or row.get("measurement_quality") == "noisy"
        for row in writer.rows
    ) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"runner infrastructure error: {error}", file=sys.stderr)
        raise SystemExit(2)
