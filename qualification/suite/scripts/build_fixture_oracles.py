#!/usr/bin/env python3

import json
import os
import re
from pathlib import Path

import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import runner  # noqa: E402


CLEAN_REJECTIONS = {
    "fpc-41346": {
        "observed_result": "compile_fail",
        "failure_class": "compile_error",
        "diagnostic_contains": "Forward type definition does not match",
    },
}
REVIEWED_PASS_FIXTURES = frozenset({
    "fpc-39890",
    "fpc-40212",
    "fpc-40661",
    "fpc-41126",
    "fpc-41184",
    "fpc-41317",
    "fpc-41410",
    "fpc-41419",
    "fpc-41431-attachment",
    "fpc-41447",
    "fpc-41451",
    "fpc-41456-attachment",
    "fpc-41480",
    "fpc-41485",
    "fpc-41497",
    "fpc-41541",
    "fpc-41544",
    "fpc-41554",
    "fpc-41558",
    "fpc-41564",
    "fpc-41579",
    "fpc-41581",
    "fpc-41589",
    "fpc-41594",
    "fpc-41598",
    "fpc-41612-bug1",
    "fpc-41612-bug2",
    "fpc-41612-bug3",
    "fpc-41614",
    "fpc-41630",
    "fpc-41678",
    "fpc-41679",
    "fpc-41696",
    "fpc-41700",
    "fpc-41702",
    "fpc-41704",
    "fpc-41711",
    "fpc-41712",
    "fpc-41741",
    "fpc-41761",
    "fpc-41766",
    "fpc-41770",
    "fpc-41781",
    "fpc-41788",
    "fpc-41794",
    "fpc-41796",
    "fpc-41805",
    "fpc-41808",
    "fpc-41810",
    "fpc-41811",
    "fpc-41813",
    "fpc-41820",
    "fpc-41824",
    "fpc-41828",
    "fpc-41834",
    "fpc-41836",
    "lab-001-constprop-absolute",
    "lab-002-o3-ppu-unicode-pointer",
    "lab-003-o3-untyped-var-huge-array",
    "mega-001-negative-constant-div",
    "min-fpc-41796",
    "min-fpc-41810",
    "unleashed-17",
    "unleashed-20",
})
DELPHI_PROOF_PATH = "research/delphi_fixture_oracle_probe.json"
REFERENCE_PROOF_PATH = "research/fixture_reference_probe.json"


def issue_id(test_id: str) -> int | None:
    match = re.search(r"(?:^|-)fpc-(\d+)", test_id)
    return int(match.group(1)) if match else None


def load_issues() -> dict[int, dict]:
    result = {}
    with (ROOT / "research/fpc_issue_index.jsonl").open(encoding="utf-8") as stream:
        for line in stream:
            issue = json.loads(line)
            result[issue["iid"]] = issue
    return result


def oracle_kind(test: dict, acceptance: dict) -> str:
    if acceptance["observed_result"] == "compile_fail":
        return "clean-diagnostic"
    if test.get("compile_only"):
        return "ppu-compile-success" if test.get("kind") == "ppu_consumer" else "compile-success"
    source = (ROOT / test["source"]).read_text(encoding="utf-8", errors="replace")
    return "runtime-self-check" if re.search(r"\bHalt\s*\(", source, re.IGNORECASE) else "compile-link-run"


def delphi_references() -> dict[str, dict]:
    path = ROOT / DELPHI_PROOF_PATH
    if not path.is_file():
        return {}
    proof = json.loads(path.read_text(encoding="utf-8"))
    result = {}
    for test in proof["tests"]:
        if test["compile_exit_code"] != 0 or test["run_exit_code"] != 0:
            raise RuntimeError(f"failed Delphi fixture oracle: {test['test_id']}")
        result[test["test_id"]] = test
    return result


def compiler_references() -> dict[str, dict]:
    path = ROOT / REFERENCE_PROOF_PATH
    proof = json.loads(path.read_text(encoding="utf-8"))
    if proof.get("schema") != 1:
        raise RuntimeError(f"invalid fixture reference schema: {path}")
    return proof["references"]


def issue_evidence(
    test_id: str, issues: dict[int, dict], delphi: dict[str, dict],
    compiler_refs: dict[str, dict],
) -> dict:
    iid = issue_id(test_id)
    if iid is not None:
        issue = issues[iid]
        result = {
            "basis": "fpc-issue",
            "issue_iid": iid,
            "issue_state": issue["state"],
            "issue_url": issue["web_url"],
            "issue_description_sha256": issue["description_sha256"],
        }
    elif test_id.startswith("unleashed-"):
        result = {"basis": "unleashed-issue"}
    elif test_id.startswith("mega-"):
        result = {"basis": "mega-independent-oracle"}
    else:
        result = {"basis": "lab-reproducer"}
    references = []
    if test_id in delphi:
        references.append({
            "kind": "delphi-12.2-win64",
            "path": DELPHI_PROOF_PATH,
            "sha256": runner.sha256(ROOT / DELPHI_PROOF_PATH),
            "adapted_source_sha256": delphi[test_id]["adapted_source_sha256"],
        })
    if test_id in compiler_refs:
        references.append({
            "kind": "fpc-reference-run",
            "path": REFERENCE_PROOF_PATH,
            "sha256": runner.sha256(ROOT / REFERENCE_PROOF_PATH),
            "passing_compilers": sorted(compiler_refs[test_id]["compilers"]),
        })
    if references:
        result["independent_references"] = references
    return result


def main() -> None:
    manifest = json.loads((ROOT / "runner_manifest.json").read_text(encoding="utf-8"))
    issues = load_issues()
    delphi = delphi_references()
    compiler_refs = compiler_references()
    fixture_ids = {test["id"] for test in manifest["fixtures"]}
    reviewed_ids = REVIEWED_PASS_FIXTURES | CLEAN_REJECTIONS.keys()
    if fixture_ids != reviewed_ids:
        raise RuntimeError(
            "fixture acceptance requires explicit review: "
            f"missing={sorted(fixture_ids - reviewed_ids)} "
            f"obsolete={sorted(reviewed_ids - fixture_ids)}"
        )
    tests = {}
    for test in manifest["fixtures"]:
        acceptance = CLEAN_REJECTIONS.get(test["id"])
        if acceptance is None:
            acceptance = {"observed_result": "pass"}
        tests[test["id"]] = {
            "acceptance": acceptance,
            "oracle_kind": oracle_kind(test, acceptance),
            "evidence": issue_evidence(test["id"], issues, delphi, compiler_refs),
            "provenance": runner.fixture_test_provenance(test),
        }
    payload = {"schema": 1, "tests": dict(sorted(tests.items()))}
    target = ROOT / "research/fixture_oracles.json"
    temporary = target.with_suffix(".json.new")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8",
    )
    os.replace(temporary, target)


if __name__ == "__main__":
    main()
