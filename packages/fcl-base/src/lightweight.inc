{ Independent implementations over the existing monitor. Observing a signaled
  event or consuming an available permit needs no monitor or OS wait. The
  monitor serializes waiter registration and wakeup, including Set/Reset races. }

function RemainingWait(Start: QWord; Timeout: Cardinal): Cardinal;
var
  Elapsed: QWord;
begin
  Result:=Timeout;
  if Timeout=INFINITE then
    Exit;
  Elapsed:=GetTickCount64-Start;
  if Elapsed>=Timeout then
    Result:=0
  else
    Result:=Timeout-Elapsed;
end;

constructor TLightweightEvent.Create;
begin
  Create(False,10);
end;

constructor TLightweightEvent.Create(InitialState: Boolean);
begin
  Create(InitialState,10);
end;

constructor TLightweightEvent.Create(InitialState: Boolean; SpinCount: Integer);
begin
  inherited Create;
  if (SpinCount<0) or (SpinCount>4095) then
    raise EArgumentOutOfRangeException.Create('Spin count must be between 0 and 4095');
  FSpinCount:=SpinCount;
  FGuard:=TObject.Create;
  FSignaled:=Ord(InitialState);
end;

destructor TLightweightEvent.Destroy;
begin
  FGuard.Free;
  inherited Destroy;
end;

function TLightweightEvent.GetIsSet: Boolean;
begin
  Result:=InterlockedCompareExchange(FSignaled,0,0)<>0;
end;

procedure TLightweightEvent.SetEvent;
begin
  TMonitor.Enter(FGuard);
  try
    if IsSet then
      Exit;
    InterlockedExchange(FSignaled,1);
    {$PUSH}{$Q-}
    Inc(FGeneration);
    {$POP}
    TMonitor.PulseAll(FGuard);
  finally
    TMonitor.Exit(FGuard);
  end;
end;

procedure TLightweightEvent.ResetEvent;
begin
  TMonitor.Enter(FGuard);
  try
    InterlockedExchange(FSignaled,0);
  finally
    TMonitor.Exit(FGuard);
  end;
end;

procedure TLightweightEvent.Acquire;
begin
  WaitFor;
end;

function TLightweightEvent.WaitFor(Timeout: Cardinal): TWaitResult;
var
  I: Integer;
  Start, Generation: QWord;
  Remaining: Cardinal;
begin
  if IsSet then
    Exit(wrSignaled);
  if Timeout=0 then
    Exit(wrTimeout);
  Start:=GetTickCount64;
  for I:=1 to FSpinCount do
  begin
    TThread.SpinWait(1);
    if IsSet then
      Exit(wrSignaled);
  end;
  TMonitor.Enter(FGuard);
  try
    if IsSet then
      Exit(wrSignaled);
    Remaining:=RemainingWait(Start,Timeout);
    if Remaining=0 then
      Exit(wrTimeout);
    InterlockedIncrement(FBlockedCount);
    Generation:=FGeneration;
    repeat
      TMonitor.Wait(FGuard,Remaining);
      { A waiter released by Set stays released even if Reset runs before
        this thread reacquires the monitor. A new waiter sees the new epoch. }
      if IsSet or (Generation<>FGeneration) then
        Exit(wrSignaled);
      Remaining:=RemainingWait(Start,Timeout);
    until Remaining=0;
    Result:=wrTimeout;
  finally
    TMonitor.Exit(FGuard);
  end;
end;

constructor TLightweightSemaphore.Create(InitialCount: Integer; MaximumCount: Integer);
begin
  inherited Create;
  if (MaximumCount<=0) or (InitialCount<0) or (InitialCount>MaximumCount) then
    raise EArgumentOutOfRangeException.Create('Invalid semaphore counts');
  FCount:=InitialCount;
  FMaximum:=MaximumCount;
  FGuard:=TObject.Create;
end;

destructor TLightweightSemaphore.Destroy;
begin
  FGuard.Free;
  inherited Destroy;
end;

function TLightweightSemaphore.GetCurrentCount: Integer;
begin
  Result:=InterlockedCompareExchange(FCount,0,0);
end;

function TLightweightSemaphore.TryAcquire: Boolean;
var
  Available: Integer;
begin
  repeat
    Available:=CurrentCount;
    if Available=0 then
      Exit(False);
  until InterlockedCompareExchange(FCount,Available-1,Available)=Available;
  Result:=True;
end;

procedure TLightweightSemaphore.Acquire;
begin
  WaitFor;
end;

function TLightweightSemaphore.Release(Count: Integer): Integer;
begin
  if Count<=0 then
    raise EArgumentOutOfRangeException.Create('Release count must be positive');
  repeat
    Result:=CurrentCount;
    if Count>FMaximum-Result then
      raise ESyncObjectException.Create('Semaphore maximum would be exceeded');
  until InterlockedCompareExchange(FCount,Result+Count,Result)=Result;
  if InterlockedCompareExchange(FWaiters,0,0)=0 then
    Exit;
  TMonitor.Enter(FGuard);
  try
    TMonitor.PulseAll(FGuard);
  finally
    TMonitor.Exit(FGuard);
  end;
end;

function TLightweightSemaphore.WaitFor(Timeout: Cardinal): TWaitResult;
var
  I: Integer;
  Start: QWord;
  Remaining: Cardinal;
begin
  if TryAcquire then
    Exit(wrSignaled);
  if Timeout=0 then
    Exit(wrTimeout);
  Start:=GetTickCount64;
  for I:=1 to 10 do
  begin
    TThread.SpinWait(1);
    if TryAcquire then
      Exit(wrSignaled);
  end;
  TMonitor.Enter(FGuard);
  InterlockedIncrement(FWaiters);
  try
    if TryAcquire then
      Exit(wrSignaled);
    Remaining:=RemainingWait(Start,Timeout);
    if Remaining=0 then
      Exit(wrTimeout);
    InterlockedIncrement(FBlockedCount);
    repeat
      TMonitor.Wait(FGuard,Remaining);
      if TryAcquire then
        Exit(wrSignaled);
      Remaining:=RemainingWait(Start,Timeout);
    until Remaining=0;
    Result:=wrTimeout;
  finally
    InterlockedDecrement(FWaiters);
    TMonitor.Exit(FGuard);
  end;
end;
