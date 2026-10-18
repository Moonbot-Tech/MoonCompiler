program current_thread_handle_contract;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, Windows;

function NativeCreate(Attributes: Pointer; StackSize: NativeUInt; Entry, Arg: Pointer;
  Flags: DWORD; var Id: DWORD): THandle; stdcall; external 'kernel32' name 'CreateThread';
function NativeThreadId(Handle: THandle): DWORD; stdcall; external 'kernel32' name 'GetThreadId';

type
  TNativeState = record
    Ready, Proceed: THandle;
    Wrapper: TThread;
    Id: DWORD;
    Observed: Integer;
    Cached, Continued: Boolean;
  end;
  PNativeState = ^TNativeState;
  TOrdinary = class(TThread)
    SelfMatches: Boolean;
    SeenPriority, RestoredPriority, Payload, Cleanup, Response: Integer;
    procedure Execute; override;
  end;
  TRemote = class(TThread)
    Target: TThread;
    SeenId: TThreadID;
    OwnBefore, OwnAfter: Integer;
    procedure Execute; override;
  end;

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;

procedure TOrdinary.Execute;
begin
  SelfMatches := TThread.CurrentThread = Self;
  SeenPriority := GetThreadPriority(Windows.GetCurrentThread);
  try
    Payload := 42;
  finally
    Priority := tpNormal;
    Cleanup := Payload + 1;
  end;
  Response := Cleanup * 2;
  RestoredPriority := GetThreadPriority(Windows.GetCurrentThread);
end;

procedure TRemote.Execute;
begin
  OwnBefore := GetThreadPriority(Windows.GetCurrentThread);
  SeenId := NativeThreadId(Target.Handle);
  Target.Priority := tpLower;
  OwnAfter := GetThreadPriority(Windows.GetCurrentThread);
end;

function NativeEntry(Arg: Pointer): DWORD; stdcall;
var
  State: PNativeState;
begin
  State := Arg;
  State.Id := GetCurrentThreadId;
  State.Wrapper := TThread.CurrentThread;
  State.Cached := TThread.CurrentThread = State.Wrapper;
  SetEvent(State.Ready);
  If WaitForSingleObject(State.Proceed, 5000) <> WAIT_OBJECT_0 then begin
    Result := 2;
    Exit;
  end;
  State.Observed := GetThreadPriority(Windows.GetCurrentThread);
  State.Continued := True;
  Result := 0;
end;

procedure MainAndRemote;
var
  Main: TThread;
  NativeBefore: Integer;
  Remote: TRemote;
begin
  Main := TThread.CurrentThread;
  Check(TThread.CurrentThread = Main, 'main wrapper is cached');
  Check(Main.Handle <> 0, 'main wrapper has a handle');
  Check(NativeThreadId(Main.Handle) = GetCurrentThreadId, 'main handle identifies the represented thread');
  NativeBefore := GetThreadPriority(Windows.GetCurrentThread);
  try
    Main.Priority := tpLower;
    Check(GetThreadPriority(Windows.GetCurrentThread) = THREAD_PRIORITY_BELOW_NORMAL, 'main setter reaches the OS');
    Check(Main.Priority = tpLower, 'main getter reads native priority');
    SetThreadPriority(Windows.GetCurrentThread, THREAD_PRIORITY_NORMAL);
    Remote := TRemote.Create(True);
    try
      Remote.Target := Main;
      Remote.Start;
      Check(Remote.WaitFor(5000), 'remote thread completes');
      Check(Remote.FatalException = nil, 'remote thread has no exception');
      Check(Remote.SeenId = Main.ThreadID, 'saved main wrapper still identifies main from another thread');
      Check(GetThreadPriority(Windows.GetCurrentThread) = THREAD_PRIORITY_BELOW_NORMAL, 'remote setter changes main');
      Check(Remote.OwnBefore = Remote.OwnAfter, 'remote setter leaves its calling thread priority alone');
    finally
      Remote.Free;
    end;
  finally
    SetThreadPriority(Windows.GetCurrentThread, NativeBefore);
  end;
end;

procedure NativeLifetime(FreeWhileAlive: Boolean);
var
  State: TNativeState;
  Native, Wrapped: THandle;
  Id, Code, Flags: DWORD;
  MainPriority: Integer;
begin
  State := Default(TNativeState);
  State.Ready := CreateEvent(nil, True, False, nil);
  State.Proceed := CreateEvent(nil, True, False, nil);
  Check((State.Ready <> 0) and (State.Proceed <> 0), 'native test events');
  Native := 0;
  MainPriority := GetThreadPriority(Windows.GetCurrentThread);
  try
    Native := NativeCreate(nil, 0, @NativeEntry, @State, 0, Id);
    Check(Native <> 0, 'native external thread starts');
    Check(WaitForSingleObject(State.Ready, 5000) = WAIT_OBJECT_0, 'native wrapper published');
    Check(State.Cached, 'native wrapper is cached');
    Check(State.Wrapper.ThreadID = State.Id, 'native wrapper ID');
    Wrapped := State.Wrapper.Handle;
    Check((Wrapped <> 0) and (Wrapped <> Native), 'native wrapper owns an independent real handle');
    Check(NativeThreadId(Wrapped) = Id, 'saved native handle identifies external thread');
    State.Wrapper.Priority := tpLower;
    Check(State.Wrapper.Priority = tpLower, 'remote external getter reads target');
    Check(GetThreadPriority(Windows.GetCurrentThread) = MainPriority, 'external setter leaves caller priority alone');
    If FreeWhileAlive then begin
      { This is a disposal/ownership probe. NativeEntry deliberately does not reacquire CurrentThread after Free. }
      State.Wrapper.Free;
      State.Wrapper := nil;
      SetLastError(0);
      Check(not GetHandleInformation(Wrapped, Flags) and (GetLastError = ERROR_INVALID_HANDLE), 'live wrapper destruction closes its owned handle');
      Check(WaitForSingleObject(Native, 0) = WAIT_TIMEOUT, 'wrapper destruction does not terminate an external thread');
    end;
    SetEvent(State.Proceed);
    Check(WaitForSingleObject(Native, 5000) = WAIT_OBJECT_0, 'native thread exits');
    Check(GetExitCodeThread(Native, Code) and (Code = 0), 'native thread completed normally');
    Check(State.Continued and (State.Observed = THREAD_PRIORITY_BELOW_NORMAL), 'external work continues with target priority');
    If not FreeWhileAlive then begin
      Check(WaitForSingleObject(Wrapped, 0) = WAIT_OBJECT_0, 'saved wrapper handle remains valid after OS thread exit');
      State.Wrapper.Free;
      State.Wrapper := nil;
      SetLastError(0);
      Check(not GetHandleInformation(Wrapped, Flags) and (GetLastError = ERROR_INVALID_HANDLE), 'terminated wrapper destruction closes its owned handle');
    end;
  finally
    SetEvent(State.Proceed);
    If Native <> 0 then begin
      WaitForSingleObject(Native, 5000);
      CloseHandle(Native);
    end;
    State.Wrapper.Free;
    CloseHandle(State.Ready);
    CloseHandle(State.Proceed);
  end;
end;

procedure OrdinaryThreads;
var
  Worker: TOrdinary;
begin
  for var I := 1 to 16 do begin
    Worker := TOrdinary.Create(True);
    try
      Worker.Priority := tpLower;
      Check(Worker.Priority = tpLower, 'ordinary suspended thread priority');
      Worker.Start;
      Check(Worker.WaitFor(5000), 'ordinary thread completes');
      Check(Worker.FatalException = nil, 'ordinary thread remains valid');
      Check(Worker.SelfMatches, 'ordinary CurrentThread returns Self');
      Check(Worker.SeenPriority = THREAD_PRIORITY_BELOW_NORMAL, 'ordinary priority reaches Execute');
      Check((Worker.RestoredPriority = THREAD_PRIORITY_NORMAL) and (Worker.Priority = tpNormal), 'ordinary priority restoration');
      Check((Worker.Payload = 42) and (Worker.Cleanup = 43) and (Worker.Response = 86), 'ordinary finally cleanup remains intact');
    finally
      Worker.Free;
    end;
  end;
end;

begin
  MainAndRemote;
  for var I := 1 to 8 do begin
    NativeLifetime(False);
    NativeLifetime(True);
  end;
  OrdinaryThreads;
  Writeln('CURRENT_THREAD_HANDLE_CONTRACT_PASS');
end.
