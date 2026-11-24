{$ifdef BREADTH_MAIN_FORCE_QUEUE}
{ The worker publishes before the main thread destroys a receiver and drains
  the queue. Waiting on the event does not pump the main thread's queue. }

type
  TBreadthQueuePublisher = class(TThread)
  public
    Posted: TEvent;
    RemovedCall, KeptCall: TThreadMethod;
    procedure Execute; override;
  end;

procedure TBreadthQueuePublisher.Execute;
begin
  try
    TThread.ForceQueue(nil, RemovedCall);
    TThread.ForceQueue(nil, KeptCall);
  finally
    Posted.SetEvent;
  end;
end;

procedure RunBreadthWorkerQueue;
var
  Removed, Kept: TBreadthQueueReceiver;
  Publisher: TBreadthQueuePublisher;
  Posted: TEvent;
  Trace: Integer;
  Ready: Boolean;
begin
  Trace := 0;
  Posted := TEvent.Create(nil, True, False, '');
  try
    Removed := TBreadthQueueReceiver.Create;
    try
      Kept := TBreadthQueueReceiver.Create;
      try
        Removed.Tag := Integer(OpaqueI(4));
        Removed.Trace := @Trace;
        Kept.Tag := Integer(OpaqueI(7));
        Kept.Trace := @Trace;
        Publisher := TBreadthQueuePublisher.Create(True);
        try
          Publisher.Posted := Posted;
          Publisher.RemovedCall := Removed.Append;
          Publisher.KeptCall := Kept.Append;
          Publisher.Start;
          try
            Ready := Posted.WaitFor(2000) = wrSignaled;
            Check(Ready, 'breadth-worker-queue-confirmed-publication');
            If not Ready then
              Exit;
            Check(Trace = 0, 'breadth-worker-queue-deferred-until-main-pump');
            TThread.RemoveQueuedEvents(Publisher.RemovedCall);
            FreeAndNil(Removed);
            Check(CheckSynchronize(0) and (Trace = 7), 'breadth-worker-queue-delivers-only-live-receiver');
            Check(not CheckSynchronize(0), 'breadth-worker-queue-drains-once');
          finally
            Publisher.WaitFor;
            TThread.RemoveQueuedEvents(Publisher.RemovedCall);
            TThread.RemoveQueuedEvents(Publisher.KeptCall);
          end;
          Check(Publisher.FatalException = nil, 'breadth-worker-queue-producer-completed');
          Mix(UInt64(Trace));
        finally
          Publisher.Free;
        end;
      finally
        Kept.Free;
      end;
    finally
      Removed.Free;
    end;
  finally
    Posted.Free;
  end;
end;
{$endif}
