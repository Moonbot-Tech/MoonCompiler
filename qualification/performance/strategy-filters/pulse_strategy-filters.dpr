program pulse_strategy_filters;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$ifndef FPC}{$APPTYPE CONSOLE}{$endif}
uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}mormot.core.fpcx64mm,{$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Math, Generics.Collections, pulse_harness;
{$I ../common/pulse_program_prefix.inc}

type
  TSample = record
    Station, Quality, Hour: Integer;
    Peak, Mean: Double;
  end;
  TMode = (Cached, EarlyExit, LongScan, Recalculate, ReadClock, ReportFailure);

const
  Batch = 64;
var
  Samples: array[0..255] of TSample;
  Calibration: TDictionary<Integer, Double>;
  Allowed: TList<Integer>;

function Classify(const S: TSample; Mode: TMode; out Detail: string): Integer;
var
  Gain, Limit: Double;
  I: Integer;
begin
  Detail := '';
  if (Mode = EarlyExit) and (S.Quality < 48) then Exit(1);
  if not Calibration.TryGetValue(S.Station, Gain) then Exit(2);
  if (Mode = LongScan) and (Allowed.IndexOf(S.Station) < 0) then Exit(3);
  if (Mode = ReadClock) and (Now <= 0) then Exit(4);
  Limit := 96;
  if Mode = Recalculate then begin
    Limit := 0;
    for I := 1 to 6 do
      Limit := Limit + Power(1 + (S.Hour + I) / 64, 2.5);
  end;
  if S.Peak * Gain - S.Mean > Limit then begin
    if Mode = ReportFailure then
      Detail := 'station ' + IntToStr(S.Station) + ' at hour ' + IntToStr(S.Hour);
    Exit(5);
  end;
  Result := 6;
end;

function Scan(Iterations: Integer; Mode: TMode): UInt64;
var
  I, J, Index, Verdict: Integer;
  Detail: string;
begin
  Result := 0;
  for I := 0 to Iterations - 1 do
    for J := 0 to Batch - 1 do begin
      Index := ((I and 3) * Batch + J * 53) and 255;
      Verdict := Classify(Samples[Index], Mode, Detail);
      Inc(Result, UInt64(1 + Index) * UInt64(Verdict + Length(Detail)));
    end;
end;

function CachedCase(N: Integer): UInt64; begin Result := Scan(N, Cached); end;
function EarlyCase(N: Integer): UInt64; begin Result := Scan(N, EarlyExit); end;
function LongCase(N: Integer): UInt64; begin Result := Scan(N, LongScan); end;
function LadderCase(N: Integer): UInt64; begin Result := Scan(N, Recalculate); end;
function ClockCase(N: Integer): UInt64; begin Result := Scan(N, ReadClock); end;
function ReportCase(N: Integer): UInt64; begin Result := Scan(N, ReportFailure); end;

procedure Initialize;
const
  { Weighted decisions and report lengths over all 256 stations. }
  Expected: array[TMode] of UInt64 = (175349, 70469, 158124, 161559, 175349, 425214);
var
  I: Integer;
  Mode: TMode;
begin
  for I := 0 to High(Samples) do begin
    Samples[I].Station := (I * 43) and 255;
    Samples[I].Quality := (I * 11) and 63;
    Samples[I].Hour := I mod 24;
    Samples[I].Peak := 30 + (I * 31) mod 137;
    Samples[I].Mean := 15 + (I * 7) mod 61;
    if I mod 13 <> 0 then Calibration.Add(I, 1 + (I mod 5) / 8);
    if I mod 5 <> 0 then Allowed.Add(I);
  end;
  for Mode := Low(TMode) to High(TMode) do
    if Scan(Length(Samples) div Batch, Mode) <> Expected[Mode] then
      raise Exception.CreateFmt('Filter fixture mismatch in case %d', [Ord(Mode)]);
end;

var
  Profile: TPulseProfile;
  Selected: string;
  Found: Boolean;
begin
  Calibration := TDictionary<Integer, Double>.Create;
  Allowed := TList<Integer>.Create;
  try
    Initialize;
    {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
    PulseInitialize('pulse_strategy_filters', Profile, Selected);
    Found := False;
    PulseRunCase('pulse_strategy_filters', 'cached-thresholds', 'compiler+rtl', 'filter', @CachedCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_strategy_filters', 'early-rejection', 'compiler+rtl', 'filter', @EarlyCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_strategy_filters', 'station-list-scan', 'compiler+rtl', 'filter', @LongCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_strategy_filters', 'recompute-limits', 'compiler+rtl', 'filter', @LadderCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_strategy_filters', 'read-clock', 'compiler+rtl', 'filter', @ClockCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_strategy_filters', 'format-rejection', 'compiler+rtl', 'filter', @ReportCase, Batch, Profile, Selected, Found, @Scan);
    PulseFinish('pulse_strategy_filters', Selected, Found);
  finally
    Allowed.Free;
    Calibration.Free;
  end;
end.
