{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Netdb;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, cNetDB, Posix.SysTypes, Posix.SysSocket;
type
  addrinfo = cNetDB.addrinfo;
  Paddrinfo = ^addrinfo;
  PPaddrinfo = ^Paddrinfo;
const
  AI_PASSIVE = cNetDB.AI_PASSIVE;
  AI_CANONNAME = cNetDB.AI_CANONNAME;
  AI_NUMERICHOST = cNetDB.AI_NUMERICHOST;
  AI_NUMERICSERV = cNetDB.AI_NUMERICSERV;
  AI_ADDRCONFIG = cNetDB.AI_ADDRCONFIG;
  AI_V4MAPPED = cNetDB.AI_V4MAPPED;
  AI_ALL = cNetDB.AI_ALL;
  EAI_AGAIN = cNetDB.EAI_AGAIN;
  EAI_NONAME = cNetDB.EAI_NONAME;
  EAI_SYSTEM = cNetDB.EAI_SYSTEM;
  NI_NUMERICHOST = cNetDB.NI_NUMERICHOST;
  NI_NUMERICSERV = cNetDB.NI_NUMERICSERV;
function getaddrinfo(Node, Service: PAnsiChar; Hints: Paddrinfo; Result: PPaddrinfo): cint; cdecl; external 'c';
procedure freeaddrinfo(Info: Paddrinfo); cdecl; external 'c';
function gai_strerror(Code: cint): PAnsiChar; cdecl; external 'c';
function getnameinfo(Address: Psockaddr; Length: socklen_t; Host: PAnsiChar; HostSize: socklen_t; Service: PAnsiChar; ServiceSize: socklen_t; Flags: cint): cint; cdecl; external 'c';
implementation

end.
