program queue244_notification_contracts;
{$mode delphiunicode}
uses {$ifdef unix}cthreads,{$endif} SysUtils, Classes, SyncObjs, Generics.Collections, queue244hooks;
type
  TWorker = class(TThread)
    Queue: TThreadedQueue<Integer>;
    Producer: Boolean;
    Value: Integer;
    Status: TWaitResult;
    procedure Execute; override;
  end;
var Completed: LongInt;
procedure TWorker.Execute;
var Size: NativeInt;
begin
  try
    If Producer then Status := Queue.PushItem(Value)
    else Status := Queue.PopItem(Size, Value);
  finally
    InterlockedIncrement(Completed);
  end;
end;
procedure Run(Producer, Sparse, Grow: Boolean);
var
  Queue: TThreadedQueue<Integer>;
  Workers: array[0..31] of TWorker;
  Seen: array[1..32] of Boolean;
  I, Value: Integer;
  Size: NativeInt;
  procedure RecordItem(Item: Integer);
  begin
    Check((Item >= 1) and (Item <= 32), 'item range');
    Check(not Seen[Item], 'duplicate item');
    Seen[Item] := True;
  end;
begin
  Completed := 0;
  FillChar(Seen, SizeOf(Seen), 0);
  BeginQueueCapture;
  Queue := TThreadedQueue<Integer>.Create(Ord(Sparse));
  EndQueueCapture;
  If Sparse then begin
    If Producer then Queue.PushItem(0);
    HoldQueueReturns(Ord(Producer));
  end;
  for I := 0 to 31 do begin
    Workers[I] := TWorker.Create(True);
    Workers[I].Queue := Queue;
    Workers[I].Producer := Producer;
    Workers[I].Value := I + 1;
    Workers[I].Start;
  end;
  WaitForQueueWaiters(Ord(Producer), 32);
  If Sparse then begin
    for I := 1 to 32 do begin
      WaitForQueueWaiters(Ord(Producer), 33 - I);
      PrepareNextReturn;
      If Producer then begin
        Check(Queue.PopItem(Size, Value) = wrSignaled, 'make one slot');
        If I > 1 then RecordItem(Value) else Check(Value = 0, 'initial full queue');
      end else
        Check(Queue.PushItem(I) = wrSignaled, 'deliver one item');
      CheckSingleWake;
      ReleaseQueueReturn;
      WaitForCount(Completed, I, 'one operation completes per sparse transition');
    end;
    If Producer then begin
      Check(Queue.PopItem(Size, Value) = wrSignaled, 'drain final item');
      RecordItem(Value);
    end;
  end else If Grow then Queue.Grow(32)
  else Queue.DoShutDown;
  WaitForCount(Completed, 32, 'all waiters complete');
  for I := 0 to 31 do begin
    Workers[I].WaitFor;
    Check(Workers[I].FatalException = nil, 'unexpected worker exception');
    Check(Workers[I].Status = wrSignaled, 'worker status');
    If Sparse and not Producer then RecordItem(Workers[I].Value);
    If not Sparse and not Producer then Check(Workers[I].Value = 0, 'closed empty output');
    Workers[I].Free;
  end;
  If Grow then begin
    Check(Queue.QueueSize = 32, 'growth released every available slot');
    Queue.DoShutDown;
    for I := 1 to 32 do begin
      Check(Queue.PopItem(Size, Value) = wrSignaled, 'drain after shutdown');
      RecordItem(Value);
    end;
    Queue.Grow(-32);
  end;
  If Sparse or Grow then for I := 1 to 32 do Check(Seen[I], 'missing item');
  Check(Queue.QueueSize = 0, 'final empty queue');
  Queue.Free;
end;
procedure FiniteDeadline;
var
  Queue: TThreadedQueue<Integer>;
  Worker: TWorker;
  Size: NativeInt;
  Value: Integer;
begin
  Completed := 0;
  BeginQueueCapture;
  Queue := TThreadedQueue<Integer>.Create(1, 0, 1000);
  EndQueueCapture;
  HoldQueueReturns(0);
  PrepareNextReturn;
  Worker := TWorker.Create(True);
  Worker.Queue := Queue;
  Worker.Start;
  WaitForQueueWaiters(0, 1);
  Check(Queue.PushItem(9) = wrSignaled, 'deadline item');
  CheckSingleWake;
  { Reproduce preemption after notification, followed by another consumer
    winning the item. The original deadline expires before the loser resumes. }
  Check(Queue.PopItem(Size, Value) = wrSignaled, 'competing consumer');
  Check(Value = 9, 'single item delivered exactly once');
  Sleep(1100);
  ReleaseQueueReturn;
  WaitForCount(Completed, 1, 'finite loser completes');
  Worker.WaitFor;
  Check(Worker.FatalException = nil, 'finite worker exception');
  Check(Worker.Status = wrTimeout, 'finite loser times out');
  Check(Worker.Value = 0, 'timed-out output stays empty');
  Check(QueueWaitCalls(0) = 1, 'notification must not restart the timeout budget');
  Check((Queue.QueueSize = 0) and (Queue.TotalItemsPushed = 1) and
    (Queue.TotalItemsPopped = 1), 'one result and no leftover item');
  Worker.Free;
  Queue.Free;
end;
begin
  InstallQueueHooks;
  Run(False, True, False);
  Run(True, True, False);
  Run(False, False, False);
  Run(True, False, False);
  Run(True, False, True);
  FiniteDeadline;
  RemoveQueueHooks;
  Writeln('QUEUE244_NOTIFICATION_CONTRACTS_OK');
end.
