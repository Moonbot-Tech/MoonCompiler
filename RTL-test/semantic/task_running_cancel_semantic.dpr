program task_running_cancel_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('TASK_RUNNING_CANCEL_FAIL: '+AMessage);
end;

procedure CheckRunningCancellation;
var
  Started, ReleaseTask: TEvent;
  Task: ITask;
  Finished: LongInt;
  Raised: Boolean;
begin
  Started:=TEvent.Create(nil,True,False,'');
  ReleaseTask:=TEvent.Create(nil,True,False,'');
  try
    Finished:=0;
    Task:=TTask.Run(
      procedure
      begin
        Started.SetEvent;
        if ReleaseTask.WaitFor(2000)<>wrSignaled then
          raise Exception.Create('release timeout');
        AtomicIncrement(Finished);
      end);
    Check(Started.WaitFor(2000)=wrSignaled,'task did not start');
    Task.Cancel;

    Raised:=False;
    try
      Check(not Task.Wait(25),'Wait completed while callback was running');
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(not Raised,'Wait raised while callback was running');

    Raised:=False;
    try
      Check(not TTask.WaitForAll([Task],25),'WaitForAll completed early');
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(not Raised,'WaitForAll raised while callback was running');

    Raised:=False;
    try
      Check(TTask.WaitForAny([Task],25)=-1,'WaitForAny completed early');
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(not Raised,'WaitForAny raised while callback was running');
    Check(Finished=0,'callback passed its release gate');

    ReleaseTask.SetEvent;
    Raised:=False;
    try
      Task.Wait(2000);
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(Raised,'completed cancellation was not reported');
    Check(Finished=1,'callback did not finish before cancellation was reported');
    Check(Task.Status=TTaskStatus.Canceled,'completed cancellation status');
  finally
    ReleaseTask.SetEvent;
    if Task<>nil then
      try
        Task.Wait(2000);
      except
        on EOperationCancelled do
          ;
      end;
    ReleaseTask.Free;
    Started.Free;
  end;
end;

procedure CheckQueuedCancellation;
var
  Pool: TThreadPool;
  BlockerStarted, ReleaseBlocker: TEvent;
  Blocker, Task: ITask;
  Executed: LongInt;
  Raised: Boolean;
begin
  Pool:=TThreadPool.Create;
  BlockerStarted:=TEvent.Create(nil,True,False,'');
  ReleaseBlocker:=TEvent.Create(nil,True,False,'');
  try
    Check(Pool.SetMinWorkerThreads(0),'queued pool minimum');
    Check(Pool.SetMaxWorkerThreads(1),'queued pool maximum');
    { the task must stay queued behind the blocker: no thread past the maximum }
    Pool.UnlimitedWorkerThreadsWhenBlocked:=False;
    Blocker:=TTask.Run(
      procedure
      begin
        BlockerStarted.SetEvent;
        ReleaseBlocker.WaitFor(2000);
      end,Pool);
    Check(BlockerStarted.WaitFor(2000)=wrSignaled,'blocker did not start');
    Executed:=0;
    Task:=TTask.Run(
      procedure
      begin
        AtomicIncrement(Executed);
      end,Pool);
    Task.Cancel;
    Raised:=False;
    try
      Task.Wait(100);
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(Raised,'queued cancellation was not terminal immediately');
    Raised:=False;
    try
      TTask.WaitForAll([Task],100);
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(Raised,'WaitForAll missed queued cancellation');
    Raised:=False;
    try
      TTask.WaitForAny([Task],100);
    except
      on EOperationCancelled do
        Raised:=True;
    end;
    Check(Raised,'WaitForAny missed queued cancellation');
    Check(Task.Status=TTaskStatus.Canceled,'queued cancellation status');
    Check(Executed=0,'queued callback ran before blocker release');
    ReleaseBlocker.SetEvent;
    Check(Blocker.Wait(2000),'blocker did not finish');
    TThread.Sleep(25);
    Check(Executed=0,'canceled queued callback executed');
  finally
    ReleaseBlocker.SetEvent;
    if Blocker<>nil then
      Blocker.Wait(2000);
    Pool.Free;
    ReleaseBlocker.Free;
    BlockerStarted.Free;
  end;
end;

begin
  CheckQueuedCancellation;
  CheckRunningCancellation;
  WriteLn('TASK_RUNNING_CANCEL_SEMANTIC_PASS');
end.
