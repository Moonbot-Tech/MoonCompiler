{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Fcntl;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, BaseUnix, Posix.SysTypes;
const
  O_RDONLY = BaseUnix.O_RDONLY;
  O_WRONLY = BaseUnix.O_WRONLY;
  O_RDWR = BaseUnix.O_RDWR;
  O_CREAT = BaseUnix.O_CREAT;
  O_EXCL = BaseUnix.O_EXCL;
  O_TRUNC = BaseUnix.O_TRUNC;
  O_APPEND = BaseUnix.O_APPEND;
  O_NONBLOCK = BaseUnix.O_NONBLOCK;
  O_CLOEXEC = $80000;
  F_GETFD = BaseUnix.F_GETFD;
  F_SETFD = BaseUnix.F_SETFD;
  F_GETFL = BaseUnix.F_GETFL;
  F_SETFL = BaseUnix.F_SETFL;
  FD_CLOEXEC = 1;

function open(Path: PAnsiChar; Flags: cint): cint; cdecl; varargs; external 'c';
function fcntl(FD, Command: cint): cint; cdecl; varargs; external 'c';
function creat(Path: PAnsiChar; Mode: mode_t): cint; cdecl; external 'c';
implementation

end.
