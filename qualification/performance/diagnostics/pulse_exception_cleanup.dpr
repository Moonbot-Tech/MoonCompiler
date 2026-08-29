program pulse_exception_cleanup;

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
  Classes,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

var
  SourceUnicode: array[0..63] of UnicodeString;
  SourceBytes: array[0..63] of TBytes;
  RaiseEnabled: Boolean;

function CopyBytes(const Value: TBytes): TBytes;
begin
  Result := System.Copy(Value);
end;

function CaseAssignOnly(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
    begin
      S := SourceUnicode[(I + J) and 63];
      B := CopyBytes(SourceBytes[(I + J + 1) and 63]);
      Digest := Digest + UInt64(Length(S)) + UInt64(Length(B));
    end;
  Result := Digest;
end;

function CaseTryNoRaise(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
      try
        S := SourceUnicode[(I + J) and 63];
        B := CopyBytes(SourceBytes[(I + J + 1) and 63]);
        If RaiseEnabled then
          raise EAbort.Create('pulse');
        Digest := Digest + UInt64(Length(S)) + UInt64(Length(B));
      except
        on EAbort do
          Digest := Digest + 1;
      end;
  Result := Digest;
end;

function CaseRaiseOnly(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
      try
        If J = 7 then
          raise EAbort.Create('pulse');
        Digest := Digest + UInt64(I + J);
      except
        on EAbort do
          Digest := Digest + 1;
      end;
  Result := Digest;
end;

function CaseFull(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
      try
        S := SourceUnicode[(I + J) and 63];
        B := CopyBytes(SourceBytes[(I + J + 1) and 63]);
        If J = 7 then
          raise EAbort.Create('pulse');
        Digest := Digest + UInt64(Length(S)) + UInt64(Length(B));
      except
        on EAbort do
          Digest := Digest + 1;
      end;
  Result := Digest;
end;

procedure InitializeSources;
var
  I, J: Integer;
begin
  RaiseEnabled := False;
  for I := 0 to 63 do
  begin
    SourceUnicode[I] := UnicodeString('symbol-') + UnicodeString(IntToStr(I)) +
      UnicodeString('-price');
    SetLength(SourceBytes[I], 16 + (I and 31));
    for J := 0 to High(SourceBytes[I]) do
      SourceBytes[I][J] := Byte(I * 17 + J * 29);
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeSources;
  PulseInitialize('pulse_exception_cleanup', Profile, SelectedCase);
  Found := False;
  PulseRunCase('pulse_exception_cleanup', 'assign-only', 'compiler+rtl',
    'managed assignment without EH', @CaseAssignOnly, 8, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_exception_cleanup', 'try-no-raise', 'compiler+rtl',
    'managed assignment through EH region', @CaseTryNoRaise, 8, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_exception_cleanup', 'raise-only', 'compiler+rtl',
    'one raise/catch per eight operations', @CaseRaiseOnly, 8, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_exception_cleanup', 'full', 'compiler+rtl',
    'managed assignment plus one raise/catch per eight operations', @CaseFull,
    8, Profile, SelectedCase, Found);
  PulseFinish('pulse_exception_cleanup', SelectedCase, Found);
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
