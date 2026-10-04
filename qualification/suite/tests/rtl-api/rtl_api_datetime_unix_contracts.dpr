program rtl_api_datetime_unix_contracts;
{$mode delphi}{$R-}{$Q-}
uses SysUtils, DateUtils, Math;

function Reference(const AValue: TDateTime; AInputIsUTC: Boolean): Int64;
var T: TDateTime;
begin
  T := AValue;
  If not AInputIsUTC then
    T := IncMinute(T, GetLocalTimeOffset(AValue, AInputIsUTC));
  T := RecodeMillisecond(T, 0);
  If T < 0 then
    T := Trunc(T) - Frac(T);
  Result := Round((T - UnixEpoch) * SecsPerDay);
end;

var Checks: Int64;
procedure Check(T: TDateTime; UTC: Boolean);
var A, B: Int64;
    Before, After: UnicodeString;
begin
  Before := '';
  After := '';
  A := 0;
  B := 0;
  try
    A := Reference(T, UTC);
  except
    on E: Exception do
      Before := E.ClassName;
  end;
  try
    B := DateTimeToUnix(T, UTC);
  except
    on E: Exception do
      After := E.ClassName;
  end;
  If (Before <> After) or ((Before = '') and (A <> B)) then
  begin
    Writeln('FAIL ', T:0:18, ' UTC=', UTC, ' old=', A, ' new=', B, ' exceptions=', Before, '/', After, ' check=', Checks);
    Halt(1);
  end;
  Inc(Checks);
end;

const Days: array[0..9] of Integer = (0, 1, 365, 25568, 25569, 45200, 73049, 100000, 1000000, 2958465);
      Milliseconds: array[0..10] of Integer = (0, 1, 2, 998, 999, 1000, 1001, 3599999, 43200000, 86399998, 86399999);
var I, J, K, M: Integer;
    T: TDateTime;
    Bits, Seed: UInt64;
    Mode: TFPURoundingMode;
begin
  for I := 0 to High(Days) do
    for J := 0 to High(Milliseconds) do
    begin
      T := Days[I] + (Milliseconds[J] + 0.5) / MSecsPerDay;
      Move(T, Bits, 8);
      for K := -4 to 4 do
      begin
        Seed := UInt64(Int64(Bits) + K);
        Move(Seed, T, 8);
        Check(T, True);
      end;
    end;
  Seed := $1258aefa09876543;
  for I := 0 to 199999 do
  begin
    Seed := Seed * UInt64($5851f42d4c957f2d) + 1;
    T := (Seed mod 2958466000000) / 1000000;
    Check(T, True);
  end;
  for I := -1000 to 1000 do
  begin
    Check(I / 4, True);
    If I mod 100 = 0 then
      Check(I / 4, False);
  end;
  Check(MaxDateTime, True);
  Check(NaN, True);
  Check(Infinity, True);
  Check(NegInfinity, True);
  Bits := UInt64($8000000000000000);
  Move(Bits, T, 8);
  Check(T, True);
  Bits := UInt64($fff8000000000001);
  Move(Bits, T, 8);
  Check(T, True);
  Mode := GetRoundMode;
  try
    for M := 0 to 3 do
    begin
      SetRoundMode(TFPURoundingMode(M));
      for I := 0 to 999 do
      begin
        T := 45200 + (I * 73 + 0.5) / SecsPerDay;
        Check(T, True);
      end;
    end;
  finally
    SetRoundMode(Mode);
  end;
  Writeln('RTL_API_DATETIME_UNIX_CONTRACTS_OK');
end.
