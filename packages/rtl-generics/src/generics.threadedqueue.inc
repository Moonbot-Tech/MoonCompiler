{ MoonCompiler bounded producer/consumer queue. No worker threads or polling. }

constructor TThreadedQueue<T>.Create(AQueueDepth: Integer; PushTimeout, PopTimeout: Cardinal);
begin
  inherited Create;
  InitCriticalSection(FGuard);
  If AQueueDepth < 0 then
    raise EArgumentOutOfRangeException.Create('Queue depth must not be negative');
  SetLength(FBuffer, AQueueDepth);
  FPushTimeout := PushTimeout;
  FPopTimeout := PopTimeout;
  FReadable := BasicEventCreate(nil, True, False, '');
  FWritable := BasicEventCreate(nil, True, AQueueDepth > 0, '');
  If (FReadable = nil) or (FWritable = nil) then
    raise EInvalidOperation.Create('Cannot create queue events');
end;

destructor TThreadedQueue<T>.Destroy;
begin
  { Object lifetime belongs to the caller; no thread may still use this instance. }
  If FReadable <> nil then
    BasicEventDestroy(FReadable);
  If FWritable <> nil then
    BasicEventDestroy(FWritable);
  DoneCriticalSection(FGuard);
  inherited Destroy;
end;

function TThreadedQueue<T>.WaitReady(Event: PEventState; Timeout: Cardinal; Started: QWord): TWaitResult;
var
  Elapsed: QWord;
begin
  If Timeout <> High(Cardinal) then begin
    Elapsed := GetTickCount64 - Started;
    If Elapsed >= Timeout then
      Exit(wrTimeout);
    Dec(Timeout, Elapsed);
  end;
  Result := TWaitResult(BasicEventWaitFor(Timeout, Event));
end;

function TThreadedQueue<T>.PushItem(const AItem: T; out AQueueSize: NativeInt): TWaitResult;
var
  Started: QWord;
  Tail: NativeInt;
begin
  Started := GetTickCount64;
  repeat
    EnterCriticalSection(FGuard);
    try
      AQueueSize := FCount;
      If FClosed then
        Exit(wrSignaled); // Delphi signals shutdown without accepting another item.
      If FCount < Length(FBuffer) then begin
        Tail := FHead + FCount;
        If Tail >= Length(FBuffer) then
          Dec(Tail, Length(FBuffer));
        FBuffer[Tail] := AItem;
        Inc(FCount);
        Inc(FPushed);
        AQueueSize := FCount;
        If FCount = 1 then
          BasicEventSetEvent(FReadable);
        If FCount = Length(FBuffer) then
          BasicEventResetEvent(FWritable);
        Exit(wrSignaled);
      end;
    finally
      LeaveCriticalSection(FGuard);
    end;
    Result := WaitReady(FWritable, FPushTimeout, Started);
  until Result <> wrSignaled;
end;

function TThreadedQueue<T>.PopItem(out AQueueSize: NativeInt; var AItem: T): TWaitResult;
var
  Started: QWord;
begin
  AItem := Default(T);
  Started := GetTickCount64;
  repeat
    EnterCriticalSection(FGuard);
    try
      AQueueSize := FCount;
      If FCount > 0 then begin
        AItem := FBuffer[FHead];
        FBuffer[FHead] := Default(T);
        Inc(FHead);
        If FHead = Length(FBuffer) then
          FHead := 0;
        Dec(FCount);
        Inc(FPopped);
        AQueueSize := FCount;
        If not FClosed then begin
          If FCount = 0 then
            BasicEventResetEvent(FReadable);
          If FCount = Length(FBuffer) - 1 then
            BasicEventSetEvent(FWritable);
        end;
        Exit(wrSignaled);
      end;
      If FClosed then
        Exit(wrSignaled);
    finally
      LeaveCriticalSection(FGuard);
    end;
    Result := WaitReady(FReadable, FPopTimeout, Started);
  until Result <> wrSignaled;
end;

procedure TThreadedQueue<T>.Grow(ADelta: NativeInt);
var
  Expanded: array of T;
  I, Source: NativeInt;
begin
  If ADelta = 0 then
    Exit;
  EnterCriticalSection(FGuard);
  try
    If ((ADelta > 0) and (ADelta > High(NativeInt) - Length(FBuffer))) or
      (ADelta < FCount - Length(FBuffer)) then
      raise EArgumentOutOfRangeException.Create('Queue capacity overflow');
    SetLength(Expanded, Length(FBuffer) + ADelta);
    Source := FHead;
    for I := 0 to FCount - 1 do begin
      Expanded[I] := FBuffer[Source];
      Inc(Source);
      If Source = Length(FBuffer) then
        Source := 0;
    end;
    FBuffer := Expanded;
    FHead := 0;
    If FClosed or (FCount < Length(FBuffer)) then
      BasicEventSetEvent(FWritable)
    else
      BasicEventResetEvent(FWritable);
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

procedure TThreadedQueue<T>.DoShutDown;
begin
  EnterCriticalSection(FGuard);
  try
    FClosed := True;
    BasicEventSetEvent(FReadable);
    BasicEventSetEvent(FWritable);
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

function TThreadedQueue<T>.GetQueueSize: NativeInt;
begin
  EnterCriticalSection(FGuard);
  try
    Result := FCount;
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

function TThreadedQueue<T>.GetShutDown: Boolean;
begin
  EnterCriticalSection(FGuard);
  try
    Result := FClosed;
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

function TThreadedQueue<T>.GetTotalItemsPushed: UInt64;
begin
  EnterCriticalSection(FGuard);
  try
    Result := FPushed;
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

function TThreadedQueue<T>.GetTotalItemsPopped: UInt64;
begin
  EnterCriticalSection(FGuard);
  try
    Result := FPopped;
  finally
    LeaveCriticalSection(FGuard);
  end;
end;

function TThreadedQueue<T>.PushItem(const AItem: T): TWaitResult;
var
  Count: NativeInt;
begin
  Result := PushItem(AItem, Count);
end;

function TThreadedQueue<T>.PopItem(var AItem: T): TWaitResult;
var
  Count: NativeInt;
begin
  Result := PopItem(Count, AItem);
end;

function TThreadedQueue<T>.PopItem: T;
var
  Count: NativeInt;
begin
  Result := Default(T);
  PopItem(Count, Result);
end;

function TThreadedQueue<T>.PopItem(out AQueueSize: NativeInt): T;
begin
  Result := Default(T);
  PopItem(AQueueSize, Result);
end;

{$ifdef CPU64}
function TThreadedQueue<T>.PushItem(const AItem: T; out AQueueSize: Integer): TWaitResult;
var
  Count: NativeInt;
begin
  Result := PushItem(AItem, Count);
  AQueueSize := Count;
end;

function TThreadedQueue<T>.PopItem(out AQueueSize: Integer; var AItem: T): TWaitResult;
var
  Count: NativeInt;
begin
  Result := PopItem(Count, AItem);
  AQueueSize := Count;
end;

function TThreadedQueue<T>.PopItem(out AQueueSize: Integer): T;
begin
  Result := Default(T);
  PopItem(AQueueSize, Result);
end;
{$endif}
