program posix_wait_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  SyncObjs;

type
  TMutexHolderThread = class(TThread)
  private
    FMutex: TMutex;
    FReady, FRelease: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AMutex: TMutex; AReady, ARelease: TEvent);
  end;

constructor TMutexHolderThread.Create(AMutex: TMutex;
  AReady, ARelease: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FMutex := AMutex;
  FReady := AReady;
  FRelease := ARelease;
end;

procedure TMutexHolderThread.Execute;
begin
  FMutex.Acquire;
  try
    FReady.SetEvent;
    FRelease.WaitFor(INFINITE);
  finally
    FMutex.Release;
  end;
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('POSIX_WAIT_SEMANTIC_FAIL: ' + MessageText);
end;

procedure TestWaitResults;
var
  EmptySemaphore: TSemaphore;
  Holder: TMutexHolderThread;
  Mutex: TMutex;
  ReadyEvent, ReleaseEvent: TEvent;
  SemaphorePoll, SemaphoreTimed, MutexPoll, MutexTimed: TWaitResult;
begin
  EmptySemaphore := TSemaphore.Create(nil, 0, 1, '');
  try
    SemaphorePoll := EmptySemaphore.WaitFor(0);
    SemaphoreTimed := EmptySemaphore.WaitFor(2);
  finally
    EmptySemaphore.Free;
  end;

  Mutex := TMutex.Create;
  ReadyEvent := TEvent.Create(nil, True, False, '');
  ReleaseEvent := TEvent.Create(nil, True, False, '');
  Holder := TMutexHolderThread.Create(Mutex, ReadyEvent, ReleaseEvent);
  try
    Holder.Start;
    Check(ReadyEvent.WaitFor(5000) = wrSignaled, 'holder start');
    MutexPoll := Mutex.WaitFor(0);
    MutexTimed := Mutex.WaitFor(2);
    ReleaseEvent.SetEvent;
    Holder.WaitFor;
    Check(Holder.FatalException = nil, 'holder exception');
    Check(Mutex.WaitFor(100) = wrSignaled, 'mutex acquire after release');
    Mutex.Release;
  finally
    ReleaseEvent.SetEvent;
    Holder.WaitFor;
    Holder.Free;
    ReleaseEvent.Free;
    ReadyEvent.Free;
    Mutex.Free;
  end;

  Check((SemaphorePoll = wrTimeout) and (SemaphoreTimed = wrTimeout) and
    (MutexPoll = wrTimeout) and (MutexTimed = wrTimeout),
    Format('results semaphore=%d/%d mutex=%d/%d',
      [Ord(SemaphorePoll), Ord(SemaphoreTimed), Ord(MutexPoll),
       Ord(MutexTimed)]));
end;

begin
  try
    TestWaitResults;
    WriteLn('POSIX_WAIT_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
