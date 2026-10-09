constructor TURI.Create(const AURIStr: string);
var
  Parsed: URIParser.TURI;
begin
  Self := Default(TURI);
  try
    Parsed := URIParser.ParseURI(AURIStr, False);
  except
    on EConvertError do
      raise ENetURIException.CreateFailure('Invalid URI port', TNetFailureReason.InvalidParameter);
  end;
  If Parsed.Protocol = '' then
    raise ENetURIException.CreateFailure('A URI requires a scheme', TNetFailureReason.InvalidParameter);
  FScheme := LowerCase(Parsed.Protocol);
  FHost := LowerCase(Parsed.Host);
  FUsername := URLDecode(Parsed.Username);
  FPassword := URLDecode(Parsed.Password);
  FPort := Parsed.Port;
  If FPort = 0 then begin
    If FScheme = 'http' then
      FPort := 80
    else If FScheme = 'https' then
      FPort := 443;
  end;
  { Keep reserved escaped octets intact: /a%2Fb and /a/b are different
    resources. Converting a request through TURI must not change its target. }
  FPath := Parsed.Path + Parsed.Document;
  SetQuery(Parsed.Params);
  FFragment := URLDecode(Parsed.Bookmark);
end;

procedure TURI.ComposeURI(const AScheme, AUsername, APassword, AHostname: string; APort: Integer;
  const APath: string; const AParams: TURIParameters; const AFragment: string);
begin
  Self := Default(TURI);
  FScheme := LowerCase(AScheme);
  FHost := LowerCase(AHostname);
  FUsername := AUsername;
  FPassword := APassword;
  FPort := APort;
  FPath := APath;
  FFragment := AFragment;
  SetParams(AParams);
end;

function EncodeURIComponent(const Value: string; Query: Boolean): string;
const
  Hex = '0123456789ABCDEF';
var
  Bytes: TBytes;
  I: Integer;
  B: Byte;
begin
  Bytes := TEncoding.UTF8.GetBytes(Value);
  Result := '';
  I := 0;
  while I < Length(Bytes) do begin
    B := Bytes[I];
    If (B = Ord('%')) and (I + 2 < Length(Bytes)) and
      (Char(Bytes[I + 1]) in ['0'..'9', 'a'..'f', 'A'..'F']) and
      (Char(Bytes[I + 2]) in ['0'..'9', 'a'..'f', 'A'..'F']) then begin
      Result := Result + '%' + Char(Bytes[I + 1]) + Char(Bytes[I + 2]);
      Inc(I, 3);
      Continue;
    end;
    If (B in [Ord('a')..Ord('z'), Ord('A')..Ord('Z'), Ord('0')..Ord('9'),
      45, 46, 95, 126, 47, 58, 64, 33, 36, 38, 39, 40, 41, 42, 43, 44, 59, 61]) or
      (Query and (B = Ord('?'))) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + Hex[(B shr 4) + 1] + Hex[(B and 15) + 1];
    Inc(I);
  end;
end;

function TURI.ToString: string;
begin
  Result := FScheme + ':';
  If FHost <> '' then begin
    Result := Result + '//';
    If (FUsername <> '') or (FPassword <> '') then begin
      Result := Result + URLEncode(FUsername);
      If FPassword <> '' then
        Result := Result + ':' + URLEncode(FPassword);
      Result := Result + '@';
    end;
    If (Pos(':', FHost) <> 0) and (FHost[1] <> '[') then
      Result := Result + '[' + FHost + ']'
    else
      Result := Result + FHost;
    If (FPort < 0) or (FPort > 65535) then
      raise ENetURIException.CreateFailure('Invalid URI port', TNetFailureReason.InvalidParameter);
    If (FPort <> 0) and not (((FScheme = 'http') and (FPort = 80)) or
      ((FScheme = 'https') and (FPort = 443))) then
      Result := Result + ':' + IntToStr(FPort);
    If (FPath = '') or (FPath[1] <> '/') then
      Result := Result + '/';
  end;
  Result := Result + EncodeURIComponent(FPath, False);
  If FQuery <> '' then
    Result := Result + '?' + EncodeURIComponent(FQuery, True);
  If FFragment <> '' then
    Result := Result + '#' + URLEncode(FFragment);
end;

class operator TURI.Implicit(const Value: TURI): string;
begin
  Result := Value.ToString;
end;

function TURI.Encode: string;
begin
  Result := ToString;
end;

class function TURI.URLEncode(const Value: string; SpacesAsPlus: Boolean): string;
var
  B: Byte;
  Bytes: TBytes;
const
  Hex = '0123456789ABCDEF';
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(Value);
  for B in Bytes do
    If B in [Ord('a')..Ord('z'), Ord('A')..Ord('Z'), Ord('0')..Ord('9'), 45, 46, 95, 126] then
      Result := Result + Char(B)
    else If (B = 32) and SpacesAsPlus then
      Result := Result + '+'
    else
      Result := Result + '%' + Hex[(B shr 4) + 1] + Hex[(B and 15) + 1];
end;

class function TURI.URLDecode(const Value: string; PlusAsSpaces: Boolean): string;
begin
  Result := TURLEncoding.URIDecode(Value, PlusAsSpaces);
end;

procedure TURI.SetQuery(const Value: string);
var
  Start, Stop, Sep, N: Integer;
  Item: string;
begin
  FQuery := Value;
  FParams := nil;
  Start := 1;
  while Start <= Length(Value) do begin
    Stop := Start;
    while (Stop <= Length(Value)) and (Value[Stop] <> '&') do
      Inc(Stop);
    Item := Copy(Value, Start, Stop - Start);
    Sep := Pos('=', Item);
    N := Length(FParams);
    SetLength(FParams, N + 1);
    If Sep = 0 then
      FParams[N] := TURIParameter.Create(URLDecode(Item, True), '')
    else
      FParams[N] := TURIParameter.Create(URLDecode(Copy(Item, 1, Sep - 1), True),
        URLDecode(Copy(Item, Sep + 1, MaxInt), True));
    Start := Stop + 1;
  end;
end;

procedure TURI.SetParams(const Value: TURIParameters);
var
  Param: TURIParameter;
begin
  FParams := Copy(Value);
  FQuery := '';
  for Param in FParams do begin
    If FQuery <> '' then
      FQuery := FQuery + '&';
    FQuery := FQuery + URLEncode(Param.Name) + '=' + URLEncode(Param.Value);
  end;
end;

function TURI.GetParameter(I: Integer): TURIParameter;
begin
  If (I < 0) or (I >= Length(FParams)) then
    raise EArgumentOutOfRangeException.Create('URI parameter index');
  Result := FParams[I];
end;

procedure TURI.SetParameter(I: Integer; const Value: TURIParameter);
begin
  GetParameter(I);
  FParams[I] := Value;
  SetParams(FParams);
end;

function TURI.GetParameterByName(const Name: string): string;
var
  Param: TURIParameter;
begin
  for Param in FParams do
    If Param.Name = Name then
      Exit(Param.Value);
  Result := '';
end;

procedure TURI.SetParameterByName(const Name, Value: string);
var
  I: Integer;
begin
  for I := 0 to High(FParams) do
    If FParams[I].Name = Name then begin
      SetParameter(I, TURIParameter.Create(Name, Value));
      Exit;
    end;
  AddParameter(Name, Value);
end;

procedure TURI.AddParameter(const AName, AValue: string);
begin
  AddParameter(TURIParameter.Create(AName, AValue));
end;

procedure TURI.AddParameter(const AParameter: TURIParameter);
begin
  SetLength(FParams, Length(FParams) + 1);
  FParams[High(FParams)] := AParameter;
  SetParams(FParams);
end;

procedure TURI.DeleteParameter(AIndex: Integer);
var
  I: Integer;
begin
  GetParameter(AIndex);
  for I := AIndex to High(FParams) - 1 do
    FParams[I] := FParams[I + 1];
  SetLength(FParams, Length(FParams) - 1);
  SetParams(FParams);
end;

procedure TURI.DeleteParameter(const AName: string);
var
  I: Integer;
begin
  for I := High(FParams) downto 0 do
    If FParams[I].Name = AName then
      DeleteParameter(I);
end;

class function TURI.PathRelativeToAbs(const RelPath: string; const Base: TURI): string;
begin
  If not URIParser.ResolveRelativeURI(Base.ToString, RelPath, Result) then
    raise ENetURIException.CreateFailure('Cannot resolve relative URI', TNetFailureReason.InvalidParameter);
end;

class function TURI.FixupForREST(const AURL: string): string;
var
  URI: TURI;
begin
  Result := Trim(AURL);
  If Pos('://', Result) = 0 then
    Result := 'http://' + Result;
  URI := TURI.Create(Result);
  Result := URI.ToString;
end;

constructor TCredentialsStorage.TCredential.Create(Target: TAuthTargetType;
  const ARealm, AURL, AUserName, APassword: string);
begin
  AuthTarget := Target;
  Realm := ARealm;
  URL := AURL;
  UserName := AUserName;
  Password := APassword;
end;

function TCredentialsStorage.TCredential.IsEmpty: Boolean;
begin
  Result := (UserName = '') and (Password = '');
end;

constructor TCredentialsStorage.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TCredentialsStorage.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TCredentialsStorage.ClearCredentials;
begin
  FLock.Acquire;
  try
    FCredentials := nil;
  finally
    FLock.Release;
  end;
end;

function TCredentialsStorage.GetCredentials: TCredentialArray;
begin
  FLock.Acquire;
  try
    Result := Copy(FCredentials);
  finally
    FLock.Release;
  end;
end;

function TCredentialsStorage.AddCredential(const Credential: TCredential): Boolean;
var
  I: Integer;
begin
  FLock.Acquire;
  try
    for I := 0 to High(FCredentials) do
      If (FCredentials[I].AuthTarget = Credential.AuthTarget) and
        (FCredentials[I].Realm = Credential.Realm) and (FCredentials[I].URL = Credential.URL) and
        (FCredentials[I].UserName = Credential.UserName) then begin
        FCredentials[I] := Credential;
        Exit(True);
      end;
    SetLength(FCredentials, Length(FCredentials) + 1);
    FCredentials[High(FCredentials)] := Credential;
    Result := True;
  finally
    FLock.Release;
  end;
end;

function CredentialMatches(const Credential: TCredentialsStorage.TCredential;
  Target: TAuthTargetType; const Realm, URL, User: string): Boolean;
var
  Scope, Request: TURI;
begin
  Result := (Credential.AuthTarget = Target) and ((Realm = '') or (Credential.Realm = Realm)) and
    ((User = '') or (Credential.UserName = User));
  If not Result or (URL = '') or (Credential.URL = '') then
    Exit;
  Scope := TURI.Create(Credential.URL);
  Request := TURI.Create(URL);
  Result := SameText(Scope.Scheme, Request.Scheme) and SameText(Scope.Host, Request.Host) and
    (Scope.Port = Request.Port) and (Copy(Request.Path, 1, Length(Scope.Path)) = Scope.Path);
  If Result and (Length(Request.Path) > Length(Scope.Path)) and (Scope.Path <> '') and
    (Scope.Path[Length(Scope.Path)] <> '/') then
    Result := Request.Path[Length(Scope.Path) + 1] = '/';
end;

function TCredentialsStorage.RemoveCredential(Target: TAuthTargetType; const Realm, URL, User: string): Boolean;
var
  I, N: Integer;
begin
  FLock.Acquire;
  try
    N := 0;
    for I := 0 to High(FCredentials) do
      If not CredentialMatches(FCredentials[I], Target, Realm, URL, User) then begin
        FCredentials[N] := FCredentials[I];
        Inc(N);
      end;
    Result := N <> Length(FCredentials);
    SetLength(FCredentials, N);
  finally
    FLock.Release;
  end;
end;

class function TCredentialsStorage.SortCredentials(const Credentials: TCredentialArray): TCredentialArray;
var
  I, J: Integer;
  Value: TCredential;
begin
  Result := Copy(Credentials);
  { More specific scopes win; keep insertion order for equal specificity. }
  for I := 1 to High(Result) do begin
    Value := Result[I];
    J := I;
    while (J > 0) and (Length(Result[J - 1].URL) < Length(Value.URL)) do begin
      Result[J] := Result[J - 1];
      Dec(J);
    end;
    Result[J] := Value;
  end;
end;

function TCredentialsStorage.FindCredentials(Target: TAuthTargetType; const Realm, URL, User: string): TCredentialArray;
var
  All: TCredentialArray;
  Credential: TCredential;
  N: Integer;
begin
  All := GetCredentials;
  SetLength(Result, Length(All));
  N := 0;
  for Credential in All do
    If CredentialMatches(Credential, Target, Realm, URL, User) then begin
      Result[N] := Credential;
      Inc(N);
    end;
  SetLength(Result, N);
  Result := SortCredentials(Result);
end;

function TCredentialsStorage.FindAccurateCredential(Target: TAuthTargetType;
  const Realm, URL, User: string): TCredential;
var
  Matches: TCredentialArray;
begin
  Matches := FindCredentials(Target, Realm, URL, User);
  If Length(Matches) = 0 then
    Result := Default(TCredential)
  else
    Result := Matches[0];
end;

constructor TProxySettings.Create(const URL: string);
var
  URI: TURI;
begin
  URI := TURI.Create(URL);
  Self := TProxySettings.Create(URI.Host, URI.Port, URI.Username, URI.Password, URI.Scheme);
end;

constructor TProxySettings.Create(const Host: string; Port: Integer;
  const UserName, Password, Scheme: string);
begin
  FHost := Host;
  FPort := Port;
  FUserName := UserName;
  FPassword := Password;
  FScheme := Scheme;
end;

function TProxySettings.ToString: string;
var
  URI: TURI;
  Scheme: string;
begin
  If FHost = '' then
    Exit('');
  Scheme := FScheme;
  If Scheme = '' then
    Scheme := 'http';
  URI.ComposeURI(Scheme, FUserName, FPassword, FHost, FPort, '', nil, '');
  Result := URI.ToString;
end;

function TProxySettings.GetCredential: TCredentialsStorage.TCredential;
begin
  Result := TCredentialsStorage.TCredential.Create(TAuthTargetType.Proxy, '', ToString, FUserName, FPassword);
end;

constructor TURLRequest.Create(const AURL, AMethodString: string);
begin
  inherited Create;
  FURL := TURI.Create(AURL);
  FMethodString := AMethodString;
end;

function TURLRequest.GetCredential: TCredentialsStorage.TCredential;
begin
  Result := FCredential;
end;

procedure TURLRequest.SetCredential(const Credential: TCredentialsStorage.TCredential);
begin
  FCredential := Credential;
end;

procedure TURLRequest.SetCredential(const UserName, Password: string);
begin
  FCredential := TCredentialsStorage.TCredential.Create(TAuthTargetType.Server, '', FURL.ToString, UserName, Password);
end;

function TURLRequest.GetURL: TURI;
begin
  Result := FURL;
end;

procedure TURLRequest.SetURL(const Value: TURI);
begin
  FURL := Value;
end;

function TURLRequest.GetMethodString: string;
begin
  Result := FMethodString;
end;

procedure TURLRequest.SetMethodString(const Value: string);
begin
  FMethodString := Value;
end;

function TURLRequest.GetSourceStream: TStream;
begin
  Result := FSource;
end;

procedure TURLRequest.SetSourceStream(const Value: TStream);
begin
  FSource := Value;
end;

procedure TURLRequest.Cancel;
begin
  InterlockedExchange(FCancelled, 1);
end;

function TURLRequest.GetIsCancelled: Boolean;
begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
end;

type
  TURLSchemeEntry = record
    Scheme: string;
    ClientClass: TURLClientClass;
  end;
var
  URLSchemes: array of TURLSchemeEntry;
  URLSchemesLock: TRTLCriticalSection;

class procedure TURLSchemes.RegisterURLClientScheme(ClientClass: TURLClientClass; const Scheme: string);
var
  I: Integer;
begin
  EnterCriticalSection(URLSchemesLock);
  try
    for I := 0 to High(URLSchemes) do
      If SameText(URLSchemes[I].Scheme, Scheme) then begin
        URLSchemes[I].ClientClass := ClientClass;
        Exit;
      end;
    SetLength(URLSchemes, Length(URLSchemes) + 1);
    URLSchemes[High(URLSchemes)].Scheme := Scheme;
    URLSchemes[High(URLSchemes)].ClientClass := ClientClass;
  finally
    LeaveCriticalSection(URLSchemesLock);
  end;
end;

class procedure TURLSchemes.UnRegisterURLClientScheme(const Scheme: string);
begin
  RegisterURLClientScheme(nil, Scheme);
end;

class function TURLSchemes.GetURLClientInstance(const Scheme: string): TURLClient;
var
  I: Integer;
  Factory: TURLClientClass;
begin
  Factory := nil;
  EnterCriticalSection(URLSchemesLock);
  try
    for I := 0 to High(URLSchemes) do
      If SameText(URLSchemes[I].Scheme, Scheme) then begin
        Factory := URLSchemes[I].ClientClass;
        Break;
      end;
  finally
    LeaveCriticalSection(URLSchemesLock);
  end;
  If Factory = nil then
    raise ENetURIClientException.CreateFailure('No URL client registered for request scheme', TNetFailureReason.InvalidParameter);
  Result := Factory.Create;
end;

constructor TURLClient.Create;
begin
  inherited Create;
  FTransportLock := TCriticalSection.Create;
  FCustomHeaders := TURLHeaders.Create;
  FInternalCredentialsStorage := TCredentialsStorage.Create;
  FSharedCredentials := FInternalCredentialsStorage;
  FCredentialsStorage := FInternalCredentialsStorage;
  FConnectionTimeout := DefaultConnectionTimeout;
  FSendTimeout := DefaultSendTimeout;
  FResponseTimeout := DefaultResponseTimeout;
end;

destructor TURLClient.Destroy;
var
  Transport: TTransport;
begin
  for Transport in FTransports do
    Transport.Client.Free;
  FTransportLock.Free;
  FSharedCredentials := nil;
  FCustomHeaders.Free;
  inherited Destroy;
end;

function TURLClient.GetCustomHeader(const Name: string): string;
begin
  Result := FCustomHeaders.Value[Name];
end;

procedure TURLClient.SetCustomHeader(const Name, Value: string);
begin
  FCustomHeaders.Value[Name] := Value;
end;

function TURLClient.GetUserAgent: string;
begin
  Result := GetCustomHeader('User-Agent');
end;

procedure TURLClient.SetUserAgent(const Value: string);
begin
  SetCustomHeader('User-Agent', Value);
end;

procedure TURLClient.CopySettingsTo(Target: TURLClient);
begin
  Target.FConnectionTimeout := FConnectionTimeout;
  Target.FSendTimeout := FSendTimeout;
  Target.FResponseTimeout := FResponseTimeout;
  Target.FProxySettings := FProxySettings;
  Target.FCustomHeaders.Assign(FCustomHeaders);
  Target.FAuthCallback := FAuthCallback;
  Target.FAuthEvent := FAuthEvent;
  Target.FSharedCredentials := FSharedCredentials;
  Target.FInternalCredentialsStorage := FInternalCredentialsStorage;
  Target.FCredentialsStorage := FCredentialsStorage;
end;

function TURLClient.TransportFor(const Scheme: string): TURLClient;
var
  I: Integer;
begin
  FTransportLock.Acquire;
  try
    for I := 0 to High(FTransports) do
      If SameText(FTransports[I].Scheme, Scheme) then
        Exit(FTransports[I].Client);
    Result := TURLSchemes.GetURLClientInstance(Scheme);
    SetLength(FTransports, Length(FTransports) + 1);
    FTransports[High(FTransports)].Scheme := Scheme;
    FTransports[High(FTransports)].Client := Result;
  finally
    FTransportLock.Release;
  end;
end;

function TURLClient.CloneClient(const Scheme: string): TURLClient;
var
  Transport: TURLClient;
begin
  If ClassType <> TURLClient then begin
    { A subclass can use the generic asynchronous dispatcher by overriding
      DoExecute alone. }
    Result := TURLClientClass(ClassType).Create;
    CopySettingsTo(Result);
  end else begin
    Transport := TransportFor(Scheme);
    If Transport.ClassType = TURLClient then
      raise ENetURIClientException.CreateFailure('A scheme must register a transport subclass', TNetFailureReason.InvalidParameter);
    CopySettingsTo(Transport);
    Result := Transport.CloneClient(Scheme);
  end;
end;

function TURLClient.AsyncResultClass: TURLAsyncResultClass;
begin
  Result := TURLAsyncResult;
end;

procedure TURLClient.Abort;
begin
  { Base dispatch uses the request's cancellation flag. Transports override
    this to interrupt their active I/O as well. }
end;

function TURLClient.GetRequest(const Method: string; const URI: TURI): IURLRequest;
begin
  Result := GetRequest(Method, URI.ToString);
end;

function TURLClient.GetRequest(const Method, URI: string): IURLRequest;
begin
  Result := TURLRequest.Create(URI, Method);
end;

function TURLClient.DoExecute(const Request: IURLRequest; Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
var
  Client: TURLClient;
begin
  Client := TransportFor(Request.URL.Scheme);
  CopySettingsTo(Client);
  Result := Client.Execute(Request, Content, Headers);
end;

function TURLClient.Execute(const Request: IURLRequest; const Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
begin
  If Request = nil then
    raise ENetURIRequestException.CreateFailure('Request cannot be nil', TNetFailureReason.InvalidParameter);
  If Request.IsCancelled then
    raise ENetURIRequestException.CreateFailure('Request was cancelled', TNetFailureReason.Cancelled);
  Result := DoExecute(Request, Content, Headers);
end;

function TURLClient.Execute(const Method, URI: string; const Source, Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
var
  Request: IURLRequest;
begin
  Request := GetRequest(Method, URI);
  Request.SourceStream := Source;
  Result := Execute(Request, Content, Headers);
end;

function TURLClient.Execute(const Method: string; const URI: TURI; const Source, Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
begin
  Result := Execute(Method, URI.ToString, Source, Content, Headers);
end;

type
  TURLWorker = class(TThread)
  private
    FOperation: TURLAsyncOperation;
  protected
    procedure Execute; override;
  public
    constructor Create(Operation: TURLAsyncOperation);
    destructor Destroy; override;
  end;

constructor TURLWorker.Create(Operation: TURLAsyncOperation);
begin
  inherited Create(True);
  FOperation := Operation;
  FOperation._AddRef;
  FreeOnTerminate := True;
end;

destructor TURLWorker.Destroy;
begin
  inherited Destroy;
  If FOperation <> nil then
    FOperation._Release;
end;

procedure TURLWorker.Execute;
begin
  If not Terminated then
    FOperation.Run;
end;

constructor TURLAsyncOperation.Create(Client: TURLClient; const Request: IURLRequest;
  Content, OwnedSource: TStream; const Headers: TNetHeaders; Context: TObject;
  const Callback: TAsyncCallback; const CallbackEvent: TAsyncCallbackEvent; ResultClass: TURLAsyncResultClass);
begin
  inherited Create;
  FClient := Client;
  FRequest := Request;
  FContent := Content;
  FOwnedSource := OwnedSource;
  FHeaders := Copy(Headers);
  FContext := Context;
  FCallback := Callback;
  FCallbackEvent := CallbackEvent;
  FResultClass := ResultClass;
  FLock := TCriticalSection.Create;
  FDone := TMultiWaitEvent.Create;
  FCallbacksDone := TMultiWaitEvent.Create;
end;

destructor TURLAsyncOperation.Destroy;
begin
  FClient.Free;
  FOwnedSource.Free;
  FError.Free;
  FDone.Free;
  FCallbacksDone.Free;
  FLock.Free;
  inherited Destroy;
end;

function TURLAsyncOperation.NewView(CallbackView: Boolean): IAsyncResult;
begin
  Result := FResultClass.Create(Self, CallbackView);
end;

procedure TURLAsyncOperation.Run;
var
  View: IAsyncResult;
  Client: TURLClient;
begin
  FWorkerThread := GetCurrentThreadId;
  try
    try
      FResponse := FClient.Execute(FRequest, FContent, FHeaders);
    except
      FError := Exception(AcquireExceptionObject);
    end;
  finally
    { Publish completion only after the transport and owned input have stopped
      touching streams. A completion callback can call EndAsync without joining
      its own thread. }
    FLock.Acquire;
    try
      Client := FClient;
      FClient := nil;
    finally
      FLock.Release;
    end;
    try
      Client.Free;
    except
      on Exception do
        If FError = nil then
          FError := Exception(AcquireExceptionObject);
    end;
    try
      FreeAndNil(FOwnedSource);
    except
      on Exception do
        If FError = nil then
          FError := Exception(AcquireExceptionObject);
    end;
    FLock.Acquire;
    try
      FCompleted := True;
      FDone.SetEvent;
    finally
      FLock.Release;
    end;
  end;
  try
    If Assigned(FCallback) or Assigned(FCallbackEvent) then begin
      View := NewView(True);
      If Assigned(FCallback) then
        FCallback(View)
      else
        FCallbackEvent(View);
    end;
  finally
    View := nil;
    FCallback := nil;
    FCallbackEvent := nil;
    FCallbacksDone.SetEvent;
  end;
end;

function TURLAsyncOperation.Cancel: Boolean;
begin
  FLock.Acquire;
  try
    Result := not FCompleted and not FCancelled;
    If Result then begin
      FCancelled := True;
      FRequest.Cancel;
      If FClient <> nil then
        FClient.Abort;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TURLAsyncOperation.DetachView;
var
  Last: Boolean;
begin
  FLock.Acquire;
  try
    Dec(FViews);
    Last := FViews = 0;
  finally
    FLock.Release;
  end;
  If Last then begin
    Cancel;
    FDone.WaitFor;
    If GetCurrentThreadId <> FWorkerThread then
      FCallbacksDone.WaitFor;
  end;
end;

function TURLAsyncOperation.Await: IURLResponse;
var
  Error: Exception;
begin
  If FDone.WaitFor <> Types.wrSignaled then
    raise ENetURIResponseException.CreateFailure('Cannot wait for URL request', TNetFailureReason.Unknown);
  If FError <> nil then begin
    { Await can be called repeatedly, including from the completion callback.
      The operation keeps ownership of the original exception. }
    Error := ExceptClass(FError.ClassType).Create(FError.Message);
    If (FError is ENetException) and (Error is ENetException) then
      ENetException(Error).AssignFailure(ENetException(FError));
    raise Error;
  end;
  If FCancelled or FRequest.IsCancelled then
    raise ENetURIRequestException.CreateFailure('Request was cancelled', TNetFailureReason.Cancelled);
  Result := FResponse;
end;

constructor TURLAsyncResult.Create(Operation: TURLAsyncOperation; CallbackView: Boolean);
begin
  inherited Create;
  FOperation := Operation;
  FCallbackView := CallbackView;
  FOperation._AddRef;
  FOperation.FLock.Acquire;
  try
    If not FCallbackView then
      Inc(FOperation.FViews);
  finally
    FOperation.FLock.Release;
  end;
end;

destructor TURLAsyncResult.Destroy;
begin
  If not FCallbackView then
    FOperation.DetachView;
  FOperation._Release;
  inherited Destroy;
end;

function TURLAsyncResult.AwaitResponse: IURLResponse;
begin
  Result := FOperation.Await;
end;

function TURLAsyncResult.GetAsyncContext: TObject;
begin
  Result := FOperation.FContext;
end;

function TURLAsyncResult.GetAsyncWaitEvent: TMultiWaitEvent;
begin
  Result := FOperation.FDone;
end;

function TURLAsyncResult.GetCompletedSynchronously: Boolean;
begin
  Result := False;
end;

function TURLAsyncResult.GetIsCompleted: Boolean;
begin
  Result := FOperation.FDone.WaitFor(0) = Types.wrSignaled;
end;

function TURLAsyncResult.GetIsCancelled: Boolean;
begin
  Result := FOperation.FRequest.IsCancelled;
end;

function TURLAsyncResult.Cancel: Boolean;
begin
  Result := FOperation.Cancel;
end;

function TURLAsyncResult.GetHeaders: TNetHeaders;
begin
  Result := AwaitResponse.Headers;
end;

function TURLAsyncResult.GetMimeType: string;
begin
  Result := AwaitResponse.MimeType;
end;

function TURLAsyncResult.GetContentStream: TStream;
begin
  Result := AwaitResponse.ContentStream;
end;

function TURLAsyncResult.ContentAsString(const Encoding: TEncoding): string;
begin
  Result := AwaitResponse.ContentAsString(Encoding);
end;

function TURLAsyncResult.GetAsyncResult: IAsyncResult;
begin
  Result := Self;
end;

function TURLClient.StartAsync(const Callback: TAsyncCallback; const CallbackEvent: TAsyncCallbackEvent;
  const Request: IURLRequest; Content: TStream; const Headers: TNetHeaders; OwnedSource: TStream): IAsyncResult;
var
  Operation: TURLAsyncOperation;
  Worker: TURLWorker;
  Client: TURLClient;
begin
  Client := nil;
  try
    Client := CloneClient(Request.URL.Scheme);
  except
    OwnedSource.Free;
    raise;
  end;
  Operation := TURLAsyncOperation.Create(Client, Request, Content, OwnedSource, Headers,
    Self, Callback, CallbackEvent, Client.AsyncResultClass);
  Operation._AddRef;
  try
    Worker := TURLWorker.Create(Operation);
    try
      Result := Operation.NewView;
      Worker.Start;
    except
      Worker.Terminate;
      Operation.FCompleted := True;
      Operation.FDone.SetEvent;
      Operation.FCallbacksDone.SetEvent;
      Worker.Free;
      raise;
    end;
  finally
    Operation._Release;
  end;
end;

function TURLClient.BeginExecute(const Method, URI: string; const Source, Content: TStream;
  const Headers: TNetHeaders): IAsyncResult;
begin
  Result := BeginExecute(TAsyncCallback(nil), Method, URI, Source, Content, Headers);
end;

function TURLClient.BeginExecute(const Method: string; const URI: TURI; const Source, Content: TStream;
  const Headers: TNetHeaders): IAsyncResult;
begin
  Result := BeginExecute(Method, URI.ToString, Source, Content, Headers);
end;

function TURLClient.BeginExecute(const Callback: TAsyncCallback; const Method, URI: string;
  const Source, Content: TStream; const Headers: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest(Method, URI);
  Request.SourceStream := Source;
  Result := StartAsync(Callback, nil, Request, Content, Headers);
end;

function TURLClient.BeginExecute(const Callback: TAsyncCallback; const Method: string; const URI: TURI;
  const Source, Content: TStream; const Headers: TNetHeaders): IAsyncResult;
begin
  Result := BeginExecute(Callback, Method, URI.ToString, Source, Content, Headers);
end;

function TURLClient.BeginExecute(const Callback: TAsyncCallbackEvent; const Method, URI: string;
  const Source, Content: TStream; const Headers: TNetHeaders): IAsyncResult;
var
  Request: IURLRequest;
begin
  Request := GetRequest(Method, URI);
  Request.SourceStream := Source;
  Result := StartAsync(nil, Callback, Request, Content, Headers);
end;

function TURLClient.BeginExecute(const Callback: TAsyncCallbackEvent; const Method: string; const URI: TURI;
  const Source, Content: TStream; const Headers: TNetHeaders): IAsyncResult;
begin
  Result := BeginExecute(Callback, Method, URI.ToString, Source, Content, Headers);
end;

class function TURLClient.EndAsyncURL(const AsyncResult: IAsyncResult): IURLResponse;
var
  Response: IURLResponse;
begin
  If not Supports(AsyncResult, IURLResponse, Response) then
    raise ENetURIResponseException.CreateFailure('Async result is not a URL response', TNetFailureReason.InvalidParameter);
  Response.GetHeaders;
  Result := Response;
end;

class function TURLClient.EndAsyncURL(const AsyncResponse: IURLResponse): IURLResponse;
begin
  If AsyncResponse = nil then
    raise ENetURIResponseException.CreateFailure('Response cannot be nil', TNetFailureReason.InvalidParameter);
  AsyncResponse.GetHeaders;
  Result := AsyncResponse;
end;
