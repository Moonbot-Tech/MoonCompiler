{ A system resolver may block inside an OS provider. It owns only its copied
  name and result and is bounded by MaxResolvers. No request/client/stream is
  retained by a resolver, and it never opens a connection after cancellation. }
const
  MaxResolvers = 8;
var
  ActiveResolvers: Longint;
type
  TResolveState = class(TInterfacedObject)
    Host, Port: RawUtf8;
    Address: TNetAddr;
    Error: TNetResult;
    Done: TMultiWaitEvent;
    constructor Create(const AHost, APort: RawUtf8);
    destructor Destroy; override;
  end;
  TResolveWorker = class(TThread)
  private
    FState: TResolveState;
  protected
    procedure Execute; override;
  public
    constructor Create(State: TResolveState);
    destructor Destroy; override;
  end;
  TRequestWatch = class(TThread)
  private
    FClient: THTTPClient;
    FStop: TMultiWaitEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(Client: THTTPClient);
    destructor Destroy; override;
  end;

{$ifdef WINDOWS}
function ShutdownSocket(Socket: NativeUInt; How: Integer): Integer; stdcall; external 'ws2_32.dll' name 'shutdown';
{$else}
function ShutdownSocket(Socket: Integer; How: Integer): Integer; cdecl; external 'c' name 'shutdown';
{$endif}

procedure TMoonHttpSocket.Abort;
begin
  fAborted := True;
  { Only the I/O owner closes the descriptor. A close from a cancelling thread
    could let another connection reuse the number before the old I/O unwinds. }
  If FCancelSocket <> nil then
    ShutdownSocket(FCancelSocket.Socket, 2);
end;

procedure TMoonHttpSocket.Close;
begin
  { TLS cleanup may write. Keep its live descriptor available to cancellation. }
  fSecure := nil;
  { The backend also closes on Connection: close and I/O errors. Withdraw the
    cancellation handle before close can recycle its descriptor; TLS cleanup
    stays outside the guard. Abort is always called under this same guard. }
  If FCancelGuard <> nil then begin
    FCancelGuard.Acquire;
    try
      FCancelSocket := nil;
    finally
      FCancelGuard.Release;
    end;
  end;
  inherited Close;
end;

constructor TResolveState.Create(const AHost, APort: RawUtf8);
begin
  inherited Create;
  Host := AHost;
  Port := APort;
  Error := nrNotFound;
  Done := TMultiWaitEvent.Create;
end;

destructor TResolveState.Destroy;
begin
  Done.Free;
  inherited Destroy;
end;

constructor TResolveWorker.Create(State: TResolveState);
begin
  inherited Create(True);
  FState := State;
  FState._AddRef;
  FreeOnTerminate := True;
end;

destructor TResolveWorker.Destroy;
begin
  inherited Destroy;
  If FState <> nil then
    FState._Release;
end;

procedure TResolveWorker.Execute;
begin
  try
    If not Terminated then
      FState.Error := FState.Address.SetFrom(FState.Host, FState.Port, nlTcp);
  finally
    InterlockedDecrement(ActiveResolvers);
    FState.Done.SetEvent;
  end;
end;

function ResolveForRequest(const Host, Port: RawUtf8; Client: THTTPClient): TNetAddr;
var
  State: TResolveState;
  Worker: TResolveWorker;
  AddressOnly: Boolean;
  I: Integer;
begin
  Client.CheckRequest;
  { Literal addresses have no blocking provider stage. IPv6 and names use the
    same system resolver as the existing backend, including local/NSS names. }
  AddressOnly := Host <> '';
  for I := 1 to Length(Host) do
    If not (Host[I] in ['0'..'9', '.']) then begin
      AddressOnly := False;
      Break;
    end;
  If AddressOnly then begin
    If Result.SetFrom(Host, Port, nlTcp) <> nrOK then
      raise ENetHTTPClientException.Create('Invalid numeric socket address');
    Exit;
  end;
  State := TResolveState.Create(Host, Port);
  State._AddRef;
  try
    repeat
      Client.CheckRequest;
      If InterlockedIncrement(ActiveResolvers) <= MaxResolvers then
        Break;
      InterlockedDecrement(ActiveResolvers);
      Sleep(10);
    until False;
    try
      Worker := TResolveWorker.Create(State);
    except
      InterlockedDecrement(ActiveResolvers);
      raise;
    end;
    try
      Worker.Start;
    except
      Worker.Free;
      raise;
    end;
    while State.Done.WaitFor(20) <> Types.wrSignaled do
      Client.CheckRequest;
    Client.CheckRequest;
    If State.Error <> nrOK then
      raise ENetHTTPClientException.Create('Cannot resolve host ' + Utf8ToString(Host));
    Result := State.Address;
  finally
    State._Release;
  end;
end;

constructor TRequestWatch.Create(Client: THTTPClient);
begin
  inherited Create(True);
  FClient := Client;
  FStop := TMultiWaitEvent.Create;
  Start;
end;

destructor TRequestWatch.Destroy;
begin
  Terminate;
  If FStop <> nil then
    FStop.SetEvent;
  inherited Destroy;
  FStop.Free;
end;

procedure TRequestWatch.Execute;
begin
  while not Terminated and (FStop.WaitFor(20) <> Types.wrSignaled) do begin
    FClient.FSocketGuard.Acquire;
    try
      If (FClient.FActiveRequest <> nil) and FClient.FActiveRequest.IsCancelled then
        FClient.FAbortRequested := True;
      If (FClient.FConnectionDeadline <> 0) and
        (SysUtils.GetTickCount64 >= FClient.FConnectionDeadline) then begin
        FClient.FConnectionExpired := True;
        FClient.FAbortRequested := True;
      end;
      If FClient.FAbortRequested and (FClient.FSocket <> nil) then
        TMoonHttpSocket(FClient.FSocket).Abort;
    finally
      FClient.FSocketGuard.Release;
    end;
  end;
end;

procedure THTTPClient.CheckRequest;
var
  RequestURL: System.Net.URLClient.TURI;
begin
  FSocketGuard.Acquire;
  try
    If FConnectionExpired or ((FConnectionDeadline <> 0) and
      (SysUtils.GetTickCount64 >= FConnectionDeadline)) then begin
      RequestURL := FActiveRequest.URL;
      RequestURL.UserName := '';
      RequestURL.Password := '';
      raise ENetHTTPClientException.Create('HTTP connection deadline expired for ' + RequestURL.ToString);
    end;
    If FAbortRequested or ((FActiveRequest <> nil) and FActiveRequest.IsCancelled) then
      raise ENetHTTPClientException.Create('HTTP request was cancelled');
  finally
    FSocketGuard.Release;
  end;
end;

procedure TMoonHttpSocket.ConnectCancelable(const URI: TUri;
  const Options: THttpRequestExtendedOptions; Client: THTTPClient);
var
  Target: TUri;
  Address: TNetAddr;
  Socket: TNetSocket;
  Code: TNetResult;
  Line: RawUtf8;
  HeaderCount, ProxyStatus: Integer;
begin
  FCancelGuard := Client.FSocketGuard;
  fExtendedOptions := Options;
  TLS := Options.TLS;
  ResetNetTlsContext(TLS);
  fServer := URI.Server;
  fPort := URI.Port;
  fSocketLayer := nlTcp;
  Target := URI;
  FPlainProxy := False;
  If Options.Proxy <> '' then begin
    If not Tunnel.From(Options.Proxy) or not SameText(Utf8ToString(Tunnel.Scheme), 'http') then
      raise ENetHTTPClientException.Create('The socket transport requires an HTTP proxy');
    Target := Tunnel;
    FPlainProxy := not URI.Https;
    fProxyUrl := Options.Proxy;
  end;
  Address := ResolveForRequest(Target.Server, Target.Port, Client);
  Client.CheckRequest;
  Socket := Address.NewSocket(nlTcp);
  If Socket = nil then
    raise ENetHTTPClientException.Create('Cannot create HTTP socket');
  Client.FSocketGuard.Acquire;
  try
    fSock := Socket;
    FCancelSocket := Socket;
  finally
    Client.FSocketGuard.Release;
  end;
  Client.CheckRequest;
  Code := Address.SocketConnect(Socket, -1);
  If Code <> nrOK then
    raise ENetHTTPClientException.Create('Cannot start HTTP connection');
  repeat
    Client.CheckRequest;
    Code := NetEventsToNetResult(Socket.WaitFor(20, [neWrite, neError]));
  until Code <> nrRetry;
  Client.CheckRequest;
  If Code <> nrOK then
    raise ENetHTTPClientException.Create('HTTP connection failed');
  Socket.MakeBlocking;
  Socket.SetupConnection(nlTcp, Client.FConnectionTimeout, Client.FConnectionTimeout);
  Address.IP(fRemoteIP, True);
  fSocketFamily := Address.Family;
  If (Options.Proxy <> '') and URI.Https then begin
    SockSend(['CONNECT ', HTTPHost(fServer), ':', fPort, ' HTTP/1.1']);
    SockSend(['Host: ', HTTPHost(fServer), ':', fPort]);
    If Tunnel.User <> '' then
      SockSend(['Proxy-Authorization: Basic ', Tunnel.UserPasswordBase64]);
    SockSendFlush(#13#10);
    SockRecvLn(Line);
    If Copy(Line, 1, 5) <> 'HTTP/' then
      raise ENetHTTPClientException.Create('Invalid HTTP proxy response');
    ProxyStatus := StrToIntDef(string(Copy(Line, 10, 3)), 0);
    HeaderCount := 0;
    repeat
      Client.CheckRequest;
      SockRecvLn(Line);
      Inc(HeaderCount);
      If HeaderCount > 1000 then
        raise ENetHTTPClientException.Create('Too many HTTP proxy headers');
    until Line = '';
    If (ProxyStatus < 200) or (ProxyStatus >= 300) then
      raise ENetHTTPClientException.CreateFmt('HTTP proxy rejected CONNECT (%d)', [ProxyStatus]);
  end;
  If URI.Https then
    DoTlsAfter(cstaConnect);
  Client.CheckRequest;
end;
