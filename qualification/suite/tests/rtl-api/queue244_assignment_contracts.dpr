program queue244_assignment_contracts;
{$mode delphiunicode}
{$modeswitch advancedrecords}
uses {$ifdef unix}cthreads,{$endif} SysUtils, Classes, SyncObjs, Generics.Collections, queue244hooks;
type
  EInjected = class(Exception);
  TValue = record
    Value: Integer;
    class operator Assign(var Dest: TValue; const [ref] Source: TValue);
  end;
  TWorker = class(TThread)
    Queue: TThreadedQueue<TValue>;
    Producer: Boolean;
    Value: TValue;
    procedure Execute; override;
  end;
var Armed, Failures, Completed: LongInt;
threadvar InWorker: Boolean;
class operator TValue.Assign(var Dest: TValue; const [ref] Source: TValue);
begin
  If InWorker and (Source.Value <> 0) and (InterlockedCompareExchange(Armed, 0, 1) = 1) then
    raise EInjected.Create('intentional assignment failure before destination mutation');
  Dest.Value := Source.Value;
end;
procedure TWorker.Execute;
var Size: NativeInt;
begin
  InWorker := True;
  try
    try
      If Producer then Check(Queue.PushItem(Value) = wrSignaled, 'producer result')
      else Check(Queue.PopItem(Size, Value) = wrSignaled, 'consumer result');
    except
      on EInjected do InterlockedIncrement(Failures);
    end;
  finally
    InWorker := False;
    InterlockedIncrement(Completed);
  end;
end;
procedure Run(Producer: Boolean);
var Queue: TThreadedQueue<TValue>; Workers: array[0..1] of TWorker; Item: TValue; I: Integer;
begin
  Armed := 0;
  Failures := 0;
  Completed := 0;
  BeginQueueCapture;
  If Producer then Queue := TThreadedQueue<TValue>.Create(0)
  else Queue := TThreadedQueue<TValue>.Create(1);
  EndQueueCapture;
  for I := 0 to 1 do begin
    Workers[I] := TWorker.Create(True);
    Workers[I].Queue := Queue;
    Workers[I].Producer := Producer;
    Workers[I].Value.Value := I + 1;
    Workers[I].Start;
  end;
  WaitForQueueWaiters(Ord(Producer), 2);
  Armed := 1;
  If Producer then Queue.Grow(1)
  else begin
    Item.Value := 123;
    Queue.PushItem(Item);
  end;
  WaitForCount(Completed, 2, 'assignment failure must pass readiness to another waiter');
  for I := 0 to 1 do begin
    Workers[I].WaitFor;
    Check(Workers[I].FatalException = nil, 'unexpected worker exception');
    Workers[I].Free;
  end;
  Check(Failures = 1, 'exactly one injected assignment failure');
  Check(Queue.QueueSize = Ord(Producer), 'queue contents after failed assignment');
  Check(Queue.TotalItemsPushed = 1, 'one successful push');
  Check(Queue.TotalItemsPopped = QWord(Ord(not Producer)), 'successful pop count');
  Queue.Free;
end;
begin
  InstallQueueHooks;
  Run(False);
  Run(True);
  RemoveQueueHooks;
  Writeln('QUEUE244_ASSIGNMENT_CONTRACTS_OK');
end.
