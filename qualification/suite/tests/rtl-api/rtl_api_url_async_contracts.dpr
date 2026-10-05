program rtl_api_url_async_contracts;
{$mode delphi}{$H+}{$codepage utf8}
{$modeswitch anonymousfunctions}{$modeswitch functionreferences}
uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes, Types, System.Net.URLClient;

procedure Check(Value: Boolean; const Message: string);
begin
  If not Value then
    raise Exception.Create(Message);
end;

var
  Entered, ReleaseRequest, CallbackDone: TMultiWaitEvent;
  ActiveWorkers: Longint;

type
  TReply = class(TInterfacedObject, IURLResponse)
  private
    FContent: TStringStream;
  public
    constructor Create(const Text: string);
    destructor Destroy; override;
    function GetHeaders: TNetHeaders;
    function GetMimeType: string;
    function GetContentStream: TStream;
    function ContentAsString(const Encoding: TEncoding = nil): string;
    function GetAsyncResult: IAsyncResult;
  end;
  TLocalClient = class(TURLClient)
  protected
    function DoExecute(const Request: IURLRequest; Content: TStream;
      const Headers: TNetHeaders): IURLResponse; override;
  end;
  TCompletion = class
    Text: string;
    Calls: Integer;
    procedure Complete(const Async: IAsyncResult);
  end;

constructor TReply.Create(const Text: string);
begin
  inherited Create;
  FContent := TStringStream.Create(Text, TEncoding.UTF8);
end;

destructor TReply.Destroy;
begin
  FContent.Free;
  inherited Destroy;
end;

function TReply.GetHeaders: TNetHeaders;
begin
  Result := [TNetHeader.Create('Content-Type', 'text/plain')];
end;

function TReply.GetMimeType: string;
begin
  Result := 'text/plain';
end;

function TReply.GetContentStream: TStream;
begin
  Result := FContent;
end;

function TReply.ContentAsString(const Encoding: TEncoding): string;
begin
  Result := FContent.DataString;
end;

function TReply.GetAsyncResult: IAsyncResult;
begin
  Result := nil;
end;

function TLocalClient.DoExecute(const Request: IURLRequest; Content: TStream;
  const Headers: TNetHeaders): IURLResponse;
begin
  InterlockedIncrement(ActiveWorkers);
  try
    Entered.SetEvent;
    while ReleaseRequest.WaitFor(10) <> wrSignaled do
      If Request.IsCancelled then
        raise ENetURIRequestException.Create('cancelled');
    If Request.URL.Path = '/error' then
      raise EConvertError.Create('expected worker error');
    Result := TReply.Create(Request.MethodString + ' ' + Request.URL.Path + ' ' + UserAgent);
  finally
    InterlockedDecrement(ActiveWorkers);
  end;
end;

procedure TCompletion.Complete(const Async: IAsyncResult);
begin
  Text := TURLClient.EndAsyncURL(Async).ContentAsString;
  Inc(Calls);
  CallbackDone.SetEvent;
end;

var
  Client: TURLClient;
  Completion: TCompletion;
  Async: IAsyncResult;
  Response: IURLResponse;
  URI: TURI;
  Index: Integer;
  Selected: TMultiWaitEvent;
  Callback: TAsyncCallback;
  SavedContext: TObject;
  Storage: TCredentialsStorage;
begin
  URI := TURI.Create('https://example.com/a%2Fb//c/?q=x%2Fy&n=1');
  Check(URI.ToString = 'https://example.com/a%2Fb//c/?q=x%2Fy&n=1', 'URI changes escaped path or slash multiplicity');
  URI.ParameterByName['q'] := 'Привет & /';
  Check(URI.ParameterByName['q'] = 'Привет & /', 'URI Unicode parameter');
  Check(Pos('q=%D0', URI.ToString) > 0, 'URI UTF-8 escaping');
  Check(TURI.PathRelativeToAbs('../d', TURI.Create('https://example.com/a/b')) = 'https://example.com/d', 'relative URI');
  Storage := TCredentialsStorage.Create;
  try
    Storage.AddCredential(TCredentialsStorage.TCredential.Create(TAuthTargetType.Server, 'r',
      'https://example.com/private', 'u', 'p'));
    Check(not Storage.FindAccurateCredential(TAuthTargetType.Server, 'r', 'https://example.com/private/x').IsEmpty, 'credential scope');
    Check(Storage.FindAccurateCredential(TAuthTargetType.Server, 'r', 'https://example.com/private-other').IsEmpty, 'credential path boundary');
    Check(Storage.FindAccurateCredential(TAuthTargetType.Server, 'r', 'https://other.example.com/private').IsEmpty, 'credential origin isolation');
  finally
    Storage.Free;
  end;
  Entered := TMultiWaitEvent.Create;
  ReleaseRequest := TMultiWaitEvent.Create;
  CallbackDone := TMultiWaitEvent.Create;
  Completion := TCompletion.Create;
  TURLSchemes.RegisterURLClientScheme(TLocalClient, 'test');
  try
    Check(TMultiWaitEvent.WaitForAny([Entered, ReleaseRequest], Index, 0) = wrTimeout, 'wait any timeout');
    ReleaseRequest.SetEvent;
    Check((TMultiWaitEvent.WaitForAny([Entered, ReleaseRequest], Index, 0) = wrSignaled) and (Index = 1), 'wait any index');
    Check((TMultiWaitEvent.WaitForAny([Entered, ReleaseRequest], Selected, 0) = wrSignaled) and
      (Selected = ReleaseRequest), 'wait any event');
    Check(TMultiWaitEvent.WaitForAll([Entered, ReleaseRequest], 0) = wrTimeout, 'wait all not prematurely signaled');
    Entered.SetEvent;
    Check(TMultiWaitEvent.WaitForAll([Entered, ReleaseRequest], 0) = wrSignaled, 'wait all');
    Client := TURLClient.Create;
    try
      Client.UserAgent := 'snapshot';
      SavedContext := Client;
      ReleaseRequest.ResetEvent;
      Async := Client.BeginExecute(Completion.Complete, 'POST', 'test://local/echo');
      Check(Async.AsyncContext = SavedContext, 'async context');
      Check(not Async.CompletedSynchronously, 'async execution flag');
      Client.Free;
      Client := nil;
      ReleaseRequest.SetEvent;
      Check(Async.AsyncWaitEvent.WaitFor(3000) = wrSignaled, 'async event');
      Check(CallbackDone.WaitFor(3000) = wrSignaled, 'callback can EndAsync on its own worker');
      Check((Completion.Calls = 1) and (Completion.Text = 'POST /echo snapshot'), 'callback/settings snapshot');
      Response := TURLClient.EndAsyncURL(Async);
      Async := nil;
      Check(Response.AsyncResult.IsCompleted and (Response.ContentAsString = Completion.Text), 'response retains completion state');
      Response := nil;
    finally
      Client.Free;
    end;
    Client := TURLClient.Create;
    try
      Entered.ResetEvent;
      ReleaseRequest.ResetEvent;
      Async := Client.BeginExecute('GET', 'test://local/wait');
      Check(Entered.WaitFor(3000) = wrSignaled, 'cancel worker entered');
      Check(Async.Cancel and not Async.Cancel, 'cancel once');
      Async := nil;
      Check(InterlockedCompareExchange(ActiveWorkers, 0, 0) = 0, 'last result release waits until borrowed state is no longer used');
      ReleaseRequest.SetEvent;
      Async := Client.BeginExecute('GET', 'test://local/error');
      for Index := 1 to 2 do
        try
          Response := TURLClient.EndAsyncURL(Async);
          Check(False, 'worker exception lost');
        except
          on E: EConvertError do
            Check(E.Message = 'expected worker error', 'worker exception preserved on repeated EndAsync');
        end;
      Async := nil;
      CallbackDone.ResetEvent;
      Callback := procedure(const Value: IAsyncResult)
        begin
          Check(TURLClient.EndAsyncURL(Value).ContentAsString = 'PUT /closure ', 'anonymous callback result');
          CallbackDone.SetEvent;
          Sleep(50);
          InterlockedIncrement(Completion.Calls);
        end;
      Async := Client.BeginExecute(Callback, 'PUT', TURI.Create('test://local/closure'));
      Check(CallbackDone.WaitFor(3000) = wrSignaled, 'anonymous callback');
      Async := nil;
      Check(Completion.Calls = 2, 'last result release waits for callback code to finish');
      Callback := nil;
    finally
      Client.Free;
    end;
  finally
    TURLSchemes.UnRegisterURLClientScheme('test');
    Completion.Free;
    Entered.Free;
    ReleaseRequest.Free;
    CallbackDone.Free;
  end;
  WriteLn('RTL_API_URL_ASYNC_CONTRACTS_OK');
end.
