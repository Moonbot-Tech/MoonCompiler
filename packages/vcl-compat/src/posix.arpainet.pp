{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.ArpaInet;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, Posix.SysTypes, Posix.NetinetIn;
function inet_pton(Family: cint; Text: PAnsiChar; Address: Pointer): cint; cdecl; external 'c';
function inet_ntop(Family: cint; Address: Pointer; Buffer: PAnsiChar; Capacity: socklen_t): PAnsiChar; cdecl; external 'c';
function inet_addr(Text: PAnsiChar): cuint32; cdecl; external 'c';
implementation

end.
