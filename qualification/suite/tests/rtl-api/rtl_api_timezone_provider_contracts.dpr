program rtl_api_timezone_provider_contracts;

{$mode delphiunicode}

uses
  {$ifdef unix}cwstring,{$endif}
  SysUtils, DateUtils{$ifdef windows}, Windows{$endif};

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then
    raise Exception.Create(Name);
end;

{$ifdef windows}
{$i timezone.inc}

var
  Fixture: TTimeZoneInformation;
  Disabled, Failed: Boolean;
  NextYear: Boolean;
  RequestedYear: Word;

function FixtureRules(Year: USHORT; Info: PDynamicTimeZoneInformation;
  var Rules: TTimeZoneInformation): BOOL; stdcall;
begin
  Rules := Fixture;
  RequestedYear := Year;
  If NextYear and (Year = 2027) then
    Rules.Bias := -30;
  Result := not Failed;
end;

function FixtureConvert(Info: PDynamicTimeZoneInformation; UTC, Local: PSystemTime): BOOL; stdcall;
var
  U, StartUTC, EndUTC: TDateTime;
  Daylight: Boolean;
  Bias: Integer;
begin
  Result := not Failed;
  If not Result then
    Exit;
  U := SystemTimeToDateTime(UTC^);
  If NextYear then begin
    DateTimeToSystemTime(EncodeDateTime(2027, 1, 1, 1, 15, 0, 0), Local^);
    Exit;
  end;
  StartUTC := ZoneTransition(UTC^.Year, Fixture.DaylightDate) +
    (Fixture.Bias + Fixture.StandardBias) / MinsPerDay;
  EndUTC := ZoneTransition(UTC^.Year, Fixture.StandardDate) +
    (Fixture.Bias + Fixture.DaylightBias) / MinsPerDay;
  If StartUTC < EndUTC then
    Daylight := (U >= StartUTC) and (U < EndUTC)
  else
    Daylight := (U >= StartUTC) or (U < EndUTC);
  If Daylight and not Disabled then
    Bias := Fixture.Bias + Fixture.DaylightBias
  else
    Bias := Fixture.Bias + Fixture.StandardBias;
  DateTimeToSystemTime(U - Bias / MinsPerDay, Local^);
end;

function FixtureDynamic(var Info: TDynamicTimeZoneInformation): DWORD; stdcall;
begin
  Info := Default(TDynamicTimeZoneInformation);
  Info.DynamicDaylightTimeDisabled := Disabled;
  Result := TIME_ZONE_ID_UNKNOWN;
end;

procedure WindowsRules;
var
  Seconds: Int64;
  Minutes: Integer;
  DST: Boolean;
  Name: string;
  U: TDateTime;
begin
  Check(Win32MajorVersion >= 6, 'Windows version startup');
  Check(SysUtils.GetTickCount64 > 0, '64-bit uptime available');
  GetTimeZoneInformationForYear := FixtureRules;
  GetDynamicTimeZoneInformation := FixtureDynamic;
  ConvertDynamicLocalTime := FixtureConvert;
  Fixture := Default(TTimeZoneInformation);
  Fixture.Bias := -630;
  Fixture.DaylightBias := -30;
  Fixture.DaylightDate.Month := 10;
  Fixture.DaylightDate.Day := 1;
  Fixture.DaylightDate.Hour := 2;
  Fixture.StandardDate.Month := 4;
  Fixture.StandardDate.Day := 1;
  Fixture.StandardDate.Hour := 2;
  Check(GetLocalTimeZoneInfo(EncodeDate(2026, 1, 15), Seconds, DST, Name), 'southern provider');
  Check(DST and (Seconds = 39600), 'southern summer +11');
  Check(GetLocalTimeZoneInfo(EncodeDate(2026, 7, 15), Seconds, DST, Name), 'winter provider');
  Check(not DST and (Seconds = 37800), 'southern winter +10:30');
  U := EncodeDateTime(2026, 10, 3, 15, 30, 0, 0);
  Check(GetLocalTimeZoneInfo(IncSecond(U, -1), Seconds, DST, Name) and not DST, 'before spring change');
  Check(GetLocalTimeZoneInfo(U, Seconds, DST, Name) and DST, 'at spring change');
  Check(not GetLocalTimeOffset(EncodeDateTime(2026, 10, 4, 2, 15, 0, 0), False, Minutes, DST),
    'gap has no UTC candidate');
  Check(GetLocalTimeOffset(EncodeDateTime(2026, 4, 5, 1, 45, 0, 0), False, Minutes, DST) and
    not DST and (Minutes = -630), 'fold prefers standard');
  Disabled := True;
  Check(GetLocalTimeZoneInfo(EncodeDate(2026, 1, 15), Seconds, DST, Name) and not DST and
    (Seconds = 37800), 'disabled seasonal adjustment');
  Disabled := False;
  Fixture.DaylightBias := 0;
  Fixture.StandardName[0] := 'S';
  Fixture.DaylightName[0] := 'D';
  Check(GetLocalTimeZoneInfo(EncodeDate(2026, 1, 15), Seconds, DST, Name) and DST and
    (Name = 'D') and (Seconds = 37800), 'equal offsets retain daylight season and name');
  Fixture.DaylightBias := -30;
  Fixture.DaylightDate.Month := 12;
  Fixture.DaylightDate.Day := 5;
  U := EncodeDateTime(2026, 12, 26, 15, 30, 0, 0);
  Check(GetLocalTimeZoneInfo(U, Seconds, DST, Name) and DST, 'last Sunday across December boundary');
  NextYear := True;
  Fixture.Bias := 0;
  Fixture.DaylightBias := -60;
  U := EncodeDateTime(2026, 12, 31, 23, 45, 0, 0);
  Check(GetLocalTimeZoneInfo(U, Seconds, DST, Name) and (RequestedYear = 2027) and
    DST and (Seconds = 5400), 'native local year selects historical rules across New Year');
  NextYear := False;
  Failed := True;
  Seconds := 999;
  DST := True;
  Check(not GetLocalTimeZoneInfo(U, Seconds, DST, Name), 'provider failure reported');
  Check((Seconds = 0) and not DST, 'provider failure initializes outputs');
end;
{$endif}

{$ifdef linux}
function SetEnv(Name, Value: PAnsiChar; Overwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
procedure TZSet; cdecl; external 'c' name 'tzset';

procedure Zone(const Value: AnsiString);
begin
  Check(SetEnv('TZ', PAnsiChar(Value), 1) = 0, 'set test timezone');
  TZSet;
end;

type
  TClockValue = record Seconds, Microseconds: Int64; end;
function ClockValue(var Value: TClockValue; Zone: Pointer): Integer; cdecl; external 'c' name 'gettimeofday';

procedure CheckLiveClocks(const ZoneName: AnsiString);
var
  Before, After: TClockValue;
  LocalNow, LocalSystem, UTC, U0, U1, LocalBefore, LocalAfter, LocalDate, LocalTime: TDateTime;
  Calendar: TSystemTime;
  Offset: Int64;
  DST: Boolean;
  Name: string;
begin
  // Deliberately omit explicit tzset: changing TZ is observed by all public clocks.
  Check(SetEnv('TZ', PAnsiChar(ZoneName), 1) = 0, 'set live TZ');
  Check(ClockValue(Before, nil) = 0, 'clock before');
  LocalNow := Now;
  GetLocalTime(Calendar);
  LocalSystem := SystemTimeToDateTime(Calendar);
  UTC := TTimeZone.Local.ToUniversalTime(LocalNow);
  Check(ClockValue(After, nil) = 0, 'clock after');
  U0 := UnixToDateTime(Before.Seconds, True) + Before.Microseconds / (1000000.0 * SecsPerDay);
  U1 := UnixToDateTime(After.Seconds, True) + After.Microseconds / (1000000.0 * SecsPerDay);
  Check((UTC >= U0 - 0.002 / SecsPerDay) and (UTC <= U1 + 0.002 / SecsPerDay), 'Now uses same TZ as TTimeZone');
  Check(Abs(LocalSystem - LocalNow) <= (U1 - U0) + 0.002 / SecsPerDay, 'GetLocalTime agrees with Now');
  Check(GetLocalTimeZoneInfo(UTC, Offset, DST, Name), 'current offset');
  Check(GetLocalTimeOffset = -Offset div 60, 'plain offset agrees with dated offset');
  LocalBefore := Now;
  LocalDate := Date;
  LocalTime := Time;
  LocalAfter := Now;
  Check((LocalDate >= Trunc(LocalBefore)) and (LocalDate <= Trunc(LocalAfter)), 'Date is local');
  // Reconstruct both possible dates when the measurements straddle midnight.
  Check(((Trunc(LocalBefore) + LocalTime >= LocalBefore) and
         (Trunc(LocalBefore) + LocalTime <= LocalAfter)) or
        ((Trunc(LocalAfter) + LocalTime >= LocalBefore) and
         (Trunc(LocalAfter) + LocalTime <= LocalAfter)), 'Time is local');
end;

procedure LinuxRules;
var
  Local, UTC, Other: TDateTime;
  Z: TTimeZone;
begin
  CheckLiveClocks('UTC0');
  CheckLiveClocks('MSK-3');
  CheckLiveClocks(':Europe/Moscow');
  CheckLiveClocks('America/New_York');
  CheckLiveClocks('<+0545>-5:45');
  Z := TTimeZone.Local;
  Zone('Europe/Berlin');
  Check(Z.HasDST(EncodeDate(2026, 1, 1)), 'Berlin HasDST in winter');
  Check(Z.GetDisplayName(EncodeDate(2026, 1, 15)) <> Z.GetDisplayName(EncodeDate(2026, 7, 15)),
    'seasonal names');
  Local := EncodeDateTime(2026, 3, 29, 2, 30, 0, 0);
  Check(Z.IsInvalidTime(Local), 'Berlin spring gap');
  try
    DateTimeToUnix(Local, False);
    Check(False, 'Unix accepted a gap');
  except
    on ELocalTimeInvalid do ;
  end;
  Local := EncodeDateTime(2026, 10, 25, 2, 30, 0, 0);
  UTC := Z.ToUniversalTime(Local);
  Other := Z.ToUniversalTime(Local, True);
  Check(Z.IsAmbiguousTime(Local) and (SecondsBetween(UTC, Other) = 3600), 'Berlin fold');
  Check((Abs(Z.ToLocalTime(UTC) - Local) < 0.1 / SecsPerDay) and
    (Abs(Z.ToLocalTime(Other) - Local) < 0.1 / SecsPerDay), 'both fold round trips');
  Check(DateToISO8601(Local, False) = '2026-10-25T02:30:00.000+01:00', 'ISO fold offset');
  Check(Abs(UnixToDateTime(DateTimeToUnix(Local, False), False) - Local) < 0.1 / SecsPerDay, 'Unix local round trip');
  Zone('Australia/Lord_Howe');
  Check(Z.GetUtcOffset(EncodeDate(2026, 1, 15)).TotalSeconds = 39600, 'Lord Howe summer');
  Check(Z.GetUtcOffset(EncodeDate(2026, 7, 15)).TotalSeconds = 37800, 'Lord Howe winter');
  Local := EncodeDateTime(2026, 4, 5, 1, 45, 0, 0);
  Check(Z.IsAmbiguousTime(Local) and
    (SecondsBetween(Z.ToUniversalTime(Local), Z.ToUniversalTime(Local, True)) = 1800), 'Lord Howe fold');
  Zone('Europe/Moscow');
  Check(Z.GetUtcOffset(EncodeDate(2012, 1, 15)).TotalSeconds = 14400, 'historical Moscow +4');
  Check(Z.GetUtcOffset(EncodeDate(2026, 1, 15)).TotalSeconds = 10800, 'current Moscow +3');
  Check(not Z.HasDST(EncodeDate(2026, 1, 1)), 'Moscow has no DST');
  Zone('Etc/UTC');
  Check(not Z.HasDST(EncodeDate(2026, 1, 1)), 'UTC has no DST');
  Check(Z.GetAbbreviation(EncodeDate(2026, 1, 1)) = 'GMT', 'UTC abbreviation');
  Zone('Europe/Berlin');
  Check(Z.GetUtcOffset(EncodeDate(2099, 7, 15)).TotalSeconds = 7200, 'TZif future rule');
end;
{$endif}

begin
  {$ifdef windows}WindowsRules;{$endif}
  {$ifdef linux}LinuxRules;{$endif}
  WriteLn('RTL_API_TIMEZONE_PROVIDER_CONTRACTS_OK');
end.
