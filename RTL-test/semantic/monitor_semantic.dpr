program monitor_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  {$ifdef WINDOWS}
  fpwinmonitor,
  {$else WINDOWS}
  fpmonitor,
  {$endif WINDOWS}
  SyncObjs;

type
  TMonitorHolder = class(TThread)
  private
    FObject: TObject;
    FReady, FRelease: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AObject: TObject; AReady, ARelease: TEvent);
  end;

  TMonitorWaiter = class(TThread)
  private
    FPulseObject, FLockObject: TObject;
    FReady: TEvent;
    FReadyCount: PLongInt;
    FReadyTarget: LongInt;
    FWaitResult: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(APulseObject, ALockObject: TObject; AReady: TEvent;
      AReadyCount: PLongInt; AReadyTarget: LongInt);
    property WaitResult: Boolean read FWaitResult;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('MONITOR_FAIL: ' + AMessage);
end;

constructor TMonitorHolder.Create(AObject: TObject; AReady, ARelease: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FObject := AObject;
  FReady := AReady;
  FRelease := ARelease;
end;

procedure TMonitorHolder.Execute;
begin
  TMonitor.Enter(FObject);
  try
    FReady.SetEvent;
    if FRelease.WaitFor(5000) <> wrSignaled then
      raise Exception.Create('holder release timeout');
  finally
    TMonitor.Exit(FObject);
  end;
end;

constructor TMonitorWaiter.Create(APulseObject, ALockObject: TObject;
  AReady: TEvent; AReadyCount: PLongInt; AReadyTarget: LongInt);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPulseObject := APulseObject;
  FLockObject := ALockObject;
  FReady := AReady;
  FReadyCount := AReadyCount;
  FReadyTarget := AReadyTarget;
end;

procedure TMonitorWaiter.Execute;
begin
  TMonitor.Enter(FLockObject);
  try
    if InterlockedIncrement(FReadyCount^) = FReadyTarget then
      FReady.SetEvent;
    FWaitResult := TMonitor.Wait(FPulseObject, FLockObject, 2000);
  finally
    TMonitor.Exit(FLockObject);
  end;
end;

procedure TestEnterTryRecursiveAndErrors;
var
  LockObject: TObject;
  OldSpinCount: LongInt;
  Raised: Boolean;
begin
  LockObject := TObject.Create;
  try
    TMonitor.Enter(LockObject);
    Check(TMonitor.TryEnter(LockObject), 'recursive TryEnter');
    Check(TMonitor.Enter(LockObject, 0), 'recursive timed Enter');
    TMonitor.Exit(LockObject);
    TMonitor.Exit(LockObject);
    TMonitor.Exit(LockObject);

    Raised := False;
    try
      TMonitor.Exit(LockObject);
    except
      on E: Exception do
        Raised := E.ClassName = 'EMonitor';
    end;
    Check(Raised, 'unowned Exit exception');

    Raised := False;
    try
      TMonitor.Wait(LockObject, 0);
    except
      on E: Exception do
        Raised := E.ClassName = 'EMonitor';
    end;
    Check(Raised, 'unowned Wait exception');

    OldSpinCount := TMonitor.DefaultSpinCount;
    TMonitor.DefaultSpinCount := 37;
    Check(TMonitor.DefaultSpinCount = 37, 'spin-count property');
    TMonitor.DefaultSpinCount := OldSpinCount;
  finally
    LockObject.Free;
  end;
end;

procedure TestContentionAndTimeout;
var
  LockObject: TObject;
  Ready, Release: TEvent;
  Holder: TMonitorHolder;
begin
  LockObject := TObject.Create;
  Ready := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
  Holder := TMonitorHolder.Create(LockObject, Ready, Release);
  try
    Holder.Start;
    Check(Ready.WaitFor(5000) = wrSignaled, 'holder ready');
    Check(not TMonitor.TryEnter(LockObject), 'contended TryEnter false');
    Check(not TMonitor.Enter(LockObject, 5), 'contended timed Enter false');
    Release.SetEvent;
    Holder.WaitFor;
    Check(Holder.FatalException = nil, 'holder completed');
    Check(TMonitor.Enter(LockObject, 1000), 'acquire after release');
    TMonitor.Exit(LockObject);
  finally
    Release.SetEvent;
    Holder.WaitFor;
    Holder.Free;
    Release.Free;
    Ready.Free;
    LockObject.Free;
  end;
end;

procedure TestWaitTimeoutRestoresRecursion;
var
  LockObject: TObject;
begin
  LockObject := TObject.Create;
  try
    TMonitor.Enter(LockObject);
    TMonitor.Enter(LockObject);
    Check(not TMonitor.Wait(LockObject, 5), 'Wait timeout');
    Check(TMonitor.TryEnter(LockObject), 'recursive ownership restored');
    TMonitor.Exit(LockObject);
    TMonitor.Exit(LockObject);
    TMonitor.Exit(LockObject);
  finally
    LockObject.Free;
  end;
end;

procedure TestPulseAndCrossLockWait;
var
  PulseObject, LockObject: TObject;
  Ready: TEvent;
  ReadyCount: LongInt;
  Waiter: TMonitorWaiter;
begin
  PulseObject := TObject.Create;
  LockObject := TObject.Create;
  Ready := TEvent.Create(nil, True, False, '');
  ReadyCount := 0;
  Waiter := TMonitorWaiter.Create(PulseObject, LockObject, Ready,
    @ReadyCount, 1);
  try
    Waiter.Start;
    Check(Ready.WaitFor(5000) = wrSignaled, 'cross-lock waiter ready');
    TMonitor.Enter(LockObject);
    try
      TMonitor.Pulse(PulseObject);
    finally
      TMonitor.Exit(LockObject);
    end;
    Waiter.WaitFor;
    Check(Waiter.FatalException = nil, 'cross-lock waiter completed');
    Check(Waiter.WaitResult, 'cross-lock waiter pulsed');
  finally
    Waiter.WaitFor;
    Waiter.Free;
    Ready.Free;
    LockObject.Free;
    PulseObject.Free;
  end;
end;

procedure TestPulseAll;
const
  WaiterCount = 3;
var
  LockObject: TObject;
  Ready: TEvent;
  ReadyCount, I: LongInt;
  Waiters: array[0..WaiterCount - 1] of TMonitorWaiter;
begin
  LockObject := TObject.Create;
  Ready := TEvent.Create(nil, True, False, '');
  ReadyCount := 0;
  FillChar(Waiters, SizeOf(Waiters), 0);
  try
    for I := 0 to High(Waiters) do
    begin
      Waiters[I] := TMonitorWaiter.Create(LockObject, LockObject, Ready,
        @ReadyCount, WaiterCount);
      Waiters[I].Start;
    end;
    Check(Ready.WaitFor(5000) = wrSignaled, 'PulseAll waiters ready');
    TMonitor.Enter(LockObject);
    try
      TMonitor.PulseAll(LockObject);
    finally
      TMonitor.Exit(LockObject);
    end;
    for I := 0 to High(Waiters) do
    begin
      Waiters[I].WaitFor;
      Check(Waiters[I].FatalException = nil, 'PulseAll waiter completed');
      Check(Waiters[I].WaitResult, 'PulseAll waiter signaled');
    end;
  finally
    TMonitor.PulseAll(LockObject);
    for I := 0 to High(Waiters) do
      if Waiters[I] <> nil then
      begin
        Waiters[I].WaitFor;
        Waiters[I].Free;
      end;
    Ready.Free;
    LockObject.Free;
  end;
end;

begin
  try
    TestEnterTryRecursiveAndErrors;
    TestContentionAndTimeout;
    TestWaitTimeoutRestoresRecursion;
    TestPulseAndCrossLockWait;
    TestPulseAll;
    WriteLn('MONITOR_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
