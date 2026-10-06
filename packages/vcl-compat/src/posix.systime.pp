{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.SysTime;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, UnixType, Posix.SysTypes;
type
  timeval = UnixType.timeval;
  Ptimeval = ^timeval;
  timezone = record
    tz_minuteswest, tz_dsttime: cint;
  end;
  Ptimezone = ^timezone;
function gettimeofday(Value: Ptimeval; Zone: Ptimezone): cint; cdecl; external 'c';
function utimes(Path: PAnsiChar; Times: Ptimeval): cint; cdecl; external 'c';
implementation

end.
