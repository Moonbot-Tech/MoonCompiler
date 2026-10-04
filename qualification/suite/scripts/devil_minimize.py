#!/usr/bin/env python3
"""Cut a red Devil check down to a standalone program.

Takes the generated layer, keeps the single procedure that produced the check
plus the shared support declarations, and writes a small program that still
reproduces the disagreement.  Then it verifies the cut: the program is built at
the two optimization levels that disagreed and the outputs are compared.

    devil_minimize.py dvl-expr-00203-form --seed 1 --cases 200 \
        --profiles debug,release
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
GENERATOR = ROOT / "scripts" / "generate_devil.py"
FINALIZATION_RE = re.compile(r"^DEVIL_FINALIZATION checks=(?P<checks>\d+)$")
FAILURE_RE = re.compile(
    r"^DEVIL_FAILURE (?P<name>[a-z0-9-]+) "
    r"actual=(?P<actual>[0-9A-F]{16}) "
    r"expected=(?P<expected>[0-9A-F]{16})$")
CHECK_RE = re.compile(
    r"^DEVIL_CHECK (?P<name>[a-z0-9-]+) "
    r"actual=(?P<actual>[0-9A-F]{16}) "
    r"expected=(?P<expected>[0-9A-F]{16})$")
NOTE_RE = re.compile(r"^DEVIL_NOTE [a-z0-9-]+=[0-9A-F]{16}$")
TRAIL_RE = re.compile(r"^DEVIL_TRAIL [a-z0-9-]+=\S*$")
PASS_SUMMARY_RE = re.compile(
    r"^DEVIL_MIN_PASS seed=(?P<seed>\d+) checks=(?P<checks>\d+) "
    r"digest=[0-9A-F]{16}$")
FAIL_SUMMARY_RE = re.compile(
    r"^DEVIL_MIN_FAIL seed=(?P<seed>\d+) "
    r"failures=(?P<failures>[1-9][0-9]*) checks=(?P<checks>\d+) "
    r"digest=[0-9A-F]{16}$")

PROGRAM = """program devil_min;

{{ Cut from Devil layer {layer}, seed {seed}, case {case}. }}

{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
  {{$modeswitch advancedrecords}}
  {{$modeswitch anonymousfunctions}}
  {{$modeswitch functionreferences}}
  {{$modeswitch INLINEVARS}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}

uses
{{$ifdef FPC}}
  {{$ifdef UNIX}}cthreads,{{$endif}}
{{$endif}}
  SysUtils, Classes, Math, TypInfo, Rtti, devil_runtime;

{{$I devil_support.inc}}

{body}

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  {call};
  DevilArmReport('DEVIL_MIN', {seed});
end.
"""


def run(cmd: list[str], cwd: Path, timeout: int = 300) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def runtime_signature(
        code: int, output: str, expected_seed: int | None = None,
        ) -> tuple[bool, tuple[int, str, tuple[str, ...]], str]:
    """Bind a minimized observation to normal finalization and process exit."""
    finalization: list[tuple[int, int]] = []
    summaries: list[tuple[int, re.Match[str], str, str]] = []
    failure_count = 0
    check_count = 0
    failed_check_count = 0
    last_check: tuple[int, str, str, str] | None = None
    protocol_errors: list[str] = []
    events: list[str] = []
    last_nonempty = -1
    for line_no, raw in enumerate(output.splitlines()):
        line = raw.strip()
        if line:
            last_nonempty = line_no
        match = FINALIZATION_RE.match(line)
        if match:
            finalization.append((line_no, int(match.group("checks"))))
            continue
        match = PASS_SUMMARY_RE.match(line)
        verdict = "PASS"
        if not match:
            match = FAIL_SUMMARY_RE.match(line)
            verdict = "FAIL"
        if match:
            summaries.append((line_no, match, verdict, line))
            continue
        match = CHECK_RE.match(line)
        if match:
            check_count += 1
            if match.group("actual") != match.group("expected"):
                failed_check_count += 1
            last_check = (line_no, match.group("name"),
                          match.group("actual"), match.group("expected"))
            events.append(line)
            continue
        match = FAILURE_RE.match(line)
        if match:
            failure_count += 1
            paired = (line_no - 1, match.group("name"),
                      match.group("actual"), match.group("expected"))
            if last_check != paired or paired[2] == paired[3]:
                protocol_errors.append(
                    f"line {line_no + 1}: failure is not paired with "
                    "the preceding failed check"
                )
            events.append(line)
            continue
        if NOTE_RE.match(line) or TRAIL_RE.match(line):
            events.append(line)
            continue
        if line.startswith("DEVIL_"):
            protocol_errors.append(
                f"line {line_no + 1}: malformed protocol record"
            )
    errors: list[str] = list(protocol_errors)
    if len(finalization) != 1:
        errors.append(f"finalization markers={len(finalization)}")
    if len(summaries) != 1:
        errors.append(f"terminal summaries={len(summaries)}")
    if not errors:
        final_line, final_checks = finalization[0]
        summary_line, summary, verdict, _ = summaries[0]
        if (summary_line != final_line + 1 or summary_line != last_nonempty
                or final_checks != int(summary.group("checks"))):
            errors.append("summary does not follow complete finalization")
        if (expected_seed is not None
                and int(summary.group("seed")) != expected_seed):
            errors.append(
                f"terminal seed={summary.group('seed')}, "
                f"expected={expected_seed}"
            )
        reported = (0 if verdict == "PASS"
                    else int(summary.group("failures")))
        if (check_count != final_checks
                or failed_check_count != failure_count
                or (verdict == "PASS" and reported != 0)
                or (verdict == "FAIL" and reported == 0)
                or reported != failure_count):
            errors.append("verdict/failure count is inconsistent")
        if code != 0:
            errors.append(f"abnormal process exit={code}")
    terminal = summaries[0][3] if len(summaries) == 1 else "(no valid summary)"
    return not errors, (code, terminal, tuple(events)), "; ".join(errors)


def collect_routines(text: str) -> list[tuple[str, int, int]]:
    """Return complete ranges for top-level generated routines.

    Generated layers contain nested ``case``/``try`` blocks and overloaded
    forward declarations.  Counting bare ``begin``/``end`` lines loses both
    contracts: an inner ``end;`` looks like the end of the routine, while a
    dict keyed by name drops overloads.  Top-level headers are unindented, so
    the next one is the authoritative outer boundary.  The last ``end;`` in
    that segment closes an implementation; a segment without one is a
    declaration and must be preserved as-is.
    """
    lines = text.splitlines()
    header = re.compile(r"^(?:procedure|function)\s+([A-Za-z_][\w.]*)")
    headers: list[tuple[str, int]] = []
    for i, line in enumerate(lines):
        m = header.match(line)
        if m:
            headers.append((m.group(1), i))
    spans: list[tuple[str, int, int]] = []
    for pos, (name, start) in enumerate(headers):
        boundary = headers[pos + 1][1] if pos + 1 < len(headers) else len(lines)
        closes = [i for i in range(start, boundary)
                  if lines[i].strip().lower() == "end;"]
        if closes:
            end = closes[-1] + 1
        else:
            end = boundary
            while end > start and not lines[end - 1].strip():
                end -= 1
        spans.append((name, start, end))
    return spans


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("name")
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--cases", type=int, default=200)
    p.add_argument("--profiles", default="debug,release")
    p.add_argument("--out", type=Path,
                   default=ROOT / "results" / "runs" / "devil-minimized")
    args = p.parse_args()

    generated = args.out.resolve().parent / (args.out.name + "-source")
    if generated.exists():
        shutil.rmtree(generated)
    code, log = run([sys.executable, str(GENERATOR), "--seed", str(args.seed),
                     "--cases", str(args.cases), "--out", str(generated)],
                    ROOT.parent.parent)
    if code != 0:
        shutil.rmtree(generated, ignore_errors=True)
        print("generator failed: " + (log.strip().splitlines()[-1]
                                      if log.strip() else "no diagnostic"))
        sys.exit(2)

    manifest = json.loads(
        (generated / "devil_manifest.json").read_text(encoding="utf-8"))
    case = None
    for c in manifest["cases"]:
        if args.name.startswith(c["name"]):
            case = c
            break
    if case is None:
        shutil.rmtree(generated, ignore_errors=True)
        print(f"no case for {args.name}")
        sys.exit(1)

    layer = case["layer"]
    inc = generated / f"devil_{layer}.inc"
    text = inc.read_text(encoding="utf-8")
    shutil.rmtree(generated)
    spans = collect_routines(text)
    index = case["name"].rsplit("-", 1)[-1]
    proc = "Dvl" + layer.capitalize() + index

    # the case procedure plus everything the generator emitted for it: types
    # declared right before it and helper routines carrying the same index
    wanted = [span for span in spans if index in span[0]]
    if not any(name == proc for name, _, _ in wanted):
        print(f"procedure {proc} not found in {inc.name}")
        sys.exit(1)
    lines = text.splitlines()
    keep: list[str] = []
    # type blocks that mention the case index
    for i, line in enumerate(lines):
        if line.strip() == "type" and any(index in lines[j]
                                          for j in range(i, min(i + 12, len(lines)))):
            j = i
            while j < len(lines) and lines[j].strip() != "":
                keep.append(lines[j])
                j += 1
            keep.append("")
    for _, start, end in sorted(wanted, key=lambda span: span[1]):
        keep.extend(lines[start:end])
        keep.append("")

    # Keep every compiler/output path independent from the subprocess cwd.
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy(DEVIL / "devil_support.inc", out / "devil_support.inc")
    shutil.copy(DEVIL / "devil_runtime.pas", out / "devil_runtime.pas")
    program = PROGRAM.format(layer=layer, seed=args.seed, case=case["name"],
                             body="\n".join(keep), call=proc)
    (out / "devil_min.dpr").write_text(program, encoding="utf-8")
    print(f"cut {len(keep)} lines into {out / 'devil_min.dpr'}")

    results: dict[str, object] = {}
    compile_failed = False
    invalid_runtime = False
    for profile in args.profiles.split(","):
        build = out / f"out-{profile}"
        if build.exists():
            shutil.rmtree(build)
        build.mkdir()
        code, log = run(tc.compile_command(out / "devil_min.dpr", build,
                                           profile), out)
        exe = tc.executable(build, "devil_min")
        if not exe.exists():
            lines = log.strip().splitlines()
            results[profile] = "COMPILE FAILED: " + (lines[-1] if lines else "no diagnostic")
            print(f"{profile:8}: {results[profile]}")
            compile_failed = True
            continue
        code, output = run([str(exe)], out)
        valid, signature, error = runtime_signature(code, output, args.seed)
        results[profile] = signature
        if not valid:
            invalid_runtime = True
            print(f"{profile:8}: INVALID {error}")
        else:
            print(f"{profile:8}: exit={signature[0]} {signature[1]}")
    if compile_failed:
        print("MINIMIZATION FAILED: the cut does not compile")
        sys.exit(2)
    if invalid_runtime:
        print("MINIMIZATION FAILED: incomplete finalization contract")
        sys.exit(2)
    if len(set(results.values())) > 1:
        print("MINIMIZED: the cut still reproduces the disagreement")
    else:
        print("cut agrees everywhere: the trigger needs the surrounding forms")


if __name__ == "__main__":
    main()
