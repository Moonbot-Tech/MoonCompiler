#!/usr/bin/env python3
"""Pascal runtime and emitted-code checks for SETcc/CMP byte,1."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "f2"))
from run_f2_gate import default_compiler, default_rtl, link_args


def routine(asm, name):
    blocks = re.split(r"(?=^\.section )", asm, flags=re.M)
    matches = [b for b in blocks if re.search(r"^P\$[^\n]*_\$\$_" + name.upper() + r"\$[^\n]*:", b, re.M)]
    if len(matches) != 1:
        raise AssertionError(f"missing or ambiguous routine {name}")
    return matches[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    if args.rtl is None:
        args.rtl = default_rtl()
    root = args.output or Path(tempfile.mkdtemp(prefix="setcc_compare_"))
    for level in ("-O-", "-O2", "-O3"):
        out = root / level
        out.mkdir(parents=True, exist_ok=True)
        cmd = [str(args.compiler.resolve()), "-n", "-Mdelphi", level, "-al", "-Aas",
               "-dMOONCOMPILER_VANILLA_RUNTIME", f"-Fu{args.rtl.resolve()}",
               f"-FE{out.resolve()}", f"-FU{out.resolve()}"] + link_args() + [str(HERE / "setcc_semantic.dpr")]
        cp = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        (out / "build.log").write_text(cp.stdout + cp.stderr)
        assert cp.returncode == 0, f"compile failed: {out / 'build.log'}"
        exe = out / ("setcc_semantic.exe" if os.name == "nt" else "setcc_semantic")
        cp = subprocess.run([str(exe.resolve())], capture_output=True, text=True, timeout=30)
        (out / "run.log").write_text(cp.stdout + cp.stderr)
        assert cp.returncode == 0 and cp.stdout == "SETCC-CMP1:PASS\n", f"runtime failed: {out}"
        if level != "-O-":
            asm = (out / "setcc_semantic.s").read_text()
            live = routine(asm, "LiveValue")
            assert re.search(r"\tset\w+\s", live), "live enum result was lost"
            assert not re.search(r"\tcmpb\s+\$1,", live), "materialized condition was not folded"
            assert re.search(r"\tcmpb\s+\$1,", routine(asm, "NotBoolean")), "non-Boolean enum comparison lost"
            if level == "-O3":
                three = routine(asm, "MultiplyThree")
                assert re.search(r"\tleal\s", three), "useful multiply strength reduction lost"
                assert not re.search(r"\tcmpb\s+\$1,", three), "safe intervening multiply blocked folding"
                for name in ("MultiplySeven", "BooleanMultiplySeven"):
                    assert re.search(r"\timull\s+\$7,", routine(asm, name)), f"{name}: invalid LEA multiplier"
                callback = routine(asm, "SelectCallback")
                assert re.search(r"\tcall\s+\*", callback), "callback did not exercise indirect call"
                assert not re.search(r"\ttestb\s", callback), "released flags were kept alive to callback"
    print(f"SETCC GATE: PASS (runtime and Pascal code shape); evidence {root}")


if __name__ == "__main__":
    main()
