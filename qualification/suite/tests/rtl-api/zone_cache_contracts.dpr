program zone_cache_contracts;
{$mode delphiunicode}
uses cthreads, SysUtils, Classes, DateUtils, UnixType, Linux, BaseUnix;
{$i zonecalendar.inc}
function SetEnv(Name, Value: PAnsiChar; Overwrite: LongInt): LongInt; cdecl; external 'c' name 'setenv';
function UnsetEnv(Name: PAnsiChar): LongInt; cdecl; external 'c' name 'unsetenv';
function MountZone(Source, Target, Kind: PAnsiChar; Flags: NativeUInt; Data: Pointer): LongInt;
  cdecl; external 'c' name 'mount';
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
procedure AdministrativeZone;
const
  Epochs: array[0..4] of Int64 = (1774745999,1774746000,1792889999,1792890000,1774745999);
  Offsets: array[0..4] of LongInt = (3600,7200,7200,3600,3600);
var I: Integer; Epoch: Int64; C:TZoneCalendar; Start,Finish:TTimeSpec;
  U:TSystemTime; N,UTC:TDateTime; Delta,Elapsed:Int64; Minutes:Integer; DST:Boolean;
  UTCFile,TokyoFile,BerlinFile:LongInt;

  procedure BindFile(Handle:LongInt);
  var Source:AnsiString;
  begin
    Source:='/proc/self/fd/'+AnsiString(IntToStr(Handle));
    Check(MountZone(PAnsiChar(Source),'/etc/localtime',nil,4096,nil)=0,'bind captured zone file');
  end;
begin
  { Only invoked inside an isolated mount namespace, never against the host. }
  Check((fpreadlink('/proc/self/ns/mnt')<>'') and
    (fpreadlink('/proc/self/ns/mnt')<>fpreadlink('/proc/1/ns/mnt')), 'private mount namespace required');
  { /etc/localtime may be a symlink into zoneinfo. Keep original files open so
    mounting Tokyo over that target cannot also replace our UTC source. }
  UTCFile:=FpOpen('/usr/share/zoneinfo/UTC',O_RDONLY);
  TokyoFile:=FpOpen('/usr/share/zoneinfo/Asia/Tokyo',O_RDONLY);
  BerlinFile:=FpOpen('/usr/share/zoneinfo/Europe/Berlin',O_RDONLY);
  Check((UTCFile>=0) and (TokyoFile>=0) and (BerlinFile>=0),'open original zone files');
  BindFile(UTCFile);
  Check(UnsetEnv('TZ')=0,'system TZ');
  Epoch:=1774745999;
  Check(Assigned(ZoneLocalTime(Epoch,C,True)) and (C.Offset=0),'initial UTC');
  repeat
    Check(ZoneMonotonic(CLOCK_MONOTONIC,Start)=0,'select mktime bucket');
    if Start.tv_nsec<100000000 then Break;
    Sleep(1);
  until False;
  N:=Now;
  BindFile(TokyoFile);
  Check(GetLocalTimeOffset(N+9/24,False,Minutes,DST) and (Minutes=-540),
    'mktime validation must not reuse an older calendar for the same epoch');
  Check(ZoneMonotonic(CLOCK_MONOTONIC,Finish)=0,'mktime bucket after');
  Check(Start.tv_sec=Finish.tv_sec,'mktime negative control requires the same bucket');
  N:=Now;
  BindFile(UTCFile);
  Check(ZoneMonotonic(CLOCK_MONOTONIC,Start)=0,'admin start');
  repeat
    N:=Now;
    GetUniversalTime(U);
    UTC:=SystemTimeToDateTime(U);
    Delta:=Round((N-UTC)*SecsPerDay);
    Check(ZoneMonotonic(CLOCK_MONOTONIC,Finish)=0,'admin polling clock');
    Elapsed:=(Finish.tv_sec-Start.tv_sec)*1000+(Finish.tv_nsec-Start.tv_nsec) div 1000000;
    if Delta=0 then Break;
    Sleep(1);
  until Elapsed>1200;
  Check((Delta=0) and (Elapsed<=1200),Format('system-zone refresh delta=%d elapsed=%d ms',[Delta,Elapsed]));
  BindFile(BerlinFile);
  Check(Assigned(ZoneLocalTime(Epoch,C,True)),'refresh Berlin rules');
  for I:=0 to High(Epochs) do begin
    Epoch:=Epochs[I];
    Check(Assigned(ZoneLocalTime(Epoch,C)) and (C.Offset=Offsets[I]),'cached DST boundary and rollback');
    Check(Assigned(ZoneLocalTime(Epoch,C)) and (C.Offset=Offsets[I]),'repeated DST epoch');
  end;
  WriteLn('ZONE_ADMIN_CONTRACTS_OK refresh_ms=',Elapsed);
  FpClose(BerlinFile);
  FpClose(TokyoFile);
  FpClose(UTCFile);
end;
procedure Verify(Epoch: Int64);
var Actual, Expected: TZoneCalendar;
begin
  Check(Assigned(ZoneLocalTime(Epoch, Actual)), 'numeric provider');
  ZoneRefresh;
  Check(Assigned(ZoneCLocalTime(Epoch, Expected)), 'libc oracle');
  Actual.Name := nil;
  Expected.Name := nil;
  { Compare fields, not ABI padding. }
  Check((Actual.Second=Expected.Second) and (Actual.Minute=Expected.Minute) and
    (Actual.Hour=Expected.Hour) and (Actual.Day=Expected.Day) and
    (Actual.Month=Expected.Month) and (Actual.Year=Expected.Year) and
    (Actual.WeekDay=Expected.WeekDay) and (Actual.YearDay=Expected.YearDay) and
    (Actual.Daylight=Expected.Daylight) and (Actual.Offset=Expected.Offset), 'calendar differs');
end;
type
  TWorker = class(TThread)
    procedure Execute; override;
  end;
procedure TWorker.Execute;
var I: Integer;
begin
  for I:=1 to 10000 do Verify(1774745999 + I mod 3);
end;
procedure Run;
const
  Epochs: array[0..9] of Int64 = (0,-1,1774745999,1774746000,1792889999,1792890000,
    4087756800,1332637199,1332637200,1774745999);
  Zones: array[0..6] of AnsiString = ('','UTC0','Europe/Berlin','Australia/Lord_Howe',
    'Asia/Kathmandu',':/usr/share/zoneinfo/Asia/Tokyo','UTC0');
var I,J,Status: Integer; Epoch: Int64; A,B:TZoneCalendar; Before,After:TTimeSpec;
  Threads: array[0..3] of TWorker; Pid: TPid;
begin
  for I:=0 to High(Zones) do begin
    Check(SetEnv('TZ',PAnsiChar(Zones[I]),1)=0, 'set TZ');
    for J:=0 to High(Epochs) do begin Verify(Epochs[J]); Verify(Epochs[J]); end;
  end;
  Check(UnsetEnv('TZ')=0,'unset TZ');
  for I:=0 to High(Epochs) do begin Verify(Epochs[I]); Verify(Epochs[I]); end;
  Epoch:=1774745999;
  repeat
    Check(ZoneMonotonic(CLOCK_MONOTONIC,Before)=0,'monotonic before');
    Check(Assigned(ZoneLocalTime(Epoch,A,True)) and Assigned(A.Name),'live name');
    Check(Assigned(ZoneLocalTime(Epoch,B)),'numeric after named');
    Check(ZoneMonotonic(CLOCK_MONOTONIC,After)=0,'monotonic after');
  until Before.tv_sec=After.tv_sec;
  Check((A.Offset=B.Offset) and (B.Name=nil),'named refill numeric cache');
  Check(SetEnv('TZ','ZZZ-9',1)=0,'native excursion');
  ZoneRefresh;
  Check(UnsetEnv('TZ')=0,'native return');
  Verify(Epoch);
  if Assigned(ZoneEnvironment('MOON_ZONE_FAULT_SHIM')) then begin
    Check(SetEnv('MOON_ZONE_CLOCK_FAIL','1',1)=0,'inject clock failure');
    Check(Assigned(ZoneLocalTime(Epoch,B)) and Assigned(B.Name),'clock failure uses live provider');
    Verify(Epoch);
    Check(UnsetEnv('MOON_ZONE_CLOCK_FAIL')=0,'remove clock failure');
    Verify(Epoch);
  end;
  for I:=0 to High(Threads) do Threads[I]:=TWorker.Create(False);
  for I:=0 to High(Threads) do begin
    Threads[I].WaitFor;
    Check(Threads[I].FatalException=nil,'parallel conversion');
    Threads[I].Free;
  end;
  Pid:=FpFork;
  Check(Pid>=0,'fork');
  if Pid=0 then begin Verify(Epoch); Verify(Epoch-1); Halt(0); end;
  Check(FpWaitPid(Pid,@Status,0)=Pid,'waitpid');
  Check(Status=0,'fork conversion');
end;
begin
  if (ParamCount=1) and (ParamStr(1)='--admin') then AdministrativeZone else Run;
  WriteLn('ZONE_CACHE_CONTRACTS_OK');
end.
