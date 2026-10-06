{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.NetinetIn;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, Sockets;
type
  in_addr = Sockets.in_addr;
  in6_addr = Sockets.in6_addr;
  sockaddr_in = Sockets.sockaddr_in;
  sockaddr_in6 = Sockets.sockaddr_in6;
  Pin_addr = ^in_addr;
  Pin6_addr = ^in6_addr;
  Psockaddr_in = ^sockaddr_in;
  Psockaddr_in6 = ^sockaddr_in6;
const
  IPPROTO_IP = 0;
  IPPROTO_TCP = 6;
  IPPROTO_UDP = 17;
  IPPROTO_IPV6 = 41;
  INADDR_ANY = cuint32(0);
  INADDR_LOOPBACK = cuint32($7F000001);
  INADDR_BROADCAST = cuint32($FFFFFFFF);
function htons(Value: cuint16): cuint16; cdecl; external 'c';
function ntohs(Value: cuint16): cuint16; cdecl; external 'c';
function htonl(Value: cuint32): cuint32; cdecl; external 'c';
function ntohl(Value: cuint32): cuint32; cdecl; external 'c';
implementation

end.
