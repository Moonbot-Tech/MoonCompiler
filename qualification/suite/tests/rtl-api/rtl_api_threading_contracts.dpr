program rtl_api_threading_contracts;
{$APPTYPE CONSOLE}
{$ifdef FPC}{$mode delphiunicode}{$endif}
uses
  {$ifdef unix}cthreads,{$endif}
  {$ifdef MSWINDOWS}Windows,{$endif}
  SysUtils, Classes, SyncObjs, System.TimeSpan, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then
    raise Exception.Create(Name);
end;

type
  TAction = (pushOne, popOne, produce, consume, signalCount, waitCount);
  TWorker = class(TThread)
  public
    Queue: TThreadedQueue<Integer>;
    Countdown: TCountdownEvent;
    Started, Done: TEvent;
    Action: TAction;
    Value, Base, Number: Integer;
    Status: TWaitResult;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    procedure Join;
  end;
  TTracked = class(TInterfacedObject)
    destructor Destroy; override;
  end;
var
  Seen: array[0..1999] of Integer;
  Released: Integer;

constructor TWorker.Create;
begin
  inherited Create(True);
  Started := TEvent.Create(nil, True, False, '');
  Done := TEvent.Create(nil, True, False, '');
end;

destructor TWorker.Destroy;
begin
  inherited Destroy;
  Started.Free;
  Done.Free;
end;

procedure TWorker.Execute;
var
  I, Item: Integer;
  Size: NativeInt;
begin
  try
    Started.SetEvent;
    case Action of
      pushOne: Status := Queue.PushItem(Value);
      popOne: Status := Queue.PopItem(Size, Value);
      produce:
        for I := 0 to Number - 1 do
          Check(Queue.PushItem(Base + I) = wrSignaled, 'producer push');
      consume:
        for I := 1 to Number do begin
          Check(Queue.PopItem(Size, Item) = wrSignaled, 'consumer pop');
          Check((Item >= 0) and (Item < Length(Seen)), 'consumer range');
          Check(TInterlocked.Increment(Seen[Item]) = 1, 'duplicate item');
        end;
      signalCount:
        for I := 1 to Number do
          Countdown.Signal;
      waitCount: Status := Countdown.WaitFor(2000);
    end;
  finally
    Done.SetEvent;
  end;
end;

procedure TWorker.Join;
begin
  Check(Done.WaitFor(4000) = wrSignaled, 'worker stuck');
  WaitFor;
  Check(FatalException = nil, 'worker exception');
end;

destructor TTracked.Destroy;
begin
  Inc(Released);
  inherited Destroy;
end;

procedure QueueBasics;
var
  Q: TThreadedQueue<string>;
  R: TThreadedQueue<IInterface>;
  O: IInterface;
  N: NativeInt;
  Small: Integer;
  S: string;
begin
  Q := TThreadedQueue<string>.Create(2, 0, 0);
  try
    S := 'old';
    Check((Q.PopItem(N, S) = wrTimeout) and (N = 0) and (S = ''), 'empty timeout clears output');
    Check(Q.PushItem('one', N) = wrSignaled, 'push native size');
    Check(N = 1, 'native size result');
    Check(Q.PushItem('two', Small) = wrSignaled, 'push integer size');
    Check(Small = 2, 'integer size result');
    Check(Q.PushItem('overflow') = wrTimeout, 'bounded queue');
    Check(Q.PopItem = 'one', 'FIFO first');
    Q.PushItem('three');
    Q.Grow(3);
    Check(Q.PopItem(N) = 'two', 'wrapped growth first');
    Check((N = 1) and (Q.PopItem(Small) = 'three') and (Small = 0), 'wrapped growth second');
    Q.PushItem('four');
    Check((Q.PopItem(Small, S) = wrSignaled) and (S = 'four'), 'integer pop overload');
    Q.PushItem('five');
    Check((Q.PopItem(S) = wrSignaled) and (S = 'five'), 'value pop overload');
    Check((Q.TotalItemsPushed = 5) and (Q.TotalItemsPopped = 5), 'successful operation counters');
    Q.Grow(-5);
    Check(Q.PushItem('no capacity') = wrTimeout, 'shrink empty to zero');
    Q.Grow(2);
    Q.PushItem('drain');
    Q.Grow(-1);
    Check(Q.PushItem('full after shrink') = wrTimeout, 'shrink retains pending item');
    try
      Q.Grow(-1);
      Check(False, 'shrink below occupancy accepted');
    except
      on EArgumentOutOfRangeException do ;
    end;
    Q.DoShutDown;
    Q.DoShutDown;
    Check(Q.ShutDown, 'shutdown property');
    Check((Q.PushItem('rejected') = wrSignaled) and (Q.QueueSize = 1), 'closed queue rejects new work');
    Check(Q.PopItem = 'drain', 'drain after shutdown');
    Check((Q.PopItem(S) = wrSignaled) and (S = ''), 'closed empty queue');
    Check((Q.TotalItemsPushed = 6) and (Q.TotalItemsPopped = 6), 'shutdown does not count phantom items');
  finally
    Q.Free;
  end;
  Q := TThreadedQueue<string>.Create(0, 0, 0);
  try
    Check(Q.PushItem('blocked') = wrTimeout, 'zero depth');
    Q.Grow(1);
    Check((Q.PushItem('grown') = wrSignaled) and (Q.PopItem = 'grown'), 'grow from zero');
  finally
    Q.Free;
  end;
  R := TThreadedQueue<IInterface>.Create(2, 0, 0);
  try
    Released := 0;
    O := TTracked.Create;
    R.PushItem(O);
    O := nil;
    R.Grow(2);
    Check(Released = 0, 'growth retains interface');
    Check(R.PopItem(O) = wrSignaled, 'managed pop');
    O := nil;
    Check(Released = 1, 'popped slot releases interface');
    R.PushItem(TTracked.Create);
  finally
    R.Free;
  end;
  Check(Released = 2, 'destructor releases pending interface');
end;

procedure QueueWaiting;
var
  Q: TThreadedQueue<Integer>;
  W: array[0..2] of TWorker;
  I: Integer;
  N: NativeInt;
  Value: Integer;
  Started: UInt64;
begin
  Q := TThreadedQueue<Integer>.Create(1, 35, 35);
  try
    Started := GetTickCount64;
    Check(Q.PopItem(N, Value) = wrTimeout, 'finite pop timeout');
    Check(GetTickCount64 - Started >= 15, 'pop waited');
    Q.PushItem(1);
    Started := GetTickCount64;
    Check(Q.PushItem(2) = wrTimeout, 'finite push timeout');
    Check(GetTickCount64 - Started >= 15, 'push waited');
  finally
    Q.Free;
  end;
  Q := TThreadedQueue<Integer>.Create(1);
  try
    Q.PushItem(1);
    for I := 0 to High(W) do begin
      W[I] := TWorker.Create;
      W[I].Queue := Q;
      W[I].Action := pushOne;
      W[I].Value := I + 10;
      W[I].Start;
      Check(W[I].Started.WaitFor(2000) = wrSignaled, 'producer started');
    end;
    Check(W[0].Done.WaitFor(25) = wrTimeout, 'full queue waits');
    Q.Grow(3);
    for I := 0 to High(W) do begin
      W[I].Join;
      Check(W[I].Status = wrSignaled, 'grow wakes all producers');
      W[I].Free;
    end;
    Check(Q.QueueSize = 4, 'all producers inserted');
    while Q.QueueSize <> 0 do
      Q.PopItem(N, Value);
    for I := 0 to High(W) do begin
      W[I] := TWorker.Create;
      W[I].Queue := Q;
      W[I].Action := popOne;
      W[I].Start;
      Check(W[I].Started.WaitFor(2000) = wrSignaled, 'consumer started');
    end;
    Check(W[0].Done.WaitFor(25) = wrTimeout, 'empty queue waits');
    Q.DoShutDown;
    for I := 0 to High(W) do begin
      W[I].Join;
      Check((W[I].Status = wrSignaled) and (W[I].Value = 0), 'shutdown wakes all consumers');
      W[I].Free;
    end;
  finally
    Q.Free;
  end;
  Q := TThreadedQueue<Integer>.Create(0);
  try
    W[0] := TWorker.Create;
    W[0].Queue := Q;
    W[0].Action := pushOne;
    W[0].Start;
    Check(W[0].Started.WaitFor(2000) = wrSignaled, 'shutdown producer started');
    Check(W[0].Done.WaitFor(25) = wrTimeout, 'zero capacity waits');
    Q.DoShutDown;
    W[0].Join;
    Check((W[0].Status = wrSignaled) and (Q.TotalItemsPushed = 0), 'shutdown wakes producer without insertion');
    W[0].Free;
  finally
    Q.Free;
  end;
end;

procedure QueueConcurrent;
var
  Q: TThreadedQueue<Integer>;
  W: array[0..7] of TWorker;
  I: Integer;
begin
  Q := TThreadedQueue<Integer>.Create(7, 2000, 2000);
  try
    for I := 0 to High(W) do begin
      W[I] := TWorker.Create;
      W[I].Queue := Q;
      W[I].Number := 500;
      W[I].Base := (I mod 4) * 500;
      If I < 4 then
        W[I].Action := produce
      else
        W[I].Action := consume;
      W[I].Start;
    end;
    for I := 0 to High(W) do begin
      W[I].Join;
      W[I].Free;
    end;
    for I := 0 to High(Seen) do
      Check(Seen[I] = 1, 'missing item');
    Check((Q.QueueSize = 0) and (Q.TotalItemsPushed = 2000) and
      (Q.TotalItemsPopped = 2000), 'concurrent totals');
  finally
    Q.Free;
  end;
end;

procedure CountdownBasics;
var
  C: TCountdownEvent;
  Base: TSynchroObject;
  W: array[0..5] of TWorker;
  I: Integer;
begin
  C := TCountdownEvent.Create;
  try
    Check((C.InitialCount = 1) and (C.CurrentCount = 1), 'default countdown');
    Base := C;
    Check(Base.WaitFor(TTimeSpan.FromMilliseconds(0)) = wrTimeout, 'polymorphic timespan wait');
    Check(C.WaitFor(0) = wrTimeout, 'initially not signaled');
    C.AddCount(2);
    Check(not C.Signal(2), 'partial completion');
    Check(C.Signal, 'last completion');
    Check(C.IsSet and (C.WaitFor(0) = wrSignaled), 'zero is signaled');
    Check(Base.WaitFor(0) = wrSignaled, 'polymorphic completed wait');
    Check(C.WaitFor(TTimeSpan.FromMilliseconds(0)) = wrSignaled, 'countdown timespan overload');
    Check(not C.TryAddCount, 'completed count cannot reopen');
    try
      C.AddCount;
      Check(False, 'add after completion accepted');
    except
      on EInvalidOperation do ;
    end;
    try
      C.Signal;
      Check(False, 'over-signal accepted');
    except
      on EInvalidOperation do ;
    end;
    C.Reset;
    Check((C.CurrentCount = 1) and not C.IsSet, 'reset initial count');
    C.Reset(2000);
    Check(C.InitialCount = 2000, 'reset replaces initial count');
    for I := 0 to High(W) do begin
      W[I] := TWorker.Create;
      W[I].Countdown := C;
      W[I].Number := 500;
      If I < 2 then
        W[I].Action := waitCount
      else
        W[I].Action := signalCount;
      W[I].Start;
    end;
    for I := 0 to High(W) do begin
      W[I].Join;
      If I < 2 then
        Check(W[I].Status = wrSignaled, 'countdown wakes every waiter');
      W[I].Free;
    end;
    Check(C.CurrentCount = 0, 'concurrent signal count');
    C.Reset(0);
    Check(C.WaitFor(0) = wrSignaled, 'reset zero');
    C.Reset(High(Integer));
    try
      C.TryAddCount;
      Check(False, 'count overflow accepted');
    except
      on EInvalidOperation do ;
    end;
  finally
    C.Free;
  end;
  C := TCountdownEvent.Create(1, 10);
  try
    Check(C.WaitFor(20) = wrTimeout, 'spin budget honors timeout');
    C.Signal;
    Check(C.WaitFor(0) = wrSignaled, 'explicit spin count completion');
  finally
    C.Free;
  end;
  C := TCountdownEvent.Create(0, -1);
  try
    Check(C.WaitFor(0) = wrSignaled, 'automatic spin count');
  finally
    C.Free;
  end;
  try
    C := TCountdownEvent.Create(1, 4096);
    C.Free;
    Check(False, 'invalid spin count accepted');
  except
    on EArgumentOutOfRangeException do ;
  end;
end;

begin
  QueueBasics;
  QueueWaiting;
  QueueConcurrent;
  CountdownBasics;
  Writeln('RTL_API_THREADING_CONTRACTS_OK');
end.
