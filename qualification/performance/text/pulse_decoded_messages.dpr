program pulse_decoded_messages;
{$ifdef FPC}
  {$mode delphiunicode}
{$else}
  {$APPTYPE CONSOLE}
{$endif}
{$R-}{$Q-}
uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$endif}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, perf_clock, pulse_process_metrics, pulse_harness;

{$I ../common/pulse_program_prefix.inc}
var Inputs: array[0..7] of RawByteString;
    Expected: array[0..7] of UnicodeString;
    Retained: array[0..63] of UnicodeString;
    Shape, Keep: Integer;

function Consume(const S: UnicodeString): UInt64;
var J: Integer;
begin
  Result := 0;
  for J := 1 to Length(S) do
    Result := Result + UInt64(Ord(S[J])) * UInt64(J);
end;

procedure PrepareDecode;
var I, J: Integer;
    S: UnicodeString;
begin
  for I := 0 to 7 do
  begin
    S := '';
    If Shape = 0 then
      for J := 0 to 31 do
        S := S + WideChar($410 + ((I + J) mod 64))
    else If Shape = 1 then
      S := 'Peer' + IntToStr(I) + ': ' + WideChar($41f) + WideChar($440) + WideChar($438) +
        WideChar($432) + WideChar($435) + WideChar($442) + ' response ready'
    else
      S := 'Peer' + IntToStr(I) + ': payload ready; sequence=12345678; status=active';
    Expected[I] := S;
    Inputs[I] := UTF8Encode(S);
  end;
  for I := 0 to 63 do
    Retained[I] := '';
end;

function CaseDecode(Iterations: Integer): UInt64;
var I, Index: Integer;
    S: UnicodeString;
    KeepResult: Boolean;
begin
  KeepResult := Keep <> 0;
  Result := 0;
  for I := 0 to Iterations - 1 do
  begin
    Index := I and 7;
    S := UTF8Decode(Inputs[Index]);
    Result := Result + Consume(S);
    If KeepResult then
      Retained[I and 63] := S;
  end;
end;

procedure DecodeOracle;
var I: Integer;
    ExpectedSum: UInt64;
begin
  ExpectedSum := 0;
  for I := 0 to 255 do
    ExpectedSum := ExpectedSum + Consume(Expected[I and 7]);
  If CaseDecode(256) <> ExpectedSum then
    raise Exception.Create('decode message digest');
  If Keep <> 0 then
    for I := 0 to 63 do
      If Retained[I] <> Expected[I and 7] then
        raise Exception.Create('decode retained message');
end;

var Profile: TPulseProfile;
    SelectedCase, Name: UnicodeString;
    Found: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_decoded_messages', Profile, SelectedCase);
  Found := False;
  for Shape := 0 to 2 do
  begin
    for Keep := 0 to 1 do
    begin
      PrepareDecode;
      DecodeOracle;
      Name := Format('decode-shape%d-retain%d', [Shape, Keep]);
      PulseRunCase('pulse_decoded_messages', Name, 'rtl+mm', 'UTF8Decode', @CaseDecode, 1,
        Profile, SelectedCase, Found, @CaseDecode);
    end;
  end;
  PulseFinish('pulse_decoded_messages', SelectedCase, Found);
end.
