program monitor_exit;

{$mode delphi}{$H+}

uses
  {$ifdef UNIX}cthreads,{$endif}
  System.SysUtils, System.Classes, System.SyncObjs, System.Threading, monitor_probe;

var
  ReleaseWorker, WorkerStarted, QueuedStarted, IdleDone: TEvent;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then
    raise Exception.Create('MONITOR_EXIT_FAIL: '+Message);
end;

procedure CheckBlocked;
var
  Pool: TThreadPool;
begin
  Pool:=TThreadPool.Create;
  try
    Check(Pool.SetMinWorkerThreads(0) and Pool.SetMaxWorkerThreads(1),'limits');
    ProbeCPUUsage:=100;
    Pool.QueueWorkItem(
      procedure
      begin
        WorkerStarted.SetEvent;
        ReleaseWorker.WaitFor(30000);
      end);
    Check(WorkerStarted.WaitFor(5000)=wrSignaled,'first worker did not start');
    // The private unit uses two 500 ms idle rounds instead of the product's 60.
    Sleep(2200);
    Check(ProbeMonitorExits=0,'monitor exited with a busy worker');
    Pool.QueueWorkItem(procedure begin QueuedStarted.SetEvent end);
    Sleep(2200);
    Check(ProbeMonitorExits=0,'monitor exited with a busy worker and queued work');
    ProbeCPUUsage:=0;
    Check(QueuedStarted.WaitFor(5000)=wrSignaled,'queued work did not start after CPU became free');
  finally
    ReleaseWorker.SetEvent;
    Pool.Free;
  end;
end;

procedure CheckIdle;
var
  Pool: TThreadPool;
  Before: Integer;
  Deadline: QWord;
begin
  Pool:=TThreadPool.Create;
  try
    Check(Pool.SetMinWorkerThreads(0) and Pool.SetMaxWorkerThreads(1),'idle limits');
    Before:=ProbeMonitorExits;
    Pool.QueueWorkItem(procedure begin IdleDone.SetEvent end);
    Check(IdleDone.WaitFor(5000)=wrSignaled,'idle work did not finish');
    Deadline:=GetTickCount64+5000;
    while (ProbeMonitorExits=Before) and (GetTickCount64<Deadline) do
      Sleep(1);
    Check(ProbeMonitorExits>Before,'idle monitor did not exit');
  finally
    Pool.Free;
  end;
end;

begin
  ReleaseWorker:=TEvent.Create(nil,True,False,'');
  WorkerStarted:=TEvent.Create(nil,True,False,'');
  QueuedStarted:=TEvent.Create(nil,True,False,'');
  IdleDone:=TEvent.Create(nil,True,False,'');
  try
    CheckBlocked;
    CheckIdle;
  finally
    ReleaseWorker.Free;
    WorkerStarted.Free;
    QueuedStarted.Free;
    IdleDone.Free;
  end;
  WriteLn('MONITOR_EXIT_PASS');
end.
