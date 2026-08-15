program pulse_local_pressure;

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
  SysUtils,
  pulse_harness in '..\common\pulse_harness.pas';

const
  LocalCount = 100;

type
  TPressureProc = procedure;
  TSourceStrings = array[0..LocalCount - 1] of UnicodeString;
  TSourceBuffers = array[0..LocalCount - 1] of TBytes;
  TSourcePlain = array[0..LocalCount - 1] of UInt64;

var
  SourceStrings: TSourceStrings;
  SourceBuffers: TSourceBuffers;
  SourcePlain: TSourcePlain;
  Sink: UInt64;
  ActivePressureProc: TPressureProc;

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

function RepeatActive(Iterations: Integer): UInt64;
var
  I: Integer;
  Before: UInt64;
begin
  Before := Sink;
  for I := 1 to Iterations do
    ActivePressureProc;
  Result := Sink - Before;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_local_pressure', Profile, SelectedCase);
  InitializeSources;
  Found := False;
  ActivePressureProc := @CaseEmpty;
  PulseRunCase('pulse_local_pressure', 'empty', 'codegen', 'call', @RepeatActive,
    1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUnusedPlain100;
  PulseRunCase('pulse_local_pressure', 'unused-plain-100', 'codegen', 'call',
    @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUnusedStrings100;
  PulseRunCase('pulse_local_pressure', 'unused-strings-100', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUnusedBuffers100;
  PulseRunCase('pulse_local_pressure', 'unused-buffers-100', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUnusedMixed300;
  PulseRunCase('pulse_local_pressure', 'unused-mixed-300', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUsedPlain100;
  PulseRunCase('pulse_local_pressure', 'used-plain-100', 'codegen', 'call',
    @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUsedStrings100;
  PulseRunCase('pulse_local_pressure', 'used-strings-100', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUsedBuffers100;
  PulseRunCase('pulse_local_pressure', 'used-buffers-100', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  ActivePressureProc := @CaseUsedMixed300;
  PulseRunCase('pulse_local_pressure', 'used-mixed-300', 'codegen+managed',
    'call', @RepeatActive, 1, Profile, SelectedCase, Found);
  PulseFinish('pulse_local_pressure', SelectedCase, Found);
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
