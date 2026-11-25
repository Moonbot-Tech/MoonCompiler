{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A dispatcher reuses its job slots and its completion count across batches. }

procedure RunBreadthSemaphoreSlots;
const
  { Windows returns the previous count. Linux returns the number posted. }
{$ifdef MSWINDOWS}
  BatchResult = 0;
  LastResult = 2;
{$else}
  BatchResult = 2;
  LastResult = 1;
{$endif}
var
  Slots: TSemaphore;
begin
  Slots := TSemaphore.Create(nil, 1, 3, '');
  try
    Check(Slots.WaitFor(0) = wrSignaled, 'breadth-semaphore-initial-slot-acquires-without-waiting');
    Check(Slots.WaitFor(0) = wrTimeout, 'breadth-semaphore-exhausted-slots-time-out-immediately');
    Check(Slots.Release(Integer(OpaqueI(2))) = BatchResult, 'breadth-semaphore-batched-release-returns-platform-result');
    Check(Slots.Release(1) = LastResult, 'breadth-semaphore-final-release-returns-platform-result');
    Check((Slots.WaitFor(0) = wrSignaled) and (Slots.WaitFor(0) = wrSignaled) and (Slots.WaitFor(0) = wrSignaled),
      'breadth-semaphore-three-released-slots-can-each-be-consumed');
    Check(Slots.WaitFor(0) = wrTimeout, 'breadth-semaphore-drain-leaves-no-extra-slot');
  finally
    FreeAndNil(Slots);
  end;
end;

procedure RunBreadthCountdownReset;
var
  Completion: TCountdownEvent;
begin
  Completion := TCountdownEvent.Create(Integer(OpaqueI(2)));
  try
    Check(Completion.TryAddCount(1) and (Completion.CurrentCount = 3) and (Completion.InitialCount = 2),
      'breadth-countdown-accepts-added-work-before-completion');
    Check(not Completion.Signal(2) and (Completion.CurrentCount = 1) and (Completion.WaitFor(0) = wrTimeout),
      'breadth-countdown-partial-completion-leaves-event-unsignaled');
    Check(Completion.Signal and Completion.IsSet and (Completion.WaitFor(0) = wrSignaled),
      'breadth-countdown-final-completion-publishes-event');
    Check(not Completion.TryAddCount(1) and (Completion.CurrentCount = 0),
      'breadth-countdown-completed-batch-cannot-be-grown');
    Completion.Reset(Integer(OpaqueI(1)));
    Check((Completion.InitialCount = 1) and (Completion.CurrentCount = 1) and (Completion.WaitFor(0) = wrTimeout),
      'breadth-countdown-reset-clears-signal-and-establishes-next-batch');
    Check(Completion.Signal and (Completion.WaitFor(0) = wrSignaled), 'breadth-countdown-reset-batch-can-complete-again');
  finally
    FreeAndNil(Completion);
  end;
end;
{$endif}
