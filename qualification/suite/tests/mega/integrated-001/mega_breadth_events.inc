{ A zero-time wait consumes an automatic event signal but leaves a manual one set. }

procedure RunBreadthEventPolling;
var
  ManualReset: Boolean;
  Gate: TEvent;
  RepeatState, First, Second: TWaitResult;
begin
  for ManualReset := False to True do begin
    Gate := TEvent.Create(nil, ManualReset, False, '');
    try
      If ManualReset then
        RepeatState := wrSignaled
      else
        RepeatState := wrTimeout;
      Check(Gate.WaitFor(0) = wrTimeout, 'breadth-event-poll-initially-unsignaled');
      Gate.SetEvent;
      First := Gate.WaitFor(0);
      Second := Gate.WaitFor(0);
      Check((First = wrSignaled) and (Second = RepeatState), 'breadth-event-poll-respects-reset-mode');
      Gate.ResetEvent;
      Check(Gate.WaitFor(0) = wrTimeout, 'breadth-event-poll-explicit-reset-clears-signal');
      Gate.SetEvent;
      Gate.SetEvent;
      First := Gate.WaitFor(0);
      Second := Gate.WaitFor(0);
      Check((First = wrSignaled) and (Second = RepeatState), 'breadth-event-poll-consecutive-sets-do-not-queue-signals');
      Mix(UInt64(Ord(Second)));
    finally
      Gate.Free;
    end;
  end;
end;
