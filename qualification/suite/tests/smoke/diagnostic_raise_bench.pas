program diagnostic_raise_bench;
{$ifdef FPC}{$mode delphi}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses
  {$ifdef EUREKA}EResourceStrings, EDebugExports, EMapWin32, EAppConsole, EBase, ExceptionLog7,{$endif}
  {$ifdef UNIX}cthreads, cwstring, UnixType,{$endif}
  {$ifdef MSWINDOWS}Windows,{$endif}
  SysUtils, Classes
  {$ifdef REPORTING}, Moon.Diagnostics{$endif};

{$ifdef UNIX}
type TTimeValue = record Seconds, Nanoseconds: Int64; end;
function clock_gettime(Id: Integer; var Value: TTimeValue): Integer; cdecl; external 'c';
{$endif}

function ClockNS: Int64;
{$ifdef UNIX}
var V: TTimeValue;
begin
  clock_gettime(1, V);
  Result := V.Seconds * 1000000000 + V.Nanoseconds;
end;
{$else}
var Counter, Frequency: Int64;
begin
  QueryPerformanceCounter(Counter);
  QueryPerformanceFrequency(Frequency);
  Result := (Counter div Frequency) * 1000000000 + (Counter mod Frequency) * 1000000000 div Frequency;
end;
{$endif}

procedure ThrowLeaf;
begin
  raise Exception.Create('benchmark');
end;

procedure RunLoop(Count: Integer);
var I, Caught: Integer;
begin
  Caught := 0;
  for I := 1 to Count do begin
    try
      ThrowLeaf;
    except
      on E: Exception do If E.Message = 'benchmark' then Inc(Caught);
    end;
  end;
  If Caught <> Count then Halt(2);
end;

function ThreadState(Enabled: Boolean): Boolean;
begin
  {$ifdef REPORTING}Result := SetThreadReportsEnabled(Enabled);{$endif}
  {$ifdef EUREKA}Result := SetEurekaLogStateInThread(0, Enabled);{$endif}
  {$if not defined(REPORTING) and not defined(EUREKA)}Result := True;{$ifend}
end;

type
  TBenchmark = class(TThread)
    Count: Integer;
    Mode: string;
    Elapsed: Int64;
    procedure Execute; override;
  end;

procedure TBenchmark.Execute;
var Started: Int64; I: Integer; Saved: Boolean;
begin
  {$ifdef EUREKA}
  If not IsEurekaLogActiveInThread(0) then Halt(4);
  {$endif}
  If Mode = 'thread-off' then ThreadState(False);
  If Mode = 'global-off' then begin
    {$ifdef REPORTING}SetReportsEnabled(False);{$endif}
    {$ifdef EUREKA}SetEurekaLogState(False);{$endif}
  end;
  {$ifdef EUREKA}
  If (IsEurekaLogActive and IsEurekaLogActiveInThread(0)) <>
    ((Mode <> 'thread-off') and (Mode <> 'global-off')) then Halt(7);
  {$endif}
  {$ifdef REPORTING}
  try
    ThrowLeaf;
  except
    on E: Exception do
      If (E.DiagnosticContext <> nil) <> ((Mode <> 'thread-off') and (Mode <> 'global-off')) then Halt(5);
  end;
  {$endif}
  RunLoop(1000);
  Started := ClockNS;
  If Mode = 'toggle' then begin
    for I := 1 to Count do begin
      Saved := ThreadState(False);
      ThreadState(Saved);
    end;
  end else RunLoop(Count);
  Elapsed := ClockNS - Started;
end;

var Worker: TBenchmark;
begin
  {$ifdef REPORTING}
  InitializeReports(ParamStr(2));
  {$endif}
  {$ifdef EUREKA}
  If not IsEurekaLogActive then begin
    WriteLn('EUREKA_NOT_ACTIVE');
    Halt(3);
  end;
  WriteLn('EUREKA_ACTIVE');
  {$endif}
  Worker := TBenchmark.Create(True);
  Worker.Count := StrToInt(ParamStr(1));
  Worker.Mode := ParamStr(3);
  Worker.Start;
  Worker.WaitFor;
  If Worker.FatalException <> nil then Halt(6);
  If Worker.Mode = 'toggle' then Write('NS_PER_TOGGLE_PAIR=') else Write('NS_PER_RAISE=');
  WriteLn(Worker.Elapsed / Worker.Count:0:2);
  Worker.Free;
end.
