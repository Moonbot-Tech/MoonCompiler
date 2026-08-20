#!/usr/bin/env python3
"""How a Devil program is built.

The build driver (`build.ps1` / `build`) is the contract every real project
compiles under: Delphi Unicode ABI, the pinned memory manager as the first
unit, System namespace aliases, and one of two profiles.  A test that compiles
under anything else is testing a compiler nobody ships.

Devil needs one thing the driver does not offer: intermediate optimization
levels, because a defect that appears at `-O2` and disappears at `-O3` is
invisible when only the two production profiles exist.  So the option set here
mirrors the driver exactly and varies nothing but the level, the same way
`RTL-test/run.py` does for the RTL matrix.  `debug` and `release` are byte for
byte what the driver passes; `o1` and `o2` are the same build with the level
moved.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# The compiler being tested does not have to live in the tree these scripts
# came from: the mutation stand reverts repairs inside a separate worktree and
# points here, so its rebuilds cannot touch the working copy.
ROOT = Path(os.environ.get("DEVIL_TOOLCHAIN_ROOT")
            or Path(__file__).resolve().parents[3])
MM_UNIT = "mormot.core.fpcx64mm"
MM_SOURCE = ROOT / "runtime" / "mm" / f"{MM_UNIT}.pas"

LANGUAGE = [
    "-dMOONCOMPILER_UNICODE_DEFAULT",
    "-Mdelphi",
    "-Municodestrings",
    "-MduplicateLocals",
    "-Madvancedrecords",
    "-Marrayoperators",
    "-Munderscoreisseparator",
    "-Mfunctionreferences",
    "-Manonymousfunctions",
    "-Minlinevars",
    "-Mimplicitgenerics",
    "-Mautoderef",
]

NAMESPACES = [
    "-FNSystem",
    "-UaSystem.SysUtils=SysUtils",
    "-UaSystem.Variants=Variants",
    "-UaSystem.Classes=Classes",
    "-UaSystem.DateUtils=DateUtils",
    "-UaSystem.Math=Math",
    "-UaSystem.Types=Types",
    "-UaSystem.TypInfo=TypInfo",
    "-UaSystem.Rtti=Rtti",
    "-UaSystem.StrUtils=StrUtils",
    "-UaSystem.Character=Character",
    "-UaSystem.SyncObjs=SyncObjs",
    "-UaSystem.Generics.Defaults=Generics.Defaults",
    "-UaSystem.Generics.Collections=Generics.Collections",
    "-UaSystem.IniFiles=IniFiles",
    "-UaSystem.SysConst=SysConst",
    "-UaSystem.RTLConsts=RTLConsts",
]

# what the driver calls debug and release, plus the two levels in between
PROFILES = {
    "debug": ["-O-", "-gl", "-gw3", "-Criot", "-Sa"],
    "o1": ["-O1", "-gl", "-gw3"],
    "o2": ["-O2", "-gl", "-gw3"],
    "release": ["-O3", "-gl", "-gw3"],
}
DEFAULT_PROFILES = "debug,o1,o2,release"


def toolchain() -> tuple[Path, Path, list[str], str]:
    """Compiler, config, target options and executable suffix for this host."""
    if os.name == "nt":
        base = ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64"
        return base / "fpc.exe", base / "fpc.cfg", ["-Px86_64", "-Twin64"], ".exe"
    if sys.platform == "linux" and os.uname().machine == "x86_64":
        base = ROOT / ".moonbot" / "toolchain"
        return (base / "bin" / "fpc", base / "etc" / "fpc.cfg",
                ["-Px86_64", "-Tlinux", "-dPOSIX"], "")
    raise RuntimeError("Devil supports only Win64 and Linux x86-64")


def required_first_unit() -> str:
    if os.name == "nt":
        return f"--required-first-unit={MM_UNIT}"
    return f"--required-first-unit={MM_UNIT},cthreads"


def compile_command(source: Path, output: Path, profile: str,
                    *, search: list[Path] = (), defines: list[str] = (),
                    extra: list[str] = ()) -> list[str]:
    """The driver's command line with the optimization level moved."""
    if profile not in PROFILES:
        raise ValueError(f"unknown profile: {profile}")
    compiler, config, target, _ = toolchain()
    command = [str(compiler), "-n", f"@{config}",
               *LANGUAGE, *target, "-Rintel", "-B",
               "-dMOONBOT_MM_PROFILE_REQUIRED", "-dFPCMM_BOOSTER",
               "-dFPCMM_MOONSHARD",
               f"--pinned-unit={MM_UNIT}={MM_SOURCE}",
               required_first_unit(),
               *NAMESPACES]
    for directory in (source.parent, *search):
        command += [f"-Fu{directory}", f"-Fi{directory}"]
    command += [f"-FU{output}", f"-FE{output}"]
    command += [f"-d{define}" for define in defines]
    command += [*PROFILES[profile], *extra, str(source)]
    return command


def executable(output: Path, stem: str) -> Path:
    _, _, _, suffix = toolchain()
    return output / f"{stem}{suffix}"


def preflight() -> None:
    """Fail early and clearly when the product half of the build is missing."""
    compiler, config, _, _ = toolchain()
    for required in (compiler, config, MM_SOURCE):
        if not required.is_file():
            raise SystemExit(
                f"missing build input: {required}\n"
                "run build.ps1 compiler (or ./build compiler) first")
