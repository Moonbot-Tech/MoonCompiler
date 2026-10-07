program http_error_privacy;
{$mode delphi}
uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, System.Net.URLClient, System.Net.HttpClient;
var
  Client: THTTPClient;
  Pending: IAsyncResult;
  Response: IHTTPResponse;
  AsyncMode: Boolean;
begin
  Client := THTTPClient.Create;
  try
    for AsyncMode := False to True do begin
      try
        If AsyncMode then begin
          Pending := Client.BeginGet('ftp://FAKE_USER:FAKE_PASSWORD@localhost/FAKE_PATH?key=FAKE_QUERY#FAKE_FRAGMENT');
          Response := THTTPClient.EndAsyncHTTP(Pending);
        end else
          Response := Client.Get('ftp://FAKE_USER:FAKE_PASSWORD@localhost/FAKE_PATH?key=FAKE_QUERY#FAKE_FRAGMENT');
        raise Exception.Create('Unsupported scheme unexpectedly accepted');
      except
        on E: ENetHTTPClientException do
          If (Pos('FAKE_', E.Message) <> 0) or (Pos('scheme', E.Message) = 0) then
            raise Exception.Create('HTTP exception privacy failed');
      end;
      Pending := nil;
    end;
  finally
    Pending := nil;
    Response := nil;
    Client.Free;
  end;
  Writeln('HTTP_ERROR_PRIVACY_PASS');
end.
