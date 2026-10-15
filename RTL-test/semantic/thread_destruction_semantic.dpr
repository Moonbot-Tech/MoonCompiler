program thread_destruction_semantic;
{$APPTYPE CONSOLE}
uses
  {$ifdef UNIX}cthreads,{$endif}
  {$ifdef MSWINDOWS}Windows,{$endif}
  SysUtils, Classes;

var
  DestroyCalls, Finalized, Executed, Callbacks, Queued: LongInt;
  DestroyThread: NativeUInt;

procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then begin
    WriteLn('FAIL: ', Text);
    Halt(1);
  end;
end;

type
  TProbe = class(TThread)
  protected
    procedure Execute; override;
  public
    destructor Destroy; override;
    procedure FreeInstance; override;
  end;
  TBroken = class(TProbe)
    constructor Create(Phase: Integer);
  end;
  TStartOnTerminate = class(TProbe)
  protected
    procedure TerminatedSet; override;
  end;
  TReceiver = class
    procedure Completed(Sender: TObject);
    procedure Ping;
  end;

procedure TProbe.Execute;
begin
  InterlockedIncrement(Executed);
  ReturnValue := 17;
end;

destructor TProbe.Destroy;
begin
  Check(InterlockedIncrement(DestroyCalls) = 1, 'duplicate destructor');
  DestroyThread := GetCurrentThreadID;
  inherited Destroy;
end;

procedure TProbe.FreeInstance;
begin
  inherited FreeInstance;
  InterlockedIncrement(Finalized);
end;

constructor TBroken.Create(Phase: Integer);
begin
  If Phase <> 0 then begin
    inherited Create(Phase = 1);
    FreeOnTerminate := True;
  end;
  raise Exception.Create('constructor failure');
end;

procedure TStartOnTerminate.TerminatedSet;
begin
  Check(not FreeOnTerminate, 'destructor ownership before virtual termination hook');
  Start;
end;

procedure TReceiver.Completed(Sender: TObject);
begin
  Check(GetCurrentThreadID = MainThreadID, 'OnTerminate thread');
  Inc(Callbacks);
end;

procedure TReceiver.Ping;
begin
  Inc(Queued);
end;

procedure Reset;
begin
  DestroyCalls := 0;
  Finalized := 0;
  Executed := 0;
  Callbacks := 0;
  DestroyThread := 0;
end;

procedure CheckQueue;
var Receiver: TReceiver;
begin
  Receiver := TReceiver.Create;
  try
    Queued := 0;
    TThread.ForceQueue(nil, Receiver.Ping);
    Check(Queued = 0, 'ForceQueue ran immediately');
    CheckSynchronize;
    Check(Queued = 1, 'queue damaged by thread destruction');
  finally
    Receiver.Free;
  end;
end;

procedure CancelSuspended(AutoFree, Notify: Boolean);
var Worker: TProbe; Receiver: TReceiver;
begin
  Reset;
  Receiver := TReceiver.Create;
  try
    Worker := TProbe.Create(True);
    Worker.FreeOnTerminate := AutoFree;
    If Notify then Worker.OnTerminate := Receiver.Completed;
    Worker.Free;
    Check((DestroyCalls = 1) and (Finalized = 1), 'cancelled object lifetime');
    Check(DestroyThread = GetCurrentThreadID, 'owner must destroy cancelled object');
    Check(Executed = 0, 'cancelled Execute ran');
    Check(Callbacks = Ord(Notify), 'cancelled OnTerminate');
  finally
    Receiver.Free;
  end;
  CheckQueue;
end;

procedure ConstructorFailure(Phase: Integer);
var Failed: Boolean;
begin
  Reset;
  Failed := False;
  try
    TBroken.Create(Phase);
  except
    on E: Exception do Failed := E.Message = 'constructor failure';
  end;
  Check(Failed, 'constructor exception');
  Check((DestroyCalls = 1) and (Finalized = 1) and (Executed = 0),
    'constructor cleanup phase=' + IntToStr(Phase) + ' destroyed=' + IntToStr(DestroyCalls) +
    'finalized=' + IntToStr(Finalized) + ' executed=' + IntToStr(Executed));
  Check(DestroyThread = GetCurrentThreadID, 'constructor cleanup owner');
  CheckQueue;
end;

procedure TerminationHook;
var Worker: TStartOnTerminate;
begin
  Reset;
  Worker := TStartOnTerminate.Create(True);
  Worker.FreeOnTerminate := True;
  Worker.Free;
  Check((DestroyCalls = 1) and (Finalized = 1) and (Executed = 0), 'termination hook lifetime');
  CheckQueue;
end;

procedure Started(AutoFree, Suspended: Boolean);
var Worker: TProbe; Receiver: TReceiver; Deadline: UInt64;
begin
  Reset;
  Receiver := TReceiver.Create;
  try
    { Self-free ownership must be installed before Start. }
    Worker := TProbe.Create(Suspended);
    If AutoFree then begin
      Worker.FreeOnTerminate := True;
      Worker.OnTerminate := Receiver.Completed;
      Worker.Start;
      Deadline := GetTickCount64 + 5000;
      While InterlockedCompareExchange(Finalized, 0, 0) = 0 do begin
        Check(GetTickCount64 < Deadline, 'automatic destruction timeout');
        CheckSynchronize(1);
      end;
      Check(Callbacks = 1, 'automatic OnTerminate');
      Check(DestroyThread <> GetCurrentThreadID, 'automatic destructor thread');
      { Worker has been destroyed: never read or Free it here. }
    end else begin
      If Suspended then Worker.Start;
      Check(Worker.WaitFor = 17, 'owned completion');
      Check(Worker.WaitFor = 17, 'repeat owned wait');
      Check(DestroyCalls = 0, 'owned thread freed itself');
      Worker.Free;
      Check(DestroyThread = GetCurrentThreadID, 'owned destructor thread');
    end;
    Check((Executed = 1) and (DestroyCalls = 1) and (Finalized = 1), 'started object lifetime');
  finally
    Receiver.Free;
  end;
  CheckQueue;
end;

var I: Integer;
begin
  for I := 1 to 16 do begin
    CancelSuspended(False, False);
    CancelSuspended(True, False);
    CancelSuspended(False, True);
    CancelSuspended(True, True);
    ConstructorFailure(0);
    ConstructorFailure(1);
    ConstructorFailure(2);
    TerminationHook;
    Started(False, False);
    Started(False, True);
    Started(True, True);
  end;
  WriteLn('THREAD_DESTRUCTION_PASS');
end.
