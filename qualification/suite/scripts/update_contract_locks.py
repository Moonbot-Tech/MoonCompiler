#!/usr/bin/env python3
"""Explicitly update qualification locks after an intentional review."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from qualification_contracts import (
    ContractError,
    LOCKS_PATH,
    MANIFEST_PATH,
    canonical_sha256,
    focused_projection,
    load_json,
    parse_resident_stage_output,
    resident_projection,
    resident_stage_projection,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--resident-exe", type=Path)
    args = parser.parse_args()
    if not args.inventory and args.resident_exe is None:
        parser.error("select --inventory and/or --resident-exe")

    manifest = load_json(MANIFEST_PATH)
    locks = load_json(LOCKS_PATH) if LOCKS_PATH.is_file() else {"schema": 1, "locks": {}}
    if locks.get("schema") != 1 or not isinstance(locks.get("locks"), dict):
        raise ContractError("qualification locks have an unsupported schema")
    values = locks["locks"]
    if args.inventory:
        gate = manifest["focused_gates"]["win64-repairs"]
        layer = manifest["qualification_layers"]["resident"]
        values[gate["inventory_lock"]] = {
            "sha256": canonical_sha256(focused_projection(gate))
        }
        values[layer["inventory_lock"]] = {
            "sha256": canonical_sha256(resident_projection(layer))
        }
    if args.resident_exe is not None:
        executable = args.resident_exe.resolve()
        result = subprocess.run(
            [str(executable), "--list-stages"],
            cwd=executable.parent,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"resident --list-stages failed: {result.returncode}")
        names = parse_resident_stage_output(result.stdout)
        layer = manifest["qualification_layers"]["resident"]
        values[layer["stage_lock"]] = {
            "sha256": canonical_sha256(resident_stage_projection(names))
        }
    temporary = LOCKS_PATH.with_suffix(LOCKS_PATH.suffix + ".tmp")
    temporary.write_text(
        json.dumps(locks, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(LOCKS_PATH)
    print(f"updated qualification locks: {LOCKS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
