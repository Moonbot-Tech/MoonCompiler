program pulse_ema_filters;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$B-}
{$ifndef FPC}{$APPTYPE CONSOLE}{$endif}
uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}mormot.core.fpcx64mm,{$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Generics.Collections, pulse_harness;
{$I ../common/pulse_program_prefix.inc}

type
  TBand = record
    Weight: array[0..3] of Double;
    Lower, Upper, Offset: Double;
    Delay, Channel: Integer;
  end;
  TLevel = array[0..3] of Double;
  TMode = (SingleBand, GroupEight, RingHistory, Envelope, AlternativeGroups, MissingChannel);

const
  Batch = 64;
var
  History: array[0..2047] of TLevel;
  Bands: TList<TBand>;

function WithinBand(Index, Rule: Integer; Mode: TMode): Boolean;
var
  B: TBand;
  Level: TLevel;
  Row, K: Integer;
  Score, Peak, Value: Double;
begin
  B := Bands.Items[Rule];
  if (Mode = MissingChannel) and ((Index + B.Channel) mod 11 = 0) then Exit(False);
  Row := Index;
  if Mode in [RingHistory, AlternativeGroups] then Row := (Row - B.Delay) and High(History);
  Level := History[Row];
  Score := B.Offset;
  for K := 0 to High(Level) do
    Score := Score + B.Weight[K] * Level[(K + B.Channel) and 3];
  if Mode = AlternativeGroups then
    Score := (Score + History[Index][B.Channel] * 0.625) / 2;
  if Mode = Envelope then begin
    Peak := Score;
    for K := 1 to 12 do begin
      Value := History[(Row - K) and High(History)][B.Channel] * 0.625;
      if Value > Peak then Peak := Value;
    end;
    Score := Peak;
  end;
  Result := (Score >= B.Lower) and (Score <= B.Upper);
end;

function Matches(Index: Integer; Mode: TMode): Boolean;
var
  Group, Rule, Start: Integer;
begin
  if Mode = SingleBand then Exit(WithinBand(Index, 0, Mode));
  if Mode = AlternativeGroups then begin
    for Group := 0 to 3 do begin
      Start := Group * 8;
      Rule := 0;
      while (Rule < 8) and WithinBand(Index, Start + Rule, Mode) do Inc(Rule);
      if Rule = 8 then Exit(True);
    end;
    Exit(False);
  end;
  for Rule := 0 to 7 do
    if not WithinBand(Index, Rule, Mode) then Exit(False);
  Result := True;
end;

function Scan(Iterations: Integer; Mode: TMode): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 0 to Iterations - 1 do
    for J := 0 to Batch - 1 do begin
      Index := ((I and 31) * Batch + J * 29) and High(History);
      if Matches(Index, Mode) then Inc(Result, Index + 1);
    end;
end;

function SingleCase(N: Integer): UInt64; begin Result := Scan(N, SingleBand); end;
function GroupCase(N: Integer): UInt64; begin Result := Scan(N, GroupEight); end;
function HistoryCase(N: Integer): UInt64; begin Result := Scan(N, RingHistory); end;
function EnvelopeCase(N: Integer): UInt64; begin Result := Scan(N, Envelope); end;
function AlternativesCase(N: Integer): UInt64; begin Result := Scan(N, AlternativeGroups); end;
function MissingCase(N: Integer): UInt64; begin Result := Scan(N, MissingChannel); end;

procedure Initialize;
const
  { Sum of the accepted row numbers (one-based) over the entire fixture. }
  Expected: array[TMode] of UInt64 = (2085688, 1240416, 746761, 1035736, 2078233, 787675);
var
  I, K, Reading: Integer;
  Acc: array[0..3] of Integer;
  B: TBand;
  Mode: TMode;
begin
  for K := 0 to High(Acc) do Acc[K] := 100 * 256;
  for I := 0 to High(History) do begin
    Reading := 64 + ((I div 29 * 13 + I mod 17) mod 80);
    for K := 0 to High(Acc) do begin
      Inc(Acc[K], (Reading * 256 - Acc[K]) div (2 shl K));
      History[I][K] := Acc[K] / 256;
    end;
  end;
  for I := 0 to 31 do begin
    for K := 0 to 3 do B.Weight[K] := (1 + ((I + K) and 3)) / 16;
    B.Delay := 1 + (I * 37) mod 251;
    B.Channel := I and 3;
    B.Offset := I mod 7;
    B.Lower := 40 + (I mod 4) * 3;
    B.Upper := 84 + (I div 8) * 3;
    if I mod 8 = 7 then B.Upper := 68 + I div 8;
    Bands.Add(B);
  end;
  for Mode := Low(TMode) to High(TMode) do
    if Scan(Length(History) div Batch, Mode) <> Expected[Mode] then
      raise Exception.CreateFmt('EMA fixture mismatch in case %d', [Ord(Mode)]);
end;

var
  Profile: TPulseProfile;
  Selected: string;
  Found: Boolean;
begin
  Bands := TList<TBand>.Create;
  try
    if SizeOf(TBand) <> 64 then raise Exception.Create('Unexpected band record size');
    Initialize;
    {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
    PulseInitialize('pulse_ema_filters', Profile, Selected);
    Found := False;
    PulseRunCase('pulse_ema_filters', 'one-band', 'compiler+rtl', 'ema', @SingleCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_ema_filters', 'eight-bands', 'compiler+rtl', 'ema', @GroupCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_ema_filters', 'delayed-history', 'compiler+rtl', 'ema', @HistoryCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_ema_filters', 'channel-envelope', 'compiler+rtl', 'ema', @EnvelopeCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_ema_filters', 'alternative-groups', 'compiler+rtl', 'ema', @AlternativesCase, Batch, Profile, Selected, Found, @Scan);
    PulseRunCase('pulse_ema_filters', 'missing-channel', 'compiler+rtl', 'ema', @MissingCase, Batch, Profile, Selected, Found, @Scan);
    PulseFinish('pulse_ema_filters', Selected, Found);
  finally
    Bands.Free;
  end;
end.
