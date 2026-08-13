#!/usr/bin/env python3
"""Compile complete Pascal examples embedded in all post-3.2.2 FPC issues."""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import runner


ROOT = Path(__file__).resolve().parent.parent
CUTOFF = "2021-05-15T15:38:31.000Z"
FENCE = re.compile(
    r"^```(?P<label>pas|pascal|delphi|fpc|freepascal|objfpc)?[ \t]*\n"
    r"(?P<code>.*?)^```[ \t]*$",
    re.IGNORECASE | re.MULTILINE | re.DOTALL,
)
SOURCE_START = re.compile(r"^\s*(program|unit|library)\s+", re.IGNORECASE)
SOURCE_END = re.compile(r"\bend\s*\.\s*(?:\{.*?\}|//[^\n]*)?\s*$", re.IGNORECASE | re.DOTALL)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_issues() -> list[dict]:
    issues: list[dict] = []
    for name in sorted(glob.glob(str(ROOT / "cache/issues/fpc/page-*.json"))):
        with open(name, encoding="utf-8") as stream:
            for issue in json.load(stream):
                if issue.get("created_at", "") < CUTOFF:
                    continue
                if "Category::Compiler" not in issue.get("labels", []):
                    continue
                issues.append(issue)
    return issues


def normalize_source(block: str) -> str | None:
    block = block.replace("\r\n", "\n").replace("\r", "\n")
    lines = block.splitlines()
    source_at = next((i for i, line in enumerate(lines) if SOURCE_START.match(line)), None)
    if source_at is None:
        return None
    if any(line.strip() and not line.lstrip().startswith(("{$", "(*", "//", "{"))
           for line in lines[:source_at]):
        lines = lines[source_at:]
    source = "\n".join(lines).strip() + "\n"
    if not SOURCE_END.search(source):
        return None
    return source


def extract_sources(output: Path) -> list[dict]:
    source_dir = output / "sources"
    source_dir.mkdir(parents=True)
    records: list[dict] = []
    seen: set[tuple[int, str]] = set()
    for issue in load_issues():
        description = issue.get("description") or ""
        for ordinal, match in enumerate(FENCE.finditer(description), 1):
            source = normalize_source(match.group("code"))
            if source is None:
                continue
            encoded = source.encode("utf-8")
            digest = sha256_bytes(encoded)
            key = (issue["iid"], digest)
            if key in seen:
                continue
            seen.add(key)
            relative = Path("sources") / f"fpc-{issue['iid']}-{ordinal:02d}.pas"
            (output / relative).write_bytes(encoded)
            records.append({
                "issue_iid": issue["iid"],
                "issue_title": issue["title"],
                "issue_url": issue["web_url"],
                "issue_state": issue["state"],
                "created_at": issue["created_at"],
                "fence_ordinal": ordinal,
                "source": str(relative),
                "source_sha256": digest,
            })
    return records


def compile_one(
    output: Path, record: dict, compiler_id: str, compiler: dict,
    option_id: str, options: list[str], timeout: int,
) -> dict:
    work = output / "build" / Path(record["source"]).stem / compiler_id / option_id
    work.mkdir(parents=True)
    log = work / "compile.log"
    command = [
        *runner.compiler_command(compiler), *options,
        f"-FE{work}", f"-FU{work}", str(output / record["source"]),
    ]
    exit_code, timed_out, elapsed = runner.run_process(
        command, ROOT, timeout, log,
    )
    observed = (
        "compile_timeout" if timed_out else
        "pass" if exit_code == 0 else
        "compile_fail"
    )
    failure_class, diagnostic = (None, None)
    if observed != "pass":
        failure_class, diagnostic = runner.classify_compile_log(log)
    return {
        **record,
        "compiler_id": compiler_id,
        "compiler_commit": compiler["commit"],
        "compiler_artifact_sha256": runner.compiler_provenance(compiler),
        "options_id": option_id,
        "options": options,
        "observed_result": observed,
        "compile_exit_code": exit_code,
        "compile_seconds": round(elapsed, 6),
        "failure_class": failure_class,
        "first_diagnostic": diagnostic,
        "compile_log": str(log.relative_to(output)),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--timeout", type=int, default=8)
    args = parser.parse_args()
    output = ROOT / "results/research" / args.run_id
    output.mkdir(parents=True, exist_ok=False)
    sources = extract_sources(output)
    manifest = runner.load_manifest()
    matrix = tuple(
        (compiler_id, option_id, manifest["option_sets"][option_id])
        for compiler_id in manifest["primary_compilers"]
        for option_id in ("default", "O3")
    )
    results: list[dict] = []
    for source_index, record in enumerate(sources, 1):
        for compiler_id, option_id, options in matrix:
            results.append(compile_one(
                output, record, compiler_id, manifest["compilers"][compiler_id],
                option_id, options, args.timeout,
            ))
        if source_index % 25 == 0 or source_index == len(sources):
            print(f"compiled {source_index}/{len(sources)} sources", flush=True)
    result_path = output / "results.jsonl"
    with result_path.open("w", encoding="utf-8") as stream:
        for result in results:
            stream.write(json.dumps(result, sort_keys=True) + "\n")
    summary = {
        "run_id": args.run_id,
        "sources": len(sources),
        "rows": len(results),
        "result_table_sha256": runner.sha256(result_path),
    }
    (output / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8",
    )
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
