{$push}
{$packrecords c}
type
  { Linux libc struct tm: nine int fields followed by long and char*. }
  TZoneCalendar = record
    Second, Minute, Hour, Day, Month, Year, WeekDay, YearDay, Daylight: LongInt;
    Offset: NativeInt;
    Name: PAnsiChar;
  end;
  PZoneCalendar = ^TZoneCalendar;
{$pop}
function ZoneCLocalTime(var Epoch: Int64; var Calendar: TZoneCalendar): PZoneCalendar;
  cdecl; external 'c' name 'localtime_r';
function ZoneMakeTime(var Calendar: TZoneCalendar): Int64; cdecl; external 'c' name 'mktime';
procedure ZoneRefresh; cdecl; external 'c' name 'tzset';
function ZoneEnvironment(Name: PAnsiChar): PAnsiChar; cdecl; external 'c' name 'getenv';
function ZoneMonotonic(ClockId: LongInt; var Stamp: TTimeSpec): LongInt;
  cdecl; external 'c' name 'clock_gettime';

threadvar
  ZoneCacheValid: Boolean;
  ZoneCacheEpoch, ZoneCacheSecond: Int64;
  ZoneCacheCalendar: TZoneCalendar;

function ZoneLocalTime(var Epoch: Int64; var Calendar: TZoneCalendar;
  FreshRules: Boolean = False): PZoneCalendar;
var
  Stamp: TTimeSpec;
  Cacheable: Boolean;
begin
  { Explicit TZ keeps libc's immediate environment-change semantics. With TZ
    unset, tzset otherwise stats /etc/localtime on every call. Cache only the
    numeric conversion of this exact UTC second, for at most one monotonic
    second. The caller still reads the clock and its fractional part afresh. }
  if Assigned(ZoneEnvironment('TZ')) then
    begin
    ZoneRefresh;
    Exit(ZoneCLocalTime(Epoch, Calendar));
    end;
  Cacheable := ZoneMonotonic(CLOCK_MONOTONIC, Stamp) = 0;
  if Cacheable and not FreshRules and ZoneCacheValid and
    (ZoneCacheEpoch = Epoch) and (ZoneCacheSecond = Stamp.tv_sec) then
    begin
    Calendar := ZoneCacheCalendar;
    Exit(@Calendar);
    end;
  ZoneCacheValid := False;
  ZoneRefresh;
  Result := ZoneCLocalTime(Epoch, Calendar);
  if Cacheable and Assigned(Result) then
    begin
    ZoneCacheCalendar := Calendar;
    { libc owns Name; another native tzset may invalidate it. Named callers
      and validation after mktime always use the live provider. }
    ZoneCacheCalendar.Name := nil;
    ZoneCacheEpoch := Epoch;
    ZoneCacheSecond := Stamp.tv_sec;
    ZoneCacheValid := True;
    end;
end;
