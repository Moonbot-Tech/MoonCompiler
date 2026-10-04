program diagnostic_switches;
{$mode delphiunicode}{$H+}
uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, Moon.Diagnostics;

procedure Check(Condition: Boolean; const Message: string);
begin
  If not Condition then begin
    WriteLn('FAIL ', Message);
    Halt(1);
  end;
end;

threadvar PriorCaptures, PriorBacktraces: Integer;

procedure PriorCapture(Obj: TObject; Addr: CodePointer; Frame: Pointer; Count: LongInt;
  Frames: PCodePointer; Context: Pointer; Hardware: Boolean);
begin
  If Obj <> nil then Inc(PriorCaptures);
end;

function PriorBacktrace(Addr: CodePointer; Frame: Pointer; var Count: LongInt; var Frames: PCodePointer): Boolean;
begin
  Inc(PriorBacktraces);
  Result := False;
end;

procedure CheckRaise(Captured: Boolean);
var BeforeCapture, BeforeBacktrace: Integer;
begin
  BeforeCapture := PriorCaptures;
  BeforeBacktrace := PriorBacktraces;
  try
    raise Exception.Create('expected exception');
  except
    on E: Exception do begin
      Check(E.Message = 'expected exception', 'original exception changed');
      Check((E.DiagnosticContext <> nil) = Captured, 'wrong capture state');
    end;
  end;
  Check(PriorCaptures = BeforeCapture + 1, 'previous capture hook lost');
  {$ifdef UNIX}
  If not Captured then Check(PriorBacktraces = BeforeBacktrace + 1, 'previous backtrace hook lost');
  {$endif}
end;

procedure CheckFault(Captured: Boolean);
var Address: PtrUInt; Value: Integer;
begin
  Address := 1;
  try
    Value := PInteger(Address)^;
    WriteLn(Value);
    Check(False, 'missing hardware exception');
  except
    on E: EAccessViolation do Check((E.DiagnosticContext <> nil) = Captured, 'wrong hardware capture state');
  end;
end;

type
  TProbe = class(TThread)
    Disabled, Fail, ExpectedAfter: Boolean;
    Ready, Finish: LongInt;
    procedure Execute; override;
  end;

procedure TProbe.Execute;
begin
  Check(SetThreadReportsEnabled(not Disabled), 'new thread must default to enabled');
  Check(ReportsEnabled = not Disabled, 'initial worker policy');
  CheckRaise(not Disabled);
  InterlockedExchange(Ready, 1);
  while InterlockedCompareExchange(Finish, 0, 0) = 0 do Sleep(1);
  Check(ReportsEnabled = ExpectedAfter, 'global policy did not reach worker');
  CheckRaise(ExpectedAfter);
  If Fail then raise Exception.Create('disabled worker fatal');
end;

procedure WaitReady(Worker: TProbe);
begin
  while InterlockedCompareExchange(Worker.Ready, 0, 0) = 0 do Sleep(1);
end;

procedure FinishProbe(Worker: TProbe; ExpectedCaptured: Boolean);
begin
  Worker.ExpectedAfter := ExpectedCaptured;
  InterlockedExchange(Worker.Finish, 1);
  Worker.WaitFor;
  Check((Worker.FatalException <> nil) = Worker.Fail, 'worker termination semantics changed');
  Worker.Free;
end;

procedure StateChecks;
var Saved, Nested: Boolean; Context: TObject; Worker: TProbe;
begin
  Check(ReportsEnabled, 'initial state');
  CheckRaise(True);
  Saved := SetThreadReportsEnabled(False);
  Nested := SetThreadReportsEnabled(False);
  Check(Saved and not Nested, 'nested thread state');
  try
    CheckRaise(False);
    CheckFault(False);
    SetThreadReportsEnabled(Nested);
    Check(not ReportsEnabled, 'nested restore enabled outer block');
    Check(WriteManualReport('must not write') = '', 'disabled manual report');
    Check(WriteExceptionReport('must not write') = '', 'disabled active-exception report');
    Check(WriteExceptionReport(nil, 'must not write') = '', 'disabled object report');
    Worker := TProbe.Create(True);
    Worker.Start;
    WaitReady(Worker);
    FinishProbe(Worker, True);
    Check(not ReportsEnabled, 'another thread changed caller state');
  finally
    SetThreadReportsEnabled(Saved);
  end;
  CheckRaise(True);
  CheckFault(True);
  Worker := TProbe.Create(True);
  Worker.Start;
  WaitReady(Worker);
  Saved := SetReportsEnabled(False);
  Nested := SetReportsEnabled(False);
  Check(Saved and not Nested, 'nested global state');
  try
    CheckRaise(False);
    CheckFault(False);
    SetReportsEnabled(Nested);
    Check(not ReportsEnabled, 'nested global restore');
    FinishProbe(Worker, False);
    SetThreadReportsEnabled(False);
    SetReportsEnabled(True);
    Check(not ReportsEnabled, 'global enable overwrote thread disable');
    CheckRaise(False);
    SetThreadReportsEnabled(True);
  finally
    SetReportsEnabled(Saved);
  end;
  CheckRaise(True);
  CheckFault(True);
  try
    raise Exception.Create('retained original context');
  except
    on E: Exception do begin
      Context := E.DiagnosticContext;
      Saved := SetThreadReportsEnabled(False);
      try
        CheckRaise(False);
        Check(E.DiagnosticContext = Context, 'disable destroyed an existing context');
      finally
        SetThreadReportsEnabled(Saved);
      end;
      Check(E.DiagnosticContext = Context, 'restore replaced an existing context');
    end;
  end;
end;

var Mode: string; Worker: TProbe;
begin
  Mode := ParamStr(1);
  ExceptionContextProc := @PriorCapture;
  ExceptionBacktraceProc := @PriorBacktrace;
  InitializeReports(ParamStr(2));
  If Mode = 'states' then StateChecks
  else If Mode = 'disabled-main-fatal' then begin
    SetReportsEnabled(False);
    raise Exception.Create('disabled main fatal');
  end else begin
    Worker := TProbe.Create(True);
    Worker.Disabled := True;
    Worker.Fail := Mode = 'disabled-worker-fatal';
    Worker.Start;
    WaitReady(Worker);
    If Mode = 'manual-disabled-worker' then begin
      Check(ReportsEnabled, 'worker disabled main thread');
      Check(WriteManualReport('include disabled worker') <> '', 'manual report missing');
    end else Check(Mode = 'disabled-worker-fatal', 'unknown mode');
    FinishProbe(Worker, False);
  end;
  WriteLn('DIAGNOSTIC_SWITCHES_PASS');
end.
