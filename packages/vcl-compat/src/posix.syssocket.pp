{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.SysSocket;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, Sockets, Posix.SysTypes;
type
  socklen_t = Posix.SysTypes.socklen_t;
  Psocklen_t = ^socklen_t;
  sockaddr = Sockets.sockaddr;
  Psockaddr = ^sockaddr;
  sockaddr_storage = Sockets.sockaddr_storage;
  Psockaddr_storage = ^sockaddr_storage;
  linger = Sockets.linger;
const
  AF_UNSPEC = Sockets.AF_UNSPEC;
  AF_UNIX = Sockets.AF_UNIX;
  AF_INET = Sockets.AF_INET;
  AF_INET6 = Sockets.AF_INET6;
  SOCK_STREAM = Sockets.SOCK_STREAM;
  SOCK_DGRAM = Sockets.SOCK_DGRAM;
  SOCK_RAW = Sockets.SOCK_RAW;
  SOL_SOCKET = Sockets.SOL_SOCKET;
  SO_REUSEADDR = Sockets.SO_REUSEADDR;
  SO_KEEPALIVE = Sockets.SO_KEEPALIVE;
  SO_ERROR = Sockets.SO_ERROR;
  SO_RCVBUF = Sockets.SO_RCVBUF;
  SO_SNDBUF = Sockets.SO_SNDBUF;
  SO_RCVTIMEO = Sockets.SO_RCVTIMEO;
  SO_SNDTIMEO = Sockets.SO_SNDTIMEO;
  SHUT_RD = Sockets.SHUT_RD;
  SHUT_WR = Sockets.SHUT_WR;
  SHUT_RDWR = Sockets.SHUT_RDWR;
  MSG_PEEK = Sockets.MSG_PEEK;
  MSG_DONTWAIT = Sockets.MSG_DONTWAIT;
  MSG_NOSIGNAL = Sockets.MSG_NOSIGNAL;
function socket(Domain, Kind, Protocol: cint): cint; cdecl; external 'c';
function socketpair(Domain, Kind, Protocol: cint; FDs: Pcint): cint; cdecl; external 'c';
function bind(FD: cint; Address: Psockaddr; Length: socklen_t): cint; cdecl; external 'c';
function connect(FD: cint; Address: Psockaddr; Length: socklen_t): cint; cdecl; external 'c';
function listen(FD, Backlog: cint): cint; cdecl; external 'c';
function accept(FD: cint; Address: Psockaddr; Length: Psocklen_t): cint; cdecl; external 'c';
function getsockname(FD: cint; Address: Psockaddr; Length: Psocklen_t): cint; cdecl; external 'c';
function getpeername(FD: cint; Address: Psockaddr; Length: Psocklen_t): cint; cdecl; external 'c';
function getsockopt(FD, Level, Option: cint; Value: Pointer; Length: Psocklen_t): cint; cdecl; external 'c';
function setsockopt(FD, Level, Option: cint; Value: Pointer; Length: socklen_t): cint; cdecl; external 'c';
function recv(FD: cint; Buffer: Pointer; Length: size_t; Flags: cint): ssize_t; cdecl; external 'c';
function send(FD: cint; Buffer: Pointer; Length: size_t; Flags: cint): ssize_t; cdecl; external 'c';
function recvfrom(FD: cint; Buffer: Pointer; Length: size_t; Flags: cint; Address: Psockaddr; AddrLen: Psocklen_t): ssize_t; cdecl; external 'c';
function sendto(FD: cint; Buffer: Pointer; Length: size_t; Flags: cint; Address: Psockaddr; AddrLen: socklen_t): ssize_t; cdecl; external 'c';
function shutdown(FD, How: cint): cint; cdecl; external 'c';
implementation

end.
