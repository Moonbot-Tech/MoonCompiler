program thread_pool_delivery_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  System.SysUtils, System.Classes, System.SyncObjs, System.Threading;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('THREAD_POOL_DELIVERY_FAIL: '+AMessage);
end;

procedure CheckPrivatePools;
var
  First, Second: TThreadPool;
  Parent: ITask;
  Delivered: Boolean;
  Ran: LongInt;
begin
  First:=TThreadPool.Create;
  Second:=TThreadPool.Create;
  try
    Check(First.SetMinWorkerThreads(0) and First.SetMaxWorkerThreads(1),'first limits');
    Check(Second.SetMinWorkerThreads(0) and Second.SetMaxWorkerThreads(1),'second limits');
    Delivered:=False;
    Ran:=0;
    Parent:=TTask.Run(
      procedure
      var
        Child: ITask;
      begin
        Child:=TTask.Run(procedure begin AtomicIncrement(Ran) end,Second);
        Delivered:=Child.Wait(250);
      end,First);
    Check(Parent.Wait(5000),'parent finished');
    Check(Delivered,'task sent from another pool must run while its sender waits');
    Check(Ran=1,'foreign-pool task executed once');
    Check(TThreadPoolStats.Get(First).QueuedRequestCount=0,'sender request count');
    Check(TThreadPoolStats.Get(Second).QueuedRequestCount=0,'receiver request count');
  finally
    First.Free;
    Second.Free;
  end;
end;

procedure CheckBusyWorker;
var
  Pool: TThreadPool;
  Entered, ContinueWork, Done: TEvent;
  Parent, Child, Cancelled: ITask;
  Ran: LongInt;
begin
  Pool:=TThreadPool.Create;
  Entered:=TEvent.Create(nil,True,False,'');
  ContinueWork:=TEvent.Create(nil,True,False,'');
  Done:=TEvent.Create(nil,True,False,'');
  try
    Check(Pool.SetMinWorkerThreads(0) and Pool.SetMaxWorkerThreads(1),'busy limits');
    { one worker in all: past the maximum the monitor would take the child
      (thread_pool_blocked_growth_semantic) }
    Pool.UnlimitedWorkerThreadsWhenBlocked:=False;
    Ran:=0;
    Parent:=TTask.Run(
      procedure
      begin
        { Same-pool submission uses the local queue. The cancelled callback
          must be skipped, and the next request must still reach a worker. }
        Child:=TTask.Run(
          procedure
          begin
            AtomicIncrement(Ran);
            Done.SetEvent;
          end,Pool);
        Cancelled:=TTask.Run(procedure begin AtomicIncrement(Ran,100) end,Pool);
        Cancelled.Cancel;
        Entered.SetEvent;
        ContinueWork.WaitFor(5000);
      end,Pool);
    Check(Entered.WaitFor(5000)=wrSignaled,'busy worker entered');
    Check(Done.WaitFor(0)=wrTimeout,'busy max=1 does not execute child yet');
    ContinueWork.SetEvent;
    Check(Done.WaitFor(250)=wrSignaled,'local work after busy callback');
    Check(Parent.Wait(5000) and Child.Wait(5000),'callbacks completed');
    Check(Ran=1,'cancelled callback skipped, child executed once');
  finally
    ContinueWork.SetEvent;
    Pool.Free;
    Done.Free;
    ContinueWork.Free;
    Entered.Free;
  end;
end;

begin
  CheckPrivatePools;
  CheckBusyWorker;
  WriteLn('THREAD_POOL_DELIVERY_PASS');
end.
