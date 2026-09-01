program rtl_api_fphttp_overload_response;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  SysUtils,
  Classes,
  ctypes,
  sockets,
  ssockets,
  fphttpserver;

const
  ExpectedResponse: RawByteString =
    'HTTP/1.1 503 Service Unavailable'#13#10+
    'Content-Type: text/plain'#13#10+
    'Retry-After: 30'#13#10+
    'Connection: close'#13#10#13#10+
    'Server is temporarily overloaded. Please try again shortly.';

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

type
  TTestHTTPServer = class(TFPHTTPServer)
  public
    property Active;
    property ConnectionCount;
    property MaxLiveConnectionCount;
  end;

  TServerThread = class(TThread)
  private
    FServer: TTestHTTPServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AServer: TTestHTTPServer);
  end;

constructor TServerThread.Create(AServer: TTestHTTPServer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FServer := AServer;
end;

procedure TServerThread.Execute;
begin
  FServer.Active := True;
end;

function ConnectToPort(APort: Word): cint;
var
  Address: TInetSockAddr;
  Attempt: Integer;
begin
  FillChar(Address, SizeOf(Address), 0);
  Address.sin_family := AF_INET;
  Address.sin_addr := StrToNetAddr('127.0.0.1');
  Address.sin_port := HToNs(APort);
  for Attempt := 1 to 100 do begin
    Result := fpSocket(AF_INET, SOCK_STREAM, 0);
    Check(Result >= 0, 'client-socket');
    If fpConnect(Result, @Address, SizeOf(Address)) = 0 then
      Exit;
    CloseSocket(Result);
    Sleep(10);
  end;
  Check(False, 'connect');
  Result := -1;
end;

function ReservePort: Word;
var
  Address: TInetSockAddr;
  AddressLength: TSockLen;
  Socket: cint;
begin
  Socket := fpSocket(AF_INET, SOCK_STREAM, 0);
  Check(Socket >= 0, 'reserve-socket');
  try
    FillChar(Address, SizeOf(Address), 0);
    Address.sin_family := AF_INET;
    Address.sin_addr := StrToNetAddr('127.0.0.1');
    Address.sin_port := 0;
    Check(fpBind(Socket, @Address, SizeOf(Address)) = 0, 'reserve-bind');
    AddressLength := SizeOf(Address);
    Check(fpGetSockName(Socket, @Address, @AddressLength) = 0,
      'reserve-getsockname');
    Result := NToHs(Address.sin_port);
  finally
    CloseSocket(Socket);
  end;
end;

var
  Buffer: array[0..511] of Byte;
  FirstSocket: cint;
  I: Integer;
  Port: Word;
  Received: LongInt;
  Response: RawByteString;
  SecondSocket: cint;
  Server: TTestHTTPServer;
  ServerThread: TServerThread;
  Stream: TSocketStream;

begin
  FirstSocket := -1;
  SecondSocket := -1;
  Server := nil;
  ServerThread := nil;
  Stream := nil;
  try
    Port := ReservePort;
    Server := TTestHTTPServer.Create(nil);
    Server.Address := '127.0.0.1';
    Server.Port := Port;
    Server.ThreadMode := tmThread;
    Server.AcceptIdleTimeout := 10;
    Server.MaxLiveConnectionCount := 1;
    ServerThread := TServerThread.Create(Server);
    ServerThread.Start;

    FirstSocket := ConnectToPort(Port);
    for I := 1 to 100 do begin
      If Server.ConnectionCount = 1 then
        Break;
      Sleep(10);
    end;
    Check(Server.ConnectionCount = 1, 'first-connection-active');

    SecondSocket := ConnectToPort(Port);
    Stream := TSocketStream.Create(SecondSocket, nil);
    SecondSocket := -1;
    Response := '';
    while Length(Response) < Length(ExpectedResponse) do begin
      Check(Stream.CanRead(2000), 'response-timeout');
      Received := Stream.Read(Buffer[0], SizeOf(Buffer));
      Check(Received > 0, 'response-closed');
      I := Length(Response);
      SetLength(Response, I + Received);
      Move(Buffer[0], Response[I + 1], Received);
    end;
    Check(Length(Response) = Length(ExpectedResponse), 'response-length');
    Check(Response = ExpectedResponse, 'response-ascii');
  finally
    Stream.Free;
    if SecondSocket >= 0 then
      CloseSocket(SecondSocket);
    if FirstSocket >= 0 then
      CloseSocket(FirstSocket);
    if (Server <> nil) and (ServerThread <> nil) then begin
      Server.Active := False;
      ServerThread.WaitFor;
    end;
    ServerThread.Free;
    Server.Free;
  end;

  WriteLn('RTL_API_FPHTTP_OVERLOAD_RESPONSE_OK');
end.
