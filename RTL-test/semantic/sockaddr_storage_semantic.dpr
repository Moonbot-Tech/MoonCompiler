program sockaddr_storage_semantic;

{$mode delphi}{$H+}

{ Sockets.sockaddr_storage / socklen_t (planning contract 2.5): 128 bytes,
  aligned for sockaddr_in6, usable as the peer buffer of fprecvfrom for either
  family and read back through ss_family. }

uses
  SysUtils,
  Sockets;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

{ one datagram over the loopback of the given family into a storage buffer }
procedure RoundTrip(Family: Integer);
var
  Sender, Receiver: Integer;
  Addr4: TInetSockAddr;
  Addr6: TInetSockAddr6;
  Bound: sockaddr_storage;
  BoundLen: socklen_t;
  From: TSockAddrStorage;
  FromLen: socklen_t;
  Sent, Got: Integer;
  Payload, Buffer: array[0..15] of Byte;
  I: Integer;
  BoundPort, FromPort: Word;
begin
  Receiver := fpsocket(Family, SOCK_DGRAM, 0);
  If Receiver < 0 then begin
    WriteLn('family ', Family, ' not available, skipped');
    Exit;
  end;
  Sender := fpsocket(Family, SOCK_DGRAM, 0);
  Check(Sender >= 0, 'sender socket');
  try
    { bind the receiver to an ephemeral loopback port }
    If Family = AF_INET then begin
      FillChar(Addr4, SizeOf(Addr4), 0);
      Addr4.sin_family := AF_INET;
      Addr4.sin_addr.s_bytes[1] := 127;
      Addr4.sin_addr.s_bytes[4] := 1;
      If fpbind(Receiver, @Addr4, SizeOf(Addr4)) <> 0 then begin
        WriteLn('IPv4 loopback bind failed, skipped');
        Exit;
      end;
    end else begin
      FillChar(Addr6, SizeOf(Addr6), 0);
      Addr6.sin6_family := AF_INET6;
      Addr6.sin6_addr.u6_addr8[15] := 1;
      If fpbind(Receiver, @Addr6, SizeOf(Addr6)) <> 0 then begin
        WriteLn('IPv6 loopback bind failed, skipped');
        Exit;
      end;
    end;
    { the bound address comes back through the storage too }
    FillChar(Bound, SizeOf(Bound), 0);
    BoundLen := SizeOf(Bound);
    Check(fpgetsockname(Receiver, @Bound, @BoundLen) = 0, 'getsockname into storage');
    Check(Bound.ss_family = Family, 'bound family through ss_family');
    If Family = AF_INET then begin
      Check(BoundLen = SizeOf(TInetSockAddr), 'IPv4 length');
      BoundPort := PInetSockAddr(@Bound)^.sin_port;
    end else begin
      Check(BoundLen = SizeOf(TInetSockAddr6), 'IPv6 length');
      BoundPort := PInetSockAddr6(@Bound)^.sin6_port;
    end;
    Check(BoundPort <> 0, 'a port was assigned');
    for I := 0 to High(Payload) do
      Payload[I] := Byte(I * 5 + Family);
    Sent := fpsendto(Sender, @Payload, SizeOf(Payload), 0, psockaddr(@Bound), BoundLen);
    Check(Sent = SizeOf(Payload), 'sendto through the storage address: ' + IntToStr(Sent));
    FillChar(From, SizeOf(From), $AA);
    FromLen := SizeOf(From);
    Got := fprecvfrom(Receiver, @Buffer, SizeOf(Buffer), 0, psockaddr(@From), @FromLen);
    Check(Got = SizeOf(Payload), 'recvfrom into storage: ' + IntToStr(Got));
    Check(CompareMem(@Payload, @Buffer, SizeOf(Payload)), 'payload intact');
    Check(From.ss_family = Family, 'peer family through ss_family');
    If Family = AF_INET then begin
      Check(FromLen = SizeOf(TInetSockAddr), 'peer IPv4 length');
      FromPort := PInetSockAddr(@From)^.sin_port;
      Check(PInetSockAddr(@From)^.sin_addr.s_bytes[1] = 127, 'peer is loopback');
    end else begin
      Check(FromLen = SizeOf(TInetSockAddr6), 'peer IPv6 length');
      FromPort := PInetSockAddr6(@From)^.sin6_port;
      Check(PInetSockAddr6(@From)^.sin6_addr.u6_addr8[15] = 1, 'peer is ::1');
    end;
    Check(FromPort <> 0, 'peer port present');
  finally
    CloseSocket(Sender);
    CloseSocket(Receiver);
  end;
end;

var
  Storage: sockaddr_storage;
begin
  Failures := 0;
  Check(SizeOf(sockaddr_storage) = 128, 'SizeOf(sockaddr_storage) = 128: ' + IntToStr(SizeOf(sockaddr_storage)));
  Check(SizeOf(TSockAddrStorage) = 128, 'alias TSockAddrStorage');
  Check(SizeOf(sockaddr_in6) <= SizeOf(sockaddr_storage), 'sockaddr_in6 fits');
  Check(SizeOf(sockaddr_un) <= SizeOf(sockaddr_storage), 'sockaddr_un fits');
  Check(PtrUInt(@Storage) mod 8 = 0, 'storage is 8-byte aligned');
  Check(PtrUInt(@Storage.ss_family) = PtrUInt(@Storage), 'ss_family is the first field');
  Check(SizeOf(socklen_t) = SizeOf(TSockLen), 'socklen_t is TSockLen');
  RoundTrip(AF_INET);
  RoundTrip(AF_INET6);
  If Failures <> 0 then
    Halt(1);
  WriteLn('SOCKADDR_STORAGE_PASS');
end.
