program notification_lifetime_probe;
{$mode delphi}{$H+}
uses cthreads, SysUtils, Classes, SyncObjs;

type
  TWorker = class(TThread)
    Kind, Outcome: Integer;
    procedure Execute; override;
  end;
var Event: PEventState; DestroyStarted, DestroyCompleted: LongInt;

procedure TWorker.Execute;
begin
  case Kind of
    0: Outcome:=BasicEventWaitFor(INFINITE,Event);
    1: BasicEventSetEvent(Event);
    2: begin
      InterlockedExchange(DestroyStarted,1);
      BasicEventDestroy(Event);
      InterlockedExchange(DestroyCompleted,1);
    end;
  end;
end;

procedure AwaitValue(var Value: LongInt; Expected: LongInt);
var Start: QWord;
begin
  Start:=GetTickCount64;
  while InterlockedCompareExchange(Value,0,0)<>Expected do begin
    If GetTickCount64-Start>2000 then raise Exception.Create('lifetime probe deadline');
    Sleep(1);
  end;
end;

var Waiter, Setter, Destroyer: TWorker; Start: QWord;
begin
  Event:=BasicEventCreate(nil,ParamStr(1)='manual',False,'');
  Waiter:=TWorker.Create(True);
  Waiter.Kind:=0;
  Waiter.Start;
  Start:=GetTickCount64;
  while EventProbeWaiterCount(Event)<>1 do begin
    If GetTickCount64-Start>2000 then raise Exception.Create('waiter registration deadline');
    Sleep(1);
  end;
  EventProbeNotifyTarget:=Event;
  Setter:=TWorker.Create(True);
  Setter.Kind:=1;
  Setter.Start;
  AwaitValue(EventProbeNotifyStage,1);
  Destroyer:=TWorker.Create(True);
  Destroyer.Kind:=2;
  Destroyer.Start;
  AwaitValue(DestroyStarted,1);
  Sleep(20);
  If InterlockedCompareExchange(DestroyCompleted,0,0)<>0 then
    raise Exception.Create('Destroy freed the paused notifier state');
  InterlockedExchange(EventProbeNotifyRelease,1);
  If not Setter.WaitFor(2000) or not Waiter.WaitFor(2000) or not Destroyer.WaitFor(2000) then
    raise Exception.Create('lifetime completion deadline');
  If Waiter.Outcome<>Ord(wrAbandoned) then raise Exception.Create('destroyed wait result');
  If (Setter.FatalException<>nil) or (Waiter.FatalException<>nil) or (Destroyer.FatalException<>nil) then
    raise Exception.Create('lifetime worker failed');
  Setter.Free;
  Waiter.Free;
  Destroyer.Free;
  WriteLn('NOTIFICATION_LIFETIME_PASS');
end.
