#!/usr/bin/env python3
"""Verify that ptop is only the utils/ptop subdirectory target."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FPCMAKE = ROOT / "utils" / "Makefile.fpc.fpcmake"
MAKEFILE = ROOT / "utils" / "Makefile"


def assignment(text: str, name: str) -> list[str]:
    prefix = f"{name}="
    for line in text.splitlines():
        if line.startswith(prefix):
            return line[len(prefix) :].split()
    raise SystemExit(f"missing {name}= assignment in {FPCMAKE}")


fpcmake = FPCMAKE.read_text(encoding="utf-8")
makefile = MAKEFILE.read_text(encoding="utf-8")

if "ptop" not in assignment(fpcmake, "dirs"):
    raise SystemExit("utils/ptop subdirectory is no longer built")
if "ptop" in assignment(fpcmake, "programs"):
    raise SystemExit("stale top-level ptop program target returned")
if "override TARGET_PROGRAMS:=$(filter-out ptop,$(TARGET_PROGRAMS))" not in makefile:
    raise SystemExit("generated Makefile no longer mirrors the ptop contract")

print("PTOP_BUILD_CONTRACT_PASS")
