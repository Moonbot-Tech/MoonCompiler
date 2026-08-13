program mega_delphi;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  mega_portable in 'mega_portable.pas';

const
  WorkerCount = 4;
  PhaseCount = 4;
  DefaultSeed = UInt64($6D6F6F6E626F7421);
  DigestOffset = UInt64($CBF29CE484222325);

function ReadSeed: UInt64;
begin
  Result := DefaultSeed;
  if ParamCount > 0 then
    Result := StrToUInt64(ParamStr(1));
end;

var
  ScenarioResult: TPortableResult;
  Seed, Digest: UInt64;
  Checks: Int64;
  WorkerId, Phase: Integer;
begin
  try
    Seed := ReadSeed;
    Digest := DigestOffset;
    Checks := 0;
    for Phase := 0 to PhaseCount - 1 do
      for WorkerId := 0 to WorkerCount - 1 do
      begin
        RunPortableScenario(Seed, WorkerId, Phase, ScenarioResult);
        Inc(Checks, ScenarioResult.Checks);
        FoldPortableResult(Digest, ScenarioResult, WorkerId, Phase);
      end;
    WriteLn('PORTABLE_PASS seed=', UIntToStr(Seed), ' checks=', Checks,
      ' digest=', IntToHex(Digest, 16));
  except
    on E: Exception do
    begin
      WriteLn('PORTABLE_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
