program thread_pool_blocked_growth_semantic;

{$mode delphi}{$H+}

{ UnlimitedWorkerThreadsWhenBlocked, as in Delphi 12.2 (default True): when
  every worker the limits allow is busy and work is queued, the pool monitor
  adds threads past the maximum while the processors are not busy.  A producer
  that finds no free worker wakes the monitor at once; the monitor adds one
  thread per round below the maximum and up to half the maximum plus one above
  it, only for a queue not shorter than at its previous addition and not in
  the tick of a thread creation.  With the property off, the queued work waits
  for a busy worker.  MoonBot's pool (minimum 36 above the default maximum)
  stays at its limit, so without this a task queued behind 36 blocked tasks
  waited for one of them. }

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes,
  System.Math,
  System.SyncObjs,
  System.Diagnostics,
  System.Threading;

var
  Gate: TEvent;
  Started, Created: Integer;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('THREAD_POOL_BLOCKED_GROWTH_FAIL: '+AMessage);
end;

function State(Pool: TThreadPool): string;
var
  Stats: TThreadPoolStats;
begin
  Stats:=TThreadPoolStats.Get(Pool);
  Result:=Format(' (workers %d, idle %d, queued %d, cpu %d%%)',[Stats.WorkerThreadCount,
    Stats.IdleWorkerThreadCount,Stats.QueuedRequestCount,Stats.CurrentCPUUsage]);
end;

function NewPool(AMin, AMax: Integer; AUnlimited: Boolean): TThreadPool;
begin
  Result:=TThreadPool.Create;
  Check(Result.UnlimitedWorkerThreadsWhenBlocked,'UnlimitedWorkerThreadsWhenBlocked is off by default');
  Result.OnThreadStart:=
    procedure(AThread: TThread)
    begin
      AtomicIncrement(Created);
    end;
  Check(Result.SetMinWorkerThreads(AMin) and Result.SetMaxWorkerThreads(AMax),'limits');
  Result.UnlimitedWorkerThreadsWhenBlocked:=AUnlimited;
end;

procedure Block(Pool: TThreadPool);
begin
  TTask.Run(
    procedure
    begin
      AtomicIncrement(Started);
      Gate.WaitFor(60000);
    end,Pool);
end;

function WaitStarted(Count: Integer; TimeoutMs: Integer): Boolean;
var
  Watch: TStopwatch;
begin
  Watch:=TStopwatch.StartNew;
  while (Started<Count) and (Watch.ElapsedMilliseconds<TimeoutMs) do
    TThread.Sleep(1);
  Result:=Started>=Count;
end;

{ Count tasks have started within the time, or the message names the pool
  state.  The monitor adds threads only while the processors are less than 80%
  busy, as in Delphi: time during which the pool's last sample showed busy
  processors (other programs on the machine) does not count, up to 12 times
  the time in all. }
procedure Expect(Pool: TThreadPool; Count, TimeoutMs: Integer; const What: string);
var
  Watch: TStopwatch;
  Elapsed, Last, Busy: Int64;
begin
  Watch:=TStopwatch.StartNew;
  Last:=0;
  Busy:=0;
  while Started<Count do
    begin
    Elapsed:=Watch.ElapsedMilliseconds;
    if TThreadPoolStats.Get(Pool).CurrentCPUUsage>=80 then
      Inc(Busy,Elapsed-Last);
    Last:=Elapsed;
    if (Elapsed-Busy>TimeoutMs) or (Elapsed>12*Int64(TimeoutMs)) then
      Check(False,What+': '+IntToStr(Started)+' of '+IntToStr(Count)+' tasks started in '+
        IntToStr(Elapsed)+' ms, '+IntToStr(Busy)+' ms of them with busy processors'+State(Pool));
    TThread.Sleep(1);
    end;
end;

procedure ExpectNot(Pool: TThreadPool; Count, TimeoutMs: Integer; const What: string);
begin
  if WaitStarted(Count,TimeoutMs) then
    Check(False,What+': '+IntToStr(Started)+' tasks started'+State(Pool));
end;

procedure Release(Pool: TThreadPool; Count: Integer);
begin
  Gate.SetEvent;
  Expect(Pool,Count,10000,'after the release');
end;

procedure Finish(Pool: TThreadPool);
begin
  Gate.SetEvent;
  Pool.Free;
  Gate.ResetEvent;
  Started:=0;
  Created:=0;
end;

{ Two busy workers at Max=2: the next task gets a thread, and a later one
  another; with the property off both wait for the busy ones and no thread is
  added. }
procedure CheckOverflow(AUnlimited: Boolean);
var
  Pool: TThreadPool;
begin
  Pool:=NewPool(0,2,AUnlimited);
  try
    Block(Pool);
    Block(Pool);
    Expect(Pool,2,10000,'two tasks at Max=2');
    TThread.Sleep(50);
    Block(Pool);
    if AUnlimited then
      begin
      Expect(Pool,3,10000,'a task behind two blocked workers');
      TThread.Sleep(50);
      Block(Pool);
      Expect(Pool,4,10000,'the next task behind three blocked workers');
      end
    else
      begin
      ExpectNot(Pool,3,1500,'past Max=2 with UnlimitedWorkerThreadsWhenBlocked off');
      Block(Pool);
      ExpectNot(Pool,3,600,'past Max=2 with UnlimitedWorkerThreadsWhenBlocked off');
      Check(Created=2,IntToStr(Created)+' threads at Max=2');
      end;
    Release(Pool,4);
  finally
    Finish(Pool);
  end;
end;

{ The only worker blocks in a task whose child waits in that worker's queue:
  a new thread takes the child. }
procedure CheckBusyParent;
var
  Pool: TThreadPool;
  Entered, Hold: TEvent;
  Parent: ITask;
begin
  Pool:=NewPool(0,1,True);
  Entered:=TEvent.Create(nil,True,False,'');
  Hold:=TEvent.Create(nil,True,False,'');
  try
    Parent:=TTask.Run(
      procedure
      begin
        TTask.Run(
          procedure
          begin
            AtomicIncrement(Started);
          end,Pool);
        Entered.SetEvent;
        Hold.WaitFor(60000);
      end,Pool);
    Check(Entered.WaitFor(10000)=wrSignaled,'parent did not start');
    Expect(Pool,1,10000,'the child of the only worker, blocked in its parent');
    Hold.SetEvent;
    Check(Parent.Wait(10000),'parent after release');
  finally
    Hold.SetEvent;
    Pool.Free;
    Hold.Free;
    Entered.Free;
  end;
  Started:=0;
  Created:=0;
end;

{ How much the monitor adds at once, and when it stops.  Queued tasks wait
  behind the blocked workers with the property off; switched on, the
  monitor's next round adds Min(queued, MaxWorkerThreads div 2 + 1) threads
  at once and no more while the queue is shorter than at that growth.  (With
  the property on from the start, how much of a burst one growth covers
  depends on when the monitor's round falls inside the burst, as in Delphi.) }
procedure CheckAtOnce(AMin, AMax, Blocked, Queued: Integer; const What: string);
var
  Pool: TThreadPool;
  Grow, I: Integer;
begin
  Pool:=NewPool(AMin,AMax,False);
  try
    for I:=1 to Blocked+Queued do
      Block(Pool);
    Expect(Pool,Blocked,10000,What+': the allowed workers');
    ExpectNot(Pool,Blocked+1,600,What+': a task past the limit with the property off');
    Grow:=Pool.MaxWorkerThreads div 2+1;
    if Grow>Queued then
      Grow:=Queued;
    Pool.UnlimitedWorkerThreadsWhenBlocked:=True;
    Expect(Pool,Blocked+Grow,10000,What+': '+IntToStr(Grow)+' threads at once');
    if Grow<Queued then
      ExpectNot(Pool,Blocked+Grow+1,1500,What+': growth for a queue shorter than at the last one');
    Release(Pool,Blocked+Queued);
  finally
    Finish(Pool);
  end;
end;

{ A worker-start callback may submit work to its own pool.  Calling it while
  the creator holds the queue spin lock deadlocks on that submission. }
procedure CheckStartCallback;
var
  Pool: TThreadPool;
  Done: TEvent;
begin
  Pool:=TThreadPool.Create;
  Done:=TEvent.Create(nil,True,False,'');
  try
    Pool.SetMinWorkerThreads(0);
    Pool.SetMaxWorkerThreads(1);
    Pool.OnThreadStart:=
      procedure(AThread: TThread)
      begin
        TThread.Sleep(50);
        Pool.QueueWorkItem(procedure begin Done.SetEvent end);
      end;
    TTask.Run(procedure begin end,Pool);
    Check(Done.WaitFor(5000)=wrSignaled,'work queued by OnThreadStart did not run');
  finally
    Pool.Free;
    Done.Free;
  end;
end;

begin
  Gate:=TEvent.Create(nil,True,False,'');
  try
    CheckOverflow(True);
    CheckOverflow(False);
    CheckBusyParent;
    CheckAtOnce(0,2,2,8,'eight tasks behind two blocked workers at Max=2');
    { MoonBot: a minimum of Max(ProcessorCount*2,36), above the default maximum }
    CheckAtOnce(Max(TThread.ProcessorCount*2,36),TThread.ProcessorCount*2,
      Max(TThread.ProcessorCount*2,36),12,'MoonBot, twelve tasks behind its minimum');
    CheckStartCallback;
  finally
    Gate.SetEvent;
    Gate.Free;
  end;
  WriteLn('THREAD_POOL_BLOCKED_GROWTH_PASS');
end.
