program http_connect_contract;

uses System.SysUtils, System.Net.URLClient, System.Net.HttpClient;

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;

procedure Good(Client: THTTPClient; const URL: string);
begin
  var Response := Client.Get(URL);
  Check((Response.StatusCode = 200) and (Response.ContentAsString = '{}'), 'successful connection and body');
end;

var
  Client: THTTPClient;
  Request: IAsyncResult;
  Started: QWord;
begin
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 5000;
    Good(Client, ParamStr(1));
    try
      Client.Get(ParamStr(2));
      Check(False, 'refused connection returned');
    except
      on E: ENetException do begin
        Check(E.Reason = TNetFailureReason.ConnectionRefused,
          Format('deferred refusal classification: reason=%d native=%d %s', [Ord(E.Reason), E.NativeError, E.Message]));
        Check(E.Outcome = TNetRequestOutcome.NotSent, 'deferred refusal has not sent a request');
        Check(E.NativeError = {$IFDEF MSWINDOWS}10061{$ELSE}111{$ENDIF}, 'deferred refusal native errno');
      end;
    end;
    Request := Client.BeginGet(ParamStr(2));
    for var I := 1 to 2 do
      try
        THTTPClient.EndAsyncHTTP(Request);
        Check(False, 'async refused connection returned');
      except
        on E: ENetException do begin
          Check(E.Reason = TNetFailureReason.ConnectionRefused, 'async refusal classification');
          Check(E.NativeError = {$IFDEF MSWINDOWS}10061{$ELSE}111{$ENDIF}, 'async refusal native errno');
          E.Message := 'Changed by the caller';
        end;
      end;
    Good(Client, ParamStr(1));
    Client.ConnectionTimeout := 250;
    Started := GetTickCount64;
    try
      Client.Get(ParamStr(3));
      Check(False, 'pending connect must time out');
    except
      on E: ENetException do begin
        Check(E.Reason = TNetFailureReason.Timeout, 'pending connect timeout classification');
        Check(E.Outcome = TNetRequestOutcome.NotSent, 'timed out connect has not sent a request');
      end;
    end;
    Check((GetTickCount64 - Started >= 200) and (GetTickCount64 - Started < 1800), 'pending connect timeout is bounded');
    Client.ConnectionTimeout := 5000;
    Request := Client.BeginGet(ParamStr(3));
    Sleep(100);
    Started := GetTickCount64;
    Check(not Request.IsCompleted, 'connect is still pending before cancellation');
    Check(Request.Cancel, 'pending connect accepts cancellation');
    try
      THTTPClient.EndAsyncHTTP(Request);
      Check(False, 'cancelled connect returned');
    except
      on E: ENetException do begin
        Check(E.Reason = TNetFailureReason.Cancelled, 'pending connect cancellation classification');
        Check(E.Outcome = TNetRequestOutcome.NotSent, 'cancelled connect has not sent a request');
      end;
    end;
    Check(GetTickCount64 - Started < 1500, 'pending connect cancellation is bounded');
    Good(Client, ParamStr(1));
    Writeln('HTTP_CONNECT_CONTRACT_PASS');
  finally
    Client.Free;
  end;
end.
