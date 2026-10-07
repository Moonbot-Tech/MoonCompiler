{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Unistd;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, Posix.SysTypes;
const
  STDIN_FILENO = 0;
  STDOUT_FILENO = 1;
  STDERR_FILENO = 2;
  SEEK_SET = 0;
  SEEK_CUR = 1;
  SEEK_END = 2;
  F_OK = 0;
  X_OK = 1;
  W_OK = 2;
  R_OK = 4;
function getpid: pid_t; cdecl; external 'c';
function getppid: pid_t; cdecl; external 'c';
function getuid: uid_t; cdecl; external 'c';
function geteuid: uid_t; cdecl; external 'c';
function __close(FD: cint): cint; cdecl; external 'c' name 'close';
function __read(FD: cint; Buffer: Pointer; Count: size_t): ssize_t; cdecl; external 'c' name 'read';
function __write(FD: cint; Buffer: Pointer; Count: size_t): ssize_t; cdecl; external 'c' name 'write';
function lseek(FD: cint; Offset: off_t; Whence: cint): off_t; cdecl; external 'c';
function pipe(FDs: Pcint): cint; cdecl; external 'c';
function dup(FD: cint): cint; cdecl; external 'c';
function dup2(OldFD, NewFD: cint): cint; cdecl; external 'c';
function fsync(FD: cint): cint; cdecl; external 'c';
function ftruncate(FD: cint; Length: off_t): cint; cdecl; external 'c';
function unlink(Path: PAnsiChar): cint; cdecl; external 'c';
function __rmdir(Path: PAnsiChar): cint; cdecl; external 'c' name 'rmdir';
function __chdir(Path: PAnsiChar): cint; cdecl; external 'c' name 'chdir';
function getcwd(Buffer: PAnsiChar; Capacity: size_t): PAnsiChar; cdecl; external 'c';
function access(Path: PAnsiChar; Mode: cint): cint; cdecl; external 'c';
function readlink(Path, Buffer: PAnsiChar; Capacity: size_t): ssize_t; cdecl; external 'c';
function gethostname(Buffer: PAnsiChar; Capacity: size_t): cint; cdecl; external 'c';
function sysconf(Name: cint): clong; cdecl; external 'c';
function sleep(Seconds: cuint): cuint; cdecl; external 'c';
function usleep(Microseconds: cuint): cint; cdecl; external 'c';
implementation

end.
