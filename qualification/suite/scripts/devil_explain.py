#!/usr/bin/env python3
"""Explain a red Devil check: parameters from the manifest and the exact
generated source of the procedure that produced it.

    devil_explain.py dvl-expr-00203
    devil_explain.py dvl-life-00004 --seed 11 --cases 120

With --seed the program is regenerated first, so a name from an old gate run
can be explained even after the tree moved on.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
GENERATOR = ROOT / "scripts" / "generate_devil.py"


def procedure_source(text: str, proc: str) -> str:
    """The whole routine, from its header to the matching end."""
    start = re.search(r"^procedure %s;" % re.escape(proc), text, re.M)
    if not start:
        return ""
    lines = text[start.start():].splitlines()
    out, depth, started = [], 0, False
    for line in lines:
        out.append(line)
        stripped = line.strip().lower()
        if stripped == "begin" or stripped.endswith(" begin"):
            depth += 1
            started = True
        elif stripped.startswith("end;") or stripped == "end;":
            depth -= 1
            if started and depth <= 0:
                break
    return "\n".join(out)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("name", help="check name, e.g. dvl-expr-00203-form")
    p.add_argument("--seed", type=int)
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--layers", default="all")
    args = p.parse_args()

    input_dir = DEVIL
    temporary: tempfile.TemporaryDirectory[str] | None = None
    if args.seed is not None:
        temporary = tempfile.TemporaryDirectory(prefix="devil-explain-")
        input_dir = Path(temporary.name)
        subprocess.run([sys.executable, str(GENERATOR), "--seed", str(args.seed),
                        "--cases", str(args.cases), "--layers", args.layers,
                        "--out", str(input_dir)], cwd=ROOT.parent.parent,
                       check=True, capture_output=True, text=True)

    manifest_path = input_dir / "devil_manifest.json"
    if not manifest_path.exists():
        print("no manifest; generate first")
        sys.exit(2)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    base = args.name
    for suffix in ("-form", "-model", "-fold-vs-runtime", "-half-vs-runtime",
                   "-exact", "-order", "-trail", "-balance", "-negation"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    base = re.sub(r"-[a-z0-9-]+$", "", base) if base not in {
        c["name"] for c in manifest["cases"]} else base

    case = next((c for c in manifest["cases"] if c["name"] == base), None)
    if case is None:
        case = next((c for c in manifest["cases"]
                     if args.name.startswith(c["name"])), None)
    if case is None:
        print(f"no case matching {args.name} in seed {manifest['seed']}")
        sys.exit(1)

    print(f"seed      : {manifest['seed']}")
    print(f"case      : {case['name']}")
    for key, value in sorted(case.items()):
        if key not in ("name", "layer"):
            print(f"{key:10}: {value}")

    layer = case["layer"]
    inc = input_dir / f"devil_{layer}.inc"
    if not inc.exists():
        print(f"\n(no generated source for layer {layer})")
        return
    proc = "Dvl" + layer.capitalize() + case["name"].rsplit("-", 1)[-1]
    text = inc.read_text(encoding="utf-8")
    procedure = procedure_source(text, proc)
    print("\n--- generated source ---")
    print(procedure or f"(procedure {proc} not found)")
    if temporary is not None:
        temporary.cleanup()


if __name__ == "__main__":
    main()
