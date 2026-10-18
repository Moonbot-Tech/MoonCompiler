program diagnostic_expected;
{$mode delphi}{$H+}
uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, Moon.Diagnostics;

type
  EExpected = class(Exception);
  EExpectedChild = class(EExpected);
  EExpectedFamily = class(Exception);
  EExpectedDescendant = class(EExpectedFamily);
  EExpectedGrandchild = class(EExpectedDescendant);
  EUnexpected = class(Exception);
  TWorker = class(TThread)
    Mode: string;
    Saved: Exception;
    procedure Execute; override;
  end;

var
  DataCalls, HookCalls: LongInt;
  PreviousHook: TExceptionContextProc;
  {$ifdef LINUX}
  BacktraceCalls: LongInt;
  PreviousBacktrace: TExceptionBacktraceProc;
  {$endif}

procedure Check(Value: Boolean; const Message: string);
begin
  If not Value then raise Exception.Create('CHECK: ' + Message);
end;

procedure Observe(Obj: TObject; Addr: CodePointer; Frame: Pointer; FrameCount: LongInt;
  Frames: PCodePointer; Context: Pointer; Hardware: Boolean);
begin
  If Obj <> nil then InterlockedIncrement(HookCalls);
  If Assigned(PreviousHook) then PreviousHook(Obj, Addr, Frame, FrameCount, Frames, Context, Hardware);
end;

{$ifdef LINUX}
procedure PreviousFrame;
begin
end;

function ObserveBacktrace(Addr: CodePointer; Frame: Pointer;
  var FrameCount: LongInt; var Frames: PCodePointer): Boolean;
begin
  InterlockedIncrement(BacktraceCalls);
  Result := False;
  If ExceptObject is EExpected then begin
    FrameCount := 1;
    GetMem(Frames, SizeOf(CodePointer));
    Frames[0] := @PreviousFrame;
    Exit(True);
  end;
  If Assigned(PreviousBacktrace) then Result := PreviousBacktrace(Addr, Frame, FrameCount, Frames);
end;
{$endif}

procedure Data(Report: TDiagnosticReport);
begin
  Inc(DataCalls);
  Report.Add('expected_filter_test', 'true');
end;

procedure ThrowExpected; noinline;
begin
  raise EExpected.Create('expected origin');
end;

procedure HardwareOrigin; noinline;
var Address: PByte;
begin
  Address := Pointer(PtrUInt(StrToInt(ParamStr(3))));
  Address^ := 23;
end;

procedure CheckRaise(Error: Exception; Expected: Boolean);
var BeforeHooks: LongInt;
  {$ifdef LINUX}BeforeBacktrace: LongInt;{$endif}
begin
  BeforeHooks := HookCalls;
  {$ifdef LINUX}BeforeBacktrace := BacktraceCalls;{$endif}
  try
    raise Error;
  except
    on E: Exception do begin
      Check(E = Error, 'exception object changed');
      Check((E.DiagnosticContext = nil) = Expected, 'wrong capture decision: ' + E.ClassName);
      If Expected then begin
        {$ifdef LINUX}
        Check(BacktraceCalls > BeforeBacktrace, 'previous backtrace hook skipped');
        If E is EExpected then begin
          Check(ExceptFrameCount = 1, 'previous backtrace frame count lost');
          Check(ExceptFrames[0] = @PreviousFrame, 'previous backtrace frame lost');
        end;
        {$endif}
        Check(WriteExceptionReport(E) = '', 'expected explicit report');
        Check(WriteExceptionReport('active expected') = '', 'expected active report');
      end;
    end;
  end;
  Check(HookCalls > BeforeHooks, 'previous capture hook skipped');
end;

procedure TWorker.Execute;
var I: Integer;
begin
  If Mode = 'parallel' then begin
    for I := 1 to 100 do begin
      CheckRaise(EExpected.Create('parallel expected'), True);
      CheckRaise(EUnexpected.Create('parallel unexpected'), False);
    end;
    Exit;
  end;
  If Mode = 'escape' then ThrowExpected;
  If Mode = 'sync' then Synchronize(ThrowExpected)
  else begin
    CheckRaise(EExpected.Create('worker expected'), True);
    CheckRaise(EUnexpected.Create('worker unexpected'), False);
    try
      ThrowExpected;
    except
      Saved := Exception(AcquireExceptionObject);
    end;
  end;
end;

procedure TestTransfer(const Mode: string);
var Worker: TWorker; Error: Exception;
begin
  Worker := TWorker.Create(True);
  try
    Worker.Mode := Mode;
    Worker.Start;
    Worker.WaitFor;
    If (Mode = 'escape') or (Mode = 'sync') then begin
      Check(Worker.FatalException is EExpected, 'expected worker termination changed');
      Check(Exception(Worker.FatalException).DiagnosticContext = nil, 'worker exit captured');
    end else begin
      Check(Worker.FatalException = nil, 'worker test failed');
      Error := Worker.Saved;
      Worker.Saved := nil;
      Check(Error <> nil, 'acquire failed');
      try
        raise Error;
      except
        on E: EExpected do begin
          Check(E.DiagnosticContext = nil, 'cross-thread rethrow captured');
          Check(WriteExceptionReport(E) = '', 'cross-thread report');
        end;
      end;
    end;
  finally
    Worker.Free;
  end;
end;

procedure TestParallel;
var Workers: array[0..3] of TWorker; I: Integer;
begin
  for I := Low(Workers) to High(Workers) do begin
    Workers[I] := TWorker.Create(True);
    Workers[I].Mode := 'parallel';
    Workers[I].Start;
  end;
  for I := Low(Workers) to High(Workers) do begin
    Workers[I].WaitFor;
    Check(Workers[I].FatalException = nil, 'parallel worker failed');
    Workers[I].Free;
  end;
end;

procedure SoftwareOrigin; noinline;
begin
  raise EUnexpected.Create('following software');
end;

procedure TestFilteredAV;
begin
  try
    HardwareOrigin;
  except
    on E: EAccessViolation do begin
      Check(E.DiagnosticContext = nil, 'filtered AV owns snapshot');
      Check(WriteExceptionReport(E) = '', 'filtered AV reported');
    end;
  end;
  try
    SoftwareOrigin;
  except
    on E: EUnexpected do begin
      Check(E.DiagnosticContext <> nil, 'following software not captured');
      Check(WriteExceptionReport(E) <> '', 'following software not reported');
    end;
  end;
  Check(DataCalls = 1, 'filtered AV used quota or callback');
end;

procedure TestRules;
var I: Integer; Saved: Exception; Original: TObject; Previous: Boolean;
begin
  for I := 1 to 25 do CheckRaise(EExpected.Create('expected'), True);
  CheckRaise(EExpectedChild.Create('exact does not include child'), False);
  CheckRaise(EExpectedFamily.Create('family'), True);
  CheckRaise(EExpectedGrandchild.Create('family descendant'), True);
  CheckRaise(EUnexpected.Create('not configured'), False);
  CheckRaise(Exception.Create('no default blanket filter'), False);
  CheckRaise(EAbort.Create('no default abort filter'), False);
  Check(DataCalls = 0, 'expected reports used callback/quota');

  try
    raise EUnexpected.Create('outer unexpected');
  except
    on E: EUnexpected do begin
      Original := E.DiagnosticContext;
      Check(Original <> nil, 'outer context missing');
      CheckRaise(EExpected.Create('inner expected'), True);
      Check(E.DiagnosticContext = Original, 'nested expected replaced outer');
    end;
  end;
  try
    ThrowExpected;
  except
    on E: EExpected do begin
      CheckRaise(EUnexpected.Create('inner unexpected'), False);
      Check(E.DiagnosticContext = nil, 'nested unexpected attached to expected');
      Saved := Exception(AcquireExceptionObject);
    end;
  end;
  try
    raise Saved;
  except
    on E: EExpected do Check(E.DiagnosticContext = nil, 'explicit rethrow captured');
  end;
  try
    try
      ThrowExpected;
    except
      raise;
    end;
  except
    on E: EExpected do Check(E.DiagnosticContext = nil, 'bare rethrow captured');
  end;
  TThread.ForceQueue(nil, ThrowExpected);
  try
    CheckSynchronize;
    Check(False, 'queue failed to raise');
  except
    on E: EExpected do Check(E.DiagnosticContext = nil, 'queue delivery captured');
  end;
  TestTransfer('acquire');
  TestTransfer('sync');
  TestTransfer('escape');
  TestParallel;

  Previous := SetThreadReportsEnabled(False);
  CheckRaise(EUnexpected.Create('thread disabled'), True);
  SetThreadReportsEnabled(Previous);
  Previous := SetReportsEnabled(False);
  CheckRaise(EUnexpected.Create('globally disabled'), True);
  SetReportsEnabled(Previous);
  CheckRaise(EUnexpected.Create('enabled again'), False);

  Check(DataCalls = 0, 'expected writes consumed quota');
  Check(WriteManualReport('manual with filter') <> '', 'manual was filtered');
  try
    HardwareOrigin;
  except
    on E: EAccessViolation do begin
      Check(E.DiagnosticContext <> nil, 'unexpected hardware context missing');
      Check(WriteExceptionReport(E, 'unexpected AV') <> '', 'expected exhausted quota');
    end;
  end;
  CheckRaise(EExpected.Create('expected after quota'), True);
  Check(WriteManualReport('manual after quota') <> '', 'manual quota changed');
  Check(DataCalls = 3, 'wrong report count');
end;

var Options, OptionsCopy: TDiagnosticOptions; Mode: string;
begin
  If ParamCount <> 3 then Halt(2);
  Mode := ParamStr(2);
  Options := Default(TDiagnosticOptions);
  try
    Options.AddExpectedException(nil);
    Halt(3);
  except
    on E: EArgumentNilException do ;
  end;
  Options.Directory := ParamStr(1);
  Options.MaxReportsPerRun := 1;
  If Mode <> 'empty' then begin
    Options.AddExpectedException(EExpected);
    Options.AddExpectedException(EExpectedFamily, True);
  end;
  If Mode = 'filtered-av' then Options.AddExpectedException(EAccessViolation);
  OptionsCopy := Options;
  OptionsCopy.AddExpectedException(EUnexpected);
  PreviousHook := ExceptionContextProc;
  ExceptionContextProc := Observe;
  {$ifdef LINUX}
  PreviousBacktrace := ExceptionBacktraceProc;
  ExceptionBacktraceProc := ObserveBacktrace;
  {$endif}
  InitializeReports(Options, Data);
  Options.AddExpectedException(EUnexpected);
  OptionsCopy := Default(TDiagnosticOptions);
  Options := Default(TDiagnosticOptions);
  If Mode = 'unhandled' then ThrowExpected
  else If Mode = 'rules' then TestRules
  else If Mode = 'filtered-av' then TestFilteredAV
  else If Mode = 'empty' then begin
    CheckRaise(EExpected.Create('default capture'), False);
    CheckRaise(EAbort.Create('default abort capture'), False);
  end
  else Halt(4);
  Writeln('EXPECTED_FILTER_PASS');
end.
