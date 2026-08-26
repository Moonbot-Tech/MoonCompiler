program task_wait_semantic;

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
  System.Diagnostics,
  System.TimeSpan,
  System.Threading;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('TASK_WAIT_FAIL: '+AMessage);
end;

procedure CheckEmptyAndNil;
var
  NilTask: ITask;
  Raised: Boolean;
begin
  Check(TTask.WaitForAll([]),'empty WaitForAll');
  Check(TTask.WaitForAny([])=-1,'empty WaitForAny');

  NilTask:=Nil;
  Raised:=False;
  try
    TTask.WaitForAll([NilTask]);
  except
    on EArgumentNilException do
      Raised:=True;
  end;
  Check(Raised,'WaitForAll nil task');

  Raised:=False;
  try
    TTask.WaitForAny([NilTask]);
  except
    on EArgumentNilException do
      Raised:=True;
  end;
  Check(Raised,'WaitForAny nil task');
end;

procedure CheckCompletedAndMixed(APool: TThreadPool);
var
  DoneTask, PendingTask: ITask;
  Gate: TEvent;
begin
  DoneTask:=TTask.Run(procedure begin end,APool);
  Check(DoneTask.Wait(2000),'complete task');
  Check(TTask.WaitForAny([DoneTask])=0,'already-complete WaitForAny');
  Check(TTask.WaitForAll([DoneTask]),'already-complete WaitForAll');

  Gate:=TEvent.Create(Nil,True,False,'');
  try
    PendingTask:=TTask.Run(
      procedure
      begin
        if Gate.WaitFor(2000)<>wrSignaled then
          raise Exception.Create('pending task gate timeout');
      end,APool);
    Check(not TTask.WaitForAll([DoneTask,PendingTask],0),
      'mixed WaitForAll zero timeout');
    Gate.SetEvent;
    Check(TTask.WaitForAll([DoneTask,PendingTask],2000),
      'mixed WaitForAll completion');
  finally
    Gate.SetEvent;
    if PendingTask<>Nil then
      PendingTask.Wait(2000);
    Gate.Free;
  end;
end;

procedure CheckFiniteAndInfinite(APool: TThreadPool);
var
  SlowTask, FastTask: ITask;
  Gate: TEvent;
  Watch: TStopwatch;
  Index: Integer;
begin
  Gate:=TEvent.Create(Nil,True,False,'');
  try
    SlowTask:=TTask.Run(
      procedure
      begin
        if Gate.WaitFor(2000)<>wrSignaled then
          raise Exception.Create('slow task gate timeout');
      end,APool);
    FastTask:=TTask.Run(
      procedure
      begin
        TThread.Sleep(40);
      end,APool);
    Watch:=TStopwatch.StartNew;
    Index:=TTask.WaitForAny([SlowTask,FastTask],1000);
    Watch.Stop;
    Check(Index=1,'finite WaitForAny index');
    Check(Watch.ElapsedMilliseconds>=10,'finite WaitForAny waited');
    Gate.SetEvent;
    Check(TTask.WaitForAll([SlowTask,FastTask],2000),
      'finite WaitForAll completion');
  finally
    Gate.SetEvent;
    if SlowTask<>Nil then
      SlowTask.Wait(2000);
    if FastTask<>Nil then
      FastTask.Wait(2000);
    Gate.Free;
  end;

  FastTask:=TTask.Run(
    procedure
    begin
      TThread.Sleep(20);
    end,APool);
  Check(TTask.WaitForAny([FastTask])=0,'infinite WaitForAny');
  Check(TTask.WaitForAll([FastTask]),'infinite WaitForAll');
end;

procedure CheckTimeout(APool: TThreadPool);
var
  Task1, Task2: ITask;
  Gate: TEvent;
  Watch: TStopwatch;
begin
  Gate:=TEvent.Create(Nil,True,False,'');
  try
    Task1:=TTask.Run(procedure begin Gate.WaitFor(2000); end,APool);
    Task2:=TTask.Run(procedure begin Gate.WaitFor(2000); end,APool);
    Watch:=TStopwatch.StartNew;
    Check(TTask.WaitForAny([Task1,Task2],40)=-1,'WaitForAny timeout');
    Watch.Stop;
    Check(Watch.ElapsedMilliseconds>=10,'WaitForAny timeout not immediate');
    Check(not TTask.WaitForAll([Task1,Task2],0),'WaitForAll timeout');
    Gate.SetEvent;
    Check(TTask.WaitForAll([Task1,Task2],2000),'tasks after timeout');
  finally
    Gate.SetEvent;
    if Task1<>Nil then
      Task1.Wait(2000);
    if Task2<>Nil then
      Task2.Wait(2000);
    Gate.Free;
  end;
end;

procedure CheckExceptionsAndCancellation(APool: TThreadPool);
var
  Task: ITask;
  Raised: Boolean;
begin
  Task:=TTask.Run(
    procedure
    begin
      raise Exception.Create('expected task failure');
    end,APool);
  WriteLn('task-wait: WaitForAll exception');
  Raised:=False;
  try
    TTask.WaitForAll([Task]);
  except
    on EAggregateException do
      Raised:=True;
  end;
  Check(Raised,'WaitForAll aggregate exception');

  Task:=TTask.Run(
    procedure
    begin
      raise Exception.Create('expected task failure');
    end,APool);
  WriteLn('task-wait: WaitForAny exception');
  Raised:=False;
  try
    TTask.WaitForAny([Task]);
  except
    on EAggregateException do
      Raised:=True;
  end;
  Check(Raised,'WaitForAny aggregate exception');

  Task:=TTask.Create(procedure begin end,APool);
  Task.Cancel;
  WriteLn('task-wait: WaitForAll cancellation');
  Raised:=False;
  try
    TTask.WaitForAll([Task]);
  except
    on EOperationCancelled do
      Raised:=True;
  end;
  Check(Raised,'WaitForAll cancellation');

  Task:=TTask.Create(procedure begin end,APool);
  Task.Cancel;
  WriteLn('task-wait: WaitForAny cancellation');
  Raised:=False;
  try
    TTask.WaitForAny([Task]);
  except
    on EOperationCancelled do
      Raised:=True;
  end;
  Check(Raised,'WaitForAny cancellation');
end;

procedure CheckInteractive;
var
  Pool: TThreadPool;
  Task: ITask;
  OldInteractive: Boolean;
begin
  Pool:=TThreadPool.Default;
  OldInteractive:=Pool.Interactive;
  try
    Pool.Interactive:=True;
    Task:=TTask.Run(
      procedure
      begin
        TThread.Sleep(20);
      end,Pool);
    Check(Task.Wait(2000),'interactive task Wait');

    Task:=TTask.Run(
      procedure
      begin
        TThread.Sleep(20);
      end,Pool);
    Check(TTask.WaitForAll([Task],2000),'interactive WaitForAll');

    Task:=TTask.Run(
      procedure
      begin
        TThread.Sleep(20);
      end,Pool);
    Check(TTask.WaitForAny([Task],2000)=0,'interactive WaitForAny');
  finally
    Pool.Interactive:=OldInteractive;
  end;
end;

procedure CheckTimespan(APool: TThreadPool);
var
  Task: ITask;
  Raised: Boolean;
begin
  Task:=TTask.Run(procedure begin end,APool);
  Check(TTask.WaitForAll([Task],TTimeSpan.Create(0,0,0,0,2000)),
    'WaitForAll timespan');
  Check(TTask.WaitForAny([Task],TTimeSpan.Create(0,0,0,0,2000))=0,
    'WaitForAny timespan');
  Raised:=False;
  try
    TTask.WaitForAny([Task],TTimeSpan.FromMilliseconds(-1));
  except
    on EArgumentOutOfRangeException do
      Raised:=True;
  end;
  Check(Raised,'negative timespan');
end;

var
  Pool: TThreadPool;

begin
  Pool:=TThreadPool.Default;
  WriteLn('task-wait: empty/nil');
  CheckEmptyAndNil;
  WriteLn('task-wait: completed/mixed');
  CheckCompletedAndMixed(Pool);
  WriteLn('task-wait: finite/infinite');
  CheckFiniteAndInfinite(Pool);
  WriteLn('task-wait: timeout');
  CheckTimeout(Pool);
  WriteLn('task-wait: exceptions/cancellation');
  CheckExceptionsAndCancellation(Pool);
  WriteLn('task-wait: timespan');
  CheckTimespan(Pool);
  WriteLn('task-wait: interactive');
  CheckInteractive;
  WriteLn('TASK_WAIT_SEMANTIC_PASS');
end.
