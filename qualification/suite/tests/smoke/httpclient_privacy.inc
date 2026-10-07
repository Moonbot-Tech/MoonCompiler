{ Only fake secrets are used. Both sync and async failures must keep their
  exception family and reason without echoing any URI or peer-controlled text. }
type
  TPrivacySink = class(TMemoryStream)
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

function TPrivacySink.Write(const Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create('sink exposes FAKE_BODY_SECRET');
end;

procedure ErrorPrivacy;
const
  Suffix = '/FAKE_PATH_SECRET?key=FAKE_QUERY_SECRET#FAKE_FRAGMENT_SECRET';
var
  AsyncMode: Boolean;
  Sink: TPrivacySink;
  C: THTTPClient;
  GenericClient: TURLClient;
  R: IHTTPResponse;
  Request: IURLRequest;
  Text, EncodedURL: string;

  procedure PrivateMessage(E: Exception; Expected: ExceptClass; const Reason: string);
  begin
    Check(E.InheritsFrom(Expected), 'privacy exception family: ' + E.ClassName);
    Check(Pos('fake', LowerCase(E.Message)) = 0, 'HTTP exception disclosed fake secret: ' + E.Message);
    Check(Pos('999999999999999999', E.Message) = 0, 'URI exception echoed the invalid port');
    Check(Pos(Reason, LowerCase(E.Message)) > 0, 'privacy error keeps reason: ' + E.Message);
  end;

  procedure Reject(const URL: string; Expected: ExceptClass; const Reason: string);
  var
    Client: THTTPClient;
    Pending: Types.IAsyncResult;
    Response: IHTTPResponse;
  begin
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := 200;
      Client.ResponseTimeout := 100;
      Client.MaxRedirects := 1;
      try
        If AsyncMode then begin
          Pending := Client.BeginGet(URL);
          Response := THTTPClient.EndAsyncHTTP(Pending);
        end else
          Response := Client.Get(URL);
        Check(False, 'privacy fixture unexpectedly succeeded: ' + URL);
      except
        on E: Exception do
          PrivateMessage(E, Expected, Reason);
      end;
    finally
      Pending := nil;
      Response := nil;
      Client.Free;
    end;
  end;

begin
  GenericClient := TURLClient.Create;
  try
    try
      GenericClient.Execute('GET', 'FAKESECRET://localhost/FAKE_PATH?key=FAKE_QUERY');
      Check(False, 'unregistered scheme accepted');
    except
      on E: Exception do
        PrivateMessage(E, ENetURIClientException, 'scheme');
    end;
  finally
    GenericClient.Free;
  end;
  for AsyncMode := False to True do begin
    Reject('FAKE_USER_SECRET:FAKE_PASSWORD_SECRET@invalid' + Suffix, ENetURIException, 'uri');
    Reject('http://' + Suffix, ENetURIException, 'uri');
    Reject('http://127.0.0.1:999999999999999999' + Suffix, ENetURIException, 'port');
    Reject('ftp://FAKE_USER_SECRET:FAKE_PASSWORD_SECRET@127.0.0.1' + Suffix,
      ENetHTTPClientException, 'scheme');
    Reject('http://FAKE_USER_SECRET:FAKE_PASSWORD_SECRET@127.0.0.1:' + RefusedPort + Suffix,
      ENetHTTPClientException, 'http');
    Reject(Base + '/privacy232/timeout' + Suffix, ENetHTTPClientException, 'timeout');
    Reject(Base + '/privacy232/redirect' + Suffix, ENetHTTPRequestException, 'redirect');
    Reject(Base + '/privacy232/malformed' + Suffix, ENetHTTPResponseException, 'response');
    Reject(Base + '/privacy232/empty' + Suffix, ENetHTTPClientException, 'response');
    If not TlsTrusted then
      Reject(TlsBase + Suffix, ENetHTTPCertificateException, 'certificate')
    else
      Reject(TlsOtherBase + Suffix, ENetHTTPCertificateException, 'certificate');
    Reject('https://127.0.0.1:' + ParamStr(6) + Suffix, ENetHTTPClientException, 'deadline');
  end;
  C := THTTPClient.Create;
  Sink := TPrivacySink.Create;
  try
    try
      R := C.Get(Base + '/privacy232/echo' + Suffix, Sink);
      Check(False, 'privacy sink did not fail');
    except
      on E: Exception do
        PrivateMessage(E, ENetHTTPResponseException, 'estreamerror');
    end;
    R := C.Get(Base + '/privacy232/echo' + Suffix);
    Text := Body(R);
    Check(Pos('/FAKE_PATH_SECRET?key=FAKE_QUERY_SECRET', Text) > 0,
      'privacy repair must preserve the real request path/query');
    Check(Pos('FAKE_FRAGMENT_SECRET', Text) = 0, 'URI fragment is not sent to the server');
    EncodedURL := Base + '/privacy232/echo/FAKE_PATH_SECRET%23part?key=FAKE_QUERY_SECRET%23tail';
    Request := C.GetRequest('GET', EncodedURL + '#FAKE_FRAGMENT_SECRET');
    R := C.Execute(Request) as IHTTPResponse;
    Check(Body(R) = '/privacy232/echo/FAKE_PATH_SECRET%23part?key=FAKE_QUERY_SECRET%23tail',
      'escaped hash remains part of the request path and query');
    Check(Request.URL.Fragment = 'FAKE_FRAGMENT_SECRET', 'request URI retains the fragment');
    R := C.Get(Base + '/privacy232/charset' + Suffix);
    try
      Text := R.ContentAsString;
      Check(False, 'unknown response charset accepted');
    except
      on E: Exception do
        PrivateMessage(E, EEncodingError, 'charset');
    end;
    Check(R.ContentAsString(TEncoding.UTF8) = 'body', 'explicit caller encoding remains authoritative');
  finally
    R := nil;
    Sink.Free;
    C.Free;
  end;
end;
