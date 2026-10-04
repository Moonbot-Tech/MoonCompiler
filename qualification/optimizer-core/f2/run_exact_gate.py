#!/usr/bin/env python3
"""Exact int-to-FP LICM: runtime, FP state, aliases and loop code shape."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

from run_f2_gate import default_compiler, default_rtl, link_args

HERE = Path(__file__).resolve().parent
POSITIVE = ("ExactSigned", "ExactUnsigned", "ExactSmall", "ExactWidened", "WithTemps")
NEGATIVE = ("Mutated", "Escaped", "Inexact64", "InexactSingle", "CheckedChild", "Pressure")


def loop_conversions(asm, name, mnemonic="cvtsi"):
    blocks = re.split(r"(?=^\.section )", asm, flags=re.M)
    matches = [b for b in blocks if re.search(r"^P\$[^\n]*_\$\$_" + name.upper() + r"\$[^\n]*:", b, re.M)]
    assert len(matches) == 1, f"missing or ambiguous {name}"
    labels, instructions = {}, []
    for line in matches[0].splitlines():
        if re.fullmatch(r"\.Lj\d+:", line):
            labels[line[:-1]] = len(instructions)
        elif re.match(r"\t[a-z]", line):
            instructions.append(line.strip())
    loops = []
    for i, instruction in enumerate(instructions):
        m = re.match(r"j\w+\s+(\.Lj\d+)$", instruction)
        if m and labels[m[1]] <= i:
            loops.append((labels[m[1]], i))
    assert loops, f"no loop found in {name}"
    conversions = [i for i, instruction in enumerate(instructions) if instruction.startswith(mnemonic)]
    assert conversions, f"no {mnemonic} found in {name}"
    return sum(any(start <= i <= end for start, end in loops) for i in conversions), len(conversions)


def compile_run(args, source, level, mode, root):
    out = root / source.stem / (level + "-" + mode)
    out.mkdir(parents=True, exist_ok=True)
    cmd = [str(args.compiler.resolve()), "-n", "-Mdelphi", level, "-al", "-Aas",
           "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{args.rtl.resolve()}",
           f"-FE{out.resolve()}", f"-FU{out.resolve()}",
           "-OoNOLICM" if mode == "off" else "-OoLICM"] + link_args()
    if mode == "verify":
        cmd.append("-dOPTCORE_VERIFY")
    cp = subprocess.run(cmd + [str(source)], capture_output=True, text=True, timeout=120)
    (out / "build.log").write_text(cp.stdout + cp.stderr)
    assert cp.returncode == 0, f"compile failed: {out / 'build.log'}"
    exe = out / (source.stem + (".exe" if os.name == "nt" else ""))
    cp = subprocess.run([str(exe.resolve())], capture_output=True, text=True, timeout=30)
    (out / "run.log").write_text(cp.stdout + cp.stderr)
    expected = "EXACT-LICM:PASS\n" if source.stem == "exact_semantic" else "INTEGER-PRESSURE:PASS\n"
    assert cp.returncode == 0 and cp.stdout == expected, f"runtime failed: {out}"
    return (out / (source.stem + ".s")).read_text()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    if args.rtl is None:
        args.rtl = default_rtl()
    root = args.output or Path(tempfile.mkdtemp(prefix="exact_licm_"))
    compile_run(args, HERE / "exact_semantic.dpr", "-O-", "off", root)
    for level in ("-O2", "-O3"):
        off = compile_run(args, HERE / "exact_semantic.dpr", level, "off", root)
        on = compile_run(args, HERE / "exact_semantic.dpr", level, "on", root)
        compile_run(args, HERE / "exact_semantic.dpr", level, "verify", root)
        for name in POSITIVE:
            assert loop_conversions(off, name)[0] > 0, f"{name}: ineffective negative control"
            assert loop_conversions(on, name)[0] == 0, f"{name}: conversion remained in loop"
        for name in NEGATIVE:
            assert loop_conversions(on, name)[0] > 0, f"{name}: forbidden motion"
        integer = compile_run(args, HERE / "integer_pressure.dpr", level, "on", root)
        for name in ("Four", "LiveFour"):
            assert loop_conversions(integer, name, "imul") == (0, 4), f"{name}: existing integer hoists lost"
    print(f"EXACT LICM GATE: PASS; evidence {root}")


if __name__ == "__main__":
    main()
