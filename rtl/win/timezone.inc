{ Windows time-zone provider shared with the rule-fixture contract test. }

type
  TGetTimeZoneInformationForYear = function(wYear: USHORT; Info: PDynamicTimeZoneInformation;
    var Rules: TTimeZoneInformation): BOOL; stdcall;
  TGetDynamicTimeZoneInformation = function(var Info: TDynamicTimeZoneInformation): DWORD; stdcall;
  TConvertDynamicLocalTime = function(Info: PDynamicTimeZoneInformation; UTC, Local: PSystemTime): BOOL; stdcall;
var
  ConvertDynamicLocalTime: TConvertDynamicLocalTime = nil;
  GetTimeZoneInformationForYear: TGetTimeZoneInformationForYear = nil;
  GetDynamicTimeZoneInformation: TGetDynamicTimeZoneInformation = nil;

function LocalZoneRules(Year: Word; out Rules: TTimeZoneInformation;
  Info: PDynamicTimeZoneInformation = nil): Boolean;
var
  Dynamic: TDynamicTimeZoneInformation;
begin
  Rules:=Default(TTimeZoneInformation);
  if not Assigned(GetTimeZoneInformationForYear) then
    Exit(False);
  if (Info=nil) and Assigned(GetDynamicTimeZoneInformation) then
    begin
    Dynamic:=Default(TDynamicTimeZoneInformation);
    if GetDynamicTimeZoneInformation(Dynamic)=TIME_ZONE_ID_INVALID then
      Exit(False);
    Info:=@Dynamic;
    end;
  Result:=GetTimeZoneInformationForYear(Year,Info,Rules);
  if Result and Assigned(Info) and Info^.DynamicDaylightTimeDisabled then
    begin
    Rules.StandardDate.Month:=0;
    Rules.DaylightDate.Month:=0;
    end;
end;

function ZoneTransition(Year: Word; const Rule: TSystemTime): TDateTime;
var
  Day, Shift: Integer;
  Y, M, D: Word;
begin
  if Rule.Year<>0 then
    Result:=EncodeDate(Rule.Year,Rule.Month,Rule.Day)
  else
    begin
    Result:=EncodeDate(Year,Rule.Month,1);
    Shift:=(Integer(Rule.wDayOfWeek)-(DayOfWeek(Result)-1)+7) mod 7;
    Day:=1+Shift+7*(Rule.Day-1);
    Result:=Result+Day-1;
    DecodeDate(Result,Y,M,D);
    if M<>Rule.Month then
      Result:=Result-7;
    end;
  Result:=ComposeDateTime(Result,EncodeTime(Rule.Hour,Rule.Minute,Rule.Second,Rule.Millisecond));
end;

function GetLocalTimeZoneInfo(const UTC: TDateTime; out OffsetSeconds: Int64;
  out IsDST: Boolean; out ZoneName: string): Boolean;
var
  Dynamic: TDynamicTimeZoneInformation;
  Universal, Local: TSystemTime;
  UniversalStamp, LocalStamp: TTimeStamp;
  Rules: TTimeZoneInformation;
  Seconds: Int64;
  StartLocal, EndLocal, LocalValue: TDateTime;
begin
  OffsetSeconds:=0;
  IsDST:=False;
  ZoneName:='';
  if not Assigned(ConvertDynamicLocalTime) or not Assigned(GetDynamicTimeZoneInformation) then
    Exit(False);
  Dynamic:=Default(TDynamicTimeZoneInformation);
  if GetDynamicTimeZoneInformation(Dynamic)=TIME_ZONE_ID_INVALID then
    Exit(False);
  DateTimeToSystemTime(UTC,Universal);
  if not ConvertDynamicLocalTime(@Dynamic,@Universal,@Local) then
    Exit(False);
  { Windows applies historical rules before we select the local year's name.
    Inferring that year from a standard bias is wrong around New Year in DST,
    and iterating year/bias can oscillate after a political offset change. }
  if not LocalZoneRules(Local.Year,Rules,@Dynamic) then
    Exit(False);
  UniversalStamp:=DateTimeToTimeStamp(SystemTimeToDateTime(Universal));
  LocalStamp:=DateTimeToTimeStamp(SystemTimeToDateTime(Local));
  Seconds:=Int64(LocalStamp.Date-UniversalStamp.Date)*SecsPerDay+
    (LocalStamp.Time-UniversalStamp.Time) div 1000;
  IsDST:=(Rules.DaylightDate.Month<>0) and (Rules.StandardDate.Month<>0) and
    (Rules.DaylightBias<>Rules.StandardBias) and
    (Seconds=-Int64(Rules.Bias+Rules.DaylightBias)*60);
  if (Rules.DaylightDate.Month<>0) and (Rules.StandardDate.Month<>0) and
     (Rules.DaylightBias=Rules.StandardBias) then
    begin
    { Equal offsets can still have distinct seasonal names. There is no fold
      or gap in this case, so compare the actual local date to both rules. }
    LocalValue:=SystemTimeToDateTime(Local);
    StartLocal:=ZoneTransition(Local.Year,Rules.DaylightDate);
    EndLocal:=ZoneTransition(Local.Year,Rules.StandardDate);
    if StartLocal<EndLocal then
      IsDST:=(LocalValue>=StartLocal) and (LocalValue<EndLocal)
    else
      IsDST:=(LocalValue>=StartLocal) or (LocalValue<EndLocal);
    end;
  if IsDST then
    ZoneName:=string(PWideChar(@Rules.DaylightName))
  else
    ZoneName:=string(PWideChar(@Rules.StandardName));
  OffsetSeconds:=Seconds;
  Result:=True;
end;

function GetLocalTimeOffset(const DateTime: TDateTime; const InputIsUTC: Boolean;
  out Offset: Integer; out IsDST: Boolean): Boolean;
var
  Seconds, Candidate: Int64;
  Name: string;
  Rules: TTimeZoneInformation;
  Year, Month, Day: Word;
begin
  Offset:=0;
  IsDST:=False;
  if InputIsUTC then
    Result:=GetLocalTimeZoneInfo(DateTime,Seconds,IsDST,Name)
  else
    begin
    DecodeDate(DateTime,Year,Month,Day);
    if not LocalZoneRules(Year,Rules) then
      Exit(False);
    { Prefer standard time in a fold. A gap has no round-tripping candidate. }
    Candidate:=-Int64(Rules.Bias+Rules.StandardBias)*60;
    Result:=GetLocalTimeZoneInfo(DateTime-Candidate/SecsPerDay,Seconds,IsDST,Name) and (Seconds=Candidate);
    if not Result and (Rules.DaylightDate.Month<>0) then
      begin
      Candidate:=-Int64(Rules.Bias+Rules.DaylightBias)*60;
      Result:=GetLocalTimeZoneInfo(DateTime-Candidate/SecsPerDay,Seconds,IsDST,Name) and (Seconds=Candidate);
      end;
    end;
  if Result then
    Offset:=-Seconds div 60;
end;
