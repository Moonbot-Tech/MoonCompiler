program state_futex_probe;
{$mode delphi}{$H+}
uses cthreads, SysUtils, Classes, SyncObjs;

procedure Check(Value: Boolean; const Reason: string);
begin
  if not Value then raise Exception.Create(Reason);
end;

type
  TWorker = class(TThread)
    Event: PEventState;
    Kind, Outcome: LongInt;
    Timeout: Cardinal;
    procedure Execute; override;
  end;
var DestroyStarted, DestroyCompleted: LongInt;

procedure TWorker.Execute;
begin
  if Kind=0 then Outcome:=BasicEventWaitFor(Timeout,Event)
  else begin
    InterlockedExchange(DestroyStarted,1);
    BasicEventDestroy(Event);
    InterlockedExchange(DestroyCompleted,1);
  end;
end;

procedure Await(var Value: LongInt; Wanted: LongInt);
var Started: QWord;
begin
  Started:=GetTickCount64;
  while InterlockedCompareExchange(Value,0,0)<>Wanted do begin
    Check(GetTickCount64-Started<2000,'probe progress deadline');
    Sleep(1);
  end;
end;

procedure RetryBudget(Timeout: Cardinal; RetryError, FinalError: LongInt);
var E: PEventState; Outcome: LongInt;
begin
  E:=BasicEventCreate(nil,False,False,'');
  EventProbeClockReads:=0;
  EventProbeFutexCalls:=0;
  EventProbeDeadlineChanged:=False;
  EventProbeFutexRetries:=3;
  EventProbeFutexRetryError:=RetryError;
  EventProbeWaitError:=FinalError;
  EventProbeSpuriousWaits:=0;
  EventProbeCondWaits:=0;
  Outcome:=BasicEventWaitFor(Timeout,E);
  EventProbeWaitError:=0;
  Check(EventProbeFutexCalls=4,'retry count');
  Check(not EventProbeDeadlineChanged,'retry extended absolute deadline');
  Check(EventProbeClockReads=Ord(Timeout<>High(Cardinal)),'deadline read count');
  if FinalError=110 then Check(Outcome=Ord(wrTimeout),'ETIMEDOUT result')
  else Check(Outcome=Ord(wrError),'real error result');
  Check(EventProbeWaiterCount(E)=0,'retry leaked waiter reference');
  BasicEventSetEvent(E);
  Check(BasicEventWaitFor(0,E)=Ord(wrSignaled),'event after error');
  BasicEventDestroy(E);
end;

procedure UnlockWindow(Manual, DestroyInstead, ResetBeforeRelease: Boolean);
var E: PEventState; Waiter, Destroyer: TWorker;
begin
  E:=BasicEventCreate(nil,Manual,False,'');
  EventProbeWaitTarget:=E;
  EventProbeWaitStage:=0;
  EventProbeWaitRelease:=0;
  Waiter:=TWorker.Create(True);
  Waiter.Event:=E;
  Waiter.Kind:=0;
  if ResetBeforeRelease then Waiter.Timeout:=30 else Waiter.Timeout:=1000;
  Waiter.Start;
  Await(EventProbeWaitStage,1);
  Destroyer:=nil;
  if DestroyInstead then begin
    DestroyStarted:=0;
    DestroyCompleted:=0;
    Destroyer:=TWorker.Create(True);
    Destroyer.Event:=E;
    Destroyer.Kind:=1;
    Destroyer.Start;
    Await(DestroyStarted,1);
    Sleep(20);
    Check(DestroyCompleted=0,'Destroy dropped unlocked waiter reference');
  end else begin
    BasicEventSetEvent(E);
    BasicEventSetEvent(E);
    if ResetBeforeRelease then BasicEventResetEvent(E);
  end;
  InterlockedExchange(EventProbeWaitRelease,1);
  Check(Waiter.WaitFor(500),'lost signal between unlock and futex wait');
  Check(Waiter.FatalException=nil,'unlocked waiter failed');
  if DestroyInstead then begin
    Check(Waiter.Outcome=Ord(wrAbandoned),'destroy in unlock window');
    Check(Destroyer.WaitFor(500) and (Destroyer.FatalException=nil),'destroy completion');
    Destroyer.Free;
  end else begin
    if ResetBeforeRelease then begin
      Check(Waiter.Outcome=Ord(wrTimeout),'reset input must not become a saved pulse');
      Check(BasicEventWaitFor(0,E)=Ord(wrTimeout),'reset wait state');
    end else begin
      Check(Waiter.Outcome=Ord(wrSignaled),'signal in unlock window');
      Check((BasicEventWaitFor(0,E)=Ord(wrSignaled))=Manual,'auto/manual after unlock window');
    end;
    Check(EventProbeWaiterCount(E)=0,'unlock window leaked waiter');
    BasicEventDestroy(E);
  end;
  Waiter.Free;
  EventProbeWaitTarget:=nil;
end;

var Error: LongInt; Manual: Boolean;
begin
  if not EventProbeStateFutex then begin
    Writeln('STATE_FUTEX_SKIPPED');
    Halt(0);
  end;
  for Error in [4,11] do begin
    RetryBudget(16,Error,22);
    RetryBudget(High(Cardinal),Error,22);
    RetryBudget(16,Error,110);
  end;
  for Manual:=False to True do begin
    UnlockWindow(Manual,False,False);
    UnlockWindow(Manual,True,False);
    UnlockWindow(Manual,False,True);
  end;
  Writeln('STATE_FUTEX_PASS');
end.
