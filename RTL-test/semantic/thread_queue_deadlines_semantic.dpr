program thread_queue_deadlines_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
uses {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes;
type
  TReceiver = class
    ImmediateCount, DelayedCount, Reentered: Integer;
    procedure Immediate;
    procedure Delayed;
    procedure Reenter;
    procedure Failing;
  end;
procedure Check(Condition: Boolean; const Detail: string);
begin
  If not Condition then raise Exception.Create(Detail);
end;
procedure TReceiver.Immediate;
begin
  Check(GetCurrentThreadID=MainThreadID,'callback thread');
  Inc(ImmediateCount);
end;
procedure TReceiver.Delayed;
begin
  Inc(DelayedCount);
end;
procedure TReceiver.Reenter;
begin
  Inc(Reentered);
  TThread.ForceQueue(nil,Immediate);
  CheckSynchronize(0);
end;
procedure TReceiver.Failing;
begin
  raise EAbort.Create('expected queued exception');
end;
var Receiver: TReceiver; Start: UInt64; I: Integer; Raised: Boolean;
begin
  Receiver:=TReceiver.Create;
  try
    Start:=GetTickCount64;
    TThread.ForceQueue(nil,Receiver.Delayed,100);
    for I:=1 to 100 do TThread.ForceQueue(nil,Receiver.Immediate);
    CheckSynchronize(0);
    Check(Receiver.ImmediateCount=100,'delayed head blocked ordinary callbacks');
    If GetTickCount64-Start<90 then Check(Receiver.DelayedCount=0,'delayed callback ran early');
    TThread.ForceQueue(nil,Receiver.Reenter);
    CheckSynchronize(0);
    Check((Receiver.Reentered=1) and (Receiver.ImmediateCount=101),'recursive queue delivery');
    Start:=GetTickCount64;
    while Receiver.DelayedCount=0 do begin
      CheckSynchronize(0);
      Check(GetTickCount64-Start<2000,'delayed callback never became ready');
      Sleep(1);
    end;
    Check(Receiver.DelayedCount=1,'duplicate delayed callback');
    TThread.ForceQueue(nil,Receiver.Delayed,1000);
    TThread.ForceQueue(nil,Receiver.Immediate);
    TThread.RemoveQueuedEvents(nil,Receiver.Delayed);
    CheckSynchronize(0);
    Check((Receiver.ImmediateCount=102) and (Receiver.DelayedCount=1),'removal damaged immediate entry');
    TThread.ForceQueue(nil,Receiver.Failing);
    TThread.ForceQueue(nil,Receiver.Immediate);
    Raised:=False;
    try
      CheckSynchronize(0);
    except
      on E: EAbort do Raised:=True;
    end;
    Check(Raised,'queued exception lost');
    CheckSynchronize(0);
    Check(Receiver.ImmediateCount=103,'entry after exception lost');
    for I:=1 to 10000 do TThread.ForceQueue(nil,Receiver.Immediate);
    CheckSynchronize(0);
    Check(Receiver.ImmediateCount=10103,'ordinary callback batch lost');
  finally
    TThread.RemoveQueuedEvents(nil,Receiver.Immediate);
    TThread.RemoveQueuedEvents(nil,Receiver.Delayed);
    Receiver.Free;
  end;
  WriteLn('THREAD_QUEUE_DEADLINES_PASS');
end.
