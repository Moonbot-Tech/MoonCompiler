#!/usr/bin/env python3
"""Check forwarding calls, unwind/cleanup and explicit frame contracts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def routine(asm, name):
    blocks = re.split(r"(?=^\.section )", asm, flags=re.M)
    pattern = r"^P\$[^\n]*_\$\$_" + name.upper() + r"(?:\$[^\n]*)?:"
    matches = [block for block in blocks if re.search(pattern, block, re.M)]
    assert len(matches) == 1, f"missing or ambiguous routine {name}"
    return matches[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--toolchain", type=Path, default=ROOT / "toolchain")
    ap.add_argument("--compiler", type=Path)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    tc = args.toolchain.resolve()
    toolbin = tc / ("bin/x86_64-win64" if os.name == "nt" else "bin")
    compiler = (args.compiler or toolbin / ("ppcx64.exe" if os.name == "nt" else "ppcx64")).resolve()
    config = toolbin / "fpc.cfg" if os.name == "nt" else tc / "etc/fpc.cfg"
    root = (args.output or Path(tempfile.mkdtemp(prefix="tail_forwarding_"))).resolve()
    root.mkdir(parents=True, exist_ok=True)
    cfg = root / "installed.cfg"
    config_text = config.read_text().replace("$FPCBINDIR", toolbin.as_posix())
    includes = {}
    def expand_base(match):
        path = Path(match[1].strip().strip('"')).resolve()
        assert path.name == "moon-base.cfg", f"unexpected installed configuration include: {path}"
        includes[str(path)] = sha(path)
        return path.read_text().replace("$FPCBINDIR", toolbin.as_posix())
    cfg.write_text(re.sub(r"^#INCLUDE\s+([^\n]+)$", expand_base, config_text, flags=re.M))
    identity = {"compiler": str(compiler), "compiler_sha256": sha(compiler),
                "config": str(config), "config_sha256": sha(config), "resolved_config_sha256": sha(cfg),
                "included_configs": includes,
                "sources": {p.name: sha(p) for p in sorted(HERE.glob("*.dpr"))}, "runs": []}
    for profile in ("Debug", "Release"):
        for stem in ("tail_semantic", "tail_contracts", "tail_directives"):
            out = root / profile / stem
            out.mkdir(parents=True, exist_ok=True)
            cmd = [str(compiler), "-n"]
            if profile == "Release":
                cmd.append("-dRELEASE")
            cmd += ["@" + str(cfg), "-B", "-FE" + str(out), "-FU" + str(out), str(HERE / (stem + ".dpr"))]
            (out / "argv.json").write_text(json.dumps(cmd, indent=2))
            cp = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            (out / "build.log").write_text(cp.stdout + cp.stderr)
            assert cp.returncode == 0, f"compile failed: {out / 'build.log'}"
            exe = out / (stem + (".exe" if os.name == "nt" else ""))
            cp = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
            (out / "run.log").write_text(cp.stdout + cp.stderr)
            assert cp.returncode == 0 and stem.upper() + "_PASS\n" in cp.stdout, f"runtime failed: {out}"
            listing = out / "listing"
            listing.mkdir(exist_ok=True)
            listing_cmd = ["-FE" + str(listing) if p.startswith("-FE") else "-FU" + str(listing) if p.startswith("-FU") else p for p in cmd]
            listing_cmd[1:1] = ["-al", "-s"]
            lp = subprocess.run(listing_cmd, capture_output=True, text=True, timeout=120)
            (listing / "build.log").write_text(lp.stdout + lp.stderr)
            (listing / "argv.json").write_text(json.dumps(listing_cmd, indent=2))
            assert lp.returncode == 0, f"listing failed: {listing}"
            asm = (listing / (stem + ".s")).read_text()
            if stem == "tail_semantic":
                body = routine(asm, "Forwarded")
                if profile == "Release":
                    assert re.search(r"\tjmp\s+\*", body) and not re.search(r"\tcall\s", body), "forwarding frame remained"
                    assert not re.search(r"%[re](?:sp|bp)", body), "tail forwarder uses a removed frame"
                    assert "  Forwarded," not in cp.stdout, "forwarding frame survived in the target trace"
                else:
                    assert re.search(r"\tcall\s", body), "Debug forwarding call lost"
                    assert "  Forwarded," in cp.stdout, "Debug stack trace lost its frame"
            elif stem == "tail_contracts":
                if profile == "Release":
                    for name in ("DirectArgs", "ProcArg", "Factory") + (("ForwardVarArgs",) if os.name != "nt" else ()):
                        body = routine(asm, name)
                        assert re.search(r"\tjmp\s", body) and not re.search(r"\tcall\s", body), f"{name}: useful tail call lost"
                for name in ("StackArgs", "LocalArg", "FinallyArg", "ManagedArg", "WidenReturn", "MsAbiForward"):
                    assert re.search(r"\tcall\s", routine(asm, name)), f"{name}: required work lost"
            else:
                for name in ("KeepFrame", "CheckStack", "ObserveFrame", "ObserveCaller"):
                    assert re.search(r"\tcall\s", routine(asm, name)), f"{name}: explicit frame contract lost"
                if os.name == "nt":
                    assert re.search(r"\tcall\s", routine(asm, "SafeForward")), "safecall result protocol lost"
            identity["runs"].append({"profile": profile, "source": stem, "argv": cmd, "listing_argv": listing_cmd, "binary_sha256": sha(exe)})
            (root / "identity.json").write_text(json.dumps(identity, indent=2))
    print(f"TAIL FORWARDING GATE: PASS; evidence {root}")


if __name__ == "__main__":
    main()
