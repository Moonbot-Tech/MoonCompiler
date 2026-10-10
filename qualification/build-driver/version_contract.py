#!/usr/bin/env python3
"""Keep the MoonCompiler release identity separate from the FPC ABI version."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
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
        timeout=60,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode:
        raise RuntimeError(f"version probe failed ({result.returncode}): {result.stdout}")
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
            / "toolchain"
            / "bin"
            / "x86_64-win64"
            / "ppcx64.exe"
        )
    else:
        compiler = ROOT / "toolchain" / "bin" / "ppcx64"
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

    # Check public conditional/runtime identities here as well, before the long
    # qualification suites. A release bump must update their consumer oracle.
    probe = ROOT / "qualification/suite/tests/rtl-api/rtl_api_compiler_identity.dpr"
    with tempfile.TemporaryDirectory(prefix="moon-version-") as directory:
        run(compiler, "-FU" + directory, "-FE" + directory, str(probe))
        executable = Path(directory) / ("rtl_api_compiler_identity.exe" if os.name == "nt"
                                        else "rtl_api_compiler_identity")
        if run(executable) != "RTL_API_COMPILER_IDENTITY_OK":
            raise RuntimeError("public compiler identity probe failed")

    print(f"version contract PASS: {identity}; ABI {reported_base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
