program local_pressure;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  SysUtils,
  {$else}
  System.SysUtils,
  {$endif}
  {$ifdef PERF_FORCE_MULTITHREAD}
  {$ifdef FPC}
  Classes,
  {$else}
  System.Classes,
  {$endif}
  {$endif PERF_FORCE_MULTITHREAD}
  perf_clock in '..\common\perf_clock.pas';

const
  LocalCount = 100;

type
  TPressureProc = procedure;
  TSourceStrings = array[0..LocalCount - 1] of UnicodeString;
  TSourceBuffers = array[0..LocalCount - 1] of TBytes;
  TSourcePlain = array[0..LocalCount - 1] of UInt64;

  TRunProfile = record
    Name: string;
    Samples: Integer;
    TargetBatchNs: UInt64;
  end;

var
  SourceStrings: TSourceStrings;
  SourceBuffers: TSourceBuffers;
  SourcePlain: TSourcePlain;
  Sink: UInt64;

{$ifdef PERF_FORCE_MULTITHREAD}
type
  TActivationThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TActivationThread.Execute;
begin
end;

procedure ActivateMultithreadedRuntime;
var
  Thread: TActivationThread;
begin
  Thread := TActivationThread.Create(False);
  try
    Thread.WaitFor;
  finally
    Thread.Free;
  end;
end;
{$endif PERF_FORCE_MULTITHREAD}

{$HINTS OFF}
{$WARNINGS OFF}
{$ifdef FPC}{$NOTES OFF}{$endif}
{$I local_pressure_cases.inc}
{$ifdef FPC}{$NOTES ON}{$endif}
{$WARNINGS ON}
{$HINTS ON}

procedure InitializeSources;
var
  I, J: Integer;
begin
  for I := 0 to LocalCount - 1 do
  begin
    SourceStrings[I] := UnicodeString('market-') + UnicodeString(IntToStr(I));
    SetLength(SourceBuffers[I], NativeInt(8) + NativeInt(I mod 32));
    for J := 0 to High(SourceBuffers[I]) do
      SourceBuffers[I][J] := Byte(I * 17 + J * 29);
    SourcePlain[I] := UInt64(I + 1) * UInt64($9E3779B185EBCA87);
  end;
end;

function SumSourceStrings: UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to LocalCount - 1 do
    Result := Result + UInt64(Length(SourceStrings[I]));
end;

function SumSourceBuffers: UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to LocalCount - 1 do
    Result := Result + UInt64(Length(SourceBuffers[I]));
end;

function SumSourcePlain: UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to LocalCount - 1 do
    Result := Result + SourcePlain[I];
end;

function SelectProfile(const Name: string): TRunProfile;
begin
  Result.Name := LowerCase(Name);
  If Result.Name = 'quick' then
  begin
    Result.Samples := 31;
    Result.TargetBatchNs := 1000000;
  end
  else If Result.Name = 'medium' then
  begin
    Result.Samples := 61;
    Result.TargetBatchNs := 1500000;
  end
  else If Result.Name = 'long' then
  begin
    Result.Samples := 201;
    Result.TargetBatchNs := 2000000;
  end
  else
    raise EArgumentException.Create('mode must be quick, medium or long');
end;

procedure InvokeCalls(PressureProc: TPressureProc; Calls: Integer);
var
  I: Integer;
begin
  for I := 1 to Calls do
    PressureProc();
end;

function MeasureCalls(PressureProc: TPressureProc; Calls: Integer): TPerfDelta;
var
  Started: TPerfStamp;
begin
  Started := BeginPerfStamp;
  InvokeCalls(PressureProc, Calls);
  Result := EndPerfStamp(Started);
end;

function CalibrateCalls(PressureProc: TPressureProc; TargetNs: UInt64): Integer;
const
  CalibrationFloorNs = UInt64(1000000);
  MaximumCalls = 1000000000;
var
  Calls: Integer;
  Delta: TPerfDelta;
  Scaled: UInt64;
begin
  Calls := 1;
  repeat
    Delta := MeasureCalls(PressureProc, Calls);
    If Delta.WallNs >= CalibrationFloorNs then
      Break;
    If Calls > MaximumCalls div 10 then
      Break;
    Calls := Calls * 10;
  until False;

  If Delta.WallNs = 0 then
    raise EAbort.Create('calibration interval is below timer resolution');
  Scaled := UInt64(Calls) * TargetNs div Delta.WallNs;
  If Scaled < 1 then
    Scaled := 1;
  If Scaled > MaximumCalls then
    Scaled := MaximumCalls;
  Result := Integer(Scaled);
end;

procedure RunCase(const Mode, CaseName: string; PressureProc: TPressureProc;
  ExpectedPerCall: UInt64; const Profile: TRunProfile; TscOverhead: UInt64);
var
  Calls, Sample: Integer;
  Deltas: array of TPerfDelta;
  TotalStarted: TPerfStamp;
  Total: TPerfDelta;
  SinkBefore: UInt64;
begin
  Calls := CalibrateCalls(PressureProc, Profile.TargetBatchNs);
  InvokeCalls(PressureProc, Calls div 16 + 1);
  SetLength(Deltas, Profile.Samples);
  WriteLn('LOCAL_PRESSURE_CASE mode=', Mode, ' case=', CaseName,
    ' calls_per_sample=', Calls, ' samples=', Profile.Samples,
    ' tsc_overhead=', TscOverhead);
  TotalStarted := BeginPerfStamp;
  for Sample := 1 to Profile.Samples do
  begin
    SinkBefore := Sink;
    Deltas[Sample - 1] := MeasureCalls(PressureProc, Calls);
    If Sink - SinkBefore <> UInt64(Calls) * ExpectedPerCall then
      raise EAbort.Create('case digest mismatch: ' + CaseName);
    If (Deltas[Sample - 1].WallNs = 0) or
       (Deltas[Sample - 1].TscTicks = 0) then
      raise EAbort.Create('measured interval is below timer resolution');
  end;
  Total := EndPerfStamp(TotalStarted);
  for Sample := 1 to Profile.Samples do
  begin
    WriteLn('LOCAL_PRESSURE_SAMPLE mode=', Mode, ' case=', CaseName,
      ' sample=', Sample, ' calls=', Calls,
      ' wall_ns=', Deltas[Sample - 1].WallNs,
      ' thread_cpu_ns=', Deltas[Sample - 1].ThreadCpuNs,
      ' tsc_ticks=', Deltas[Sample - 1].TscTicks,
      ' sink=', IntToHex(Sink, 16));
  end;
  WriteLn('LOCAL_PRESSURE_TOTAL mode=', Mode, ' case=', CaseName,
    ' samples=', Profile.Samples, ' calls=', UInt64(Calls) *
    UInt64(Profile.Samples), ' wall_ns=', Total.WallNs,
    ' thread_cpu_ns=', Total.ThreadCpuNs, ' tsc_ticks=', Total.TscTicks);
end;

procedure MaybeRun(const SelectedCase, CaseName: string;
  PressureProc: TPressureProc; ExpectedPerCall: UInt64;
  const Profile: TRunProfile;
  TscOverhead: UInt64; var Found: Boolean);
begin
  If (SelectedCase = 'all') or SameText(SelectedCase, CaseName) then
  begin
    Found := True;
    RunCase(Profile.Name, CaseName, PressureProc, ExpectedPerCall, Profile,
      TscOverhead);
  end;
end;

procedure Run;
var
  Mode, SelectedCase: string;
  Profile: TRunProfile;
  TscOverhead: UInt64;
  AffinityCpu: Integer;
  ExpectedStrings, ExpectedBuffers, ExpectedPlain: UInt64;
  Found: Boolean;
begin
  {$ifdef PERF_FORCE_MULTITHREAD}
  ActivateMultithreadedRuntime;
  {$endif PERF_FORCE_MULTITHREAD}
  Mode := 'quick';
  SelectedCase := 'all';
  If ParamCount >= 1 then
    Mode := ParamStr(1);
  If ParamCount >= 2 then
    SelectedCase := LowerCase(ParamStr(2));
  If ParamCount > 2 then
    raise EArgumentException.Create(
      'usage: local_pressure [quick|medium|long] [case|all]');

  Profile := SelectProfile(Mode);
  InitializePerfClock;
  AffinityCpu := PinBenchmarkThread;
  InitializeSources;
  ExpectedStrings := SumSourceStrings;
  ExpectedBuffers := SumSourceBuffers;
  ExpectedPlain := SumSourcePlain;
  TscOverhead := MeasureTscOverhead(1000);
  Found := False;
  WriteLn('LOCAL_PRESSURE_BEGIN mode=', Profile.Name,
    ' selected=', SelectedCase, ' locals_per_group=', LocalCount,
    ' affinity_cpu=', AffinityCpu, ' multithread=', Ord(IsMultiThread));
  MaybeRun(SelectedCase, 'empty', @CaseEmpty, 0, Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'unused-plain-100', @CaseUnusedPlain100, 0, Profile,
    TscOverhead, Found);
  MaybeRun(SelectedCase, 'unused-strings-100', @CaseUnusedStrings100, 0,
    Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'unused-buffers-100', @CaseUnusedBuffers100, 0,
    Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'unused-mixed-300', @CaseUnusedMixed300, 0, Profile,
    TscOverhead, Found);
  MaybeRun(SelectedCase, 'used-plain-100', @CaseUsedPlain100, ExpectedPlain,
    Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'used-strings-100', @CaseUsedStrings100,
    ExpectedStrings, Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'used-buffers-100', @CaseUsedBuffers100,
    ExpectedBuffers, Profile, TscOverhead, Found);
  MaybeRun(SelectedCase, 'used-mixed-300', @CaseUsedMixed300,
    ExpectedStrings + ExpectedBuffers + ExpectedPlain, Profile, TscOverhead,
    Found);
  If not Found then
    raise EArgumentException.Create('unknown case: ' + SelectedCase);
  WriteLn('LOCAL_PRESSURE_DONE mode=', Profile.Name, ' sink=',
    IntToHex(Sink, 16));
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn('LOCAL_PRESSURE_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
