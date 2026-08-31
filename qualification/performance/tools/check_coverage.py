#!/usr/bin/env python3
"""Validate the performance qualification coverage contract."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "coverage_manifest.json"
PULSE_CASE_PATTERN = re.compile(
    r"PulseRunCase\s*\(\s*'[^']+'\s*,\s*'([^']+)'", re.DOTALL
)
PULSE_ADD_PATTERN = re.compile(r"\bAdd\s*\(\s*'([^']+)'", re.DOTALL)
CASE_CONTRACTS = {
    "PulseRunCase/v1": PULSE_CASE_PATTERN,
    "PulseAdd/v1": PULSE_ADD_PATTERN,
}


def declared_pulse_cases(source: Path, contract: str) -> list[str]:
    """Return the ordered literal case matrix registered by a Pulse program."""
    pattern = CASE_CONTRACTS.get(contract)
    if pattern is None:
        raise ValueError(f"unknown Pulse case contract: {contract}")
    return pattern.findall(source.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release",
        action="store_true",
        help="fail while any required family is not implemented",
    )
    args = parser.parse_args()

    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    errors: list[str] = []
    required_families = set(data["required_families"])
    families = data["families"]
    by_id = {family["id"]: family for family in families}
    if len(by_id) != len(families):
        errors.append("duplicate family id")

    missing_families = sorted(required_families - by_id.keys())
    extra_families = sorted(by_id.keys() - required_families)
    if missing_families:
        errors.append("missing required families: " + ", ".join(missing_families))
    if extra_families:
        errors.append("families absent from required_families: " + ", ".join(extra_families))

    for family in families:
        status = family.get("status")
        if status not in {"planned", "implemented"}:
            errors.append(f"{family['id']}: invalid status {status!r}")
        if status == "implemented":
            for field in ("source",):
                path = ROOT / family.get(field, "")
                if not path.is_file():
                    errors.append(f"{family['id']}: missing {field} {path}")
            generated = family.get("generated_source")
            if generated is not None and not (ROOT / generated).is_file():
                errors.append(f"{family['id']}: missing generated source {generated}")
            cases = family.get("cases", [])
            if not cases or len(cases) != len(set(cases)):
                errors.append(f"{family['id']}: cases are empty or duplicated")
            contract = family.get("case_contract")
            if contract not in CASE_CONTRACTS:
                errors.append(
                    f"{family['id']}: missing or unknown case contract {contract!r}"
                )
            else:
                source = ROOT / family["source"]
                declared = declared_pulse_cases(source, contract)
                if not declared:
                    errors.append(
                        f"{family['id']}: no literal case matrix in {source}"
                    )
                elif cases != declared:
                    errors.append(
                        f"{family['id']}: manifest cases differ from {source}"
                    )

    required_axes = data["required_axis_values"]
    for axis, required_values in required_axes.items():
        covered = {
            value
            for family in families
            for value in family.get("coverage", {}).get(axis, [])
        }
        missing = sorted(set(required_values) - covered)
        unknown = sorted(covered - set(required_values))
        if missing:
            errors.append(f"axis {axis}: missing values {', '.join(missing)}")
        if unknown:
            errors.append(f"axis {axis}: unknown values {', '.join(unknown)}")

    planned = sorted(
        family["id"] for family in families if family.get("status") != "implemented"
    )
    if args.release and planned:
        errors.append("release-blocking planned families: " + ", ".join(planned))

    if errors:
        for error in errors:
            print("COVERAGE_FAIL", error)
        raise SystemExit(1)

    print(
        "COVERAGE_OK",
        f"families={len(families)}",
        f"implemented={len(families) - len(planned)}",
        f"planned={len(planned)}",
        "mode=" + ("release" if args.release else "development"),
    )
    if planned:
        print("COVERAGE_PLANNED " + " ".join(planned))


if __name__ == "__main__":
    main()
