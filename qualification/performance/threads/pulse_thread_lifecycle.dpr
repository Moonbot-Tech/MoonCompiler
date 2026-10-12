program pulse_thread_lifecycle;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  Classes,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

type
  TLifecycleWorker = class(TThread)
  private
    FValue: Integer;
  protected
    procedure Execute; override;
  public
    Digest: UInt64;
    constructor Create(Value: Integer);
  end;

constructor TLifecycleWorker.Create(Value: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FValue := Value;
end;

procedure TLifecycleWorker.Execute;
begin
  { Only application work: worker affinity, PMU setup and sampling do not
    belong to the cost of creating and joining an ordinary thread. }
  Digest := UInt64(FValue);
end;

function RunBatch(Count: Integer): UInt64;
var
  Workers: array[0..3] of TLifecycleWorker;
  I, Created: Integer;
begin
  Created := 0;
  Result := 0;
  try
    for I := 0 to Count - 1 do
    begin
      Workers[I] := TLifecycleWorker.Create(I + 1);
      Inc(Created);
      Workers[I].Start;
    end;
    for I := 0 to Created - 1 do
    begin
      Workers[I].WaitFor;
      If Assigned(Workers[I].FatalException) then
        raise EAbort.Create('lifecycle worker failed');
      If Workers[I].Digest <> UInt64(I + 1) then
        raise EAbort.Create('lifecycle worker digest mismatch');
      Result := Result + Workers[I].Digest;
    end;
  finally
    for I := 0 to Created - 1 do
      Workers[I].Free;
  end;
end;

function CaseStartJoin1(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + RunBatch(1);
  If Result <> UInt64(Iterations) then
    raise EAbort.Create('single lifecycle digest mismatch');
end;

function CaseStartJoin4(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + RunBatch(4);
  If Result <> UInt64(Iterations) * 10 then
    raise EAbort.Create('batch lifecycle digest mismatch');
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_thread_lifecycle', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_thread_lifecycle', 'start-join-1', 'os+rtl+threads',
    'TThread', @CaseStartJoin1, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_thread_lifecycle', 'start-join-4', 'os+rtl+threads',
    'TThread', @CaseStartJoin4, 4, Profile, SelectedCase, Found);
  PulseFinish('pulse_thread_lifecycle', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
