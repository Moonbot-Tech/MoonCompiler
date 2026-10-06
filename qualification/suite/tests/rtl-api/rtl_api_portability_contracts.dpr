program rtl_api_portability_contracts;
{$APPTYPE CONSOLE}
{$Q+}{$R+}
{$IFDEF FPC}{$CODEPAGE UTF8}{$ENDIF}
uses
  {$IF DEFINED(MSWINDOWS) AND DEFINED(RTL_API_WINDOWS_FIRST)}Winapi.Windows,{$ENDIF}
  System.SysUtils, System.Classes, System.Generics.Defaults,
  System.Generics.Collections, System.Variants, System.SyncObjs, System.Threading
  {$IF DEFINED(MSWINDOWS) AND NOT DEFINED(RTL_API_WINDOWS_FIRST)}, Winapi.Windows{$ENDIF};

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

type
  THighHash = class(TEqualityComparer<Integer>)
    function Equals(const Left, Right: Integer): Boolean; override;
    function GetHashCode(const Value: Integer): Integer; override;
  end;
  TAutoWorker = class(TThread)
    Entered: Boolean;
    procedure Execute; override;
  end;
  TWorker = class(TThread)
    Ready, Finish: TEvent;
    Entered: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;

function THighHash.Equals(const Left, Right: Integer): Boolean;
begin
  Result := Left = Right;
end;

function THighHash.GetHashCode(const Value: Integer): Integer;
begin
  Result := Integer(UInt32($80000000) or UInt32(Value));
end;

constructor TWorker.Create;
begin
  inherited Create(True);
  Ready := TEvent.Create(nil, True, False, '');
  Finish := TEvent.Create(nil, True, False, '');
end;

destructor TWorker.Destroy;
begin
  Terminate;
  Finish.SetEvent;
  WaitFor;
  Finish.Free;
  Ready.Free;
  inherited;
end;

procedure TWorker.Execute;
begin
  Entered := Started;
  Ready.SetEvent;
  Check(Finish.WaitFor(5000) = wrSignaled, 'worker finish timeout');
end;

procedure TAutoWorker.Execute;
begin
  Entered := Started;
  raise Exception.Create('expected worker exception');
end;

procedure CheckThreads;
var W: TWorker; Lock: TCriticalSection; E: TEvent; P: TProc; Value: Integer; Task: ITask; Auto: TAutoWorker; F: TFunc<Integer>; Future: IFuture<Integer>;
  P1: TProc<Integer>; P2: TProc<Integer, Integer>; P3: TProc<Integer, Integer, Integer>;
begin
  Lock := TCriticalSection.Create;
  try
    Lock.Enter;
    Check(Lock.TryEnter, 'recursive critical section');
    Lock.Leave;
    Lock.Leave;
  finally
    Lock.Free;
  end;
  E := TEvent.Create(nil, True, True, '');
  try
    {$IFDEF MSWINDOWS}
    Check(WaitForSingleObject(E.Handle, 0) = WAIT_OBJECT_0, 'event OS handle');
    {$ELSE}
    Check(E.WaitFor(0) = wrSignaled, 'event wait');
    {$ENDIF}
  finally
    E.Free;
  end;
  W := TWorker.Create;
  try
    Check(not W.Started, 'created suspended');
    W.Start;
    Check(W.Ready.WaitFor(5000) = wrSignaled, 'worker ready timeout');
    Check(W.Started and W.Entered, 'started while executing');
    W.Finish.SetEvent;
    W.WaitFor;
    Check(W.Started and W.Finished and (W.FatalException = nil), 'started remains after completion');
  finally
    W.Finish.SetEvent;
    W.Free;
  end;
  W := TWorker.Create;
  try
    W.Terminate;
    W.Start;
    W.WaitFor;
    Check(W.Started and W.Finished and not W.Entered, 'terminated before entry');
  finally
    W.Free;
  end;
  Auto := TAutoWorker.Create(False);
  try
    Auto.WaitFor;
    Check(Auto.Entered and Auto.Started and Auto.Finished and (Auto.FatalException <> nil),
      'automatic start and failed execution retain started state');
  finally
    Auto.Free;
  end;
  Check(TThread.CurrentThread.Started, 'current thread');
  Value := 0;
  P := procedure begin Value := 73; end;
  Task := TTask.Run(P);
  Task.Wait;
  Check(Value = 73, 'typed closure passed to task');
  F := function: Integer begin Result := 91; end;
  Future := TTask.Future<Integer>(F);
  Check(Future.Value = 91, 'typed function passed to future');
  P1 := procedure(A: Integer) begin Value := A; end;
  P2 := procedure(A, B: Integer) begin P1(A + B); end;
  P3 := procedure(A, B, C: Integer) begin P2(A + B, C); end;
  P3(10, 20, 30);
  Check(Value = 60, 'callback family remains visible with Threading');
end;

procedure CheckStrings;
var L: TStringList; S: UnicodeString; A: AnsiString; Count: Integer;
    {$IFDEF FPC}SavedCodePage: TSystemCodePage;{$ENDIF}
begin
  L := TStringList.Create;
  try
    S := '  один,"два,три",''four''''five'',,шесть';
    Count := ExtractStrings([','], [' '], PWideChar(S), L);
    Check((Count = 4) and (L.Count = 4), 'wide token count');
    Check((L[0] = 'один') and (L[1] = '"два,три"') and
      (L[2] = '''four''''five''') and (L[3] = 'шесть'), 'wide exact tokens');
    Check(ExtractStrings([','], [' '], PWideChar(S), nil) = 0, 'nil destination');
    Check(ExtractStrings([','], [], PWideChar(nil), L) = 0, 'nil input');
    S := '';
    Check(ExtractStrings([','], [#0], PWideChar(S), L) = 0, 'terminator is not whitespace');
    {$IFDEF FPC}
    { Additional ANSI overload retained by Moon; Delphi exposes the Unicode form. }
    L.Clear;
    A := 'alpha,beta';
    Check(ExtractStrings([','], [], PAnsiChar(A), L) = 2, 'ANSI count');
    Check((L[0] = 'alpha') and (L[1] = 'beta'), 'ANSI-to-string conversion');
    Check(ExtractStrings([','], [], PAnsiChar(A), nil) = 2, 'ANSI count-only extension');
    SavedCodePage := DefaultSystemCodePage;
    try
      SetMultiByteConversionCodePage(CP_UTF8);
      A := UTF8Encode('один,два');
      L.Clear;
      Check(ExtractStrings([','], [], PAnsiChar(A), L) = 2, 'multibyte ANSI count');
      Check((L[0] = 'один') and (L[1] = 'два'), 'multibyte ANSI content');
    finally
      SetMultiByteConversionCodePage(SavedCodePage);
    end;
    {$ENDIF}
    L.Clear;
    S := 'a' + WideChar($0100) + ',b';
    Check(ExtractStrings([',', #0], [], PWideChar(S), L) = 2, 'wide character is not low-byte separator');
    Check(L[0] = 'a' + WideChar($0100), 'preserve wide code unit');
  finally
    L.Free;
  end;
end;

procedure CheckValues;
var C: IEqualityComparer<Integer>; D: TDictionary<Integer, string>; I: Integer; V: Variant;
begin
  C := THighHash.Create;
  Check(C.GetHashCode(0) = Low(Integer), 'signed comparer contract');
  D := TDictionary<Integer, string>.Create(C);
  try
    for I := 0 to 1023 do
      D.Add(I, IntToStr(I));
    for I := 0 to 1023 do
      Check(D[I] = IntToStr(I), 'rehash preserves high-bit hash');
    for I := 0 to 511 do
      D.Remove(I);
    Check((D.Count = 512) and not D.ContainsKey(0) and D.ContainsKey(1023), 'remove with signed hash');
  finally
    D.Free;
  end;
  V := UInt64(High(UInt64));
  Check((VarType(V) = varUInt64) and (TVarData(V).VUInt64 = High(UInt64)), 'unsigned Variant field');
end;

begin
  CheckStrings;
  CheckValues;
  CheckThreads;
  Writeln('RTL_API_PORTABILITY_PASS');
end.
