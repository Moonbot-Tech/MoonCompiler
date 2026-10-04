#!/usr/bin/env python3
"""Compiler self-build gate: the compiler sources build only under the ABI they
are written for, and a compiler built from them survives an incremental
rebuild of itself.

Why this gate exists
--------------------
Two compiler crashes seen on the RTL profile stand (2026-09-15/16), both
"Error: Compilation raised exception internally" followed by an access
violation, had nothing to do with the code the compiler was compiling:

1. A compiler built by hand with the *product* moon-base.cfg (Unicode system unit,
   -dMOONCOMPILER_UNICODE_DEFAULT: Char = WideChar, PChar = PWideChar) built
   with 300+ implicit string conversion warnings and freed foreign memory
   while parsing its first option.  The compiler sources are written for
   the classic FPC string ABI and are built against the vanilla RTL with
   -dMOONCOMPILER_VANILLA_RUNTIME (build, build.ps1, the stand scripts).
   globtype.pas now refuses any other ABI with a compile error; this gate
   proves the refusal fires with the product configuration and stays silent
   with the build configuration.

2. An incremental rebuild of the compiler sources after an interface change
   of a low-level unit (aasmtai.pas) crashed the product IDE compiler, twice
   at the same place, and a stand-built compiler once - non-deterministically
   in production, deterministically under heaptrc with keepreleased.  The
   task scheduler (ctask.pas) recompiles a unit from source in a second
   round after modules that use it were already loaded from their PPUs or
   compiled; those modules are then "re-resolved" (tppumodule.re_resolve),
   but the re-resolve skipped every module loaded from a PPU because the
   deref-availability flag was only set by buildderef, which runs when a PPU
   is written, never when one is read.  Such a module kept its pointers into
   the freed symtables of the recompiled unit, and the first typecheck that
   touched one (an "incompatible types" message, an "inline not inlined"
   note) called a virtual method of a dead tdef.  symtable.pas marks the
   deref data as available after any deref pass; symdef.pas keeps a class
   helper procdef from being added twice by a repeated derefimpl.

What it does
------------
Everything happens in a temporary copy of compiler/ (the message includes
are generated there with msg2inc when absent), with the compiler and the
vanilla configuration given on the command line (a stand's base profile or
the IDE toolchain):

- ABI guard: globtype.pas must fail with the product configuration (the
  guard's own message) and compile with the build configuration;
- a heaptrc compiler is built from the copy (-gh -gl -O2, the flags of the
  scratch recipe of the stand); it builds the copy cleanly, then aasmtai.pas
  gets an extra field in tai_cpu_abstract (an interface change that
  invalidates roughly two thirds of the PPUs) and the copy is rebuilt
  incrementally into the same unit directory with HEAPTRC=keepreleased, so a
  pointer into freed memory cannot go unnoticed: the build must succeed and
  the log must carry no heaptrc report;
- the incrementally built compiler and a cleanly built one from the same
  source must produce byte-identical compilers from the copy (the
  incremental product may differ in bytes from the clean one - inlining
  decisions depend on what is loaded from a PPU - but it must not be
  miscompiled).

Takes about three minutes on the Ryzen host; the chains run it after the
configuration gate.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from hashlib import sha256
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
COMPILER_SOURCES = ROOT / "compiler"
GUARD_MESSAGE = "The compiler sources need the AnsiChar ABI"
PROBE_ANCHOR = "padowner  : tai;"
PROBE_FIELD = "selfbuild_probe : byte; { the gate's interface change }"
COMMON = ["-O2", "-Sg", "-dx86_64", "-dGDB", "-dBROWSERLOG",
          "-Fux86_64", "-Fux86", "-Fusystems", "-Fix86_64", "-Fix86"]
HEAPTRC_REPORT = re.compile(r"was freed at|touched again at|does not point to valid memory|Marked memory at|"
                            r"Runtime error|unhandled exception|Access violation|raised exception internally")


def exe_name(stem: str) -> str:
    return stem + (".exe" if os.name == "nt" else "")


def run(cmd: list[str], cwd: Path, log: Path, env: dict[str, str] | None = None) -> tuple[int, str]:
    environment = dict(os.environ)
    if env:
        environment.update(env)
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=3600, env=environment)
    output = (proc.stdout or "") + (proc.stderr or "")
    log.write_text(output, encoding="utf-8", errors="replace")
    return proc.returncode, output


def compile_sources(compiler: Path, config: Path, source_dir: Path, out: Path, extra: list[str],
                    log: Path, env: dict[str, str] | None = None, clean: bool = True) -> tuple[int, str]:
    if clean and out.exists():
        shutil.rmtree(out)
    (out / "bin").mkdir(parents=True, exist_ok=True)
    (out / "units").mkdir(parents=True, exist_ok=True)
    cmd = [str(compiler), "-n", f"@{config}", "-dMOONCOMPILER_VANILLA_RUNTIME", *COMMON, *extra,
           f"-FE{out / 'bin'}", f"-FU{out / 'units'}", "pp.pas"]
    return run(cmd, source_dir, log, env)


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", type=Path, required=True, help="ppcx64 that builds the compiler sources")
    ap.add_argument("--config", type=Path, required=True,
                    help="vanilla moon-base.cfg for building the compiler (a stand's base profile or the IDE toolchain)")
    ap.add_argument("--product-config", type=Path, required=True,
                    help="the product moon-base.cfg the ABI guard must refuse")
    ap.add_argument("--msg2inc", type=Path, default=None,
                    help="msg2inc for the message includes (default: next to --compiler)")
    ap.add_argument("--sources", type=Path, default=COMPILER_SOURCES,
                    help="compiler source directory to test (default: this checkout's compiler/)")
    ap.add_argument("--keep", action="store_true", help="keep the temporary directory")
    args = ap.parse_args()

    compiler = args.compiler.resolve()
    config = args.config.resolve()
    product_config = args.product_config.resolve()
    msg2inc = args.msg2inc.resolve() if args.msg2inc else compiler.parent / exe_name("msg2inc")
    for required in (compiler, config, product_config, msg2inc):
        if not required.is_file():
            print(f"COMPILER SELFBUILD GATE: FAIL (missing {required})")
            return 1

    failures: list[str] = []
    notes: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="compiler_selfbuild_"))
    try:
        started = time.monotonic()
        src = tmp / "compiler"
        shutil.copytree(args.sources.resolve(), src, ignore=shutil.ignore_patterns("*.ppu", "*.o", "*.a", "*.exe", "units", "bin"))
        if not (src / "msgtxt.inc").is_file() or not (src / "msgidx.inc").is_file():
            code, _ = run([str(msg2inc), "msg/errore.msg", "msg", "msg"], src, tmp / "msg2inc.log")
            if code != 0:
                raise RuntimeError("msg2inc failed")

        # 1. the ABI guard: globtype.pas under the product configuration
        guard_out = tmp / "guard"
        guard_out.mkdir()
        code, output = run([str(compiler), "-n", f"@{product_config}", *COMMON, f"-FE{guard_out}", f"-FU{guard_out}", "globtype.pas"],
                           src, tmp / "guard-product.log")
        if code == 0:
            failures.append("ABI guard: globtype.pas compiled with the product configuration (Char = WideChar) without complaint")
        elif GUARD_MESSAGE not in output:
            failures.append("ABI guard: globtype.pas failed with the product configuration, but not with the guard message:"
                            + chr(10) + output[-1500:])
        else:
            notes.append("ABI guard refuses the product configuration")
        code, output = run([str(compiler), "-n", f"@{config}", "-dMOONCOMPILER_VANILLA_RUNTIME", *COMMON, f"-FE{guard_out}", f"-FU{guard_out}", "globtype.pas"],
                           src, tmp / "guard-vanilla.log")
        if code != 0:
            failures.append("ABI guard: globtype.pas does not compile with the build configuration:\n" + output[-1500:])

        # 2. the heaptrc compiler
        code, output = compile_sources(compiler, config, src, tmp / "ppc", ["-gl", "-gh"], tmp / "ppc.log")
        if code != 0:
            raise RuntimeError("the heaptrc compiler did not build:\n" + "\n".join(
                line for line in output.splitlines() if re.search(r"Error|Fatal", line))[-1500:])
        ppc = tmp / "ppc" / "bin" / exe_name("pp")
        notes.append(f"heaptrc compiler built in {time.monotonic() - started:.0f}s")

        # 3. clean build, interface change, incremental rebuild under heaptrc
        started = time.monotonic()
        code, output = compile_sources(ppc, config, src, tmp / "inc", [], tmp / "full.log")
        if code != 0:
            raise RuntimeError("the clean build with the heaptrc compiler failed:\n" + output[-1500:])
        aasmtai = src / "aasmtai.pas"
        text = aasmtai.read_bytes()
        anchor = PROBE_ANCHOR.encode()
        if text.count(anchor) != 1:
            raise RuntimeError("aasmtai.pas: the probe anchor is not unique")
        newline = b"\r\n" if b"\r\n" in text[:4000] else b"\n"
        indent = text[:text.index(anchor)].rsplit(newline, 1)[1]
        text = text.replace(anchor, anchor + newline + indent + PROBE_FIELD.encode())
        aasmtai.write_bytes(text)
        code, output = compile_sources(ppc, config, src, tmp / "inc", [], tmp / "incremental.log",
                                       env={"HEAPTRC": "keepreleased tracedepth=24"}, clean=False)
        report = [line for line in output.splitlines() if HEAPTRC_REPORT.search(line)]
        if code != 0 or report:
            failures.append("incremental rebuild after the aasmtai.pas interface change failed (exit "
                            f"{code}):\n" + "\n".join(output.splitlines()[-40:]))
        else:
            notes.append(f"incremental rebuild under heaptrc keepreleased clean ({time.monotonic() - started:.0f}s)")

        # 4. the incremental product self-hosts identically to a clean product
        if not failures:
            started = time.monotonic()
            incremental_pp = tmp / "inc" / "bin" / exe_name("pp")
            code, output = compile_sources(ppc, config, src, tmp / "clean", [], tmp / "clean.log")
            if code != 0:
                raise RuntimeError("the clean build of the changed sources failed:\n" + output[-1500:])
            clean_pp = tmp / "clean" / "bin" / exe_name("pp")
            products = {}
            for name, builder in (("by-incremental", incremental_pp), ("by-clean", clean_pp)):
                code, output = compile_sources(builder, config, src, tmp / name, [], tmp / f"{name}.log")
                if code != 0:
                    raise RuntimeError(f"self-host {name} failed:\n" + output[-1500:])
                products[name] = digest(tmp / name / "bin" / exe_name("pp"))
            if len(set(products.values())) != 1:
                failures.append("the incrementally built compiler and the cleanly built one produce different compilers: "
                                + ", ".join(f"{k}={v[:16]}" for k, v in products.items()))
            else:
                notes.append(f"self-host of the incremental product identical to the clean one ({time.monotonic() - started:.0f}s)")
    except Exception as exc:  # noqa: BLE001 - reported as a gate failure
        failures.append(str(exc))
    finally:
        if args.keep:
            print(f"temporary directory kept: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    for note in notes:
        print(" -", note)
    if failures:
        print(f"COMPILER SELFBUILD GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("COMPILER SELFBUILD GATE: PASS (ABI guard, incremental rebuild under heaptrc, identical self-host)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
