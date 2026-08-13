#!/usr/bin/env python3

import json
import os
from collections import defaultdict
from pathlib import Path

import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import runner  # noqa: E402


SOURCE_RUN = "fixtures-audited-001"
SOURCE_PATH = Path("results/runs") / SOURCE_RUN / "results.jsonl"
SOURCE_SHA256 = "5cbe9013db08128f4395ecda6f507eb9765c89e04c36f1e9cb321bbea61a6fdf"
REFERENCE_COMPILERS = {"fpc-3.2.2", "fpc-fixes-3.2"}
TARGET_PATH = Path("research/fixture_reference_probe.json")


def main() -> None:
    source = ROOT / SOURCE_PATH
    if runner.sha256(source) != SOURCE_SHA256:
        raise RuntimeError(f"reference result hash mismatch: {source}")

    grouped = defaultdict(lambda: defaultdict(list))
    source_hashes = defaultdict(set)
    compiler_identities = {}
    with source.open(encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            if row["run_id"] != SOURCE_RUN:
                raise RuntimeError(f"unexpected run id: {row['run_id']}")
            if row["compiler_id"] not in REFERENCE_COMPILERS:
                continue
            source_hashes[row["test_id"]].add(row["source_sha256"])
            identity = {
                "commit": row["compiler_commit"],
                "info": row["compiler_info"],
            }
            previous = compiler_identities.setdefault(row["compiler_id"], identity)
            if previous != identity:
                raise RuntimeError(f"compiler identity changed: {row['compiler_id']}")
            if row["observed_result"] == "pass":
                grouped[row["test_id"]][row["compiler_id"]].append(row["options_id"])

    manifest = json.loads((ROOT / "runner_manifest.json").read_text(encoding="utf-8"))
    fixtures = {test["id"]: test for test in manifest["fixtures"]}
    unknown = set(grouped) - set(fixtures)
    if unknown:
        raise RuntimeError(f"unknown referenced fixtures: {sorted(unknown)}")

    references = {}
    for test_id, compilers in sorted(grouped.items()):
        if len(source_hashes[test_id]) != 1:
            raise RuntimeError(f"inconsistent source hashes: {test_id}")
        current_hash = runner.fixture_test_provenance(fixtures[test_id])["source_sha256"]
        source_hash = next(iter(source_hashes[test_id]))
        if source_hash != current_hash:
            raise RuntimeError(f"stale reference source: {test_id}")
        references[test_id] = {
            "source_sha256": source_hash,
            "compilers": {
                compiler_id: {
                    **compiler_identities[compiler_id],
                    "passing_options": sorted(options),
                }
                for compiler_id, options in sorted(compilers.items())
            },
        }

    payload = {
        "schema": 1,
        "source_run": {
            "path": SOURCE_PATH.as_posix(),
            "run_id": SOURCE_RUN,
            "sha256": SOURCE_SHA256,
        },
        "references": references,
    }
    target = ROOT / TARGET_PATH
    temporary = target.with_suffix(".json.new")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8",
    )
    os.replace(temporary, target)
    print(f"references={len(references)} sha256={runner.sha256(target)}")


if __name__ == "__main__":
    main()
