#!/usr/bin/env python3
"""Run public RTL consumers outside the source tree with an installed toolchain."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "RTL-test" / "semantic"
CASES = (
    "base64_size_boundaries",
    "encoding_boundaries", "file_boundaries", "hash_regex_iso_boundaries",
    "json_lifetime_boundaries", "json_numeric_boundaries", "lightweight_boundaries", "loader_boundaries",
    "uri_boundaries",
    "anonymous_cleanup_external_owner", "asm_delphi_operands", "forcequeue_first_thread",
    "numeric_overload_precision", "typed_const_character_pointers",
    "reader_value_transfer",
)


def run(command, directory):
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                            errors="replace", timeout=60)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve(strict=True)
    output = args.out.resolve()
    cases = CASES + (("windows_boundaries", "win64_classes_callbacks") if os.name == "nt" else ())
    suffix = ".exe" if os.name == "nt" else ""
    count = 0
    for profile, options in (("debug", []), ("release", ["-dRELEASE"])):
        directory = output / profile
        directory.mkdir(parents=True, exist_ok=False)
        # Only consumer sources are staged: there is no -Fu back into the clone.
        for case in cases:
            name = case + "_semantic.dpr"
            shutil.copy2(SOURCES / name, directory / name)
        fixture = "loader_boundary_fixture.pas"
        shutil.copy2(SOURCES / "support" / fixture, directory / fixture)
        run([str(compiler), *options, fixture], directory)
        for case in cases:
            name = case + "_semantic"
            run([str(compiler), *options, name + ".dpr"], directory)
            result = run([str(directory / (name + suffix))], directory)
            if case.upper() + "_PASS" not in result.splitlines():
                raise RuntimeError(f"Missing result for {name} {profile}: {result}")
            count += 1
            print(f"PASS {name} {profile}", flush=True)
    print(f"RTL_BOUNDARIES_ARCHIVE_PASS rows={count}")


if __name__ == "__main__":
    main()
