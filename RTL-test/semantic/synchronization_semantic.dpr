program synchronization_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes,
  SyncObjs;

threadvar
  LocalValue: Integer;

type
  TIncrementThread = class(TThread)
  private
    FBase: Integer;
    FCount: Integer;
    FCritical: TCriticalSection;
    FTarget: PInt64;
  protected
    procedure Execute; override;
  public
    constructor Create(ACritical: TCriticalSection; ATarget: PInt64;
      ACount, ABase: Integer);
  end;

  TRaisingThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

constructor TIncrementThread.Create(ACritical: TCriticalSection;
  ATarget: PInt64; ACount, ABase: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FCritical := ACritical;
  FTarget := ATarget;
  FCount := ACount;
  FBase := ABase;
end;

procedure TIncrementThread.Execute;
var
  I: Integer;
begin
  LocalValue := FBase;
  for I := 1 to FCount do
  begin
    FCritical.Enter;
    Inc(FTarget^);
    FCritical.Leave;
  end;
  if LocalValue <> FBase then
    raise Exception.Create('threadvar isolation');
end;

procedure TRaisingThread.Execute;
begin
  raise EAbort.Create('thread-expected');
end;

procedure TestCriticalSectionAndThreads;
var
  Counter: Int64;
  Critical: TCriticalSection;
  First, Second: TIncrementThread;
begin
  LocalValue := 77;
  Counter := 0;
  Critical := TCriticalSection.Create;
  try
    Critical.Enter;
    Check(Critical.TryEnter, 'critical section recursive TryEnter');
    Critical.Leave;
    Critical.Leave;
    First := TIncrementThread.Create(Critical, @Counter, 50000, 101);
    Second := TIncrementThread.Create(Critical, @Counter, 50000, 202);
    try
      First.Start;
      Second.Start;
      First.WaitFor;
      Second.WaitFor;
      Check((First.FatalException = nil) and (Second.FatalException = nil),
        'worker thread no exception');
      Check(Counter = 100000, 'critical section contended exact count');
      Check(LocalValue = 77, 'main threadvar isolation');
    finally
      Second.Free;
      First.Free;
    end;
  finally
    Critical.Free;
  end;
end;

procedure TestEventsMutexSemaphore;
var
  AutoEvent, ManualEvent: TEvent;
  Mutex: TMutex;
  Semaphore: TSemaphore;
  WaitResult: TWaitResult;
begin
  ManualEvent := TEvent.Create(nil, True, False, '');
  AutoEvent := TEvent.Create(nil, False, False, '');
  try
    Check(ManualEvent.WaitFor(0) = wrTimeout, 'manual event timeout');
    ManualEvent.SetEvent;
    Check(ManualEvent.WaitFor(0) = wrSignaled, 'manual event signal');
    Check(ManualEvent.WaitFor(0) = wrSignaled, 'manual event remains signaled');
    ManualEvent.ResetEvent;
    Check(ManualEvent.WaitFor(0) = wrTimeout, 'manual event reset');
    AutoEvent.SetEvent;
    Check(AutoEvent.WaitFor(0) = wrSignaled, 'auto event signal');
    Check(AutoEvent.WaitFor(0) = wrTimeout, 'auto event consumes signal');
  finally
    AutoEvent.Free;
    ManualEvent.Free;
  end;

  Mutex := TMutex.Create;
  try
    Check(Mutex.WaitFor(0) = wrSignaled, 'mutex immediate acquire');
    Mutex.Release;
    Mutex.Acquire;
    Mutex.Release;
  finally
    Mutex.Free;
  end;

  Semaphore := TSemaphore.Create(nil, 1, 2, '');
  try
    Check(Semaphore.WaitFor(0) = wrSignaled, 'semaphore initial token');
    WaitResult := Semaphore.WaitFor(0);
    Check(WaitResult = wrTimeout, 'semaphore empty timeout result=' +
      IntToStr(Ord(WaitResult)));
    Check(Semaphore.Release(2) >= 0, 'semaphore release count');
    Check(Semaphore.WaitFor(0) = wrSignaled, 'semaphore first released token');
    Check(Semaphore.WaitFor(0) = wrSignaled, 'semaphore second released token');
    Check(Semaphore.WaitFor(0) = wrTimeout, 'semaphore tokens consumed');
  finally
    Semaphore.Free;
  end;
end;

procedure TestInterlocked;
var
  Succeeded: Boolean;
  Value32: LongInt;
  Value64: Int64;
begin
  Value32 := 0;
  Check(TInterlocked.Increment(Value32) = 1, 'interlocked increment 32');
  Check(TInterlocked.Add(Value32, 4) = 5, 'interlocked add 32');
  Check(TInterlocked.CompareExchange(Value32, 9, 5, Succeeded) = 5,
    'interlocked compare-exchange previous 32');
  Check(Succeeded and (Value32 = 9), 'interlocked compare-exchange success 32');
  Check(TInterlocked.Decrement(Value32) = 8, 'interlocked decrement 32');

  Value64 := 0;
  Check(TInterlocked.Increment(Value64) = 1, 'interlocked increment 64');
  Check(TInterlocked.Add(Value64, High(LongInt)) = Int64(High(LongInt)) + 1,
    'interlocked add 64');
  Check(TInterlocked.Exchange(Value64, -7) = Int64(High(LongInt)) + 1,
    'interlocked exchange previous 64');
  Check((Value64 = -7) and (TInterlocked.Read(Value64) = -7),
    'interlocked exchange/read 64');
end;

procedure TestThreadException;
var
  Thread: TRaisingThread;
begin
  Thread := TRaisingThread.Create(True);
  try
    Thread.FreeOnTerminate := False;
    Thread.Start;
    Thread.WaitFor;
    Check(Thread.FatalException is EAbort, 'thread exception captured');
    Check(Exception(Thread.FatalException).Message = 'thread-expected',
      'thread exception message');
  finally
    Thread.Free;
  end;
end;

begin
  try
    TestCriticalSectionAndThreads;
    TestEventsMutexSemaphore;
    TestInterlocked;
    TestThreadException;
    WriteLn('SYNCHRONIZATION_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
