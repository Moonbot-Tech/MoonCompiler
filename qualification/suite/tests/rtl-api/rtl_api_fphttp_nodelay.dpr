program rtl_api_fphttp_nodelay;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  SysUtils,
  ctypes,
  sockets,
  ssockets,
  fphttpserver;

type
  TProbeConnection = class(TFPHTTPConnection)
  public
    procedure ApplySocketSetup;
  end;

procedure TProbeConnection.ApplySocketSetup;
begin
  SetupSocket;
end;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

var
  AcceptedSocket: cint;
  Address: TInetSockAddr;
  AddressLength: TSockLen;
  ClientSocket: cint;
  Connection: TProbeConnection;
  ListenSocket: cint;
  NoDelay: LongInt;
  NoDelayLength: TSockLen;
  Server: TFPHTTPServer;
  Stream: TSocketStream;

begin
  ListenSocket := -1;
  ClientSocket := -1;
  AcceptedSocket := -1;
  Connection := nil;
  Server := nil;
  Stream := nil;
  try
    ListenSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    Check(ListenSocket >= 0, 'listen-socket');

    FillChar(Address, SizeOf(Address), 0);
    Address.sin_family := AF_INET;
    Address.sin_addr := StrToNetAddr('127.0.0.1');
    Address.sin_port := 0;
    Check(fpBind(ListenSocket, @Address, SizeOf(Address)) = 0, 'bind');
    Check(fpListen(ListenSocket, 1) = 0, 'listen');

    AddressLength := SizeOf(Address);
    Check(fpGetSockName(ListenSocket, @Address, @AddressLength) = 0,
      'getsockname');

    ClientSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    Check(ClientSocket >= 0, 'client-socket');
    Check(fpConnect(ClientSocket, @Address, SizeOf(Address)) = 0, 'connect');

    AddressLength := SizeOf(Address);
    AcceptedSocket := fpAccept(ListenSocket, @Address, @AddressLength);
    Check(AcceptedSocket >= 0, 'accept');

    Server := TFPHTTPServer.Create(nil);
    Server.KeepConnections := True;
    Stream := TSocketStream.Create(AcceptedSocket);
    AcceptedSocket := -1;
    Connection := TProbeConnection.Create(Server, Stream);
    Stream := nil;
    Connection.ApplySocketSetup;

    NoDelay := 0;
    NoDelayLength := SizeOf(NoDelay);
    Check(fpGetSockOpt(Connection.Socket.Handle, IPPROTO_TCP, TCP_NODELAY,
      @NoDelay, @NoDelayLength) = 0, 'getsockopt');
    Check(NoDelay = 1, 'tcp-nodelay');
  finally
    Connection.Free;
    Stream.Free;
    Server.Free;
    if AcceptedSocket >= 0 then
      CloseSocket(AcceptedSocket);
    if ClientSocket >= 0 then
      CloseSocket(ClientSocket);
    if ListenSocket >= 0 then
      CloseSocket(ListenSocket);
  end;

  WriteLn('RTL_API_FPHTTP_NODELAY_OK');
end.
