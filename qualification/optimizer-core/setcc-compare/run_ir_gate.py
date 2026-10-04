#!/usr/bin/env python3
"""Exercise the actual x86 peephole, built from this checkout's compiler sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ide = ROOT / "toolchain/ide"
    ap.add_argument("--compiler", type=Path, default=ide / (
        "bin/x86_64-win64/ppcx64.exe" if os.name == "nt" else "bin/ppcx64"))
    ap.add_argument("--config", type=Path, default=ide / (
        "bin/x86_64-win64/fpc.cfg" if os.name == "nt" else "etc/fpc.cfg"))
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    out = (args.output or Path(tempfile.mkdtemp(prefix="setcc_ir_"))).resolve()
    out.mkdir(parents=True, exist_ok=True)
    units = Path(tempfile.mkdtemp(prefix="units-", dir=out))
    source = ROOT / "compiler"
    exe = out / ("setcc_ir.exe" if os.name == "nt" else "setcc_ir")
    cmd = [str(args.compiler.resolve()), "-n", "@" + str(args.config.resolve()),
           "-O2", "-dx86_64", "-dRELEASE", "-dMOONCOMPILER_PRODUCT_RUNTIME",
           "-dMOONCOMPILER_VANILLA_RUNTIME", f"-FU{units}", f"-FE{out}", f"-o{exe}"]
    cmd += [f"-Fu{source / part}" for part in ("x86_64", "systems", "x86", ".")]
    cmd += [f"-Fi{source / part}" for part in ("x86_64", "x86", ".")]
    cmd.append(str(HERE / "setcc_ir.pas"))
    started = time.monotonic()
    cp = subprocess.run(cmd, cwd=out, capture_output=True, text=True, timeout=180)
    (out / "build.log").write_text(cp.stdout + cp.stderr)
    assert cp.returncode == 0, f"IR build failed: {out / 'build.log'}"
    assert (units / "aoptx86.ppu").exists(), "peephole was not rebuilt from source"
    cp = subprocess.run([str(exe)], cwd=out, capture_output=True, text=True, timeout=30)
    (out / "run.log").write_text(cp.stdout + cp.stderr)
    witnesses = [args.compiler, args.config, source / "x86/aoptx86.pas", HERE / "setcc_ir.pas", exe]
    (out / "identity.json").write_text(json.dumps({
        "argv": cmd, "elapsed_seconds": time.monotonic() - started,
        "sha256": {str(p.resolve()): hashlib.sha256(p.read_bytes()).hexdigest() for p in witnesses},
    }, indent=2))
    assert cp.returncode == 0 and "SETCC-IR:PASS\n" in cp.stdout, f"IR failed: {out / 'run.log'}"
    print(f"SETCC IR GATE: PASS; evidence {out}")


if __name__ == "__main__":
    main()
