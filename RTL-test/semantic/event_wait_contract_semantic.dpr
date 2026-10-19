program event_wait_contract_semantic;
{$mode delphi}{$H+}
uses
  {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes, SyncObjs;

type
  TWaiter = class(TThread)
    Event: PEventState;
    Timeout: Cardinal;
    Outcome: LongInt;
    procedure Execute; override;
  end;

var WaitersStarted, WaitersCompleted: LongInt;

procedure Check(Value: Boolean; const Detail: string);
begin
  If not Value then raise Exception.Create(Detail);
end;

procedure AwaitCount(var Counter: LongInt; Value: LongInt);
var Start: QWord;
begin
  Start := GetTickCount64;
  while InterlockedCompareExchange(Counter, 0, 0) < Value do begin
    Check(GetTickCount64 - Start < 3000, 'worker deadline');
    Sleep(1);
  end;
end;

procedure TWaiter.Execute;
begin
  InterlockedIncrement(WaitersStarted);
  Outcome := BasicEventWaitFor(Timeout, Event);
  InterlockedIncrement(WaitersCompleted);
end;

procedure Basic(Manual, Initial: Boolean);
var E: TEvent; Start: QWord;
begin
  E := TEvent.Create(nil, Manual, Initial, '');
  try
    If Initial then Check(E.WaitFor(0) = wrSignaled, 'initial signal')
    else Check(E.WaitFor(0) = wrTimeout, 'initial empty');
    E.ResetEvent;
    Check(E.WaitFor(0) = wrTimeout, 'reset');
    E.SetEvent;
    E.SetEvent;
    Check(E.WaitFor(200) = wrSignaled, 'ready finite');
    If Manual then Check(E.WaitFor(0) = wrSignaled, 'manual retains')
    else Check(E.WaitFor(0) = wrTimeout, 'auto consumes and coalesces');
    E.SetEvent;
    Check(E.WaitFor(High(Cardinal)) = wrSignaled, 'ready infinite');
    E.ResetEvent;
    Start := GetTickCount64;
    Check(E.WaitFor(20) = wrTimeout, 'finite empty');
    Check(GetTickCount64 - Start >= 10, 'finite wait returned early');
    E.SetEvent;
    Check(E.WaitFor(0) = wrSignaled, 'zero consumes signal');
    If not Manual then Check(E.WaitFor(0) = wrTimeout, 'zero auto-reset');
  finally
    E.Free;
  end;
end;

procedure Multiple(Manual: Boolean; Timeout: Cardinal; DestroyWaiting: Boolean = False);
var E: PEventState; Workers: array[0..3] of TWaiter; I: Integer;
  {$ifdef EVENT_PROBE}Start: QWord;{$endif}
begin
  WaitersStarted := 0;
  WaitersCompleted := 0;
  E := BasicEventCreate(nil, Manual, False, '');
  for I := 0 to High(Workers) do begin
    Workers[I] := TWaiter.Create(True);
    Workers[I].Event := E;
    Workers[I].Timeout := Timeout;
    Workers[I].Outcome := -1;
    Workers[I].Start;
  end;
  AwaitCount(WaitersStarted, Length(Workers));
  {$ifdef EVENT_PROBE}
  { The probe takes the same mutex: all four waits have registered and
    released it into cond_wait, rather than merely starting their threads. }
  Start := GetTickCount64;
  while EventProbeWaiterCount(E) <> Length(Workers) do begin
    Check(GetTickCount64 - Start < 3000, 'wait registration deadline');
    Sleep(1);
  end;
  {$endif}
  If DestroyWaiting then begin
    BasicEventDestroy(E);
    E := nil;
  end else If Manual then BasicEventSetEvent(E)
  else begin
    for I := 1 to Length(Workers) do begin
      BasicEventSetEvent(E);
      AwaitCount(WaitersCompleted, I);
      Check(InterlockedCompareExchange(WaitersCompleted, 0, 0) = I, 'auto released more than one');
    end;
  end;
  AwaitCount(WaitersCompleted, Length(Workers));
  for I := 0 to High(Workers) do begin
    Workers[I].WaitFor;
    Check(Workers[I].FatalException = nil, 'worker exception');
    If DestroyWaiting then Check(Workers[I].Outcome = Ord(wrAbandoned), 'destroy outcome')
    else Check(Workers[I].Outcome = Ord(wrSignaled), 'signal outcome');
    Workers[I].Free;
  end;
  If E <> nil then begin
    If Manual then Check(BasicEventWaitFor(0, E) = Ord(wrSignaled), 'manual remains set after waiters')
    else Check(BasicEventWaitFor(0, E) = Ord(wrTimeout), 'auto consumed by waiters');
    BasicEventDestroy(E);
  end;
end;

procedure Pollers(Manual: Boolean);
var E: PEventState; Workers: array[0..7] of TWaiter; I, Signals: Integer;
begin
  WaitersStarted := 0;
  WaitersCompleted := 0;
  E := BasicEventCreate(nil, Manual, True, '');
  for I := 0 to High(Workers) do begin
    Workers[I] := TWaiter.Create(True);
    Workers[I].Event := E;
    Workers[I].Timeout := 0;
    Workers[I].Start;
  end;
  AwaitCount(WaitersCompleted, Length(Workers));
  Signals := 0;
  for I := 0 to High(Workers) do begin
    Workers[I].WaitFor;
    Check(Workers[I].FatalException = nil, 'poller exception');
    If Workers[I].Outcome = Ord(wrSignaled) then Inc(Signals)
    else Check(Workers[I].Outcome = Ord(wrTimeout), 'poller outcome');
    Workers[I].Free;
  end;
  If Manual then Check(Signals = Length(Workers), 'manual pollers')
  else Check(Signals = 1, 'one auto signal must reach exactly one poller');
  BasicEventDestroy(E);
end;

{$ifdef EVENT_PROBE}
procedure FastPath(const Mode: string);
var E: TEvent; Manual: Boolean; I: Integer;
begin
  for Manual := False to True do begin
    E := TEvent.Create(nil, Manual, False, '');
    try
      EventProbeClockReads := 0;
      EventProbeTimedWaits := 0;
      for I := 1 to 100 do begin
        If Mode = 'ready' then begin
          E.SetEvent;
          Check(E.WaitFor(200) = wrSignaled, 'ready result');
        end else Check(E.WaitFor(0) = wrTimeout, 'poll result');
      end;
      Check(EventProbeClockReads = 0, 'unnecessary deadline calculation');
      Check(EventProbeTimedWaits = 0, 'unnecessary condition wait');
      Check(EventProbeWaiterCount(E.Handle) = 0, 'fast path leaked waiter');
    finally
      E.Free;
    end;
  end;
end;

procedure ClockFailure;
var E: TEvent; Worker: TWaiter;
begin
  E := TEvent.Create(nil, False, False, '');
  try
    EventProbeFailClock := True;
    Check(E.WaitFor(1) = wrError, 'clock failure result');
    Check(EventProbeWaiterCount(E.Handle) = 0, 'clock failure leaked waiter');
    { The mutex is recursive: only another thread proves it was unlocked. }
    WaitersStarted := 0;
    WaitersCompleted := 0;
    Worker := TWaiter.Create(True);
    Worker.Event := E.Handle;
    Worker.Timeout := 0;
    Worker.Start;
    AwaitCount(WaitersCompleted, 1);
    Worker.WaitFor;
    Check(Worker.FatalException = nil, 'clock-error worker exception');
    Check(Worker.Outcome = Ord(wrTimeout), 'clock-error worker poll');
    Worker.Free;
    E.SetEvent;
    Check(E.WaitFor(200) = wrSignaled, 'ready event must not need a clock');
    Check(E.WaitFor(0) = wrTimeout, 'poll must not need a clock');
    EventProbeFailClock := False;
    EventProbeClockReads := 0;
    EventProbeTimedWaits := 0;
    Check(E.WaitFor(5) = wrTimeout, 'real finite timeout');
    Check(EventProbeClockReads = 1, 'finite wait needs one fixed deadline');
    Check(EventProbeTimedWaits > 0, 'finite wait did not block');
  finally
    EventProbeFailClock := False;
    E.Free;
  end;
end;
{$endif}

var I: Integer;
begin
  {$ifdef EVENT_PROBE}
  If ParamCount <> 0 then begin
    If (ParamStr(1) = 'ready') or (ParamStr(1) = 'poll') then FastPath(ParamStr(1))
    else If ParamStr(1) = 'clock' then ClockFailure
    else If ParamStr(1) = 'destroy' then begin
      for I := 1 to 5 do begin
        Multiple(False, 5000, True);
        Multiple(True, 5000, True);
        Multiple(False, High(Cardinal), True);
        Multiple(True, High(Cardinal), True);
      end;
    end else Halt(2);
  end else
  {$endif}
  begin
    for I := 1 to 3 do begin
      Basic(False, False);
      Basic(False, True);
      Basic(True, False);
      Basic(True, True);
      Multiple(False, 5000);
      Multiple(True, 5000);
      Multiple(False, High(Cardinal));
      Multiple(True, High(Cardinal));
      Pollers(False);
      Pollers(True);
    end;
  end;
  WriteLn('EVENT_WAIT_CONTRACT_PASS');
end.
