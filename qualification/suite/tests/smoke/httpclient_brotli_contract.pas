program httpclient_brotli_contract;
{$mode delphi}{$H+}

{ Compile twice, with and without MOON_HTTP_BROTLI. The loopback gate also
  checks that the disabled explicit selection never reaches the server. }
uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  {$ifdef MOON_HTTP_BROTLI}Moon.HttpClient.Brotli,{$endif}
  SysUtils, Classes, System.Net.HttpClient;

procedure Check(Value: Boolean; const MessageText: string);
begin
  If not Value then
    raise Exception.Create(MessageText);
end;

var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Base, Text, Expected, Path: string;
  I: Integer;
begin
  Base := ParamStr(1);
  Client := THTTPClient.Create;
  try
    Response := Client.Get(Base + '/brotli21');
    Check((Response.ContentStream.Size = 40) and (Response.ContentEncoding = 'br'), 'raw Brotli body');
    {$ifdef MOON_HTTP_BROTLI}
    Expected := 'Brotli response: ';
    for I := 1 to 24000 do
      Expected := Expected + 'hello ';
    Response.ContentStream.Position := 7;
    Check((Response.ContentAsString = Expected) and (Response.ContentAsString = Expected), 'decode and rewind');
    Check(Response.ContentStream.Position = 0, 'string access rewinds response body');
    Client.AutomaticDecompression := [THTTPCompressionMethod.Any];
    Response := Client.Get(Base + '/brotli21');
    Check(Response.HeaderValue['X-Accept-Encoding'] = 'gzip, deflate, br', 'Any advertises registered Brotli');
    Check((Response.ContentAsString = Expected) and (Response.ContentEncoding = ''), 'Any decodes Brotli');
    Client.AutomaticDecompression := [THTTPCompressionMethod.Brotli];
    Response := Client.Get(Base + '/brotli21');
    Check((Response.ContentAsString = Expected) and (Response.ContentStream.Size = Length(Expected)) and
      (Response.HeaderValue['X-Accept-Encoding'] = 'br') and (Response.ContentEncoding = ''), 'explicit Brotli');
    Response := Client.Get(Base + '/brotli21/empty');
    Check((Response.ContentAsString = '') and (Response.ContentStream.Size = 0), 'empty Brotli stream');
    for I := 0 to 2 do begin
      case I of
        0: Path := 'cut';
        1: Path := 'invalid';
        2: Path := 'trailing';
      end;
      try
        Response := Client.Get(Base + '/brotli21/' + Path);
        Check(False, 'invalid Brotli accepted: ' + Path);
      except
        on ENetHTTPResponseException do ;
      end;
    end;
    WriteLn('HTTPCLIENT_BROTLI_ENABLED_PASS');
    {$else}
    for I := 0 to 1 do begin
      If I = 1 then begin
        Client.AutomaticDecompression := [THTTPCompressionMethod.Any];
        Response := Client.Get(Base + '/brotli21');
        Check(Response.HeaderValue['X-Accept-Encoding'] = 'gzip, deflate', 'Any excludes unavailable Brotli');
      end;
      Check((Response.ContentStream.Size = 40) and (Response.ContentEncoding = 'br'), 'unsupported body stays raw');
      try
        Text := Response.ContentAsString;
        Check(False, 'unsupported Brotli silently converted to text: ' + Text);
      except
        on E: ENetHTTPResponseException do
          Check(Pos('Moon.HttpClient.Brotli', E.Message) > 0, 'missing decoder identifies opt-in unit');
      end;
    end;
    Client.AutomaticDecompression := [THTTPCompressionMethod.Brotli];
    try
      Response := Client.Get(Base + '/brotli-disabled-must-not-connect');
      Check(False, 'explicit unsupported Brotli accepted');
    except
      on E: ENetHTTPClientException do
        Check(Pos('Moon.HttpClient.Brotli', E.Message) > 0, 'explicit selection identifies opt-in unit');
    end;
    WriteLn('HTTPCLIENT_BROTLI_DISABLED_PASS');
    {$endif}
  finally
    Response := nil;
    Client.Free;
  end;
end.
