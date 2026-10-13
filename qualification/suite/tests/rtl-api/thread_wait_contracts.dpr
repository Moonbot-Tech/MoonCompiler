program thread_wait_contracts;
{$mode delphiunicode}
{$APPTYPE CONSOLE}
uses {$ifdef UNIX}cthreads, BaseUnix,{$else}Windows,{$endif} Classes, SysUtils, Dynlibs;

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then begin
    WriteLn('FAIL: ',Text);
    Halt(1);
  end;
end;

type
  TAction = (aHeld, aImmediate, aSync, aSelf, aNativeTLS);
  TWorker = class(TThread)
  public
    Gate, Entered: PRTLEvent;
    Action: TAction;
    Code: Integer;
    Calls: Integer;
    SelfRejected: Boolean;
    constructor Create(AAction: TAction; ACode: Integer = 42);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Callback;
    procedure OnDone(Sender: TObject);
  end;
  TReleaser = class(TThread)
    Target: TWorker;
    procedure Execute; override;
  end;
  TWaiter = class(TThread)
    Target: TWorker;
    TimedOut, Joined: Boolean;
    procedure Execute; override;
  end;
{$ifdef LINUX}
type
  TNativeAction = procedure; cdecl;
  TNativeState = function: LongInt; cdecl;
var
  TLSLibrary: TLibHandle;
  TLSArm, TLSRelease: TNativeAction;
  TLSState: TNativeState;
{$endif}

constructor TWorker.Create(AAction: TAction; ACode: Integer);
begin
  inherited Create(true);
  Action:=AAction;
  Code:=ACode;
  Gate:=RTLEventCreate;
  Entered:=RTLEventCreate;
end;

destructor TWorker.Destroy;
begin
  inherited Destroy;
  RTLEventDestroy(Gate);
  RTLEventDestroy(Entered);
end;

procedure TWorker.Callback;
begin
  Inc(Calls);
end;

procedure TWorker.OnDone(Sender: TObject);
begin
  Inc(Calls);
end;

procedure TWorker.Execute;
begin
  ReturnValue:=Code;
  RTLEventSetEvent(Entered);
  case Action of
    aHeld: RTLEventWaitFor(Gate);
    aSync: Synchronize(Callback);
    aSelf:
      try
        WaitFor(0);
      except
        on E: EThread do SelfRejected:=true;
      end;
{$ifdef LINUX}
    aNativeTLS: TLSArm;
{$endif}
  end;
end;

procedure TReleaser.Execute;
begin
  Sleep(20);
  RTLEventSetEvent(Target.Gate);
end;

procedure TWaiter.Execute;
begin
  TimedOut:=not Target.WaitFor(10);
  RTLEventSetEvent(Target.Gate);
  Joined:=Target.WaitFor(1000);
end;

procedure ObjectContracts;
var W, Other: TWorker; R: TReleaser; V: TWaiter; I: Integer; Start: QWord; Failed: Boolean;
begin
  W:=TWorker.Create(aHeld);
  try
    Check(not W.WaitFor(0),'suspended poll');
    W.Start;
    RTLEventWaitFor(W.Entered);
    Check(not W.WaitFor(0),'running poll');
    Start:=GetTickCount64;
    Check(not W.WaitFor(30),'finite timeout');
    Check(GetTickCount64-Start>=10,'timeout returned too early');
    Check(GetTickCount64-Start<1000,'timeout ignored');
    R:=TReleaser.Create(true);
    try
      R.Target:=W;
      R.Start;
      Check(W.WaitFor(1000),'completion during deadline');
      R.WaitFor;
    finally
      R.Free;
    end;
    Check(W.WaitFor=42,'parameterless after timed join');
    Check(W.WaitFor(0),'repeat timed join');
    { A live new pthread may reuse W's consumed handle. The old object must
      answer its cached result, never join or inspect the new native thread. }
    for I:=1 to 32 do begin
      Other:=TWorker.Create(aHeld);
      try
        Other.Start;
        Check(W.WaitFor(0),'repeat after native handle reuse');
        RTLEventSetEvent(Other.Gate);
        Check(Other.WaitFor(1000),'new thread join');
      finally
        Other.Free;
      end;
    end;
  finally
    W.Free;
  end;
  for I:=0 to 2 do begin
    case I of
      0: W:=TWorker.Create(aImmediate,0);
      1: W:=TWorker.Create(aImmediate,-1);
      else W:=TWorker.Create(aImmediate,258);
    end;
    try
      W.Start;
      Check(W.WaitFor(High(Cardinal)),'infinite timed overload');
      Check(W.WaitFor=W.Code,'exit code is not wait status');
    finally
      W.Free;
    end;
  end;
  W:=TWorker.Create(aImmediate,57);
  W.Start;
  Check(W.WaitFor=57,'ordinary join');
  Check(W.WaitFor(0),'timed after ordinary join');
  W.Free;

  W:=TWorker.Create(aHeld);
  V:=TWaiter.Create(true);
  V.Target:=W;
  W.Start;
  V.Start;
  V.WaitFor;
  Check(V.TimedOut and V.Joined,'wait from another worker');
  V.Free;
  Check(W.WaitFor(0),'join ownership transferred after waiter finished');
  W.Free;

  W:=TWorker.Create(aSelf);
  W.Start;
  Check(W.WaitFor(1000),'self-check worker completion');
  Check(W.SelfRejected,'self wait must be an error, not timeout');
  W.Free;
  Failed:=false;
  try
    TThread.CurrentThread.WaitFor(0);
  except
    on E: EThread do Failed:=true;
  end;
  Check(Failed,'borrowed external thread must be rejected');
  W:=TWorker.Create(aHeld);
  W.FreeOnTerminate:=true;
  Failed:=false;
  try
    W.WaitFor(0);
  except
    on E: EThread do Failed:=true;
  end;
  Check(Failed,'free-on-terminate wait must be rejected');
  W.FreeOnTerminate:=false;
  W.Start;
  RTLEventSetEvent(W.Gate);
  W.WaitFor;
  W.Free;

  W:=TWorker.Create(aSync);
  W.OnTerminate:=W.OnDone;
  W.Start;
  RTLEventWaitFor(W.Entered);
  Check(not W.WaitFor(30),'bounded wait must not dispatch Synchronize');
  Check(W.Calls=0,'callback dispatched by bounded wait');
  Check(W.WaitFor=42,'ordinary wait must dispatch Synchronize and OnTerminate');
  Check(W.Calls=2,'callback count');
  Check(W.WaitFor(0),'joined synchronized thread');
  W.Free;
end;

var RawGate: PRTLEvent;
function RawWorker(P: Pointer): PtrInt;
begin
  RTLEventWaitFor(RawGate);
  Result:=PtrInt(P);
end;

var FaultStatus: TThreadWaitResult = twrError; FaultError: LongInt = 1234;
function FailedWait(H: TThreadID; TimeoutMs: Cardinal; out Code: DWord;
  out NativeError: LongInt): TThreadWaitResult;
begin
  Code:=0;
  NativeError:=FaultError;
  Result:=FaultStatus;
end;

procedure ManagerContracts;
var W: TWorker; TM, Saved: TThreadManager; Failed: Boolean; I: Integer;
begin
  W:=TWorker.Create(aHeld);
  W.Start;
  GetThreadManager(Saved);
  TM:=Saved;
  TM.WaitForThreadTerminateEx:=@FailedWait;
  SetThreadManager(TM);
  Failed:=false;
  try
    try
      W.WaitFor(0);
    except
      on E: EThread do Failed:=Pos('1234',E.Message)>0;
    end;
  finally
    SetThreadManager(Saved);
  end;
  Check(Failed,'native error is not timeout');
  Check(not W.WaitFor(0),'error must not mark thread reaped');
  RTLEventSetEvent(W.Gate);
{$ifdef LINUX}
  { A provider's error-zero or timeout-zero is not an absent provider. }
  for I:=0 to 1 do begin
    FaultError:=0;
    If I=0 then FaultStatus:=twrError else FaultStatus:=twrTimeout;
    SetThreadManager(TM);
    Failed:=false;
    try
      try
        W.WaitFor;
      except
        on E: EThread do Failed:=true;
      end;
    finally
      SetThreadManager(Saved);
    end;
    Check(Failed,'ordinary wait must not mask a present provider failure');
  end;
{$endif}
  W.WaitFor;
  W.Free;
  W:=TWorker.Create(aImmediate,63);
  W.Start;
  TM:=Saved;
  TM.WaitForThreadTerminateEx:=nil;
  SetThreadManager(TM);
  try
    Check(W.WaitFor=63,'old custom manager ordinary WaitFor preserved');
  finally
    SetThreadManager(Saved);
  end;
  W.Free;
end;

procedure NativeContracts;
var H: TThreadID; Code: DWord; Err: LongInt; TM, Saved: TThreadManager;
begin
  RawGate:=RTLEventCreate;
  H:=BeginThread(@RawWorker,Pointer(PtrUInt(High(DWord))));
  Check(H<>0,'BeginThread');
  Check(WaitForThreadTerminateEx(H,0,Code,Err)=twrTimeout,'raw poll');
  Check(WaitForThreadTerminateEx(H,20,Code,Err)=twrTimeout,'raw deadline');
{$ifdef LINUX}
  Check(WaitForThreadTerminate(H,20)=High(DWord),'legacy timeout value');
  Check(fpGetErrno=ESysETIMEDOUT,'legacy timeout errno');
{$endif}
  RTLEventSetEvent(RawGate);
  Check(WaitForThreadTerminateEx(H,1000,Code,Err)=twrSignaled,'raw completion');
  Check((Code=High(DWord)) and (Err=0),'all-ones exit code is a success');
  CloseThread(H);
  Check(WaitForThreadTerminateEx(0,0,Code,Err)=twrError,'null handle error');
  Check(Err<>0,'native error is available');
{$ifdef MSWINDOWS}
  H:=Windows.CreateEvent(nil,true,true,nil);
  Check(H<>0,'signaled event fixture');
  Check(WaitForThreadTerminateEx(H,0,Code,Err)=twrError,'signaled non-thread handle is not thread completion');
  Check(Err<>0,'GetExitCodeThread failure preserved');
  Windows.CloseHandle(H);
{$endif}
  GetThreadManager(Saved);
  TM:=Saved;
  TM.WaitForThreadTerminateEx:=nil;
  SetThreadManager(TM);
  try
    Check(WaitForThreadTerminateEx(0,0,Code,Err)=twrError,'custom manager without provider');
    Check((Err=0) and (Code=0),'unsupported provider outputs initialized');
  finally
    SetThreadManager(Saved);
  end;
  for Code:=0 to 1 do begin
    H:=BeginThread(@RawWorker,Pointer(57));
    RTLEventSetEvent(RawGate);
{$ifdef LINUX}
    If Code=0 then
      Check(WaitForThreadTerminate(H,0)=57,'legacy zero means infinite')
    else
      Check(WaitForThreadTerminate(H,-1)=57,'legacy negative means infinite');
    Check(fpGetErrno=0,'legacy success clears errno');
{$else}
    Check(WaitForThreadTerminate(H,0)=0,'Windows legacy wait status');
{$endif}
    CloseThread(H);
  end;
  RTLEventDestroy(RawGate);
end;

{$ifdef LINUX}
procedure TLSContracts;
var W: TWorker; Start: QWord;
begin
  TLSLibrary:=LoadLibrary(AnsiString(GetEnvironmentVariable('MOON_WAIT_TLS_HELPER')));
  Check(TLSLibrary<>0,'native TLS helper required');
  TLSArm:=TNativeAction(GetProcedureAddress(TLSLibrary,'wait_tls_arm'));
  TLSRelease:=TNativeAction(GetProcedureAddress(TLSLibrary,'wait_tls_release'));
  TLSState:=TNativeState(GetProcedureAddress(TLSLibrary,'wait_tls_state'));
  Check(Assigned(TLSArm) and Assigned(TLSRelease) and Assigned(TLSState),'native TLS exports');
  W:=TWorker.Create(aNativeTLS);
  try
    W.Start;
    Start:=GetTickCount64;
    while TLSState=0 do begin
      Check(GetTickCount64-Start<1000,'native TLS destructor entered');
      Sleep(1);
    end;
    Check(W.Finished,'Pascal Finished precedes native TLS destructor');
    Check(not W.WaitFor(0),'Finished is not native completion');
    Check(not W.WaitFor(30),'native TLS destructor is inside timeout');
    TLSRelease;
    Check(W.WaitFor(1000),'native TLS destructor completed');
    Check(TLSState=2,'join waits for TLS cleanup');
  finally
    W.Free;
    UnloadLibrary(TLSLibrary);
  end;
end;
{$endif}

begin
  try
    ObjectContracts;
    NativeContracts;
    ManagerContracts;
{$ifdef LINUX}
    TLSContracts;
{$endif}
    WriteLn('THREAD_WAIT_CONTRACTS_OK');
  except
    on E: Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
