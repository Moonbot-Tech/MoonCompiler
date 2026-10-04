#!/usr/bin/env python3
"""Run the complete upstream RTL unit corpus with the MoonCompiler toolchain."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "tests" / "test" / "units"
EXPECTATIONS = Path(__file__).with_name("expectations.json")
DIRECTIVE = re.compile(r"\{\s*%([A-Z]+)(?:\s*=\s*([^}]*?))?\s*\}", re.IGNORECASE)
MODES = {
    "debug": ["-O-", "-gl", "-gw3"],
    "o2": ["-O2", "-gl", "-gw3"],
    "o3": ["-O3", "-gl", "-gw3"],
}
PRODUCT_CORPUS_DIRS = {
    "character", "classes", "contnrs", "convutils", "cpu", "dateutil", "dos",
    "fmtbcd", "fpwidestring", "lineinfo", "math", "nullable", "objpas",
    "rtl-generics", "sharemem", "softfpu", "sortbase", "strings", "strutils",
    "system", "sysutils", "tuples", "types", "variants", "windows",
}


def toolchain() -> tuple[Path, Path, list[str], str, str]:
    if os.name == "nt":
        base = ROOT / "toolchain" / "bin" / "x86_64-win64"
        return base / "fpc.exe", base / "moon-base.cfg", ["-Px86_64", "-Twin64"], ".exe", "win64"
    if sys.platform == "linux" and os.uname().machine == "x86_64":
        base = ROOT / "toolchain"
        return (
            base / "bin" / "fpc",
            base / "etc" / "moon-base.cfg",
            ["-Px86_64", "-Tlinux", "-dPOSIX"],
            "",
            "linux",
        )
    raise RuntimeError("upstream RTL corpus supports only Win64 and Linux x86-64")


def directives(source: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name, value in DIRECTIVE.findall(source):
        result.setdefault(name.upper(), []).append(value.strip())
    return result


def target_matches(values: list[str], host: str) -> bool:
    if not values:
        return True
    targets = {
        item.strip().casefold()
        for value in values
        for item in value.split(",")
        if item.strip()
    }
    return host in targets


def execute(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
        check=False,
    )


def failure_tail(output: str, lines: int = 40) -> str:
    return "\n".join(output.splitlines()[-lines:])


def compile_outcome(settings: dict[str, list[str]], returncode: int) -> str:
    """Classify the compiler result, including the upstream %FAIL contract."""
    if "FAIL" in settings:
        return "expected_failure" if returncode != 0 else "unexpected_success"
    return "success" if returncode == 0 else "unexpected_failure"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--modes", nargs="+", choices=tuple(MODES), default=["o2"])
    parser.add_argument("--units", nargs="*", help="unit directory names; default is all")
    parser.add_argument("--only", help="regular expression for a relative source path")
    parser.add_argument("--compiler", type=Path, help="backend under test; defaults to the installed product compiler")
    args = parser.parse_args()

    compiler, config, target, suffix, host = toolchain()
    if args.compiler:
        compiler = args.compiler.resolve()
    for required in (compiler, config):
        if not required.is_file():
            raise RuntimeError(f"required product file is missing: {required}")

    expectations = json.loads(EXPECTATIONS.read_text(encoding="utf-8"))
    excluded = {
        item["source"].casefold(): item["reason"]
        for item in expectations["excluded"]
    }
    selected_units = {item.casefold() for item in args.units or []}
    pattern = re.compile(args.only) if args.only else None
    sources: list[tuple[Path, dict[str, list[str]]]] = []
    skipped = 0
    for source in sorted((*CORPUS.rglob("*.pp"), *CORPUS.rglob("*.pas"))):
        relative = source.relative_to(CORPUS)
        if relative.parts[0].casefold() not in PRODUCT_CORPUS_DIRS:
            continue
        if selected_units and relative.parts[0].casefold() not in selected_units:
            continue
        if pattern and not pattern.search(relative.as_posix()):
            continue
        if relative.as_posix().casefold() in excluded:
            skipped += 1
            print(f"SKIP {relative.as_posix()} {excluded[relative.as_posix().casefold()]}")
            continue
        source_text = source.read_text(encoding="utf-8", errors="replace")
        if re.match(
            r"(?is)^\s*(?:\{.*?\}|\(\*.*?\*\)|//[^\n]*\n\s*)*(?:unit|library)\s+",
            source_text,
        ):
            skipped += 1
            continue
        settings = directives(source_text)
        if "INTERACTIVE" in settings or "NEEDEDAFTER" in settings:
            skipped += 1
            continue
        if not target_matches(settings.get("TARGET", []), host):
            skipped += 1
            continue
        sources.append((source, settings))
    if not sources:
        raise RuntimeError("no upstream RTL tests selected")

    work = Path(tempfile.mkdtemp(prefix="rtl-upstream-"))
    passed = 0
    failures: list[str] = []
    try:
        for source, settings in sources:
            relative = source.relative_to(CORPUS)
            expected = int(settings.get("RESULT", ["0"])[-1] or "0")
            extra = [
                option
                for value in settings.get("OPT", [])
                for option in shlex.split(value, posix=os.name != "nt")
            ]
            for mode in args.modes:
                output = work / relative.parent / source.name.replace(".", "_") / mode
                output.mkdir(parents=True)
                for value in settings.get("FILES", []):
                    for filename in shlex.split(value, posix=os.name != "nt"):
                        shutil.copy2(source.parent / filename, output / filename)
                command = [
                    str(compiler),
                    "-n",
                    f"@{config}",
                    *target,
                    "-dMOONBOT_MM_PROFILE_REQUIRED",
                    "-dFPCMM_BOOSTER",
                    "-dFPCMM_MOONSHARD",
                    f"-Fu{source.parent}",
                    f"-Fu{ROOT / 'tests' / 'tstunits'}",
                    f"-Fi{source.parent}",
                    f"-FU{output}",
                    f"-FE{output}",
                    *MODES[mode],
                    *extra,
                    str(source),
                ]
                compiled = execute(command, source.parent)
                outcome = compile_outcome(settings, compiled.returncode)
                if outcome == "expected_failure":
                    passed += 1
                    print(
                        f"PASS {relative.as_posix()} {mode} "
                        "(expected compile failure)",
                        flush=True,
                    )
                    continue
                if outcome == "unexpected_failure":
                    failure = f"compile failed: {relative} {mode}"
                    failures.append(failure)
                    print(f"FAIL {failure}\n{failure_tail(compiled.stdout)}", file=sys.stderr)
                    continue
                if outcome == "unexpected_success":
                    failure = f"unexpected compile success: {relative} {mode}"
                    failures.append(failure)
                    print(f"FAIL {failure}", file=sys.stderr)
                    continue
                if "NORUN" not in settings:
                    executable = output / f"{source.stem}{suffix}"
                    run_args = [
                        argument
                        for value in settings.get("ARGS", [])
                        for argument in shlex.split(value, posix=os.name != "nt")
                    ]
                    try:
                        run = execute([str(executable), *run_args], output)
                    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
                        failure = f"run failed: {relative} {mode}: {error}"
                        failures.append(failure)
                        print(f"FAIL {failure}", file=sys.stderr)
                        continue
                    if run.returncode != expected:
                        failure = (
                            f"runtime failed: {relative} {mode} "
                            f"result={run.returncode} expected={expected}"
                        )
                        failures.append(failure)
                        print(f"FAIL {failure}\n{failure_tail(run.stdout)}", file=sys.stderr)
                        continue
                passed += 1
                print(f"PASS {relative.as_posix()} {mode}", flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    expected_rows = len(sources) * len(args.modes)
    print(
        f"RTL_UPSTREAM_PASS rows={passed}/{expected_rows} sources={len(sources)} "
        f"skipped={skipped} failures={len(failures)}"
    )
    if failures:
        print("RTL_UPSTREAM_FAILURES")
        for failure in failures:
            print(f"- {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
