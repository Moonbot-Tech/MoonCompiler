#!/usr/bin/env python3
"""Prove that Devil reports only after a successful process shutdown."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import devil_toolchain as tc
import run_devil_gate


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "tests" / "devil" / "devil_runtime.pas"

PROGRAM = """program devil_finalization_probe;

{$ifdef FPC}{$mode delphiunicode}{$endif}
{$APPTYPE CONSOLE}

uses SysUtils, Classes, SyncObjs, devil_runtime, devil_finalization_shutdown;

const
  TaggedPerWorker = 20000;

type
  TDevilProbeWorker = class(TThread)
  public
    { created by the worker, released by the main thread, as in the thread layer }
    Tagged: array of IInterface;
  protected
    procedure Execute; override;
  end;

var
  StartEvent: TEvent;
  Workers: array[0..7] of TDevilProbeWorker;
  I: Integer;

procedure TDevilProbeWorker.Execute;
var
  J: Integer;
begin
  StartEvent.WaitFor(INFINITE);
  SetLength(Tagged, TaggedPerWorker);
  for J := 0 to High(Tagged) do
    Tagged[J] := TDvlTagged.Create('p');
  for J := 1 to 32 do
    DevilCheckU('dvl-init-parallel', 1, 1);
end;

begin
  WriteLn('DEVIL_LAYERS init');
  DevilLayerBegin('init');
  DevilCheckU('dvl-init-body', 1, 1);
  if ParamStr(1)='parallel' then
  begin
    StartEvent := TEvent.Create(nil, True, False, '');
    try
      for I := 0 to High(Workers) do
      begin
        Workers[I] := TDevilProbeWorker.Create(True);
        Workers[I].FreeOnTerminate := False;
        Workers[I].Start;
      end;
      StartEvent.SetEvent;
      for I := 0 to High(Workers) do
        Workers[I].WaitFor;
      { the workers created their objects at once: the shared counters must
        have seen every creation }
      DevilCheckU('dvl-init-tagged-alive', UInt64(TDvlTagged.Alive),
        Length(Workers) * TaggedPerWorker);
      for I := 0 to High(Workers) do
        Workers[I].Free;
    finally
      StartEvent.Free;
    end;
  end;
  DevilLayerEnd;
  WriteLn('DEVIL_FEEDS ', DevilFeedCount);
  WriteLn('DEVIL_STEPS ', DevilStepCount);
  if ParamStr(1)='body-raise' then
    raise Exception.Create('intentional body failure');
  DevilArmReport('DEVIL', 1);
end.
"""

SHUTDOWN = """unit devil_finalization_shutdown;

{$ifdef FPC}{$mode delphiunicode}{$endif}

interface

uses SysUtils, devil_runtime;

implementation

initialization

finalization
  if ParamStr(1)='halt' then
    Halt(73);
  if (ParamStr(1)='raise') or (ParamStr(1)='check-raise') then
    begin
      if ParamStr(1)='check-raise' then
        DevilCheckU('dvl-init-finalizer', 0, 1);
      raise Exception.Create('intentional finalizer failure');
    end;
  if ParamStr(1)='exitcode' then
    System.ExitCode:=73;
  if ParamStr(1)='check' then
    DevilCheckU('dvl-init-finalizer', 0, 1);
end.
"""

SCENARIOS = {
    "normal": {"argument": "", "exit": 0, "contract": True},
    "parallel": {"argument": "parallel", "exit": 0, "contract": True,
                 "failures": {}},
    "check": {"argument": "check", "exit": 0, "contract": True,
              "failures": {"dvl-init-finalizer": 1}},
    "body-raise": {"argument": "body-raise", "nonzero": True, "contract": False},
    "finalizer-raise": {"argument": "raise", "nonzero": True, "contract": False},
    "halt": {"argument": "halt", "exit": 73, "contract": False},
    "exitcode": {"argument": "exitcode", "exit": 73, "contract": False},
    "check-raise": {"argument": "check-raise", "nonzero": True,
                    "contract": False},
}


def run(command: list[str], cwd: Path, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return tc.run_process(command, cwd=cwd, capture_output=True, text=True,
                          errors="replace", timeout=timeout, check=False)


def validate(label: str, executable: Path, work: Path) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    for name, expected in SCENARIOS.items():
        command = [str(executable)]
        if expected["argument"]:
            command.append(str(expected["argument"]))
        executed = run(command, work)
        output = (executed.stdout or "") + (executed.stderr or "")
        build = run_devil_gate.Build(f"{label}/{name}")
        build.compiled = True
        build.run_exit = executed.returncode
        build.expected_seed = 1
        build.parse(output)
        errors = run_devil_gate.instrument_contract_errors(build)
        if expected.get("nonzero"):
            exit_ok = executed.returncode != 0
        else:
            exit_ok = executed.returncode == expected["exit"]
        # Terminal text is semantic evidence; a trustworthy completed sample
        # additionally requires a normal process exit.
        contract_ok = not errors and executed.returncode == 0
        failures_ok = ("failures" not in expected or
                       build.failure_occurrences == expected["failures"])
        if not exit_ok or contract_ok != expected["contract"] or not failures_ok:
            findings.append({
                "case": f"{label}/{name}",
                "exit": executed.returncode,
                "expected": expected,
                "contract_errors": errors,
                "tail": output.strip().splitlines()[-6:],
            })
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "devil-finalization")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--dcc", type=Path)
    parser.add_argument("--dcc-lib", type=Path)
    args = parser.parse_args()
    if bool(args.dcc) != bool(args.dcc_lib):
        parser.error("--dcc and --dcc-lib must be supplied together")
    tc.preflight()
    work = args.work.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    shutil.copy(RUNTIME, work / RUNTIME.name)
    source = work / "devil_finalization_probe.dpr"
    source.write_text(PROGRAM, encoding="utf-8")
    (work / "devil_finalization_shutdown.pas").write_text(
        SHUTDOWN, encoding="utf-8")

    findings: list[dict[str, object]] = []
    fpc = work / "fpc"
    fpc.mkdir()
    compiled = run(tc.compile_command(source, fpc, "release", search=[work]), work)
    (fpc / "compile.log").write_text(
        (compiled.stdout or "") + (compiled.stderr or ""), encoding="utf-8")
    executable = tc.executable(fpc, source.stem)
    if compiled.returncode != 0 or not executable.is_file():
        findings.append({"case": "fpc/build", "exit": compiled.returncode})
    else:
        findings += validate("fpc", executable, work)

    if args.dcc and args.dcc_lib:
        dcc = work / "delphi"
        dcc.mkdir()
        compiled = run([
            str(args.dcc.resolve()), "-B", "-Q", "-CC", "-NSSystem",
            f"-U{args.dcc_lib.resolve()}", f"-NU{dcc}", f"-E{dcc}",
            str(source),
        ], work)
        (dcc / "compile.log").write_text(
            (compiled.stdout or "") + (compiled.stderr or ""), encoding="utf-8")
        executable = dcc / f"{source.stem}.exe"
        if compiled.returncode != 0 or not executable.is_file():
            findings.append({"case": "delphi/build", "exit": compiled.returncode})
        else:
            findings += validate("delphi", executable, work)

    report = {"scenarios": len(SCENARIOS), "findings": findings}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for finding in findings:
        print(json.dumps(finding, sort_keys=True))
    print(f"DEVIL_FINALIZATION {'OK' if not findings else 'FINDINGS'} "
          f"scenarios={len(SCENARIOS)} findings={len(findings)}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
