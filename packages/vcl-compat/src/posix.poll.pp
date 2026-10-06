{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Poll;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes;
type
  pollfd = record
    fd: cint;
    events, revents: cshort;
  end;
  Ppollfd = ^pollfd;
  nfds_t = culong;
const
  POLLIN = $001;
  POLLPRI = $002;
  POLLOUT = $004;
  POLLERR = $008;
  POLLHUP = $010;
  POLLNVAL = $020;
function poll(FDs: Ppollfd; Count: nfds_t; Timeout: cint): cint; cdecl; external 'c';
implementation

end.
