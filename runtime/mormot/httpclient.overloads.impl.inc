function THTTPResponse.GetMimeType: string;
var
  P: Integer;
begin
  Result := GetHeaderValue('Content-Type');
  P := Pos(';', Result);
  If P > 0 then
    SetLength(Result, P - 1);
  Result := Trim(Result);
end;

function THTTPResponse.GetContentCharSet: string;
begin
  Result := ContentCharset(GetHeaderValue('Content-Type'));
end;

function THTTPResponse.GetContentLanguage: string;
begin
  Result := GetHeaderValue('Content-Language');
end;

function THTTPResponse.GetContentLength: Int64;
begin
  Result := StrToInt64Def(GetHeaderValue('Content-Length'), -1);
end;

function THTTPResponse.GetDate: string;
begin
  Result := GetHeaderValue('Date');
end;

function THTTPResponse.GetLastModified: string;
begin
  Result := GetHeaderValue('Last-Modified');
end;

function THTTPResponse.GetVersion: THTTPProtocolVersion;
begin
  Result := FVersion;
end;

function THTTPResponse.ContainsHeader(const AName: string): Boolean;
begin
  Result := HeaderIndex(FHeaders, AName) >= 0;
end;

function THTTPResponse.GetCookies: TCookies;
begin
  Result := FCookies;
end;

function THTTPResponse.GetAsyncResult: IAsyncResult;
begin
  Result := Self;
end;

function THTTPResponse.GetAsyncContext: TObject;
begin
  Result := FContext;
end;

function THTTPResponse.GetAsyncWaitEvent: TMultiWaitEvent;
begin
  Result := FDone;
end;

function THTTPResponse.GetCompletedSynchronously: Boolean;
begin
  Result := True;
end;

function THTTPResponse.GetIsCompleted: Boolean;
begin
  Result := True;
end;

function THTTPResponse.GetIsCancelled: Boolean;
begin
  Result := False;
end;

function THTTPResponse.Cancel: Boolean;
begin
  Result := False;
end;

type
  THTTPAsyncResult = class(TURLAsyncResult, IHTTPResponse)
  private
    function Response: IHTTPResponse;
  public
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetHeaderValue(const Name: string): string;
    function GetContentCharSet: string;
    function GetContentEncoding: string;
    function GetContentLanguage: string;
    function GetContentLength: Int64;
    function GetDate: string;
    function GetLastModified: string;
    function GetVersion: THTTPProtocolVersion;
    function ContainsHeader(const Name: string): Boolean;
    function GetCookies: TCookies;
  end;

function THTTPAsyncResult.Response: IHTTPResponse;
begin
  If not Supports(AwaitResponse, IHTTPResponse, Result) then
    raise ENetHTTPResponseException.Create('Expected an HTTP response');
end;

function THTTPAsyncResult.GetStatusCode: Integer;
begin
  Result := Response.StatusCode;
end;

function THTTPAsyncResult.GetStatusText: string;
begin
  Result := Response.StatusText;
end;

function THTTPAsyncResult.GetHeaderValue(const Name: string): string;
begin
  Result := Response.HeaderValue[Name];
end;

function THTTPAsyncResult.GetContentCharSet: string;
begin
  Result := Response.ContentCharSet;
end;

function THTTPAsyncResult.GetContentEncoding: string;
begin
  Result := Response.ContentEncoding;
end;

function THTTPAsyncResult.GetContentLanguage: string;
begin
  Result := Response.ContentLanguage;
end;

function THTTPAsyncResult.GetContentLength: Int64;
begin
  Result := Response.ContentLength;
end;

function THTTPAsyncResult.GetDate: string;
begin
  Result := Response.Date;
end;

function THTTPAsyncResult.GetLastModified: string;
begin
  Result := Response.LastModified;
end;

function THTTPAsyncResult.GetVersion: THTTPProtocolVersion;
begin
  Result := Response.Version;
end;

function THTTPAsyncResult.ContainsHeader(const Name: string): Boolean;
begin
  Result := Response.ContainsHeader(Name);
end;

function THTTPAsyncResult.GetCookies: TCookies;
begin
  Result := Response.Cookies;
end;

function THTTPClient.AsyncResultClass: TURLAsyncResultClass;
begin
  Result := THTTPAsyncResult;
end;

function THTTPClient.CloneClient(const Scheme: string): TURLClient;
var
  Client: THTTPClient;
begin
  Client := THTTPClient.Create;
  try
    CopySettingsTo(Client);
    Client.FHandleRedirects := FHandleRedirects;
    Client.FMaxRedirects := FMaxRedirects;
    Client.FAutomaticDecompression := FAutomaticDecompression;
    Client.FSharedCookies := FSharedCookies;
    Client.FCookieManager := FCookieManager;
    Client.FOnReceiveData := FOnReceiveData;
    Client.FOnSendData := FOnSendData;
    Client.FOnValidateServerCertificate := FOnValidateServerCertificate;
    Result := Client;
  except
    Client.Free;
    raise;
  end;
end;

function THTTPClient.DoExecute(const Request: IURLRequest; Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
var
  RequestHeaders: TNetHeaders;
  Credential: TCredentialsStorage.TCredential;
  Watch: TRequestWatch;
begin
  FSocketGuard.Acquire;
  try
    If FActiveRequest <> nil then
      raise ENetHTTPClientException.Create('Use BeginExecute for concurrent requests on one client');
    FActiveRequest := Request;
    FAbortRequested := Request.IsCancelled;
    FConnectionExpired := False;
    FConnectionDeadline := 0;
  finally
    FSocketGuard.Release;
  end;
  Watch := nil;
  try
    Watch := TRequestWatch.Create(Self);
    Credential := Request.Credential;
    RequestHeaders := Copy(Headers);
    If not Credential.IsEmpty and (Credential.AuthTarget = TAuthTargetType.Server) and
      (HeaderIndex(RequestHeaders, 'Authorization') < 0) then
      SetHeader(RequestHeaders, 'Authorization', BasicAuthorization(Credential.UserName, Credential.Password));
    Result := ExecuteHTTP(Request.MethodString, Request.URL.ToString, Request.SourceStream, Content, RequestHeaders);
  finally
    Watch.Free;
    If FAbortRequested or Request.IsCancelled then
      CloseSocket;
    FSocketGuard.Acquire;
    try
      FActiveRequest := nil;
      FConnectionDeadline := 0;
    finally
      FSocketGuard.Release;
    end;
  end;
end;

function THTTPClient.Execute(const Method, URL: string; const Source, Content: TStream;
  const Headers: TNetHeaders): IHTTPResponse;
var
  Response: IURLResponse;
begin
  Response := inherited Execute(Method, URL, Source, Content, Headers);
  If not Supports(Response, IHTTPResponse, Result) then
    raise ENetHTTPResponseException.Create('Expected an HTTP response');
end;

function THTTPClient.Execute(const Method: string; const URI: System.Net.URLClient.TURI;
  const Source, Content: TStream; const Headers: TNetHeaders): IHTTPResponse;
begin
  Result := Execute(Method, URI.ToString, Source, Content, Headers);
end;

function THTTPClient.Execute(const Request: IURLRequest; const Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
begin
  Result := inherited Execute(Request, Content, Headers);
end;

function FormHeaders(const Headers: TNetHeaders; Encoding: TEncoding): TNetHeaders;
begin
  Result := Copy(Headers);
  SetHeader(Result, 'Content-Type', 'application/x-www-form-urlencoded; charset=' + CharsetNameOf(Encoding));
end;

function FormBody(Source: TStrings; Encoding: TEncoding): TStream;
var
  Text: string;
  I, P: Integer;
begin
  Text := '';
  If Source <> nil then
    for I := 0 to Source.Count - 1 do begin
      P := Pos('=', Source[I]);
      If P <= 0 then
        Continue;
      If Text <> '' then
        Text := Text + '&';
      Text := Text + FormEncode(Copy(Source[I], 1, P - 1), Encoding) + '=' +
        FormEncode(Copy(Source[I], P + 1, MaxInt), Encoding);
    end;
  Result := TBytesStream.Create(TEncoding.ASCII.GetBytes(Text));
end;

function MultipartHeaders(const Headers: TNetHeaders; Source: TMultipartFormData): TNetHeaders;
begin
  If Source = nil then
    raise EArgumentNilException.Create('Multipart body cannot be nil');
  Source.Stream.Position := 0;
  Result := Copy(Headers);
  SetHeader(Result, 'Content-Type', Source.MimeTypeHeader);
end;

function THTTPClient.Post(const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IHTTPResponse;
var
  Source: TStream;
begin
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  try
    Result := Execute('POST', AURL, Source, AResponseContent, AHeaders);
  finally
    Source.Free;
  end;
end;

function THTTPClient.Put(const AURL: string; const ASource: string; const AResponseContent: TStream;
  const AHeaders: TNetHeaders): IHTTPResponse;
var
  Source: TStream;
begin
  Source := TFileStream.Create(ASource, fmOpenRead or fmShareDenyWrite);
  try
    Result := Execute('PUT', AURL, Source, AResponseContent, AHeaders);
  finally
    Source.Free;
  end;
end;

function THTTPClient.Post(const AURL: string; const ASource: TStrings; const AResponseContent: TStream;
  const AEncoding: TEncoding; const AHeaders: TNetHeaders): IHTTPResponse;
var
  Source: TStream;
begin
  Source := FormBody(ASource, AEncoding);
  try
    Result := Execute('POST', AURL, Source, AResponseContent, FormHeaders(AHeaders, AEncoding));
  finally
    Source.Free;
  end;
end;

function THTTPClient.Put(const AURL: string; const ASource: TStrings; const AResponseContent: TStream;
  const AEncoding: TEncoding; const AHeaders: TNetHeaders): IHTTPResponse;
var
  Source: TStream;
begin
  Source := FormBody(ASource, AEncoding);
  try
    Result := Execute('PUT', AURL, Source, AResponseContent, FormHeaders(AHeaders, AEncoding));
  finally
    Source.Free;
  end;
end;

function THTTPClient.Post(const AURL: string; const ASource: TMultipartFormData;
  const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
var
  Headers: TNetHeaders;
begin
  Headers := MultipartHeaders(AHeaders, ASource);
  Result := Execute('POST', AURL, ASource.Stream, AResponseContent, Headers);
end;

function THTTPClient.Put(const AURL: string; const ASource: TMultipartFormData;
  const AResponseContent: TStream; const AHeaders: TNetHeaders): IHTTPResponse;
var
  Headers: TNetHeaders;
begin
  Headers := MultipartHeaders(AHeaders, ASource);
  Result := Execute('PUT', AURL, ASource.Stream, AResponseContent, Headers);
end;

{$i httpclient.begin.inc}

class function THTTPClient.EndAsyncHTTP(const AAsyncResult: IAsyncResult): IHTTPResponse;
var
  Response: IURLResponse;
begin
  try
    Response := TURLClient.EndAsyncURL(AAsyncResult);
  except
    on E: ENetURIRequestException do
      If (AAsyncResult <> nil) and AAsyncResult.IsCancelled then
        raise ENetHTTPClientException.Create(E.Message)
      else
        raise;
  end;
  If not Supports(Response, IHTTPResponse, Result) then
    raise ENetHTTPResponseException.Create('Async result is not an HTTP response');
end;

class function THTTPClient.EndAsyncHTTP(const AResponse: IHTTPResponse): IHTTPResponse;
begin
  If AResponse = nil then
    raise ENetHTTPResponseException.Create('Response cannot be nil');
  AResponse.GetHeaders;
  Result := AResponse;
end;
