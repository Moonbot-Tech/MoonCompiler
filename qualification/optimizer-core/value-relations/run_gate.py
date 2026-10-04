#!/usr/bin/env python3
"""Check unchanged integer relations across floating comparisons and local joins."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "performance/tools"))
import code_placement  # noqa: E402


def execute(argv, out, name):
    (out / (name + ".argv.json")).write_text(json.dumps(argv, indent=2))
    cp = subprocess.run(argv, cwd=out, capture_output=True, text=True, errors="replace", timeout=180)
    (out / (name + ".log")).write_text(cp.stdout + cp.stderr)
    assert cp.returncode == 0, f"{name} failed: {out / (name + '.log')}"
    return cp.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--compiler", type=Path, required=True)
    ap.add_argument("--config", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler, config = args.compiler.resolve(), args.config.resolve()
    source = HERE / "relation_semantic.dpr"
    modes = ["O-", "O2", "O3"] + (["O3-pic"] if os.name != "nt" else [])
    for mode in modes:
        work = out / mode
        work.mkdir()
        flags = ["-O3", "-Cg"] if mode == "O3-pic" else ["-" + mode]
        execute([str(compiler), "-n", "@" + str(config), *flags, "-FE" + str(work),
                 "-FU" + str(work), str(source)], work, "build")
        binary = work / ("relation_semantic.exe" if os.name == "nt" else "relation_semantic")
        result = execute([str(binary)], work, "run")
        assert "RELATION-SEMANTIC:PASS\n" in result, f"semantic marker missing: {work}"
        (work / "identity.json").write_text(json.dumps({
            str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (compiler, config, source, binary)
        }, indent=2))
    beside = compiler.parent / "objdump.exe"
    objdump = os.environ.get("MOON_OBJDUMP") or (str(beside) if beside.is_file() else code_placement.tool("objdump"))
    listing = execute([objdump, "-drw", "-M", "intel", "--no-show-raw-insn",
                       str(out / "O3/relation_semantic.o")], out, "listing")
    body = re.search(r"^[0-9a-f]+ <[^>]*_\$\$_SCANBATCH\$[^>]*>:\n(.*?)(?=^[0-9a-f]+ <|\Z)",
                     listing, re.M | re.S)
    assert body, "ScanBatch missing from object"
    instructions = re.findall(r"^\s*[0-9a-f]+:\s+([a-z][a-z0-9]*)\s", body[1], re.M)
    assert "comisd" in instructions and "jp" in instructions, "floating comparison/join missing"
    assert instructions.count("jle") == 1, "redundant integer branch remained in ScanBatch"
    print(f"VALUE RELATION GATE: PASS; {'/'.join(modes)}; evidence {out}")


if __name__ == "__main__":
    main()
