{ A worker waits for the form update and handles cancellation before submitting again. }

type
  TBreadthSynchronizedWorker = class(TThread)
  public
    Input, Reply, ReadBack, Cancellation: UnicodeString;
    WorkerThread, RenderThread, CancelThread, FollowupThread: TThreadID;
    procedure Execute; override;
    procedure Render;
    procedure Cancel;
    procedure Followup;
  end;

procedure TBreadthSynchronizedWorker.Render;
begin
  RenderThread := TThread.CurrentThread.ThreadID;
  Reply := Input + '!';
end;

procedure TBreadthSynchronizedWorker.Cancel;
begin
  CancelThread := TThread.CurrentThread.ThreadID;
  raise EAbort.Create('preview cancelled');
end;

procedure TBreadthSynchronizedWorker.Followup;
begin
  FollowupThread := TThread.CurrentThread.ThreadID;
end;

procedure TBreadthSynchronizedWorker.Execute;
begin
  WorkerThread := TThread.CurrentThread.ThreadID;
  Synchronize(Render);
  ReadBack := Reply;
  try
    Synchronize(Cancel);
  except
    on E: EAbort do Cancellation := E.Message;
  end;
  Synchronize(Followup);
end;

procedure RunBreadthSynchronousCallbacks;
var
  Worker: TBreadthSynchronizedWorker;
  UIThread: TThreadID;
begin
  UIThread := TThread.CurrentThread.ThreadID;
  Worker := TBreadthSynchronizedWorker.Create(True);
  try
    Worker.Input := 'route' + #0 + #$03BB + #$D83D + #$DE80;
    Worker.Start;
    Worker.WaitFor;
    Check((Worker.WorkerThread <> UIThread) and (Worker.FatalException = nil),
      'breadth-synchronize-callback-worker-finishes-after-different-thread-calls');
    Check((Worker.RenderThread = UIThread) and (Worker.CancelThread = UIThread) and (Worker.FollowupThread = UIThread),
      'breadth-synchronize-callbacks-run-on-the-waiting-main-thread');
    Check((Worker.Reply = 'route' + #0 + #$03BB + #$D83D + #$DE80 + '!') and (Worker.ReadBack = Worker.Reply),
      'breadth-synchronize-worker-observes-completed-managed-reply');
    Check(Worker.Cancellation = 'preview cancelled', 'breadth-synchronize-delivers-cancellation-to-waiting-worker');
    Mix(UInt64(Length(Worker.ReadBack) * 32 + Length(Worker.Cancellation)));
  finally
    FreeAndNil(Worker);
  end;
end;
