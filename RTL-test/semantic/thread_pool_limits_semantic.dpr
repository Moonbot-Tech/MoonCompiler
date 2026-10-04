program thread_pool_limits_semantic;

{$mode delphi}{$H+}

{ The pool limits accept what Delphi 12.2 accepts: a minimum from zero and a
  maximum above zero, each on its own.  MoonBot asks the default pool for a
  minimum of Max(ProcessorCount*2,36) workers.  That is never below the
  default maximum (ProcessorCount*2), and a minimum used to be accepted only
  below the maximum, so the request failed on every machine and nothing read
  the False.  A minimum above the maximum starts that many workers at once
  when work arrives, as in Delphi.  With UnlimitedWorkerThreadsWhenBlocked off
  the pool does not grow at that size, so each task must reach a worker
  without a new thread: a worker that finds the queue empty and only then
  counts itself idle misses the task queued in between, and the task waits
  for that worker's idle timeout.  The MinWorkerThreads/MaxWorkerThreads
  properties write through the same checks, as in Delphi. }

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

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('THREAD_POOL_LIMITS_FAIL: '+AMessage);
end;

procedure CheckAcceptedValues;
var
  Pool: TThreadPool;
  MinDefault, MaxDefault: Integer;
begin
  Pool:=TThreadPool.Create;
  try
    MinDefault:=Pool.MinWorkerThreads;
    MaxDefault:=Pool.MaxWorkerThreads;
    Check(not Pool.SetMinWorkerThreads(-1),'negative minimum accepted');
    Check(not Pool.SetMaxWorkerThreads(0),'zero maximum accepted');
    Check(not Pool.SetMaxWorkerThreads(-1),'negative maximum accepted');
    Check((Pool.MinWorkerThreads=MinDefault) and (Pool.MaxWorkerThreads=MaxDefault),
      'a refused limit was stored');
    Check(Pool.SetMinWorkerThreads(0),'zero minimum refused');
    Check(Pool.SetMinWorkerThreads(MaxDefault+1),'minimum above the maximum refused');
    Check(Pool.SetMaxWorkerThreads(1),'maximum below the minimum refused');
    Check((Pool.MinWorkerThreads=MaxDefault+1) and (Pool.MaxWorkerThreads=1),
      'one limit changed the other');
    { the properties write through the same checks, as in Delphi }
    Pool.MaxWorkerThreads:=MaxDefault+2;
    Pool.MinWorkerThreads:=MinDefault;
    Check((Pool.MaxWorkerThreads=MaxDefault+2) and (Pool.MinWorkerThreads=MinDefault),
      'property write ignored');
    Pool.MaxWorkerThreads:=0;
    Pool.MinWorkerThreads:=-1;
    Check((Pool.MaxWorkerThreads=MaxDefault+2) and (Pool.MinWorkerThreads=MinDefault),
      'property stored a refused limit');
  finally
    Pool.Free;
  end;
end;

var
  Created, Started: Integer;

procedure CheckMinimumStartsAtOnce;
var
  Pool: TThreadPool;
  Gate: TEvent;
  Tasks: array of ITask;
  Stats: TThreadPoolStats;
  Minimum, I: Integer;
  Watch: TStopwatch;
begin
  Minimum:=Max(TThread.ProcessorCount*2,36); // MoonBot, Unit1.pas
  Pool:=TThreadPool.Create;
  Gate:=TEvent.Create(Nil,True,False,'');
  try
    Pool.OnThreadStart:=
      procedure(AThread: TThread)
      begin
        AtomicIncrement(Created);
      end;
    Check(Pool.SetMinWorkerThreads(Minimum),'minimum '+IntToStr(Minimum)+' refused');
    Check(Pool.SetMaxWorkerThreads(1),'maximum below the minimum refused');
    { exactly the minimum: a slow start must not let the monitor add threads
      past the maximum (thread_pool_blocked_growth_semantic) }
    Pool.UnlimitedWorkerThreadsWhenBlocked:=False;
    SetLength(Tasks,Minimum);
    for I:=0 to Minimum-1 do
      Tasks[I]:=TTask.Run(
        procedure
        begin
          AtomicIncrement(Started);
          if Gate.WaitFor(30000)<>wrSignaled then
            raise Exception.Create('gate timeout');
        end,Pool);
    Watch:=TStopwatch.StartNew;
    while (Started<Minimum) and (Watch.ElapsedMilliseconds<20000) do
      TThread.Sleep(1);
    Stats:=TThreadPoolStats.Get(Pool);
    Check(Started=Minimum,IntToStr(Started)+' of '+IntToStr(Minimum)+' tasks run at once (workers '+
      IntToStr(Stats.WorkerThreadCount)+', idle '+IntToStr(Stats.IdleWorkerThreadCount)+', queued '+
      IntToStr(Stats.QueuedRequestCount)+')');
    Check(Created=Minimum,IntToStr(Created)+' workers for a minimum of '+IntToStr(Minimum));
    Gate.SetEvent;
    Check(TTask.WaitForAll(Tasks,20000),'tasks after the gate');
  finally
    Gate.SetEvent;
    Pool.Free;
    Gate.Free;
  end;
end;

begin
  Created:=0;
  Started:=0;
  CheckAcceptedValues;
  CheckMinimumStartsAtOnce;
  WriteLn('THREAD_POOL_LIMITS_PASS');
end.
