#!/usr/bin/env python3
"""Compile-and-run matrix of the bundled memory manager over its FPCMM_*
profiles.

The product ships one profile (FPCMM_BOOSTER + FPCMM_MOONSHARD, checked by
profile_contract.*), but the unit keeps every upstream conditional, and the
hand-laid _GetMem/_FreeMem/_ReallocMem bodies branch on several of them
(FPCMM_MOONSHARD, FPCMM_TINYPERTHREAD, FPCMM_ASSUMEMULTITHREAD, NOSFRAME,
FPCMM_MS_LINUX_FASTGET, FPCMM_ERMS, FPCMM_PAUSE, FPCMM_CMPBEFORELOCK ...).
This matrix builds mm_probe.dpr under a vanilla runtime for each profile in
PROFILES and runs it, so a conditional branch of the hand layout that no
longer compiles, or a profile whose allocator no longer works, fails here
instead of at a user who compiles their own mORMot with that profile.

The hand layout writes some short forward jumps out as bytes (`db $75, $76 //
jne @Pending`, doc/ASM_LAYOUT_RULES.md); such a displacement is counted over
the bytes of one profile, and a conditional between the jump and its target
has other bytes in another.  The written-out jumps are found by their bytes
(code_placement.written_jumps: a db line whose first opcode is a jump), and
each has to name its mnemonic and label in its comment, or the matrix fails
before it builds anything.  Every profile is then built a second time from a
copy with these mnemonics, placed by the assembler: the instructions are the
same, so each direct jump of the unit object - every routine of the unit,
linked into the probe or not - has to reach the same instruction in both
builds (alignment fill aside), or the profile fails naming the routine and the
jump.  The compiler says which written-out jumps a profile compiles, and they
have to be the compared jumps behind the marks of the copy, one for one (the
copy marks its mnemonic); a listing of the object that leaves any of its code
out fails the profile naming the jumps it did not compare - an empty one is no
unit without jumps -, and so does a marked jump the compiler did not name
(code_placement.same_jumps; what this does not guard: README.md).  Needs
objdump (code_placement.py).

Every profile is built at both levels a program compiles the pinned unit
with: -O3 (Release) and -O- (Debug).  From -O1 on the internal assembler
writes some addresses of hand-written code shorter (optimize_ref, rax86.pas:
an index without a base at scale 1 or 2 becomes base+index, `lea P, [rcx*2 +
SmallBlockUpsizeAdder]` in _ReallocMem is 8 bytes at -O- and 5 at -O3), so
an instruction in the span of a written-out jump can have two lengths, and
the jump can be on its label in a Release program and off it in a Debug one.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROBE = HERE / "mm_probe.dpr"
MM = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
sys.path.insert(0, str(ROOT / "qualification" / "performance" / "tools"))
import code_placement  # noqa: E402

LEVELS = ("-O3", "-O-")
PRODUCT = ["-dFPCMM_BOOSTER", "-dFPCMM_MOONSHARD"]
PROFILES: dict[str, list[str]] = {
    "plain": [],
    "standalone": ["-dFPCMM_STANDALONE"],
    "server": ["-dFPCMM_SERVER"],
    "boost": ["-dFPCMM_BOOST"],
    "booster": ["-dFPCMM_BOOSTER"],
    "product": PRODUCT,
    "product-nopause": PRODUCT + ["-dFPCMM_NOPAUSE"],
    "product-leaks": PRODUCT + ["-dFPCMM_REPORTMEMORYLEAKS"],
    "product-cmpbeforelock": PRODUCT + ["-dFPCMM_CMPBEFORELOCK"],
    "product-sleeptsc": PRODUCT + ["-dFPCMM_SLEEPTSC"],
    "product-nomremap": PRODUCT + ["-dFPCMM_NOMREMAP"],
    "product-nosframe": PRODUCT + ["-dFPCMM_NOSFRAME"],
    "server-sleeptsc": ["-dFPCMM_SERVER", "-dFPCMM_SLEEPTSC"],
    "server-nosframe": ["-dFPCMM_SERVER", "-dFPCMM_NOSFRAME"],
    "plain-sleeptsc": ["-dFPCMM_SLEEPTSC"],
    "plain-nosframe": ["-dFPCMM_NOSFRAME"],
    "moonshard": ["-dFPCMM_MOONSHARD"],
    "multithread": ["-dFPCMM_ASSUMEMULTITHREAD"],
    "erms": ["-dFPCMM_ERMS"],
    "tinyperthread": ["-dFPCMM_TINYPERTHREAD"],
    "multiplesmall": ["-dFPCMM_MULTIPLESMALLNOTWITHMEDIUM"],
}


def default_toolchain() -> tuple[Path | None, Path]:
    # the defaults are only a convenience: with --compiler/--config given
    # they must not fail (the Linux stand hosts have no toolchain)
    stand = os.environ.get("MOONBOT_TOOLCHAIN")
    base = Path(stand) if stand else ROOT / "toolchain"
    if os.name == "nt":
        return base / "bin" / "x86_64-win64" / "ppcx64.exe", base / "bin" / "x86_64-win64" / "moon-base.cfg"
    versions = sorted((base / "lib" / "fpc").glob("*/ppcx64"))
    return (versions[0] if len(versions) == 1 else None), base / "etc" / "moon-base.cfg"


def build(compiler: Path, config: Path, mm: Path, defines: list[str], out: Path, level: str) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    # the pin on the command line wins over the configuration's (the toolchain's copy)
    cmd = [str(compiler), "-n", f"@{config}", "-Mdelphi", level, "-B",
           "-dMOONCOMPILER_VANILLA_RUNTIME", "-uMOONBOT_MM_PROFILE_REQUIRED",
           "-uFPCMM_BOOSTER", "-uFPCMM_MOONSHARD", *defines, f"--pinned-unit=mormot.core.fpcx64mm={mm}",
           f"-Fu{mm.parent}", f"-FE{out}", f"-FU{out}", str(PROBE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    output = (proc.stdout or "") + (proc.stderr or "")
    (out / "build.log").write_text(output, encoding="utf-8")
    exe = out / ("mm_probe.exe" if os.name == "nt" else "mm_probe")
    if proc.returncode != 0 or not exe.is_file():
        tail = [line.strip() for line in output.splitlines() if re.search(r"Error|Fatal", line)]
        raise RuntimeError("build failed: " + " | ".join(tail[-3:]))
    return exe


def one(compiler: Path, config: Path, mm: Path, symbolic: Path, name: str, defines: list[str],
        root: Path, level: str) -> tuple[str | None, set[str], int]:
    """(problem, written-out jumps the profile compiles, jumps of the unit object compared)."""
    unit = MM.stem + ".o"
    try:
        exe = build(compiler, config, mm, defines, root / name, level)
        run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
        if run.returncode != 0 or "MMPROBE_OK" not in run.stdout:
            return f"run failed: exit {run.returncode} {run.stdout.strip()[:200]}", set(), 0
        build(compiler, config, symbolic, defines + ["-vi"], root / (name + "-symbolic"), level)
        compiled = code_placement.compiled_written_jumps(
            (root / (name + "-symbolic") / "build.log").read_text(encoding="utf-8"))
        compared, wrong = code_placement.same_jumps(root / name / unit, root / (name + "-symbolic") / unit,
                                                    compiled)
    except RuntimeError as error:
        return str(error), set(), 0
    problem = "written-out jump off its label: " + "; ".join(wrong) if wrong else None
    return problem, compiled, compared


def main() -> int:
    compiler, config = default_toolchain()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", type=Path, default=compiler)
    ap.add_argument("--config", type=Path, default=config)
    ap.add_argument("--mm", type=Path, default=MM)
    ap.add_argument("--only", help="regular expression for profile names")
    ap.add_argument("--keep", action="store_true", help="keep the build directory")
    args = ap.parse_args()
    if args.compiler is None:
        raise SystemExit("cannot uniquely locate ppcx64 in the toolchain; pass --compiler")

    text, written, problems = code_placement.written_jumps(args.mm.read_text(encoding="utf-8-sig"), MM.name)
    if problems:
        print("MM PROFILE MATRIX: FAIL (a written-out jump the matrix cannot check against its mnemonic)")
        for problem in problems:
            print(" *", problem)
        return 1
    print(f"written-out jumps: {len(written)} found by their bytes, {len(written)}/{len(written)} with the "
          f"mnemonic and label of their comment")
    selected = {k: v for k, v in PROFILES.items() if not args.only or re.search(args.only, k)}
    failures: list[str] = []
    compiled_in = {where: 0 for where in written}
    tmp = Path(tempfile.mkdtemp(prefix="mm_profile_matrix_"))
    try:
        symbolic = tmp / "symbolic" / MM.name
        symbolic.parent.mkdir()
        symbolic.write_text(text, encoding="utf-8")
        for level in LEVELS:
            for name, defines in selected.items():
                problem, compiled, compared = one(args.compiler.resolve(), args.config.resolve(),
                                                  args.mm.resolve(), symbolic, name, defines, tmp / level, level)
                for where in compiled:
                    compiled_in[where] += 1
                state = "FAIL " + problem if problem else (f"ok  {compared} jumps of the unit compared, "
                                                           f"{len(compiled)} of them written out")
                print(f"{name:24s} {level:4s} {' '.join(defines) or '(no FPCMM_* define)':60s} {state}")
                if problem:
                    failures.append(f"{name} {level}: {problem}")
    finally:
        if args.keep:
            print(f"build directory kept: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    for where in written:
        print(f"  {where}: compiled in {compiled_in[where]} of {len(selected) * len(LEVELS)} builds")
    if failures:
        print(f"MM PROFILE MATRIX: FAIL ({len(failures)} of {len(selected) * len(LEVELS)} builds)")
        for failure in failures:
            print(" *", failure)
        return 1
    print(f"MM PROFILE MATRIX: PASS ({len(selected)} profiles at {' and '.join(LEVELS)} compile and run; every "
          f"written-out jump a profile compiles compared and on its label)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
