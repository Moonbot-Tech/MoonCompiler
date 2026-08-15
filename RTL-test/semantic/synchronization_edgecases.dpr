program synchronization_edgecases;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  SyncObjs
  {$ifdef UNIX}
  ,BaseUnix,
  Unix,
  PThreads
  {$endif UNIX};

type
  TMutexHolder = class(TThread)
  private
    FMutex: TMutex;
    FReady, FRelease: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AMutex: TMutex; AReady, ARelease: TEvent);
  end;

  TSemaphoreWaiter = class(TThread)
  private
    FSemaphore: TSemaphore;
    FTimeout: Cardinal;
  protected
    procedure Execute; override;
  public
    ResultValue: TWaitResult;
    constructor Create(ASemaphore: TSemaphore; ATimeout: Cardinal);
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('SYNCHRONIZATION_EDGECASES_FAIL: '+AMessage);
end;

constructor TMutexHolder.Create(AMutex: TMutex; AReady, ARelease: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate:=False;
  FMutex:=AMutex;
  FReady:=AReady;
  FRelease:=ARelease;
end;

procedure TMutexHolder.Execute;
begin
  FMutex.Acquire;
  try
    FReady.SetEvent;
    FRelease.WaitFor(INFINITE);
  finally
    FMutex.Release;
  end;
end;

constructor TSemaphoreWaiter.Create(ASemaphore: TSemaphore;
  ATimeout: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate:=False;
  FSemaphore:=ASemaphore;
  FTimeout:=ATimeout;
  ResultValue:=wrError;
end;

procedure TSemaphoreWaiter.Execute;
begin
  ResultValue:=FSemaphore.WaitFor(FTimeout);
end;

procedure CheckBasicWaits;
var
  EmptySemaphore: TSemaphore;
  Holder: TMutexHolder;
  Mutex: TMutex;
  ReadyEvent, ReleaseEvent: TEvent;
begin
  EmptySemaphore:=TSemaphore.Create(nil,0,1,'');
  try
    Check(EmptySemaphore.WaitFor(0)=wrTimeout,'semaphore poll timeout');
    Check(EmptySemaphore.WaitFor(2)=wrTimeout,'semaphore finite timeout');
    EmptySemaphore.Release;
    Check(EmptySemaphore.WaitFor(100)=wrSignaled,'semaphore release');
  finally
    EmptySemaphore.Free;
  end;

  Mutex:=TMutex.Create;
  ReadyEvent:=TEvent.Create(nil,True,False,'');
  ReleaseEvent:=TEvent.Create(nil,True,False,'');
  Holder:=TMutexHolder.Create(Mutex,ReadyEvent,ReleaseEvent);
  try
    Holder.Start;
    Check(ReadyEvent.WaitFor(5000)=wrSignaled,'mutex holder ready');
    Check(Mutex.WaitFor(0)=wrTimeout,'mutex poll timeout');
    Check(Mutex.WaitFor(2)=wrTimeout,'mutex finite timeout');
    ReleaseEvent.SetEvent;
    Holder.WaitFor;
    Check(Holder.FatalException=nil,'mutex holder exception');
    Check(Mutex.WaitFor(100)=wrSignaled,'mutex after release');
    Mutex.Release;
  finally
    ReleaseEvent.SetEvent;
    Holder.WaitFor;
    Holder.Free;
    ReleaseEvent.Free;
    ReadyEvent.Free;
    Mutex.Free;
  end;
end;

{$ifdef UNIX}
procedure EmptySignalHandler(ASignal: LongInt); cdecl;
begin
end;

procedure CheckTimespecCarry;
var
  EmptySemaphore: TSemaphore;
  NowValue: TTimeVal;
begin
  repeat
    fpGetTimeOfDay(@NowValue,nil);
    if NowValue.tv_usec<900000 then
      Sleep(1);
  until NowValue.tv_usec>=900000;
  EmptySemaphore:=TSemaphore.Create(nil,0,1,'');
  try
    Check(EmptySemaphore.WaitFor(200)=wrTimeout,
      'absolute timeout crossing second boundary');
  finally
    EmptySemaphore.Free;
  end;
end;

procedure CheckInterruptedWaits;
var
  EmptySemaphore: TSemaphore;
  OldHandler: SignalHandler;
  Waiter: TSemaphoreWaiter;
begin
  OldHandler:=fpSignal(SIGUSR1,@EmptySignalHandler);
  Check(Assigned(OldHandler) or (fpGetErrNo=0),'install signal handler');
  EmptySemaphore:=TSemaphore.Create(nil,0,1,'');
  try
    Waiter:=TSemaphoreWaiter.Create(EmptySemaphore,INFINITE);
    try
      Waiter.Start;
      Sleep(20);
      Check(pthread_kill(Waiter.ThreadID,SIGUSR1)=0,'signal infinite waiter');
      Sleep(20);
      Check(not Waiter.Finished,'interrupted infinite wait remains active');
      EmptySemaphore.Release;
      Waiter.WaitFor;
      Check((Waiter.FatalException=nil) and (Waiter.ResultValue=wrSignaled),
        'interrupted infinite wait result');
    finally
      if not Waiter.Finished then
        EmptySemaphore.Release;
      Waiter.WaitFor;
      Waiter.Free;
    end;

    Waiter:=TSemaphoreWaiter.Create(EmptySemaphore,100);
    try
      Waiter.Start;
      Sleep(20);
      Check(pthread_kill(Waiter.ThreadID,SIGUSR1)=0,'signal timed waiter');
      Waiter.WaitFor;
      Check((Waiter.FatalException=nil) and (Waiter.ResultValue=wrTimeout),
        'interrupted timed wait reaches original deadline');
    finally
      Waiter.WaitFor;
      Waiter.Free;
    end;
  finally
    EmptySemaphore.Free;
    fpSignal(SIGUSR1,OldHandler);
  end;
end;
{$endif UNIX}

begin
  try
    CheckBasicWaits;
    {$ifdef UNIX}
    CheckTimespecCarry;
    CheckInterruptedWaits;
    {$endif UNIX}
    WriteLn('SYNCHRONIZATION_EDGECASES_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
