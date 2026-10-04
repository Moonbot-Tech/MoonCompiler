program thread_pool_idle_worker_semantic;

{$mode delphi}{$H+}

{ A worker that finished its task waits for the next one (IdleTimeout) instead
  of leaving at once: the next tasks run on it and the pool creates no thread
  for them.  The idle wait used to return at once (a manual-reset event that
  nothing reset), every idle worker left within microseconds, each task needed
  a new thread and could be left to a worker that was already leaving. }

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.Threading;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('THREAD_POOL_IDLE_WORKER_FAIL: '+AMessage);
end;

var
  Created: Integer;

procedure CheckIdleWorkerReused;
var
  Pool: TThreadPool;
  Task: ITask;
  Stats: TThreadPoolStats;
  Watch: TStopwatch;
  Workers, CreatedBefore, I: Integer;
begin
  Pool:=TThreadPool.Create;
  try
    Pool.OnThreadStart:=
      procedure(AThread: TThread)
      begin
        AtomicIncrement(Created);
      end;
    Task:=TTask.Run(procedure begin end,Pool);
    Check(Task.Wait(20000),'first task');
    { every worker the first task created has started and waits for work }
    Watch:=TStopwatch.StartNew;
    repeat
      Stats:=TThreadPoolStats.Get(Pool);
      if Stats.IdleWorkerThreadCount=Stats.WorkerThreadCount then
        Break;
      TThread.Sleep(1);
    until Watch.ElapsedMilliseconds>20000;
    TThread.Sleep(50);
    Stats:=TThreadPoolStats.Get(Pool);
    Workers:=Stats.WorkerThreadCount;
    Check(Workers>0,'no worker waits after a task');
    Check(Stats.IdleWorkerThreadCount=Workers,
      'idle workers '+IntToStr(Stats.IdleWorkerThreadCount)+' of '+IntToStr(Workers));
    CreatedBefore:=Created;
    for I:=1 to 20 do
      begin
      Task:=TTask.Run(procedure begin end,Pool);
      Check(Task.Wait(20000),'task '+IntToStr(I));
      TThread.Sleep(5);
      end;
    Check(Created=CreatedBefore,
      IntToStr(Created-CreatedBefore)+' threads created for tasks an idle worker was waiting for');
    Check(TThreadPoolStats.Get(Pool).WorkerThreadCount=Workers,'workers left the pool');
  finally
    Pool.Free;
  end;
end;

begin
  Created:=0;
  CheckIdleWorkerReused;
  WriteLn('THREAD_POOL_IDLE_WORKER_PASS');
end.
