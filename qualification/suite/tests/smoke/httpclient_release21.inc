type
  TRelease21Events = class
    Done: TMultiWaitEvent;
    CallbackBody: string;
    LastSent, SendTotal: Int64;
    SendCalls: Integer;
    StopUpload: Boolean;
    AuthCalls: Integer;
    AbortAuthentication: Boolean;
    procedure Authenticate(const Sender: TObject; Target: TAuthTargetType; const Realm, URL: string;
      var UserName, Password: string; var AbortAuth: Boolean; var Persistence: TAuthPersistenceType);
    procedure Complete(const Value: Types.IAsyncResult);
    procedure Send(const Sender: TObject; Total, Sent: Int64; var Stop: Boolean);
  end;

procedure TRelease21Events.Authenticate(const Sender: TObject; Target: TAuthTargetType; const Realm, URL: string;
  var UserName, Password: string; var AbortAuth: Boolean; var Persistence: TAuthPersistenceType);
begin
  Inc(AuthCalls);
  Check((Target = TAuthTargetType.Server) and (Realm = 'realm21'), 'authentication challenge identity');
  UserName := 'user21';
  Password := 'pass21';
  AbortAuth := AbortAuthentication;
  Persistence := TAuthPersistenceType.Client;
end;

procedure TRelease21Events.Complete(const Value: Types.IAsyncResult);
begin
  CallbackBody := THTTPClient.EndAsyncHTTP(Value).ContentAsString;
  Done.SetEvent;
end;

procedure TRelease21Events.Send(const Sender: TObject; Total, Sent: Int64; var Stop: Boolean);
begin
  Check((SendCalls = 0) or (Sent >= LastSent), 'upload progress monotonic');
  If SendCalls = 0 then
    Check(Sent = 0, 'upload initial progress');
  LastSent := Sent;
  SendTotal := Total;
  Inc(SendCalls);
  Stop := StopUpload and (Sent >= 65536);
end;

var
  ResolverEntered, ResolverRelease: TMultiWaitEvent;
  ResolverCalls, ResolversRunning: Longint;

function HeldResolver(const Host: RawUtf8; out IP: Cardinal): Boolean;
begin
  If Pos('moon-held-', string(Host)) <> 1 then
    Exit(False);
  InterlockedIncrement(ResolverCalls);
  InterlockedIncrement(ResolversRunning);
  try
    ResolverEntered.SetEvent;
    ResolverRelease.WaitFor(5000);
    IP := $0100007F;
    Result := True;
  finally
    InterlockedDecrement(ResolversRunning);
  end;
end;

procedure CancelOpening;
var
  C: THTTPClient;
  Async: Types.IAsyncResult;
  OldResolver: function(const Host: RawUtf8; out IP: Cardinal): Boolean;
  Started: UInt64;
  I: Integer;
  R: IHTTPResponse;
begin
  C := THTTPClient.Create;
  ResolverEntered := TMultiWaitEvent.Create;
  ResolverRelease := TMultiWaitEvent.Create;
  OldResolver := NewSocketIP4Lookup;
  NewSocketIP4Lookup := HeldResolver;
  try
    C.ConnectionTimeout := 150;
    for I := 1 to 10 do begin
      ResolverEntered.ResetEvent;
      Async := C.BeginGet('http://moon-held-' + IntToStr(I) + '.invalid:80/echo');
      If I <= 8 then
        Check(ResolverEntered.WaitFor(1000) = wrSignaled, 'resolver entered');
      Started := SysUtils.GetTickCount64;
      Async.Cancel;
      Async := nil;
      Check(SysUtils.GetTickCount64 - Started < 700, 'DNS cancellation does not join system resolver');
    end;
    Check(ResolverCalls = 8, 'blocked DNS work bounded to eight independent providers');
    Started := SysUtils.GetTickCount64;
    try
      R := C.Get('http://moon-held-deadline.invalid:80/echo');
      Check(False, 'resolver queue deadline ignored');
    except
      on ENetHTTPClientException do ;
    end;
    Check(SysUtils.GetTickCount64 - Started < 700, 'deadline covers resolver saturation');
  finally
    ResolverRelease.SetEvent;
    Started := SysUtils.GetTickCount64;
    while (InterlockedCompareExchange(ResolversRunning, 0, 0) <> 0) and
      (SysUtils.GetTickCount64 - Started < 3000) do
      Sleep(1);
    Check(ResolversRunning = 0, 'resolver fixtures released');
    NewSocketIP4Lookup := OldResolver;
    ResolverEntered.Free;
    ResolverRelease.Free;
    C.Free;
  end;
  If ParamCount < 6 then
    raise Exception.Create('Held TLS fixture port is required');
  C := THTTPClient.Create;
  try
    C.ConnectionTimeout := 150;
    Started := SysUtils.GetTickCount64;
    try
      R := C.Get('https://127.0.0.1:' + ParamStr(6) + '/held');
      Check(False, 'TLS handshake deadline ignored');
    except
      on ENetHTTPClientException do ;
    end;
    Check(SysUtils.GetTickCount64 - Started < 700, 'TLS deadline ends the worker');
    C.ConnectionTimeout := 10000;
    Async := C.BeginGet('https://127.0.0.1:' + ParamStr(6) + '/held');
    Sleep(100);
    Started := SysUtils.GetTickCount64;
    Async.Cancel;
    Async := nil;
    Check(SysUtils.GetTickCount64 - Started < 700, 'TLS cancellation ends the worker');
  finally
    C.Free;
  end;
end;

procedure Release21Contracts;
var
  C: THTTPClient;
  Generic: TURLClient;
  R: IHTTPResponse;
  U: IURLResponse;
  Request: IURLRequest;
  Async: Types.IAsyncResult;
  Events: TRelease21Events;
  Form: TMultipartFormData;
  Strings: TStringList;
  Source: TStringStream;
  Callback: TAsyncCallback;
  FileName, Text: string;
  Bytes: TBytes;
  Proxy: TProxySettings;
  I: Integer;
begin
  C := THTTPClient.Create;
  Events := TRelease21Events.Create;
  Events.Done := TMultiWaitEvent.Create;
  Form := TMultipartFormData.Create;
  Strings := TStringList.Create;
  Source := TStringStream.Create('payload21', TEncoding.UTF8);
  FileName := GetTempDir(False) + 'http21-' + IntToStr(GetProcessID) + '.dat';
  try
    R := C.Get(Base + '/meta21');
    U := R;
    Check((U.MimeType = 'text/plain') and (R.ContentCharSet = 'utf-8') and
      (R.ContentLength = 4) and (R.ContentLanguage = 'en'), 'response metadata');
    Check((R.Version = THTTPProtocolVersion.HTTP_1_1) and R.ContainsHeader('date') and
      not R.ContainsHeader('missing') and (R.LastModified = 'Sun, 04 Oct 2026 12:00:00 GMT'), 'response headers/version');
    Check(U.AsyncResult.IsCompleted and U.AsyncResult.CompletedSynchronously, 'synchronous completion object');
    C.AuthEvent := Events.Authenticate;
    Async := C.BeginGet(Base + '/auth21');
    R := THTTPClient.EndAsyncHTTP(Async);
    Async := nil;
    Check((R.StatusCode = 200) and (R.ContentAsString = 'authenticated'), 'async authentication callback');
    R := C.Get(Base + '/auth21');
    Check((R.StatusCode = 200) and (Events.AuthCalls = 1), 'client persistence shared with async clone');
    C.CredentialsStorage.ClearCredentials;
    Events.AbortAuthentication := True;
    R := C.Get(Base + '/auth21');
    Check((R.StatusCode = 401) and (Events.AuthCalls = 2), 'authentication abort returns challenge');
    C.AuthEvent := nil;
    C.CredentialsStorage.AddCredential(TCredentialsStorage.TCredential.Create(TAuthTargetType.Server,
      'realm21', Base + '/auth21', 'wrong', 'password'));
    R := C.Get(Base + '/auth21');
    Check(R.StatusCode = 401, 'wrong credentials terminate after one authenticated retry');
    C.CredentialsStorage.ClearCredentials;
    Strings.Add('text=Привет & мир');
    R := C.Put(Base + '/echo21', Strings);
    Check(HasLine(Body(R), 'PUT /echo21') and (Pos('text=', Body(R)) > 0), 'Put form overload');
    Source.SaveToFile(FileName);
    R := C.Post(Base + '/echo21', FileName);
    Check(HasLine(Body(R), 'BODY=payload21'), 'Post filename overload');
    R := C.Put(Base + '/echo21', FileName);
    Check(HasLine(Body(R), 'BODY=payload21'), 'Put filename overload');
    Form.AddField('caption', 'Фото → тест');
    SetLength(Bytes, 70000);
    Form.AddBytes('photo', Bytes, 'photo.dat', 'image/x-test');
    C.ContentType := 'application/saved';
    R := C.Post(Base + '/upload21', Form);
    Check((R.StatusCode = 200) and (C.ContentType = 'application/saved'), 'multipart Post does not mutate settings');
    R := C.Put(Base + '/upload21', Form);
    Check((R.StatusCode = 200) and (C.ContentType = 'application/saved'), 'multipart Put replay');
    Async := C.BeginPut(Events.Complete, Base + '/echo21', Strings);
    Check(Events.Done.WaitFor(3000) = wrSignaled, 'HTTP event callback can EndAsync');
    Check(Pos('PUT /echo21', Events.CallbackBody) > 0, 'async form body');
    Check((Async.AsyncContext = C) and not Async.CompletedSynchronously, 'HTTP shared async identity/context');
    R := THTTPClient.EndAsyncHTTP(Async);
    Async := nil;
    Check(R.AsyncResult.IsCompleted, 'HTTP response retains async state without cycle');
    Events.Done.ResetEvent;
    Callback := procedure(const Value: Types.IAsyncResult)
      begin
        Events.CallbackBody := THTTPClient.EndAsyncHTTP(Value).ContentAsString;
        Events.Done.SetEvent;
      end;
    Async := C.BeginPost(Callback, Base + '/echo21', FileName);
    Check(Events.Done.WaitFor(3000) = wrSignaled, 'HTTP anonymous callback');
    Check(Pos('BODY=payload21', Events.CallbackBody) > 0, 'async owned file');
    Async := nil;
    Callback := nil;
    Async := C.BeginPost(Base + '/upload21', Form);
    Check(THTTPClient.EndAsyncHTTP(Async).StatusCode = 200, 'async multipart');
    Async := C.BeginHead(Base + '/echo21');
    Check(THTTPClient.EndAsyncHTTP(Async).ContentStream.Size = 0, 'BeginHead');
    Async := C.BeginDelete(Base + '/echo21');
    Check(HasLine(THTTPClient.EndAsyncHTTP(Async).ContentAsString, 'DELETE /echo21'), 'BeginDelete');
    Source.Position := 0;
    Async := C.BeginPatch(Base + '/echo21', Source);
    Check(HasLine(THTTPClient.EndAsyncHTTP(Async).ContentAsString, 'BODY=payload21'), 'BeginPatch body');
    Async := nil;
    R := nil;
    C.CookieManager.AddServerCookie('root=r; Path=/', 'https://example.com/root');
    C.CookieManager.AddServerCookie('root=p; Path=/scope', 'https://example.com/root');
    C.CookieManager.AddServerCookie('shared=s; Domain=example.com; Path=/', 'https://example.com/root');
    C.CookieManager.AddServerCookie('secret=s; Secure; Path=/', 'https://example.com/root');
    C.CookieManager.AddServerCookie('wrong=x; Domain=other.com', 'https://example.com/root');
    Text := C.CookieManager.CookieHeader('https://example.com/scope/x');
    Check(Pos('root=p; root=r', Text) = 1, 'same-name cookies ordered by path');
    Check(Pos('wrong=', Text) = 0, 'foreign domain rejected');
    Text := C.CookieManager.CookieHeader('http://example.com/scoped');
    Check((Pos('root=p', Text) = 0) and (Pos('secret=', Text) = 0), 'path boundary and Secure');
    Check(C.CookieManager.CookieHeader('https://child.example.com/') = 'shared=s', 'host-only and domain cookies');
    C.CookieManager.AddServerCookie('root=gone; Path=/; Max-Age=0', 'https://example.com/root');
    Check(Pos('root=r', C.CookieManager.CookieHeader('https://example.com/')) = 0, 'Max-Age deletion');
    Async := C.BeginGet(Base + '/cookies/set');
    R := THTTPClient.EndAsyncHTTP(Async);
    Check(R.Cookies.Count = 2, 'response Cookies');
    R := C.Get(Base + '/cookies/show');
    Check(Pos('sid=abc', Body(R)) > 0, 'async and sync share a cookie jar');
    Async := nil;
    C.OnSendData := Events.Send;
    Source.Size := 200000;
    Source.Position := 0;
    R := C.Post(Base + '/digest', Source);
    Check((Events.SendCalls >= 4) and (Events.LastSent = 200000) and
      (Events.SendTotal = 200000), 'upload reports bytes after send');
    Events.StopUpload := True;
    Events.SendCalls := 0;
    Source.Position := 0;
    try
      R := C.Post(Base + '/digest', Source);
      Check(False, 'upload event cancellation ignored');
    except
      on ENetHTTPClientException do ;
    end;
    C.OnSendData := nil;
    Proxy := TProxySettings.Create(Base);
    Proxy.UserName := 'proxyuser';
    Proxy.Password := 'proxypass';
    C.ProxySettings := Proxy;
    R := C.Get('http://unresolvable.invalid/echo21');
    Check(HasLine(Body(R), 'GET /echo21') and
      HasLine(Body(R), 'H:proxy-authorization=Basic cHJveHl1c2VyOnByb3h5cGFzcw=='), 'HTTP proxy and credentials');
    Request := C.GetRequest('GET', 'http://unresolvable.invalid/echo21');
    Request.Credential := TCredentialsStorage.TCredential.Create(TAuthTargetType.Proxy, '', '', 'user21', 'pass21');
    U := C.Execute(Request);
    Text := U.ContentAsString;
    Check((Pos('H:authorization=', Text) = 0) and
      HasLine(Text, 'H:proxy-authorization=Basic dXNlcjIxOnBhc3MyMQ=='), 'proxy request credentials never become origin credentials');
    If TlsTrusted then begin
      R := C.Get(TlsBase + '/echo21');
      Check((R.StatusCode = 200) and (Pos('H:proxy-authorization=', Body(R)) = 0), 'HTTPS CONNECT does not expose proxy credentials to origin');
    end;
    Generic := TURLClient.Create;
    try
      U := Generic.Execute('GET', TURI.Create(Base + '/cookies/set'));
      U := Generic.Execute('GET', Base + '/cookies/show');
      Check(Pos('sid=abc', U.ContentAsString) > 0, 'base URL client retains session');
      Async := Generic.BeginExecute('GET', Base + '/cookies/show');
      Check(Pos('sid=abc', TURLClient.EndAsyncURL(Async).ContentAsString) > 0, 'base async shares transport session');
      Async := nil;
    finally
      Generic.Free;
    end;
  finally
    Async := nil;
    R := nil;
    U := nil;
    Source.Free;
    Strings.Free;
    Form.Free;
    Events.Done.Free;
    Events.Free;
    C.Free;
    DeleteFile(FileName);
  end;
  CancelOpening;
end;
