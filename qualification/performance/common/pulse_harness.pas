unit pulse_harness;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

uses
  SysUtils,
  perf_clock,
  pulse_process_metrics;

type
  TPulseCaseProc = function(Iterations: Integer): UInt64;

  TPulseProfile = record
    Name: string;
    Samples: Integer;
    TargetBatchNs: UInt64;
    WarmupNs: UInt64;
    MaximumIterations: Integer;
  end;

procedure PulseInitialize(const ProgramName: string;
  out Profile: TPulseProfile; out SelectedCase: string);
procedure PulseRunCase(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean);
procedure PulseFinish(const ProgramName, SelectedCase: string; Found: Boolean);

implementation

var
  PulseTscOverhead: UInt64;
  PulseAffinityCpu: Integer;

function SelectProfile(const Name: string): TPulseProfile;
begin
  Result.Name := LowerCase(Name);
  If Result.Name = 'quick' then
  begin
    Result.Samples := 17;
    Result.TargetBatchNs := 200000;
    Result.WarmupNs := 20000000;
    Result.MaximumIterations := 100000000;
  end
  else If Result.Name = 'medium' then
  begin
    Result.Samples := 37;
    Result.TargetBatchNs := 600000;
    Result.WarmupNs := 50000000;
    Result.MaximumIterations := 500000000;
  end
  else If Result.Name = 'long' then
  begin
    Result.Samples := 101;
    Result.TargetBatchNs := 2000000;
    Result.WarmupNs := 200000000;
    Result.MaximumIterations := 1000000000;
  end
  else
    raise EArgumentException.Create('mode must be quick, medium or long');
end;

function MeasureOnce(CaseProc: TPulseCaseProc; Iterations: Integer;
  out Digest: UInt64): TPerfDelta;
var
  Started: TPerfStamp;
begin
  Started := BeginPerfStamp;
  Digest := CaseProc(Iterations);
  Result := EndPerfStamp(Started);
end;

procedure Warmup(CaseProc: TPulseCaseProc; Iterations: Integer;
  TargetNs: UInt64);
var
  Delta: TPerfDelta;
  Digest, ElapsedNs: UInt64;
begin
  ElapsedNs := 0;
  repeat
    Delta := MeasureOnce(CaseProc, Iterations, Digest);
    ElapsedNs := ElapsedNs + Delta.WallNs;
  until ElapsedNs >= TargetNs;
end;

function Calibrate(CaseProc: TPulseCaseProc; const Profile: TPulseProfile): Integer;
const
  CalibrationFloorNs = UInt64(100000);
  CalibrationRepeats = 5;
  MaximumPasses = 4;
var
  Iterations, Pass: Integer;
  Delta: TPerfDelta;
  Digest, FastestNs, Scaled: UInt64;

  function FastestMeasurement: UInt64;
  var
    RepeatIndex: Integer;
  begin
    Result := High(UInt64);
    for RepeatIndex := 1 to CalibrationRepeats do
    begin
      Delta := MeasureOnce(CaseProc, Iterations, Digest);
      If (Delta.WallNs > 0) and (Delta.WallNs < Result) then
        Result := Delta.WallNs;
    end;
  end;
begin
  Digest := CaseProc(1);
  Iterations := 1;
  repeat
    FastestNs := FastestMeasurement;
    If FastestNs >= CalibrationFloorNs then
      Break;
    If Iterations > Profile.MaximumIterations div 8 then
      Break;
    Iterations := Iterations * 8;
  until False;
  If FastestNs = High(UInt64) then
    raise EAbort.Create('calibration interval is below timer resolution');
  for Pass := 1 to MaximumPasses do
  begin
    Scaled := UInt64(Iterations) * Profile.TargetBatchNs div FastestNs;
    If Scaled < 1 then
      Scaled := 1;
    If Scaled > UInt64(Profile.MaximumIterations) then
      Scaled := UInt64(Profile.MaximumIterations);
    Iterations := Integer(Scaled);
    FastestNs := FastestMeasurement;
    If (FastestNs >= Profile.TargetBatchNs * 3 div 4) and
       (FastestNs <= Profile.TargetBatchNs * 5 div 4) then
      Break;
  end;
  Result := Iterations;
end;

procedure PulseInitialize(const ProgramName: string;
  out Profile: TPulseProfile; out SelectedCase: string);
var
  Mode: string;
begin
  Mode := 'quick';
  SelectedCase := 'all';
  If ParamCount >= 1 then
    Mode := ParamStr(1);
  If ParamCount >= 2 then
    SelectedCase := LowerCase(ParamStr(2));
  If ParamCount > 2 then
    raise EArgumentException.Create(
      'usage: ' + ProgramName + ' [quick|medium|long|list] [case|all]');
  If SameText(Mode, 'list') then
  begin
    Profile.Name := 'list';
    Profile.Samples := 0;
    Profile.TargetBatchNs := 0;
    Profile.WarmupNs := 0;
    Profile.MaximumIterations := 0;
    WriteLn('PULSE_BEGIN program=', ProgramName, ' mode=list selected=',
      SelectedCase);
    Exit;
  end;
  Profile := SelectProfile(Mode);
  InitializePerfClock;
  PulseAffinityCpu := PinBenchmarkThread;
  PulseTscOverhead := MeasureTscOverhead(1000);
  WriteLn('PULSE_BEGIN program=', ProgramName, ' mode=', Profile.Name,
    ' selected=', SelectedCase, ' affinity_cpu=', PulseAffinityCpu,
    ' tsc_overhead=', PulseTscOverhead);
end;

procedure PulseRunCase(const ProgramName, CaseName, Layer, UnitName: string;
  CaseProc: TPulseCaseProc; OperationsPerIteration: UInt64;
  const Profile: TPulseProfile; const SelectedCase: string; var Found: Boolean);
var
  Iterations, Sample: Integer;
  OracleDigest, ExpectedDigest, Digest: UInt64;
  Delta: TPerfDelta;
  ProcessCpuStarted, ThreadCyclesStarted, ProcessCpuNs, ThreadCycles: UInt64;
  TotalStarted: TPerfStamp;
  TotalDelta: TPerfDelta;
  TotalProcessCpuStarted, TotalThreadCyclesStarted: UInt64;
begin
  If (SelectedCase <> 'all') and not SameText(SelectedCase, CaseName) then
    Exit;
  Found := True;
  If Profile.Name = 'list' then
  begin
    WriteLn('PULSE_CASEDEF program=', ProgramName, ' case=', CaseName,
      ' layer=', Layer, ' unit=', UnitName);
    Exit;
  end;
  OracleDigest := CaseProc(1);
  Iterations := Calibrate(CaseProc, Profile);
  Warmup(CaseProc, Iterations, Profile.WarmupNs);
  Iterations := Calibrate(CaseProc, Profile);
  ExpectedDigest := CaseProc(Iterations);
  WriteLn('PULSE_CASE program=', ProgramName, ' mode=', Profile.Name,
    ' case=', CaseName, ' layer=', Layer, ' unit=', UnitName,
    ' iterations=', Iterations, ' operations=',
    UInt64(Iterations) * OperationsPerIteration, ' samples=', Profile.Samples,
    ' warmup_ns=', Profile.WarmupNs,
    ' oracle=', IntToHex(OracleDigest, 16));
  TotalProcessCpuStarted := PulseReadProcessCpuNs;
  TotalThreadCyclesStarted := PulseReadThreadCycles;
  TotalStarted := BeginPerfStamp;
  for Sample := 1 to Profile.Samples do
  begin
    ProcessCpuStarted := PulseReadProcessCpuNs;
    ThreadCyclesStarted := PulseReadThreadCycles;
    Delta := MeasureOnce(CaseProc, Iterations, Digest);
    ThreadCycles := PulseReadThreadCycles - ThreadCyclesStarted;
    ProcessCpuNs := PulseReadProcessCpuNs - ProcessCpuStarted;
    If Digest <> ExpectedDigest then
      raise EAbort.Create('digest mismatch: ' + CaseName);
    If (Delta.WallNs = 0) or (Delta.TscTicks = 0) then
      raise EAbort.Create('measured interval is below timer resolution');
    WriteLn('PULSE_SAMPLE program=', ProgramName, ' mode=', Profile.Name,
      ' case=', CaseName, ' sample=', Sample, ' iterations=', Iterations,
      ' operations=', UInt64(Iterations) * OperationsPerIteration,
      ' wall_ns=', Delta.WallNs, ' thread_cpu_ns=', Delta.ThreadCpuNs,
      ' process_cpu_ns=', ProcessCpuNs,
      ' thread_cycles=', ThreadCycles,
      ' tsc_ticks=', Delta.TscTicks, ' digest=', IntToHex(Digest, 16));
  end;
  TotalDelta := EndPerfStamp(TotalStarted);
  ThreadCycles := PulseReadThreadCycles - TotalThreadCyclesStarted;
  ProcessCpuNs := PulseReadProcessCpuNs - TotalProcessCpuStarted;
  WriteLn('PULSE_TOTAL program=', ProgramName, ' mode=', Profile.Name,
    ' case=', CaseName, ' samples=', Profile.Samples,
    ' operations=', UInt64(Iterations) * OperationsPerIteration *
    UInt64(Profile.Samples), ' wall_ns=', TotalDelta.WallNs,
    ' thread_cpu_ns=', TotalDelta.ThreadCpuNs,
    ' process_cpu_ns=', ProcessCpuNs, ' thread_cycles=', ThreadCycles,
    ' tsc_ticks=', TotalDelta.TscTicks);
end;

procedure PulseFinish(const ProgramName, SelectedCase: string; Found: Boolean);
begin
  If not Found then
    raise EArgumentException.Create('unknown case: ' + SelectedCase);
  WriteLn('PULSE_END program=', ProgramName, ' status=PASS');
end;

end.
