program semaphore_wake_work_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
uses {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes, SyncObjs;

const WorkerCount=16;
var Semaphore: TLightweightSemaphore; ConsumersStarted, ConsumersFinished: LongInt;
{$ifdef LINUX}
var Original, Probe: TThreadManager; Notifications: LongInt;
procedure CountNotification(State: PEventState);
begin
  InterlockedIncrement(Notifications);
  Original.BasicEventSetEvent(State);
end;
{$endif}
type
  TConsumer = class(TThread)
    procedure Execute; override;
  end;

procedure TConsumer.Execute;
begin
  InterlockedIncrement(ConsumersStarted);
  If Semaphore.WaitFor(INFINITE)<>wrSignaled then raise Exception.Create('permit not received');
  InterlockedIncrement(ConsumersFinished);
end;

procedure AwaitCount(var Counter: LongInt; Expected: Integer);
var Start: UInt64;
begin
  Start:=TThread.GetTickCount64;
  while InterlockedCompareExchange(Counter,0,0)<>Expected do begin
    If TThread.GetTickCount64-Start>5000 then raise Exception.Create('consumer deadline');
    Sleep(1);
  end;
end;

var Workers: array[1..WorkerCount] of TConsumer; I: Integer;
begin
  Semaphore:=TLightweightSemaphore.Create(0,WorkerCount);
  {$ifdef LINUX}
  GetThreadManager(Original);
  Probe:=Original;
  Probe.InitManager:=nil;
  Probe.BasicEventSetEvent:=@CountNotification;
  SetThreadManager(Probe);
  {$endif}
  for I:=1 to WorkerCount do Workers[I]:=TConsumer.Create(False);
  AwaitCount(ConsumersStarted,WorkerCount);
  { All consumers have entered the empty semaphore; allow their initial spin
    to finish. A late registrant sees the permit and cannot lose it. }
  Sleep(100);
  {$ifdef LINUX}InterlockedExchange(Notifications,0);{$endif}
  Semaphore.Release(1);
  AwaitCount(ConsumersFinished,1);
  Sleep(20);
  {$ifdef LINUX}
  WriteLn('FIRST_PERMIT_NOTIFICATIONS=',InterlockedCompareExchange(Notifications,0,0));
  {$ifdef WAIT_WORK_PROBE}
  If InterlockedCompareExchange(Notifications,0,0)<>1 then
    raise Exception.Create('one permit unnecessarily notified other consumers');
  {$endif}
  {$endif}
  { Repeated releases must select different blocked consumers even when a
    previously notified consumer has not reacquired the monitor yet. }
  for I:=2 to WorkerCount do Semaphore.Release(1);
  AwaitCount(ConsumersFinished,WorkerCount);
  for I:=1 to WorkerCount do begin
    Workers[I].WaitFor;
    If Workers[I].FatalException<>nil then raise Exception.Create('consumer failed');
    Workers[I].Free;
  end;
  If Semaphore.CurrentCount<>0 then raise Exception.Create('permit count changed');
  {$ifdef LINUX}
  Original.InitManager:=nil;
  SetThreadManager(Original);
  {$endif}
  Semaphore.Free;
  WriteLn('SEMAPHORE_WAKE_WORK_PASS');
end.
