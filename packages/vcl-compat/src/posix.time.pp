{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Time;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, UnixType, Posix.SysTypes;
type
  time_t = Posix.SysTypes.time_t;
  Ptime_t = ^time_t;
  timespec = UnixType.timespec;
  Ptimespec = ^timespec;
  tm = record
    tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst: cint;
    tm_gmtoff: clong;
    tm_zone: PAnsiChar;
  end;
  Ptm = ^tm;
const
  CLOCK_REALTIME = 0;
  CLOCK_MONOTONIC = 1;
  CLOCK_PROCESS_CPUTIME_ID = 2;
  CLOCK_THREAD_CPUTIME_ID = 3;
  CLOCK_MONOTONIC_RAW = 4;
  CLOCK_BOOTTIME = 7;
  TIMER_ABSTIME = 1;
function time(Value: Ptime_t): time_t; cdecl; external 'c';
function clock: clock_t; cdecl; external 'c';
function clock_gettime(ClockID: clockid_t; Value: Ptimespec): cint; cdecl; external 'c';
function clock_getres(ClockID: clockid_t; Value: Ptimespec): cint; cdecl; external 'c';
function nanosleep(Request, Remaining: Ptimespec): cint; cdecl; external 'c';
function clock_nanosleep(ClockID: clockid_t; Flags: cint; Request, Remaining: Ptimespec): cint; cdecl; external 'c';
function localtime_r(Value: Ptime_t; Output: Ptm): Ptm; cdecl; external 'c';
function gmtime_r(Value: Ptime_t; Output: Ptm): Ptm; cdecl; external 'c';
function mktime(Value: Ptm): time_t; cdecl; external 'c';
function timegm(Value: Ptm): time_t; cdecl; external 'c';
procedure tzset; cdecl; external 'c';
function strftime(Output: PAnsiChar; Capacity: size_t; Format: PAnsiChar; Value: Ptm): size_t; cdecl; external 'c';
implementation

end.
