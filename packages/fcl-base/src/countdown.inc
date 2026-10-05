{ A reusable completion counter. The event and count change under one lock. }

constructor TCountdownEvent.Create;
begin
  Create(1, 0);
end;

constructor TCountdownEvent.Create(Count: Integer);
begin
  Create(Count, 0);
end;

constructor TCountdownEvent.Create(Count, SpinCount: Integer);
begin
  inherited Create;
  If (Count < 0) or (SpinCount > 4095) then
    raise EArgumentOutOfRangeException.Create('Invalid count or spin count');
  FGuard := TCriticalSection.Create;
  FDone := TEvent.Create(nil, True, Count = 0, '');
  FInitial := Count;
  FRemaining := Count;
  If SpinCount > 0 then
    FSpinCount := SpinCount;
end;

destructor TCountdownEvent.Destroy;
begin
  FDone.Free;
  FGuard.Free;
  inherited Destroy;
end;

function TCountdownEvent.Signal(Count: Integer): Boolean;
begin
  If Count <= 0 then
    raise EArgumentOutOfRangeException.Create('Signal count must be positive');
  FGuard.Enter;
  try
    If Count > FRemaining then
      raise EInvalidOperation.Create('Signal exceeds the remaining count');
    Dec(FRemaining, Count);
    Result := FRemaining = 0;
    If Result then
      FDone.SetEvent;
  finally
    FGuard.Leave;
  end;
end;

function TCountdownEvent.TryAddCount(Count: Integer): Boolean;
begin
  If Count <= 0 then
    raise EArgumentOutOfRangeException.Create('Added count must be positive');
  FGuard.Enter;
  try
    Result := FRemaining <> 0;
    If not Result then
      Exit;
    If Count > High(Integer) - FRemaining then
      raise EInvalidOperation.Create('Countdown overflow');
    Inc(FRemaining, Count);
  finally
    FGuard.Leave;
  end;
end;

procedure TCountdownEvent.AddCount(Count: Integer);
begin
  If not TryAddCount(Count) then
    raise EInvalidOperation.Create('A completed countdown must be reset before adding work');
end;

procedure TCountdownEvent.Reset;
begin
  FGuard.Enter;
  try
    Reset(FInitial);
  finally
    FGuard.Leave;
  end;
end;

procedure TCountdownEvent.Reset(Count: Integer);
begin
  If Count < 0 then
    raise EArgumentOutOfRangeException.Create('Count must not be negative');
  FGuard.Enter;
  try
    FInitial := Count;
    FRemaining := Count;
    If Count = 0 then
      FDone.SetEvent
    else
      FDone.ResetEvent;
  finally
    FGuard.Leave;
  end;
end;

function TCountdownEvent.GetCurrentCount: Integer;
begin
  FGuard.Enter;
  try
    Result := FRemaining;
  finally
    FGuard.Leave;
  end;
end;

function TCountdownEvent.GetInitialCount: Integer;
begin
  FGuard.Enter;
  try
    Result := FInitial;
  finally
    FGuard.Leave;
  end;
end;

function TCountdownEvent.GetIsSet: Boolean;
begin
  Result := GetCurrentCount = 0;
end;

function TCountdownEvent.WaitFor(Timeout: Cardinal): TWaitResult;
var
  Spin: TSpinWait;
  Started, Elapsed: QWord;
  I: Integer;
begin
  If GetIsSet then
    Exit(wrSignaled);
  If Timeout = 0 then
    Exit(wrTimeout);
  Started := GetTickCount64;
  Spin.Reset;
  for I := 1 to FSpinCount do begin
    If GetIsSet then
      Exit(wrSignaled);
    If (Timeout <> INFINITE) and (GetTickCount64 - Started >= Timeout) then
      Exit(wrTimeout);
    Spin.SpinCycle;
  end;
  If Timeout <> INFINITE then begin
    Elapsed := GetTickCount64 - Started;
    If Elapsed >= Timeout then
      Exit(wrTimeout);
    Dec(Timeout, Elapsed);
  end;
  Result := FDone.WaitFor(Timeout);
end;
