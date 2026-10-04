#!/usr/bin/env python3
"""Check x86_64 register-width rewrites against an independent value oracle."""

import argparse
import hashlib
from itertools import product
import json
import os
from pathlib import Path
import subprocess


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CASES = list(product(
    ("SmallInt", "LongInt"),
    ("A1", "A2", "A1 + 1"),
    ("A1 xor A2", "A1 + A2", "A1 - A2"),
    (-5, 0, 3, 7),
    ("<", "<=", ">", ">=", "<>"),
    ("Y", "1"),
))
INPUTS = ((0, 1, -4), (7, -3, 5), (0, 4294967301, -1), (32767, 5, 4294967298))


def expected(case, data):
    _, cbase, abase, threshold, comparison, increment = case
    x, a1, a2 = data
    y = a2 & 0xffffffff
    c = {"A1": a1, "A2": a2, "A1 + 1": a1 + 1}[cbase]
    acc = {"A1 xor A2": a1 ^ a2, "A1 + A2": a1 + a2,
           "A1 - A2": a1 - a2}[abase]
    if a2 > threshold:
        c += 1
    if {"<": x < y, "<=": x <= y, ">": x > y,
        ">=": x >= y, "<>": x != y}[comparison]:
        acc += c
    if c > 2:
        acc += y if increment == "Y" else 1
    return acc + c


def generate():
    source = ["program width_matrix;", "{$mode delphi}", "{$H+}"]
    for index, (xtype, cbase, abase, threshold, comparison, increment) in enumerate(CASES):
        source.extend((
            f"function F{index:03d}(P: PSmallInt; A1, A2: Int64): Int64; noinline;",
            f"var X: {xtype}; Acc, C: Int64; Y: Cardinal;",
            "begin",
            f"  C := {cbase}; Acc := {abase}; X := P^; Y := Cardinal(A2);",
            f"  if A2 > {threshold} then Inc(C);",
            f"  if X {comparison} Y then Acc := Acc + C;",
            f"  if C > 2 then Inc(Acc, {increment});",
            "  Result := Acc + C;",
            "end;",
        ))
    source.extend(("var Zero: SmallInt;", "begin"))
    rows = []
    for data in INPUTS:
        x, a1, a2 = data
        source.append(f"  Zero := {x};")
        for index, case in enumerate(CASES):
            source.append(f"  Writeln(F{index:03d}(@Zero, {a1}, {a2}));")
            rows.append((index, data, expected(case, data)))
    source.append("end.")
    return "\n".join(source) + "\n", rows


def execute(command, directory, label, timeout):
    done = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=timeout)
    (directory / f"{label}.log").write_text(done.stdout + done.stderr, encoding="utf-8")
    if done.returncode:
        raise RuntimeError(f"{label} exited {done.returncode}; see {directory / (label + '.log')}")
    return done.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    binary = ROOT / "toolchain/bin"
    parser.add_argument("--compiler", type=Path, default=binary / ("x86_64-win64/ppcx64.exe" if os.name == "nt" else "fpc"))
    parser.add_argument("--config", type=Path, default=(binary / "x86_64-win64/moon-base.cfg" if os.name == "nt"
                                                     else ROOT / "toolchain/etc/moon-base.cfg"))
    parser.add_argument("--output", type=Path, default=ROOT / ".qualification/register-width-gate")
    args = parser.parse_args()
    compiler, config, output = (path.resolve() for path in (args.compiler, args.config, args.output))
    output.mkdir(parents=True, exist_ok=False)
    source, rows = generate()
    (output / "width_matrix.dpr").write_text(source, encoding="utf-8")
    (output / "oracle.txt").write_text("\n".join(str(row[2]) for row in rows) + "\n", encoding="utf-8")
    results = []
    for mode in ("O-", "O2", "O3"):
        directory = output / mode
        directory.mkdir()
        command = [str(compiler), "-n", "@" + str(config), "-" + mode, "-B",
                   "-FU" + str(directory), "-FE" + str(directory), str(output / "width_matrix.dpr")]
        execute(command, directory, "compile", 120)
        executable = directory / ("width_matrix.exe" if os.name == "nt" else "width_matrix")
        actual = execute([str(executable)], directory, "run", 30).splitlines()
        if len(actual) != len(rows):
            raise RuntimeError(f"{mode}: expected {len(rows)} rows, got {len(actual)}")
        for position, ((index, data, value), observed) in enumerate(zip(rows, actual)):
            if observed != str(value):
                raise RuntimeError(f"{mode}: row {position}, case {index} {CASES[index]}, input {data}: expected {value}, got {observed}")
        results.append({"mode": mode, "rows": len(rows)})
    structural = output / "structural"
    execute([os.sys.executable, str(HERE / "structural_gate.py"),
             "--compiler", "candidate=" + str(compiler), "--config", str(config),
             "--output", str(structural)], output, "structural", 600)
    flags = output / "flags"
    execute([os.sys.executable, str(HERE / "flags_fixture.py"),
             "--compiler", str(compiler), "--config", str(config),
             "--output", str(flags)], output, "flags", 180)
    structural_report = json.loads((structural / "report.json").read_text(encoding="utf-8"))
    flags_report = json.loads((flags / "report.json").read_text(encoding="utf-8"))
    if any(run["wrong"] for run in structural_report["runs"]):
        raise RuntimeError("structural width oracle disagreed; see structural/report.json")
    report = {"status": "pass", "functions": len(CASES), "inputs": len(INPUTS),
              "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "results": results, "structural_functions": structural_report["functions"],
              "structural_rows_per_mode": structural_report["rows"],
              "flags_rows": len(flags_report["results"])}
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"REGISTER_WIDTH_GATE_PASS original_functions={len(CASES)} "
          f"structural_functions={structural_report['functions']} "
          f"oracle_rows_per_mode={len(rows) + structural_report['rows']} "
          f"flags_rows={len(flags_report['results'])} modes=3")


if __name__ == "__main__":
    main()
