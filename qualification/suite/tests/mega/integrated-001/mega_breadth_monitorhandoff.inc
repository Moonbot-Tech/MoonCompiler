{$define BREADTH_HAS_MONITOR}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    {$undef BREADTH_HAS_MONITOR}
  {$endif}
{$endif}
{$ifdef BREADTH_HAS_MONITOR}
{ Waiting releases the full recursive acquisition and restores it on return. }

type
  TBreadthMonitorPublisher = class(TThread)
  public
    Lock: TObject;
    TryAgain, Tried: TEvent;
    Token: Int64;
    Acquired: Boolean;
    procedure Execute; override;
  end;

procedure TBreadthMonitorPublisher.Execute;
begin
  TMonitor.Enter(Lock);
  try
    Token := 72000000081;
    TMonitor.Pulse(Lock);
  finally
    TMonitor.Exit(Lock);
  end;
  If TryAgain.WaitFor(3000) <> wrSignaled then
    raise EAbort.Create('monitor receiver did not request second acquisition');
  try
    Acquired := TMonitor.TryEnter(Lock);
    If Acquired then
      TMonitor.Exit(Lock);
  finally
    Tried.SetEvent;
  end;
end;

procedure RunBreadthMonitorHandoff;
var
  Publisher: TBreadthMonitorPublisher;
  Lock: TObject;
  TryAgain, Tried: TEvent;
begin
  Lock := TObject.Create;
  try
    TryAgain := TEvent.Create(nil, True, False, '');
    try
      Tried := TEvent.Create(nil, True, False, '');
      try
        Publisher := TBreadthMonitorPublisher.Create(True);
        try
          Publisher.Lock := Lock;
          Publisher.TryAgain := TryAgain;
          Publisher.Tried := Tried;
          TMonitor.Enter(Lock);
          try
            TMonitor.Enter(Lock);
            try
              Publisher.Start;
              Check(TMonitor.Wait(Lock, 2000) and (Publisher.Token = 72000000081),
                'breadth-monitor-wait-releases-all-recursive-locks-for-publisher');
            finally
              TMonitor.Exit(Lock);
            end;
            TryAgain.SetEvent;
            Check((Tried.WaitFor(2000) = wrSignaled) and not Publisher.Acquired,
              'breadth-monitor-wait-restores-both-recursive-acquisitions');
            Check(not TMonitor.Wait(Lock, 0), 'breadth-monitor-post-pulse-poll-is-empty');
          finally
            TMonitor.Exit(Lock);
          end;
          Publisher.WaitFor;
          Check(Publisher.FatalException = nil, 'breadth-monitor-publisher-completes');
          Mix(UInt64(Publisher.Token));
        finally
          TryAgain.SetEvent;
          Publisher.Free;
        end;
      finally
        Tried.Free;
      end;
    finally
      TryAgain.Free;
    end;
  finally
    Lock.Free;
  end;
end;
{$endif}
