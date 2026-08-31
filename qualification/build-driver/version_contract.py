#!/usr/bin/env python3
"""Keep the MoonCompiler release identity separate from the FPC ABI version."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERSION_SOURCE = ROOT / "compiler" / "version.pas"


def source_constant(source: str, name: str) -> str:
    match = re.search(
        rf"^\s*{re.escape(name)}\s*=\s*'([^']*)';",
        source,
        flags=re.MULTILINE,
    )
    if not match:
        raise RuntimeError(f"missing {name} in {VERSION_SOURCE}")
    return match.group(1)


def run(compiler: Path, *args: str) -> str:
    result = subprocess.run(
        [str(compiler), *args],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.stdout.strip()


def main() -> int:
    source = VERSION_SOURCE.read_text(encoding="utf-8")
    base_version = ".".join(
        source_constant(source, part)
        for part in ("version_nr", "release_nr", "patch_nr")
    )
    product_version = source_constant(source, "mooncompiler_version")
    identity = (
        f"MoonCompiler {product_version} (Free Pascal base {base_version})"
    )

    if os.name == "nt":
        compiler = (
            ROOT
            / ".moonbot"
            / "toolchain"
            / "bin"
            / "x86_64-win64"
            / "ppcx64.exe"
        )
    else:
        compiler = ROOT / ".moonbot" / "toolchain" / "bin" / "ppcx64"
    if not compiler.is_file():
        raise RuntimeError(f"built compiler is missing: {compiler}")

    reported_base = run(compiler, "-iV")
    if reported_base != base_version:
        raise RuntimeError(
            f"-iV changed from the FPC ABI version: {reported_base!r}"
        )
    banner = run(compiler, "-h").splitlines()[0]
    if not banner.startswith(identity + " ["):
        raise RuntimeError(f"unexpected compiler banner: {banner!r}")

    print(f"version contract PASS: {identity}; ABI {reported_base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
