#!/usr/bin/env python3
"""Check ordinal case dispatch against raw-storage values and an independent oracle."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from check_shapes import run_shapes

MODES = {"O-": ["-O-"], "O1": ["-O1"], "O2": ["-O2"], "O3": ["-O3"],
         "Os": ["-O2", "-Os"], "checked": ["-O3", "-Cr", "-Co"], "ppu": ["-O3"]}


def labels(items):
    return ",\n    ".join(",".join(items[i:i+10]) for i in range(0, len(items), 10))


def generate(directory, delphi=False):
    # Values immediately outside the declaration, storage extrema, and every
    # byte pattern catch both skipped guards and narrowed selector arithmetic.
    specifications = [
        ("E8", 1, list(range(37)), None),
        ("E16", 2, list(range(37)), None),
        ("E32", 4, list(range(37)), None),
        ("Twelve", 1, list(range(12)), None),
        ("Thirteen", 1, list(range(13)), None),
        ("Offset", 1, list(range(11, 48)), None),
        ("Holes", 1, [0, 1, 7, 11, 19, 23, 31, 36], None),
        ("Almost", 1, list(range(240)), None),
        ("U8Sub", 1, list(range(10, 47)), "10..46"),
        ("S8Sub", 1, list(range(-19, 18)), "-19..17"),
        ("S16Sub", 2, list(range(-273, -236)), "-273..-237"),
        ("U16Sub", 2, list(range(260, 297)), "260..296"),
        ("ByteFull", 1, list(range(256)), "Byte"),
        ("Int64", 8, list(range(-19, 18)), "Int64"),
    ]
    if not delphi:
        specifications += [
            ("U64Sub", 8, list(range(2**63, 2**63+37)), "$8000000000000000..$8000000000000024"),
            ("U64Top", 8, list(range(2**64-37, 2**64)), "UInt64"),
            ("I64Bottom", 8, list(range(-2**63, -2**63+37)), "Int64"),
        ]
    header = ["unit case_inputs;", "{$IFDEF FPC}{$mode delphi}{$ENDIF}", "{$INLINE OFF}", "interface",
              "var Evaluations: Integer;"]
    implementation = ["implementation"]
    body = ["program case_matrix;", "{$APPTYPE CONSOLE}", "{$IFDEF FPC}{$mode delphi}{$ENDIF}",
            "{$INLINE OFF}", "uses case_inputs;", "var Visits: Integer;"]
    calls = ["begin"]
    checks = 0
    functions = 0
    for name, size, values, ordinal in specifications:
        label = lambda v: str(v) if ordinal else f"{name}_{v}"
        rawtype = "UInt64" if name.startswith("U64") else "Int64"
        definition = ordinal or "(" + labels([f"{label(v)}={v}" for v in values]) + ")"
        header += [f"{{$Z{min(size, 4)}}}", f"type T{name} = {definition};",
                   f"function Read{name}(Raw: {rawtype}): T{name};"]
        implementation += [f"function Read{name}(Raw: {rawtype}): T{name};", "begin",
                           "  Inc(Evaluations);", "  Move(Raw, Result, SizeOf(Result));", "end;"]
        inputs = list(range(256))
        if min(values) < 0:
            inputs = list(range(-128, 128)) + [min(values)-1, min(values), max(values), max(values)+1]
        if size >= 2:
            inputs += [255, 256, 259, 260, 296, 297, 32767, 32768, 65535]
        if size >= 4:
            inputs += [65536, 2147483647, 2147483648, 4294967295]
        if size == 8 and not delphi:
            inputs += [-9223372036854775808, 9223372036854775807]
        if rawtype == "UInt64":
            inputs = [v for v in inputs if v >= 0] + [2**63-1, 2**63, 2**64-1]
            inputs += [min(values)-1] + values
        elif size == 8:
            inputs = [v for v in inputs + values if -2**63 <= v < 2**63]
        if size == 8 and delphi:
            # Delphi Win64 narrows this case selector to 32 bits. Keep the
            # full-width boundaries under the independent Moon ordinal oracle.
            inputs = [v for v in inputs if -2147483648 <= v <= 2147483647]
        inputs = sorted(set(inputs))
        for shape in ("full", "partial", "tree", "grouped", "range", "single", "noelse"):
            if shape in ("full", "noelse"):
                groups = [[v] for v in values]
            elif shape == "partial":
                groups = [[v] for v in values[1:-1:2]]
            elif shape == "tree":
                groups = [[v] for v in values[::max(1, len(values)//8)]]
            elif shape == "grouped":
                groups = [values[i::3] for i in range(3)]
            elif shape == "single":
                groups = [[values[0]]]
            else:
                groups = [values]
            expected = {}
            fname = f"Dispatch{name}_{shape}"
            body += [f"function {fname}(Raw: {rawtype}): Integer;", "begin", "  Result := -1;",
                     f"  case Read{name}(Raw) of"]
            for i, group in enumerate(groups):
                result = 1009 + i*37
                case_labels = f"{label(group[0])}..{label(group[-1])}" if shape == "range" else labels(list(map(label, group)))
                for v in (range(group[0], group[-1]+1) if shape == "range" else group):
                    expected[v] = result
                body += [f"    {case_labels}: begin Result := {result}; Inc(Visits); end;"]
            if shape != "noelse":
                body += ["  else", "    Result := -1;"]
            body += ["  end;", "end;"]
            functions += 1
            body += [f"procedure Check{fname};", "begin"]
            for raw in inputs:
                # Interpret bytes independently of the declared type range.
                stored = raw & ((1 << (8*size))-1)
                if min(values) < 0 and stored >= (1 << (8*size-1)):
                    stored -= 1 << (8*size)
                value = expected.get(stored, -1)
                body += ["  Evaluations := 0; Visits := 0;",
                          f"  if ({fname}({raw}) <> {value}) or (Evaluations <> 1) or (Visits <> {int(value != -1)}) then begin",
                          f"    Writeln('FAIL {fname} raw={raw}'); Halt(1); end;"]
                checks += 1
            body += ["end;"]
            calls += [f"  Check{fname};"]
    body += ["function BoolControl(B: Boolean): Integer;", "begin", "  case B of",
             "    False: Result := 7; True: Result := 9; else Result := -1; end;", "end;",
             "function CharControl(C: WideChar): Integer;", "begin", "  case C of",
             "    'A': Result := 1; 'Z': Result := 2; else Result := -1; end;", "end;"]
    calls += ["  if (BoolControl(False) <> 7) or (BoolControl(True) <> 9) then Halt(2);",
              "  if (CharControl('A') <> 1) or (CharControl(WideChar($FFFF)) <> -1) then Halt(3);",
              f"  Writeln('CASE_STORAGE_PASS checks={checks} functions={functions}');", "end."]
    (directory / "case_inputs.pas").write_text("\n".join(header + implementation + ["end."]) + "\n", encoding="utf-8")
    (directory / "case_matrix.dpr").write_text("\n".join(body + calls) + "\n", encoding="utf-8")
    return checks, functions


def run(command, directory, name, timeout=120):
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=timeout)
    (directory / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{name}: exit {result.returncode}; see {directory / (name + '.log')}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--delphi", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--modes", nargs="+", choices=list(MODES), default=list(MODES))
    args = parser.parse_args()
    if not args.delphi and args.config is None:
        parser.error("--config is required for MoonCompiler")
    compiler = args.compiler.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    checks, functions = generate(output, args.delphi)
    results = []
    for mode in (["O3"] if args.delphi else args.modes):
        directory = output / mode
        directory.mkdir()
        if args.delphi:
            command = [str(compiler), "-B", "-Q", "-NSSystem", "-E"+str(directory), "-N0"+str(directory)]
        else:
            command = [str(compiler), "-n", "@"+str(args.config.resolve()), "-Fu"+str(output),
                       "-FU"+str(directory), "-FE"+str(directory)]
            if mode == "ppu":
                run(command + ["-O-", str(output/"case_inputs.pas")], directory, "producer")
            command += MODES[mode]
        run(command + [str(output/"case_matrix.dpr")], directory, "compile")
        executable = directory / ("case_matrix.exe" if os.name == "nt" else "case_matrix")
        actual = run([str(executable)], directory, "run", 30).strip()
        expected = f"CASE_STORAGE_PASS checks={checks} functions={functions}"
        if actual != expected:
            raise RuntimeError(f"Unexpected result: {actual!r}")
        fixture = Path(__file__).resolve().with_name("case_stream_bool.dpr")
        run(command + [str(fixture)], directory, "stream-compile")
        executable = directory / ("case_stream_bool.exe" if os.name == "nt" else "case_stream_bool")
        if run([str(executable)], directory, "stream-run", 30).strip() != "CASE_STREAM_BOOL_PASS":
            raise RuntimeError("Raw stream or Boolean case contract failed")
        results.append({"mode": mode, "checks": checks})
        print(mode, actual, flush=True)
    shapes = {} if args.delphi else run_shapes(compiler, args.config.resolve(), output/"shapes")
    report = {"status": "pass", "shapes": shapes, "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "checks_per_mode": checks, "functions": functions, "results": results}
    (output/"result.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(f"CASE_STORAGE_GATE_PASS modes={len(results)} checks={checks*len(results)}")


if __name__ == "__main__":
    main()
