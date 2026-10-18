program socket_connect_native_immediate;

uses System.SysUtils, mormot.core.base, mormot.net.sock;

type
{$IFDEF MSWINDOWS}
  TNativeSocket = NativeUInt;
{$ELSE}
  TNativeSocket = Integer;
{$ENDIF}
  TNativeIPv6 = record
    Family, Port: Word;
    FlowInfo: Cardinal;
    Address: array[0..15] of Byte;
    ScopeId: Cardinal;
  end;

{$IFDEF MSWINDOWS}
function NativeConnect(Socket: TNativeSocket; Address: Pointer; Size: Integer): Integer; stdcall;
  external 'ws2_32.dll' name 'connect';
function NativeSocketOption(Socket: TNativeSocket; Level, Option: Integer; Value: Pointer; var Size: Integer): Integer; stdcall;
  external 'ws2_32.dll' name 'getsockopt';
const
  NativeIPv6Family = 23;
  NativeUnsupportedFamily = 10047;
  NativeSocketLevel = $FFFF;
  NativeSocketError = $1007;
{$ELSE}
function NativeConnect(Socket: TNativeSocket; Address: Pointer; Size: Integer): Integer; cdecl;
  external 'c' name 'connect';
function NativeSocketOption(Socket: TNativeSocket; Level, Option: Integer; Value: Pointer; var Size: Integer): Integer; cdecl;
  external 'c' name 'getsockopt';
const
  NativeIPv6Family = 10;
  NativeUnsupportedFamily = 97;
  NativeSocketLevel = 1;
  NativeSocketError = 4;
{$ENDIF}

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;

var
  IPv4, IPv6: TNetAddr;
  Socket: TNetSocket;
  RawAddress: TNativeIPv6;
  NativeResult, NativeError, SocketError, Size: Integer;
  Code: TNetResult;
const
  Timeouts: array[0..1] of Integer = (-1, 1000);
begin
  Check(IPv4.SetIP4Port(cLocalhost32, 1) = nrOK, 'IPv4 address');
  RawAddress := Default(TNativeIPv6);
  RawAddress.Family := NativeIPv6Family;
  RawAddress.Port := $0100;
  RawAddress.Address[0] := $20;
  RawAddress.Address[1] := $01;
  RawAddress.Address[2] := $0D;
  RawAddress.Address[3] := $B8;
  RawAddress.Address[15] := 1;
  { TNetAddr's only field is its opaque native sockaddr buffer. Construct these bytes
    directly so an IPv6-disabled host's resolver cannot prevent the connect test. }
  IPv6 := Default(TNetAddr);
  Check(SizeOf(IPv6) >= SizeOf(RawAddress), 'native address storage');
  Move(RawAddress, IPv6, SizeOf(RawAddress));
  Check(IPv6.Size = SizeOf(RawAddress), 'native IPv6 address layout');
  Socket := IPv4.NewSocket(nlTcp);
  Check(Socket <> nil, 'native oracle socket');
  try
    Check(Socket.MakeAsync = nrOK, 'native oracle nonblocking mode');
    NativeResult := NativeConnect(Socket.Socket, @RawAddress, SizeOf(RawAddress));
    NativeError := RawSocketErrNo;
    Check((NativeResult <> 0) and (NativeError = NativeUnsupportedFamily), 'native connect refuses mismatched family immediately');
    SocketError := -1;
    Size := SizeOf(SocketError);
    Check(NativeSocketOption(Socket.Socket, NativeSocketLevel, NativeSocketError, @SocketError, Size) = 0, 'native SO_ERROR oracle');
    Writeln('NATIVE_IMMEDIATE=', NativeError, ' SO_ERROR=', SocketError);
    Check(SocketError = 0, 'SO_ERROR cannot recover this immediate failure');
  finally
    Socket.Close;
  end;
  for var Ms in Timeouts do begin
    Socket := IPv4.NewSocket(nlTcp);
    Check(Socket <> nil, 'wrapper socket');
    try
      Code := IPv6.SocketConnect(Socket, Ms);
      NativeError := RawSocketErrNo;
      Writeln('WRAPPER ms=', Ms, ' result=', Ord(Code), ' native=', NativeError,
        ' family=', Ord(IPv6.Family), ' address=', Utf8ToString(IPv6.IP));
      Check(Code = nrFatalError, 'SocketConnect must return the immediate native failure');
      Check(NativeError = NativeUnsupportedFamily, 'SocketConnect preserves immediate native errno');
    finally
      Socket.Close;
    end;
  end;
  Writeln('SOCKET_CONNECT_NATIVE_IMMEDIATE_PASS');
end.
