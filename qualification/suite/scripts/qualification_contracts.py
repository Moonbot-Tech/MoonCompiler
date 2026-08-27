#!/usr/bin/env python3
"""Fail-closed inventory contracts shared by qualification gates."""

from __future__ import annotations

import hashlib
import json
import subprocess
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


SUITE = Path(__file__).resolve().parent.parent
REPOSITORY = SUITE.parents[1]
MANIFEST_PATH = SUITE / "runner_manifest.json"
LOCKS_PATH = SUITE / "contract_locks.json"


class ContractError(RuntimeError):
    pass


def require_relative_posix_path(value: Any, label: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ContractError(f"invalid {label}: {value!r}")
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or not path.parts
        or path.as_posix() != value
        or ".." in path.parts
        or (path.parts and ":" in path.parts[0])
    ):
        raise ContractError(f"invalid {label}: {value!r}")
    return path


def require_suite_file(value: Any, label: str) -> Path:
    path = require_relative_posix_path(value, label)
    suite = SUITE.resolve()
    target = (suite / Path(*path.parts)).resolve()
    try:
        target.relative_to(suite)
    except ValueError as exc:
        raise ContractError(f"{label} escapes the qualification suite: {value}") from exc
    if not target.is_file():
        raise ContractError(f"{label} target does not exist: {target}")
    return target


def require_repository_file_from_suite(value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ContractError(f"invalid {label}: {value!r}")
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or not path.parts
        or path.as_posix() != value
        or (path.parts and ":" in path.parts[0])
    ):
        raise ContractError(f"invalid {label}: {value!r}")
    repository = REPOSITORY.resolve()
    target = (SUITE.resolve() / Path(*path.parts)).resolve()
    try:
        target.relative_to(repository)
    except ValueError as exc:
        raise ContractError(f"{label} escapes the repository: {value}") from exc
    if not target.is_file():
        raise ContractError(f"{label} target does not exist: {target}")
    return target


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"cannot read qualification contract {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ContractError(f"qualification contract must be an object: {path}")
    return value


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def focused_projection(gate: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": gate.get("id"),
        "runner": gate.get("runner"),
        "profiles": gate.get("profiles"),
        "argument_sets": gate.get("argument_sets"),
        "cases": sorted(gate.get("cases", []), key=lambda item: item.get("id", "")),
    }


def resident_projection(layer: dict[str, Any]) -> dict[str, Any]:
    return {
        key: layer.get(key)
        for key in (
            "id",
            "state",
            "source",
            "runner",
            "readme",
            "journal",
            "known_issues",
            "profiles",
            "shapes",
        )
    }


def require_lock(
    locks: dict[str, Any], lock_id: str, projection: Any
) -> str:
    if locks.get("schema") != 1 or not isinstance(locks.get("locks"), dict):
        raise ContractError("qualification locks have an unsupported schema")
    lock = locks.get("locks", {}).get(lock_id)
    if (
        not isinstance(lock, dict)
        or not isinstance(lock.get("sha256"), str)
        or len(lock["sha256"]) != 64
        or any(character not in "0123456789abcdef" for character in lock["sha256"])
    ):
        raise ContractError(f"missing qualification lock: {lock_id}")
    actual = canonical_sha256(projection)
    if actual != lock["sha256"]:
        raise ContractError(
            f"qualification lock mismatch for {lock_id}: "
            f"expected {lock['sha256']}, actual {actual}; "
            "use update_contract_locks.py only for an intentional inventory change"
        )
    return actual


def _case_map(gate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    cases = gate.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ContractError("focused gate must contain a non-empty cases array")
    result: dict[str, dict[str, Any]] = {}
    required = {
        "id", "state", "source_root", "source", "profiles", "args",
        "expectation", "asm",
    }
    for case in cases:
        if not isinstance(case, dict):
            raise ContractError("focused gate case must be an object")
        missing = sorted(required - set(case))
        if missing:
            raise ContractError(
                f"focused case {case.get('id', '<unknown>')} misses {missing}"
            )
        case_id = case["id"]
        if not isinstance(case_id, str) or not case_id:
            raise ContractError("focused case id must be a non-empty string")
        if case_id in result:
            raise ContractError(f"duplicate focused case id: {case_id}")
        if case["state"] not in ("active", "retired"):
            raise ContractError(f"invalid state for focused case {case_id}")
        if case["state"] == "retired":
            if not case.get("retirement_reason") or not case.get("replacement"):
                raise ContractError(
                    f"retired focused case needs reason and replacement: {case_id}"
                )
        if case["source_root"] not in ("compiler", "suite"):
            raise ContractError(f"invalid source_root for focused case {case_id}")
        require_relative_posix_path(
            case["source"], f"source path for focused case {case_id}"
        )
        if (
            not isinstance(case["profiles"], list)
            or not case["profiles"]
            or not all(isinstance(value, str) and value for value in case["profiles"])
        ):
            raise ContractError(f"focused case has no profiles: {case_id}")
        if len(case["profiles"]) != len(set(case["profiles"])):
            raise ContractError(f"focused case repeats a profile: {case_id}")
        if not isinstance(case["args"], list) or not isinstance(case["asm"], list):
            raise ContractError(f"focused case args/asm must be arrays: {case_id}")
        if not all(isinstance(value, str) and value for value in case["args"]):
            raise ContractError(f"focused case has an invalid argument set: {case_id}")
        setup = case.get("setup")
        if setup is not None:
            if not isinstance(setup, dict) or set(setup) != {"source_root", "source"}:
                raise ContractError(f"invalid setup source for focused case {case_id}")
            if (
                setup["source_root"] not in ("compiler", "suite")
                or not isinstance(setup["source"], str)
            ):
                raise ContractError(f"invalid setup source for focused case {case_id}")
            require_relative_posix_path(
                setup["source"], f"setup source for focused case {case_id}"
            )
        expectation = case["expectation"]
        if not isinstance(expectation, dict) or expectation.get("compile") not in (
            "pass", "fail"
        ):
            raise ContractError(f"invalid expectation for focused case {case_id}")
        if expectation["compile"] == "pass" and expectation.get("run") != "pass":
            raise ContractError(f"passing focused case must run: {case_id}")
        if expectation["compile"] == "fail" and not expectation.get("diagnostic"):
            raise ContractError(f"negative focused case needs a diagnostic: {case_id}")
        result[case_id] = case
    return result


def validate_focused_gate(
    manifest: dict[str, Any], locks: dict[str, Any], gate_id: str
) -> tuple[dict[str, Any], str]:
    gate = manifest.get("focused_gates", {}).get(gate_id)
    if not isinstance(gate, dict) or gate.get("id") != gate_id:
        raise ContractError(f"missing focused gate inventory: {gate_id}")
    require_suite_file(gate.get("runner"), "focused gate runner")
    profiles = gate.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise ContractError(f"focused gate has no profile definitions: {gate_id}")
    if not all(
        isinstance(name, str)
        and name
        and isinstance(values, list)
        and all(isinstance(value, str) and value for value in values)
        for name, values in profiles.items()
    ):
        raise ContractError(f"focused gate has an invalid profile: {gate_id}")
    argument_sets = gate.get("argument_sets")
    if not isinstance(argument_sets, dict) or not all(
        isinstance(name, str)
        and name
        and isinstance(values, list)
        and all(isinstance(value, str) and value for value in values)
        for name, values in argument_sets.items()
    ):
        raise ContractError(f"focused gate argument_sets must be an object: {gate_id}")
    cases = _case_map(gate)
    for case_id, case in cases.items():
        unknown_profiles = set(case["profiles"]) - set(profiles)
        unknown_args = set(case["args"]) - set(argument_sets)
        if unknown_profiles:
            raise ContractError(
                f"focused case {case_id} uses unknown profiles {sorted(unknown_profiles)}"
            )
        if unknown_args:
            raise ContractError(
                f"focused case {case_id} uses unknown argument sets {sorted(unknown_args)}"
            )
        for binding in case["asm"]:
            if not isinstance(binding, dict) or set(binding) != {"profile", "verifier"}:
                raise ContractError(f"invalid ASM binding for focused case {case_id}")
            if not all(isinstance(value, str) and value for value in binding.values()):
                raise ContractError(f"invalid ASM binding for focused case {case_id}")
            if binding["profile"] not in case["profiles"]:
                raise ContractError(
                    f"ASM binding uses an unplanned profile for {case_id}"
                )
    digest = require_lock(locks, gate.get("inventory_lock", ""), focused_projection(gate))
    return gate, digest


def planned_pairs(gate: dict[str, Any]) -> list[tuple[str, str]]:
    return [
        (case["id"], profile)
        for case in gate["cases"]
        if case["state"] == "active"
        for profile in case["profiles"]
    ]


def require_exact_actual(
    planned: Iterable[tuple[str, str]], actual: Iterable[tuple[str, str]]
) -> None:
    planned_list = list(planned)
    actual_list = list(actual)
    planned_duplicates = sorted(
        pair for pair, count in Counter(planned_list).items() if count != 1
    )
    actual_duplicates = sorted(
        pair for pair, count in Counter(actual_list).items() if count != 1
    )
    if planned_duplicates:
        raise ContractError(f"duplicate planned focused rows: {planned_duplicates}")
    if actual_duplicates:
        raise ContractError(f"duplicate actual focused rows: {actual_duplicates}")
    missing = sorted(set(planned_list) - set(actual_list))
    extra = sorted(set(actual_list) - set(planned_list))
    if missing or extra:
        raise ContractError(
            f"focused planned/actual mismatch: missing={missing}, extra={extra}"
        )


def validate_resident_layer(
    manifest: dict[str, Any], locks: dict[str, Any]
) -> tuple[dict[str, Any], str]:
    layer = manifest.get("qualification_layers", {}).get("resident")
    if not isinstance(layer, dict) or layer.get("id") != "resident":
        raise ContractError("missing resident qualification layer")
    required = {
        "id", "state", "source", "runner", "readme", "journal",
        "known_issues", "profiles", "shapes", "inventory_lock", "stage_lock",
    }
    missing = sorted(required - set(layer))
    if missing:
        raise ContractError(f"resident manifest misses {missing}")
    if layer["state"] != "active":
        raise ContractError("resident qualification layer must be active")
    for key in ("source", "runner", "readme", "journal", "known_issues"):
        require_repository_file_from_suite(layer[key], f"resident {key}")
    shapes = layer["shapes"]
    if not isinstance(shapes, dict) or set(shapes) != {
        "readme-direct", "handoff", "default"
    }:
        raise ContractError("resident manifest must define its three run shapes")
    if not all(
        isinstance(shape, dict)
        and set(shape) == {"carriers", "laps"}
        and all(isinstance(value, int) and value > 0 for value in shape.values())
        for shape in shapes.values()
    ):
        raise ContractError("resident run shapes must use positive carriers/laps")
    if (
        not isinstance(layer["profiles"], list)
        or not layer["profiles"]
        or not all(isinstance(value, str) and value for value in layer["profiles"])
        or len(layer["profiles"]) != len(set(layer["profiles"]))
    ):
        raise ContractError("resident profiles must be a non-empty array")
    digest = require_lock(
        locks, layer["inventory_lock"], resident_projection(layer)
    )
    return layer, digest


def parse_resident_stage_output(text: str) -> list[str]:
    announced: int | None = None
    rows: list[tuple[int, str]] = []
    for line in text.splitlines():
        parts = line.strip().split(" ", 2)
        if len(parts) == 2 and parts[0] == "RESIDENT_STAGES":
            if announced is not None:
                raise ContractError("resident stage count is printed more than once")
            try:
                announced = int(parts[1])
            except ValueError as exc:
                raise ContractError("resident stage count is not an integer") from exc
        elif len(parts) == 3 and parts[0] == "RESIDENT_STAGE":
            try:
                rows.append((int(parts[1]), parts[2]))
            except ValueError as exc:
                raise ContractError("resident stage index is not an integer") from exc
    if announced is None:
        raise ContractError("resident --list-stages omitted RESIDENT_STAGES")
    if [index for index, _ in rows] != list(range(announced)):
        raise ContractError("resident stage indices are not contiguous and complete")
    names = [name for _, name in rows]
    if len(names) != len(set(names)):
        raise ContractError("resident stage names are not unique")
    return names


def resident_stage_projection(names: list[str]) -> dict[str, Any]:
    return {"schema": "resident-stage-order/v1", "stages": names}


def require_resident_stage_lock(
    locks: dict[str, Any], lock_id: str, names: list[str]
) -> str:
    return require_lock(locks, lock_id, resident_stage_projection(names))


def _git_manifest(revision: str) -> dict[str, Any] | None:
    path = MANIFEST_PATH.relative_to(REPOSITORY).as_posix()
    result = subprocess.run(
        ["git", "show", f"{revision}:{path}"],
        cwd=REPOSITORY,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ContractError(f"cannot parse parent runner manifest: {exc}") from exc
    return value if isinstance(value, dict) else None


def require_retirement_only(current: dict[str, Any]) -> None:
    head = _git_manifest("HEAD")
    if head is None:
        return
    current_gate = current.get("focused_gates", {}).get("win64-repairs")
    if not isinstance(current_gate, dict):
        return
    head_gate = head.get("focused_gates", {}).get("win64-repairs")
    baseline = head
    if isinstance(head_gate, dict) and canonical_sha256(head_gate) == canonical_sha256(current_gate):
        parent = _git_manifest("HEAD^")
        if parent is not None:
            baseline = parent
    old_gate = baseline.get("focused_gates", {}).get("win64-repairs")
    if not isinstance(old_gate, dict):
        return
    old = _case_map(old_gate)
    new = _case_map(current_gate)
    for case_id, new_case in new.items():
        if case_id not in old and new_case["state"] != "active":
            raise ContractError(f"new focused case must start active: {case_id}")
    for case_id, old_case in old.items():
        if case_id not in new:
            raise ContractError(f"focused case was deleted instead of retired: {case_id}")
        new_case = new[case_id]
        if old_case["state"] == "retired" and new_case["state"] != "retired":
            raise ContractError(f"retired focused case was reactivated: {case_id}")
        if old_case["state"] == "active" and new_case["state"] == "retired":
            replacement = new_case.get("replacement")
            if replacement != "none" and (
                replacement not in new or new[replacement]["state"] != "active"
            ):
                raise ContractError(
                    f"retired focused case has an unknown replacement: {case_id}"
                )
