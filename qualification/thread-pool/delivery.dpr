program delivery;

{$mode delphi}{$H+}

uses
  {$ifdef UNIX}cthreads,{$endif}
  System.SysUtils, System.Classes, System.SyncObjs, System.Threading, pool_probe;

var
  Pool: TThreadPool;
  Done: TSemaphore;
  Ran: LongInt;
  Point: Integer;

procedure Work;
begin
  AtomicIncrement(Ran);
  Done.Release;
end;

procedure Warmup;
begin
  AtomicIncrement(Ran);
  AtomicExchange(ProbePoint,Point);
  Done.Release;
end;

procedure Check(ACondition: Boolean; const AMessage: string);
var
  Stats: TThreadPoolStats;
begin
  if ACondition then
    Exit;
  Stats:=TThreadPoolStats.Get(Pool);
  WriteLn('DELIVERY_FAIL: ',AMessage,'; queued=',Stats.QueuedRequestCount,
    '; idle=',Stats.IdleWorkerThreadCount,'; workers=',Stats.WorkerThreadCount);
  Flush(Output);
  Halt(1);
end;

procedure WaitIdle;
var
  Deadline: QWord;
  Stats: TThreadPoolStats;
begin
  Deadline:=GetTickCount64+5000;
  repeat
    Stats:=TThreadPoolStats.Get(Pool);
    if (Stats.IdleWorkerThreadCount=1) and (Stats.QueuedRequestCount=0) then
      Exit;
    Sleep(1);
  until GetTickCount64>=Deadline;
  Check(False,'worker did not become idle');
end;

var
  Rounds, I, J: Integer;
  Before, Started, Elapsed, MaxElapsed: QWord;
  Senders: array[0..1] of TThread;
begin
  Point:=StrToInt(ParamStr(1));
  Rounds:=StrToInt(ParamStr(2));
  Pool:=TThreadPool.Create;
  Arrived:=TSemaphore.Create(nil,0,MaxInt,'');
  Proceed:=TSemaphore.Create(nil,0,MaxInt,'');
  Done:=TSemaphore.Create(nil,0,MaxInt,'');
  try
    Check(Pool.SetMinWorkerThreads(0),'min');
    Check(Pool.SetMaxWorkerThreads(1),'max');
    ProbePool:=Pool;
    MaxElapsed:=0;
    for I:=1 to Rounds do
      begin
      if Point=2 then
        begin
        Pool.QueueWorkItem(Work);
        Check(Done.WaitFor(5000)=wrSignaled,'warmup');
        WaitIdle;
        AtomicExchange(ProbePoint,Point);
        Before:=Ran;
        for J:=0 to High(Senders) do
          begin
          Senders[J]:=TThread.CreateAnonymousThread(procedure begin Pool.QueueWorkItem(Work) end);
          Senders[J].FreeOnTerminate:=False;
          Senders[J].Start;
          end;
        Check(Arrived.WaitFor(5000)=wrSignaled,'first producer at barrier');
        Check(Arrived.WaitFor(5000)=wrSignaled,'second producer at barrier');
        AtomicExchange(ProbePoint,0);
        Started:=GetTickCount64;
        Proceed.Release(2);
        Check(Done.WaitFor(5000)=wrSignaled,'first concurrent request');
        Check(Done.WaitFor(5000)=wrSignaled,'second concurrent request');
        for J:=0 to High(Senders) do
          begin
          Senders[J].WaitFor;
          Senders[J].Free;
          end;
        Check(Ran=Before+2,'concurrent requests executed once');
        end
      else
        begin
        Before:=Ran;
        if Point=4 then
          begin
          AtomicExchange(ProbePoint,Point);
          Pool.QueueWorkItem(Work);
          end
        else
          begin
          Pool.QueueWorkItem(Warmup);
          Check(Done.WaitFor(5000)=wrSignaled,'warmup');
          Inc(Before);
          end;
        Check(Arrived.WaitFor(5000)=wrSignaled,'worker at barrier');
        Pool.QueueWorkItem(Work);
        AtomicExchange(ProbePoint,0);
        Started:=GetTickCount64;
        Proceed.Release;
        Check(Done.WaitFor(5000)=wrSignaled,'request across worker transition');
        if Point=4 then
          begin
          Check(Done.WaitFor(5000)=wrSignaled,'request before queue check');
          Inc(Before);
          end;
        Check(Ran=Before+1,'request executed once');
        end;
      Elapsed:=GetTickCount64-Started;
      if Elapsed>MaxElapsed then
        MaxElapsed:=Elapsed;
      end;
    WriteLn('DELIVERY_PASS point=',Point,' rounds=',Rounds,' max_completion_ms=',MaxElapsed);
  finally
    AtomicExchange(ProbePoint,0);
    Pool.Free;
    Done.Free;
    Proceed.Free;
    Arrived.Free;
  end;
end.
