{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Measure active job latency across pause, resume and reset. }

function BreadthObserveTimerAdvance(Stamp: Int64): Boolean;
var
  Attempt: Integer;
begin
  for Attempt := 1 to 10000 do
    If TStopwatch.GetTimeStamp > Stamp then
      Exit(True);
  Result := False;
end;

procedure RunBreadthPausedJobClock;
var
  Watch: TStopwatch;
  First, Converted: Int64;
  Progress: Boolean;
begin
  Watch := TStopwatch.StartNew;
  Check(Watch.IsRunning and (TStopwatch.Frequency > 0), 'breadth-paused-clock-starts-with-a-valid-frequency');
  Progress := BreadthObserveTimerAdvance(TStopwatch.GetTimeStamp);
  Watch.Stop;
  First := Watch.ElapsedTicks;
  Converted := Watch.Elapsed.Ticks;
  Check(Progress and (First > 0) and (TStopwatch.Frequency > 0)
    and (Abs(Converted - First * 10000000.0 / TStopwatch.Frequency) <= 1)
    and (Watch.ElapsedMilliseconds = Converted div 10000), 'breadth-paused-clock-converts-units-consistently');

  Progress := BreadthObserveTimerAdvance(TStopwatch.GetTimeStamp);
  Check(Progress and not Watch.IsRunning and (Watch.ElapsedTicks = First), 'breadth-paused-clock-excludes-paused-interval');
  Watch.Start;
  Progress := BreadthObserveTimerAdvance(TStopwatch.GetTimeStamp);
  Watch.Stop;
  Check(Progress and (Watch.ElapsedTicks > First), 'breadth-paused-clock-resume-adds-second-active-segment');

  Watch.Reset;
  Check(not Watch.IsRunning and (Watch.ElapsedTicks = 0) and (Watch.Elapsed.Ticks = 0),
    'breadth-paused-clock-reset-clears-accumulated-segments');
  Mix(UInt64(Watch.ElapsedTicks));
end;
{$endif}
