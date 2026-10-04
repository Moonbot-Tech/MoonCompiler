#!/usr/bin/env python3
"""Gate for the hand-laid code placement of the bundled memory manager.

runtime/mm/mormot.core.fpcx64mm.pas lays out _GetMem, _FreeMem and
_ReallocMem by hand: the block order puts the common path (a tiny/small block
from a partially free pool, the lock free, nothing pending) straight behind
the entry without a taken branch, and DS prefixes (`db $3E`) shift the
remaining branches so that on the hot and warm paths no jump, call or
macro-fused compare/jump pair crosses or ends on a 32-byte boundary (rule 4
of doc/ASM_LAYOUT_RULES.md; the layout itself is described in
doc/MEMORY_MANAGER.md, "Hand-laid hot paths").

Win64 additionally separates ABI-correct framed slow entries. The gate
checks those entries too; their residue ceilings cover the complete body,
while the leaf entries keep the hot-region invariant.

The gate builds mm_probe.dpr with the product profile and the pinned MM,
runs it, disassembles the selected routines and checks, per routine:

* the entry is on a 64-byte line (rule 1);
* no rule-4 site starts in the hot region (the first `hot` bytes);
* the number of rule-4 sites behind the hot region does not exceed the
  documented residue (cold retry/contention/medium sites that were left).

Any change of the MM source or of the assembler's encoding that moves a
branch of the hot paths onto a 32-byte boundary fails the gate; the residue
ceilings catch drift in the cold parts.  Needs objdump (code_placement.py).
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
TOOLS = ROOT / "qualification" / "performance" / "tools"
sys.path.insert(0, str(TOOLS))
import code_placement  # noqa: E402
import check_placement_rules as rules  # noqa: E402

PROBE = HERE / "mm_probe.dpr"
MM = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"

# routine pattern -> hot bytes (Win64, Linux), residue ceiling (Win64, Linux).
# The hot region covers the laid-out paths; the residue counts the rule-4
# sites left behind it on purpose (see doc/MEMORY_MANAGER.md).  WHOLE says that
# the routine is laid out to its last byte, whatever its size is after an edit:
# an explicit number larger than the body is a stale number and fails.
WHOLE = -1
ROUTINES = {
    r"\$\$__GETMEM\$": (250, 280, 1, 8),
    r"\$\$__FREEMEM\$": (256, WHOLE, 0, 0),
    r"\$\$__REALLOCMEM\$": (128, 280, 0, 9),
    r"\$\$__ALLOCMEM\$": (120, WHOLE, 0, 0),
    r"\$\$_FREEMEDIUMBLOCK\$": (270, 270, 1, 1),
    r"\$\$_INSERTMEDIUMBLOCKINTOBIN$": (128, WHOLE, 0, 0),
}
WIN64_SLOW = {
    r"\$\$_FREESMALLPOOLLOCKEDHANDOFF\$": (WHOLE, 0, 0, 0),
    r"\$\$__GETMEMSLOW\$": (0, 0, 13, 0),
    r"\$\$__FREEMEMSLOW\$": (0, 0, 3, 0),
    r"\$\$__REALLOCMEMSLOW\$": (0, 0, 12, 0),
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


def build(compiler: Path, config: Path, mm: Path, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    first = "mormot.core.fpcx64mm" if os.name == "nt" else "mormot.core.fpcx64mm,cthreads"
    cmd = [str(compiler), "-n", f"@{config}", "-Mdelphi", "-O3", "-B", "-gw3",
           "-uMOONCOMPILER_VANILLA_RUNTIME", "-dMOONBOT_MM_PROFILE_REQUIRED",
           "-dFPCMM_BOOSTER", "-dFPCMM_MOONSHARD", "-dNOPATCHRTL",
           f"--pinned-unit=mormot.core.fpcx64mm={mm}", f"--required-first-unit={first}",
           f"-Fu{mm.parent}", f"-FE{out}", f"-FU{out}", str(PROBE)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    (out / "build.log").write_text((proc.stdout or "") + (proc.stderr or ""), encoding="utf-8")
    exe = out / ("mm_probe.exe" if os.name == "nt" else "mm_probe")
    if proc.returncode != 0 or not exe.is_file():
        tail = [line for line in ((proc.stdout or "") + (proc.stderr or "")).splitlines()
                if re.search(r"Error|Fatal", line)]
        raise RuntimeError("probe build failed\n" + "\n".join(tail[-20:]))
    run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
    if run.returncode != 0 or "MMPROBE_OK" not in run.stdout:
        raise RuntimeError(f"probe run failed: exit {run.returncode}\n{run.stdout}{run.stderr}")
    return exe


def rule4_sites(insns: dict, begin: int, end: int) -> list[tuple[int, int, int, str]]:
    """(offset of the site start, start, stop, mnemonic) of every branch or
    macro-fused pair crossing or ending on a 32-byte boundary."""
    sites = []
    prev = None
    for a in sorted(x for x in insns if begin <= x < end):
        mnemonic, operands, raw = insns[a]
        mnemonic, _ = code_placement.effective_instruction(mnemonic, operands)
        size = len(raw)
        if rules.is_branch(mnemonic):
            start = a
            if (mnemonic.startswith("j") and mnemonic != "jmp" and prev is not None
                    and prev[1] in rules.FUSABLE and prev[0] + prev[2] == a):
                start = prev[0]
            stop = a + size
            if (start // 32) != ((stop - 1) // 32) or (stop % 32) == 0:
                sites.append((start - begin, start, stop, mnemonic))
        prev = (a, mnemonic, size)
    return sites


def main() -> int:
    compiler, config = default_toolchain()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", type=Path, default=compiler)
    ap.add_argument("--config", type=Path, default=config)
    ap.add_argument("--mm", type=Path, default=MM)
    ap.add_argument("--keep", action="store_true", help="keep the build directory")
    ap.add_argument("--list-sites", action="store_true", help="print every rule-4 site")
    args = ap.parse_args()
    if args.compiler is None:
        raise SystemExit("cannot uniquely locate ppcx64 in the toolchain; pass --compiler")

    column = 0 if os.name == "nt" else 1
    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="mm_layout_gate_"))
    try:
        exe = build(args.compiler.resolve(), args.config.resolve(), args.mm.resolve(), tmp)
        insns = code_placement.disassemble(exe)
        procedures = code_placement.procedures(exe)
        print(f"# {exe}")
        print("routine                       entry   size  hot  sites  in-hot  residue/max")
        selected = ROUTINES | (WIN64_SLOW if column == 0 else {})
        for pattern, (hot_win, hot_lin, max_win, max_lin) in selected.items():
            hot = (hot_win, hot_lin)[column]
            ceiling = (max_win, max_lin)[column]
            found = [(n, b, e) for n, b, e in procedures if re.search(pattern, n)]
            if len(found) != 1:
                failures.append(f"{pattern}: {len(found)} procedures match")
                continue
            name, begin, end = found[0]
            short = name.split("$$_")[-1]
            if hot == WHOLE:
                hot = end - begin
            if hot > end - begin:
                failures.append(f"{short}: hot region {hot} exceeds body size {end - begin}")
            sites = rule4_sites(insns, begin, end)
            in_hot = [s for s in sites if s[0] < hot]
            residue = len(sites) - len(in_hot)
            print(f"{short:30s} @{begin % 64:2d} {end - begin:6d} {hot:4d} {len(sites):6d} {len(in_hot):7d} {residue:5d}/{ceiling}")
            if begin % 64 != 0:
                failures.append(f"{short}: entry on byte {begin % 64} of a 64-byte line (rule 1)")
            for offset, start, stop, mnemonic in in_hot:
                failures.append(f"{short}: {mnemonic} at +{offset} occupies bytes {start % 32}..{(stop - 1) % 32} "
                                f"of a 32-byte line inside the hot region (rule 4)")
            if residue > ceiling:
                failures.append(f"{short}: {residue} rule-4 sites behind the hot region, {ceiling} documented")
            if args.list_sites:
                for offset, start, stop, mnemonic in sites:
                    tag = "  (hot)" if offset < hot else ""
                    print(f"    +{offset:4d} {mnemonic:6s} bytes {start % 32:2d}..{(stop - 1) % 32:2d}{tag}")
    except Exception as exc:  # noqa: BLE001 - reported as a gate failure
        failures.append(str(exc))
    finally:
        if args.keep:
            print(f"build directory kept: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print(f"MM LAYOUT GATE: FAIL ({len(failures)} problems)")
        for failure in failures:
            print(" *", failure)
        return 1
    print("MM LAYOUT GATE: PASS (entries on 64-byte lines, hot paths free of rule-4 sites, residue within the documented ceilings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
