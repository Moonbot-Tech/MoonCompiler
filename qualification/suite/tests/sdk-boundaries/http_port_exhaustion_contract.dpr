program http_port_exhaustion_contract;

uses System.SysUtils, System.Net.URLClient, System.Net.HttpClient;

procedure CheckFailure(const E: ENetException);
begin
  If (E.NativeError <> 99) or (E.Reason <> TNetFailureReason.Connection) or
     (E.Outcome <> TNetRequestOutcome.NotSent) then
    raise Exception.CreateFmt('Expected EADDRNOTAVAIL, got native=%d reason=%d outcome=%d message=%s',
      [E.NativeError, Ord(E.Reason), Ord(E.Outcome), E.Message]);
end;

procedure CheckResponse(const Response: IHTTPResponse);
begin
  If (Response.StatusCode <> 200) or (Response.ContentAsString <> '{}') then
    raise Exception.Create('HTTP client failed to recover');
end;

var
  Client: THTTPClient;
  Request: IAsyncResult;
  Resume: string;
begin
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 2000;
    Client.ResponseTimeout := 2000;
    try
      Client.Get(ParamStr(1));
      raise Exception.Create('Expected synchronous exhaustion');
    except
      on E: ENetException do CheckFailure(E);
    end;
    Request := Client.BeginGet(ParamStr(1));
    for var I := 1 to 2 do
      try
        THTTPClient.EndAsyncHTTP(Request);
        raise Exception.Create('Expected asynchronous exhaustion');
      except
        on E: ENetException do begin
          CheckFailure(E);
          E.Message := 'Changed by the caller';
        end;
      end;
    Writeln('PORT_EXHAUSTION_DETECTED');
    Flush(Output);
    Readln(Resume);
    If Resume <> 'resume' then raise Exception.Create('Unexpected fixture handshake');
    CheckResponse(Client.Get(ParamStr(1)));
    Request := Client.BeginGet(ParamStr(1));
    CheckResponse(THTTPClient.EndAsyncHTTP(Request));
    Writeln('PORT_EXHAUSTION_RECOVERED');
  finally
    Client.Free;
  end;
end.
