#!/usr/bin/env python3
"""Cross-check EH-aware entry values, stable array bases and scalar controls.

Both builds use the same installed RTL and independently built program units.
Each generated case is a separate main program: moving its globals into helper
procedures would change the property under test. Every observation is compared
with a baseline, and array cases also have independent integer oracles. Without
--baseline, the reference is the current compiler with optimizations disabled.
"""

import argparse
import ctypes
import hashlib
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import array_cases
import entry_cases

ROOT = Path(__file__).resolve().parents[3]
MODES = {
    "O-": ["-O-"],
    "O2": ["-O-", "-O2"],
    "O3": ["-O-", "-O3"],
    "checked": ["-O-", "-O3", "-Cr", "-Co", "-Ct", "-Ci"],
}


def array_oracle(name, n):
    if name in {
        "descriptor_assignment",
        "absolute_descriptor",
        "pointer_descriptor",
        "var_call",
        "global_call",
        "indirect_call",
        "inline_mutation",
        "named_descriptor_alias",
        "generated_symbol_alias",
        "generated_symbol_field_alias",
    }:
        return 0 if n == 0 else 6 + 24 * (n - 1)
    if name == "descriptor_clear":
        return 6 * min(n, 2)
    if name == "setlength":
        return 94 if n == 4 else 6 * n
    if name in {"element_write", "aliased_elements"}:
        return {0: 0, 1: 9, 4: 42}[n]
    if name == "break":
        return 6 * min(n, 2)
    if name == "continue":
        return 6 * (n - int(n > 2))
    return 0 if name == "zero_nil" else 6 * n


def sources(directory):
    cases = []
    for name, body in entry_cases.cases.items():
        source = directory / ("entry_" + name + ".dpr")
        source.write_text(entry_cases.header + body + entry_cases.footer)
        cases.append((source, ("0", "1", "3"), None))
    for name, (declarations, before, body) in array_cases.cases.items():
        source = directory / ("array_" + name + ".dpr")
        source.write_text(
            array_cases.header
            + declarations
            + "\nbegin\n"
            + array_cases.setup
            + before
            + "\n"
            + body
            + "\nWriteln(Total);\nend.\n"
        )
        cases.append((source, ("0", "1", "4"), name))
    for name in (
        "tbranchscalarreuse1",
        "tbranchscalarvalues1",
        "tloopregvarliveness1",
        "tloopregvarpromote1",
        "tloopdynarraybase1",
        "tfoldruntimereal1",
        "tobservableintrinsics1",
        "tfloatminselect1",
        "tdelphinegativezero1",
        "tifminmaxtarget1",
        "tinlineminmaxsnapshot1",
        "tloopcompareorient1",
    ):
        inputs = ("1", "19", "43") if name == "tbranchscalarreuse1" else ("",)
        cases.append((ROOT / "tests/test/cg" / (name + ".pp"), inputs, None))
    for name in (
        "loop_global_array_semantic",
        "loop_local_dynarray_call_semantic",
        "loop_mutable_string_base_semantic",
        "loop_counter_observability_semantic",
        "dynarray_loop_latch_semantic",
    ):
        cases.append((ROOT / "RTL-test/semantic" / (name + ".dpr"), ("",), None))
    case_dir = Path(__file__).resolve().parent / "cases"
    for case in json.loads((case_dir / "cases.json").read_text()):
        cases.append(
            (
                case_dir / case["source"],
                case["inputs"],
                dict(zip(case["inputs"], case["last_lines"])),
            )
        )
    return cases


def check_case(case, mode, args, compilers, output):
    source, inputs, array_case = case
    flags = MODES[mode]
    rows = []
    observations = {}
    for variant, compiler in compilers.items():
        build_flags = flags
        if variant == "baseline" and args.baseline is None:
            build_flags = ["-O-"] + [flag for flag in flags if not flag.startswith("-O")]
        work = output / variant / mode / source.stem
        work.mkdir(parents=True, exist_ok=True)
        command = [
            str(compiler),
            "-n",
            "@" + str(args.config.resolve()),
            "-dRELEASE",
            *build_flags,
            "-Fu" + str(source.parent),
            "-FU" + str(work),
            "-FE" + str(work),
            str(source),
        ]
        build = subprocess.run(command, cwd=work, capture_output=True, timeout=90)
        (work / (source.stem + ".build.log")).write_bytes(build.stdout + build.stderr)
        if build.returncode:
            raise RuntimeError(f"build failed: {source.name}, {variant}, {mode}")
        executable = work / (source.stem + (".exe" if os.name == "nt" else ""))
        binary_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
        for value in inputs:
            run = subprocess.run(
                [str(executable)] + ([value] if value else []),
                cwd=work,
                capture_output=True,
                timeout=30,
            )
            stdout = run.stdout.replace(b"\r\n", b"\n")
            (work / (source.stem + value + ".run.log")).write_bytes(run.stdout + run.stderr)
            if run.returncode:
                raise RuntimeError(f"run failed: {source.name}, {variant}, {mode}, {value}")
            if isinstance(array_case, dict):
                if stdout.decode().splitlines()[-1] != array_case[value]:
                    raise AssertionError((source.name, variant, mode, value, stdout))
            elif array_case and int(stdout.splitlines()[-1]) != array_oracle(array_case, int(value)):
                raise AssertionError((source.name, variant, mode, value, stdout))
            observations[(variant, value)] = stdout
            rows.append(
                dict(
                    source=source.name,
                    variant=variant,
                    mode=mode,
                    flags=build_flags,
                    input=value,
                    sha256=hashlib.sha256(stdout).hexdigest(),
                    binary_sha256=binary_hash,
                )
            )
        executable.unlink()
        executable.with_suffix(".o").unlink(missing_ok=True)
    for value in inputs:
        if observations[("candidate", value)] != observations[("baseline", value)]:
            raise AssertionError((source.name, mode, value, observations))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--modes", nargs="+", choices=list(MODES), default=list(MODES))
    parser.add_argument(
        "--cases",
        default="",
        help="Optional source-name substring for a focused repeat",
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if os.name == "nt":
        ctypes.windll.kernel32.SetErrorMode(0x8003)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    generated = output / "sources"
    generated.mkdir()
    cases = [case for case in sources(generated) if args.cases in case[0].name]
    if not cases:
        raise SystemExit("No matching cases")
    compilers = {
        "baseline": (args.baseline or args.compiler).resolve(),
        "candidate": args.compiler.resolve(),
    }
    rows = []
    for mode in args.modes:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for checked in pool.map(lambda case: check_case(case, mode, args, compilers, output), cases):
                rows.extend(checked)
                (output / "results.json").write_text(json.dumps(rows, indent=2))
        print("PASS", mode, len(rows), "executions", flush=True)
    manifest = {name: hashlib.file_digest(path.open("rb"), "sha256").hexdigest() for name, path in compilers.items()}
    (output / "compilers.json").write_text(json.dumps(manifest, indent=2))
    inputs = [
        args.config.resolve(),
        *sorted(Path(__file__).resolve().parent.glob("*.py")),
        *sorted(generated.glob("*.dpr")),
        *(source for source, _, _ in cases),
    ]
    inputs.extend(sorted((Path(__file__).resolve().parent / "cases").glob("*.inc")))
    (output / "inputs.json").write_text(
        json.dumps(
            {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
            indent=2,
        )
    )
    print("ANALYTICS_GATE_PASS", len(rows), flush=True)


if __name__ == "__main__":
    main()
