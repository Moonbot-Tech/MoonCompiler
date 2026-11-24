{$define BREADTH_MAIN_FORCE_QUEUE}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    { The upstream bootstrap RTL does not defer ForceQueue before the first worker. }
    {$undef BREADTH_MAIN_FORCE_QUEUE}
  {$endif}
{$endif}
{ Queue cancellation matches both halves of a method pointer without starting a worker. }

type
  TBreadthQueueReceiver = class
    Tag: Integer;
    Trace: PInteger;
    procedure Append;
  end;

procedure TBreadthQueueReceiver.Append;
begin
  Trace^ := Trace^ * 10 + Tag;
end;

procedure RunBreadthQueueRemoval;
var
  Remove, Keep: TBreadthQueueReceiver;
  DropCall, KeepCall: TThreadMethod;
  Trace: Integer;
begin
  Trace := 0;
  Remove := TBreadthQueueReceiver.Create;
  try
    Keep := TBreadthQueueReceiver.Create;
    try
      Remove.Tag := 3;
      Remove.Trace := @Trace;
      Keep.Tag := 7;
      Keep.Trace := @Trace;
      DropCall := Remove.Append;
      KeepCall := Keep.Append;
      TThread.Queue(nil, DropCall);
      Check(Trace = 3, 'breadth-main-thread-queue-runs-immediately');
      try
        TThread.ForceQueue(nil, DropCall);
        TThread.ForceQueue(nil, KeepCall);
        TThread.ForceQueue(nil, DropCall);
        Check(Trace = 3, 'breadth-force-queue-defers-even-on-main-thread');
        TThread.RemoveQueuedEvents(DropCall);
        TThread.ForceQueue(nil, KeepCall);
        Check(CheckSynchronize(0) and (Trace = 377), 'breadth-queue-remove-matches-receiver-and-preserves-tail');
        Check((not CheckSynchronize(0)) and (Trace = 377), 'breadth-queue-poll-is-empty-after-drain');
      finally
        TThread.RemoveQueuedEvents(DropCall);
        TThread.RemoveQueuedEvents(KeepCall);
      end;
    finally
      Keep.Free;
    end;
  finally
    Remove.Free;
  end;
end;
