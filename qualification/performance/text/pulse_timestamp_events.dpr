program pulse_timestamp_events;
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
  SysUtils, DateUtils, perf_clock, pulse_process_metrics, pulse_harness;

{$I ../common/pulse_program_prefix.inc}

const EpochDay = 25569.0;

var Inputs: array[0..63] of TDateTime;
    Expected: array[0..63] of Int64;
    Shape: Integer;

function CaseEvents(Iterations: Integer): UInt64;
var I, J: Integer;
    Seconds, Previous, FirstPrevious: Int64;
begin
  FirstPrevious := Expected[0] - 1;
  Result := 0;
  for I := 0 to Iterations - 1 do
  begin
    Previous := FirstPrevious;
    for J := 0 to 63 do
    begin
      Seconds := DateTimeToUnix(Inputs[J]);
      Result := Result + UInt64(Seconds div 3600);
      If Seconds > Previous then
        Inc(Result);
      Previous := Seconds;
    end;
  end;
end;

procedure PrepareEvents;
var J: Integer;
    T: TDateTime;
    ExpectedSum: UInt64;
    Previous: Int64;
begin
  for J := 0 to 63 do
  begin
    If (Shape = 1) or ((Shape = 2) and (J and 3 = 0)) then
      Inputs[J] := -10 - J / 100
    else
      Inputs[J] := 45200 + (J * 173 + 0.25) / SecsPerDay;
    T := RecodeMillisecond(Inputs[J], 0);
    If T < 0 then
      T := Trunc(T) - Frac(T);
    Expected[J] := Round((T - EpochDay) * SecsPerDay);
    If DateTimeToUnix(Inputs[J]) <> Expected[J] then
      raise Exception.Create('timestamp value');
  end;
  ExpectedSum := 0;
  Previous := Expected[0] - 1;
  for J := 0 to 63 do
  begin
    ExpectedSum := ExpectedSum + UInt64(Expected[J] div 3600);
    If Expected[J] > Previous then
      Inc(ExpectedSum);
    Previous := Expected[J];
  end;
  If CaseEvents(1) <> ExpectedSum then
    raise Exception.Create('timestamp event buckets/order');
end;

var Profile: TPulseProfile;
    SelectedCase, Name: UnicodeString;
    Found: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_timestamp_events', Profile, SelectedCase);
  Found := False;
  for Shape := 0 to 2 do
  begin
    PrepareEvents;
    Name := Format('event-times-shape%d', [Shape]);
    PulseRunCase('pulse_timestamp_events', Name, 'rtl', 'DateTimeToUnix', @CaseEvents, 64,
      Profile, SelectedCase, Found, @CaseEvents);
  end;
  PulseFinish('pulse_timestamp_events', SelectedCase, Found);
end.
