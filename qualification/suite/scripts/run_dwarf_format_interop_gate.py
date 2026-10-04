#!/usr/bin/env python3
"""Link interface debug types across separately compiled DWARF formats."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


FORMAT_PAIRS = ((3, 2), (4, 2), (5, 2), (2, 3))
MARKER = "DWARF_FORMAT_INTEROP_PASS"


def compilation_unit_versions(output: str) -> dict[str, set[int]]:
    units: dict[str, set[int]] = {}
    blocks = re.split(r"(?=^\s*Compilation Unit @ offset )", output, flags=re.MULTILINE)
    for block in blocks:
        version_match = re.search(r"^\s*Version:\s+(\d+)\s*$", block, re.MULTILINE)
        name_match = re.search(r"DW_AT_name\s*:\s*(.+?)\s*$", block, re.MULTILINE)
        if version_match and name_match:
            units.setdefault(Path(name_match.group(1)).name, set()).add(int(version_match.group(1)))
    return units


def run(
    command: list[str], cwd: Path, log: Path, env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, cwd=cwd, capture_output=True, text=True, timeout=120,
        check=False, env=env,
    )
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("run_id")
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    config = args.config.resolve()
    root = args.compiler_root.resolve()
    if not compiler.is_file() or not config.is_file():
        parser.error("compiler and config must exist")

    sources = root / "qualification" / "suite" / "tests" / "smoke" / "dwarf-format-interop"
    provider_source = sources / "provider" / "dwarf_format_provider.pas"
    consumer_source = sources / "consumer" / "dwarf_format_link.pas"
    output = root / "qualification" / "suite" / "results" / "runs" / args.run_id / "dwarf-format-interop"
    if output.exists():
        parser.error(f"run already exists: {output}")
    output.mkdir(parents=True)

    failures: list[str] = []
    results: list[dict[str, object]] = []
    common = [
        str(compiler), "-n", f"@{config}", "-Mdelphi", "-O2",
        "-dMOONCOMPILER_VANILLA_RUNTIME",
    ]
    executable_name = "dwarf_format_link" + (".exe" if os.name == "nt" else "")

    for provider_format, consumer_format in FORMAT_PAIRS:
        label = f"dwarf{provider_format}-to-dwarf{consumer_format}"
        case = output / label
        provider_output = case / "provider"
        consumer_output = case / "consumer"
        provider_output.mkdir(parents=True)
        consumer_output.mkdir(parents=True)

        provider = run(
            [*common, f"-gw{provider_format}", f"-FU{provider_output}", str(provider_source)],
            root, case / "provider.log",
        )
        consumer: subprocess.CompletedProcess[str] | None = None
        executed: subprocess.CompletedProcess[str] | None = None
        inspected: subprocess.CompletedProcess[str] | None = None
        if provider.returncode == 0:
            consumer = run(
                [*common, f"-gw{consumer_format}", "-CX", "-XX",
                 f"-Fu{provider_output}", f"-FU{consumer_output}",
                 f"-FE{consumer_output}", str(consumer_source)],
                root, case / "consumer.log",
            )
        executable = consumer_output / executable_name
        inspection_available = True
        debug_units: dict[str, set[int]] = {}
        if consumer is not None and consumer.returncode == 0 and executable.is_file():
            executed = run([str(executable)], root, case / "run.log")
            readelf = shutil.which("readelf") if os.name != "nt" else None
            if os.name != "nt" and readelf is None:
                inspection_available = False
            elif readelf:
                inspect_env = os.environ.copy()
                inspect_env["LC_ALL"] = "C"
                inspected = run(
                    [readelf, "--debug-dump=info", str(executable)],
                    root, case / "readelf.log", inspect_env,
                )
                debug_units = compilation_unit_versions(inspected.stdout)

        passed = (
            provider.returncode == 0
            and consumer is not None
            and consumer.returncode == 0
            and executed is not None
            and executed.returncode == 0
            and executed.stdout.count(MARKER) == 1
            and inspection_available
            and (inspected is None or (
                inspected.returncode == 0
                and not inspected.stderr
                and provider_format in debug_units.get(provider_source.name, set())
                and consumer_format in debug_units.get(consumer_source.name, set())
            ))
        )
        if not passed:
            failures.append(label)
        results.append({
            "case": label,
            "provider_exit": provider.returncode,
            "consumer_exit": None if consumer is None else consumer.returncode,
            "run_exit": None if executed is None else executed.returncode,
            "debug_info_exit": None if inspected is None else inspected.returncode,
            "debug_units": {
                name: sorted(versions) for name, versions in sorted(debug_units.items())
                if name in {provider_source.name, consumer_source.name}
            },
            "marker_count": 0 if executed is None else executed.stdout.count(MARKER),
            "passed": passed,
        })

    (output / "manifest.json").write_text(
        json.dumps({"results": results, "failures": failures}, indent=2) + "\n",
        encoding="utf-8",
    )
    if failures:
        print("DWARF_FORMAT_INTEROP_FAIL: " + ", ".join(failures))
        return 1
    print(f"DWARF_FORMAT_INTEROP_PASS cases={len(results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
