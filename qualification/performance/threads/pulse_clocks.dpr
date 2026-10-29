program pulse_clocks;
{$ifndef FPC}{$APPTYPE CONSOLE}{$endif}
{$ifdef FPC}{$mode delphi}{$H+}{$endif}
{$Q-}{$R-}
uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Classes, SyncObjs, System.Diagnostics,
  {$ifndef FPC}Windows,{$endif}
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';
{$I ../common/pulse_program_prefix.inc}

const CallsPerIteration = 4096;

type
  TQueuedCounter = class
    Count: UInt64;
    procedure Increment;
  end;

procedure TQueuedCounter.Increment;
begin
  Inc(Count);
end;

function CalendarNow(Iterations: Integer): UInt64;
var I, J: Integer;
begin
  Result:=0;
  for I:=1 to Iterations do
    for J:=1 to CallsPerIteration do Inc(Result,Ord(Now>0));
end;

function StopwatchTicks(Iterations: Integer): UInt64;
var I, J: Integer;
begin
  Result:=0;
  for I:=1 to Iterations do
    for J:=1 to CallsPerIteration do Inc(Result,Ord(TStopwatch.GetTimeStamp>0));
end;

function ReadyEvent(Iterations: Integer): UInt64;
var I, J: Integer; Event: TEvent;
begin
  Result:=0;
  Event:=TEvent.Create(nil,False,False,'');
  try
    for I:=1 to Iterations do
      for J:=1 to CallsPerIteration do begin
        Event.SetEvent;
        Inc(Result,Ord(Event.WaitFor(200)=wrSignaled));
      end;
  finally
    Event.Free;
  end;
end;

function EmptyEvent(Iterations: Integer): UInt64;
var I, J: Integer; Event: TEvent;
begin
  Result:=0;
  Event:=TEvent.Create(nil,False,False,'');
  try
    for I:=1 to Iterations do
      for J:=1 to CallsPerIteration do Inc(Result,Ord(Event.WaitFor(0)=wrTimeout));
  finally
    Event.Free;
  end;
end;

function QueuedCallbacks(Iterations: Integer): UInt64;
var I, J: Integer; Counter: TQueuedCounter;
begin
  Counter:=TQueuedCounter.Create;
  try
    for I:=1 to Iterations do begin
      for J:=1 to CallsPerIteration do TThread.ForceQueue(nil,Counter.Increment);
      CheckSynchronize(0);
    end;
    Result:=Counter.Count;
  finally
    TThread.RemoveQueuedEvents(nil,Counter.Increment);
    Counter.Free;
  end;
end;

function SysUtilsTicks(Iterations: Integer): UInt64;
var I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to CallsPerIteration do
      Result := Result + UInt64(Ord({$ifdef FPC}SysUtils.{$else}Windows.{$endif}GetTickCount64 > 0));
end;

function ThreadTicks(Iterations: Integer): UInt64;
var I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to CallsPerIteration do Result := Result + UInt64(Ord(TThread.GetTickCount64 > 0));
end;

var Profile: TPulseProfile; Selected: string; Found: Boolean;
begin
  PulseInitialize('pulse_clocks', Profile, Selected);
  Found := False;
  PulseRunCase('pulse_clocks', 'sysutils-tick64', 'rtl+clock', 'SysUtils', @SysUtilsTicks,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'thread-tick64', 'rtl+clock', 'Classes', @ThreadTicks,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'calendar-now', 'rtl+clock', 'SysUtils', @CalendarNow,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'stopwatch', 'rtl+clock', 'Diagnostics', @StopwatchTicks,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'event-ready', 'rtl+sync', 'SyncObjs', @ReadyEvent,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'event-poll', 'rtl+sync', 'SyncObjs', @EmptyEvent,
    CallsPerIteration, Profile, Selected, Found);
  PulseRunCase('pulse_clocks', 'queued-callbacks', 'rtl+sync', 'Classes', @QueuedCallbacks,
    CallsPerIteration, Profile, Selected, Found);
  PulseFinish('pulse_clocks', Selected, Found);
end.
