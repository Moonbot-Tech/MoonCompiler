{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.SysTypes;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, UnixType;
type
  size_t = UnixType.size_t;
  ssize_t = UnixType.ssize_t;
  off_t = UnixType.off_t;
  pid_t = UnixType.pid_t;
  uid_t = UnixType.uid_t;
  gid_t = UnixType.gid_t;
  mode_t = cuint;
  dev_t = cuint64;
  ino_t = culong;
  nlink_t = culong;
  time_t = UnixType.time_t;
  clock_t = clong;
  clockid_t = cint;
  socklen_t = UnixType.socklen_t;
  pthread_t = UnixType.pthread_t;
  Ptime_t = ^time_t;
  Psize_t = ^size_t;
  Psocklen_t = ^socklen_t;

implementation

end.
