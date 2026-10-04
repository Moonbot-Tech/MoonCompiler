program diagnostic_reports;
{$mode delphi}{$H+}{$codepage utf8}

uses
  {$ifdef UNIX}cthreads, cwstring, BaseUnix,{$endif}
  SysUtils, Classes, Moon.Diagnostics;

type
  TWorker = class(TThread)
    Mode: Integer;
    ReportPath: string;
    procedure Execute; override;
  end;
  TTermination = class
    Count: Integer;
    procedure Done(Sender: TObject);
  end;

var
  StopBusy, BusyReady, DepthDigest: LongInt;
  Attachment: string;
  FailData: Boolean;

procedure Require(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create('TEST: ' + Text);
end;

procedure AppData(Report: TDiagnosticReport);
begin
  If FailData then raise Exception.Create('deliberate callback failure');
  Report.Add('custom', 'Диагностика → ✓');
  If Attachment <> '' then Report.AttachFile(Attachment);
end;

procedure OriginLeaf;
begin
  raise Exception.Create('original error → 42');
end;

procedure OriginParent;
begin
  OriginLeaf;
end;

procedure HardwareLeaf;
var
  Sentinel: array[0..63] of QWord;
  Bad: PLongInt;
  I: Integer;
begin
  for I := 0 to High(Sentinel) do Sentinel[I] := $0123456789ABCDEF;
  Bad := Pointer(PtrUInt(StrToInt(ParamStr(3))));
  Bad^ := LongInt(Sentinel[7]);
  WriteLn(Sentinel[0]);
end;

procedure WorkerSpinLeaf;
begin
  InterlockedExchange(BusyReady, 1);
  while InterlockedCompareExchange(StopBusy, 0, 0) = 0 do Sleep(1);
end;

procedure MainBusyLeaf;
begin
  InterlockedExchange(BusyReady, 1);
  while InterlockedCompareExchange(StopBusy, 0, 0) = 0 do ;
end;

procedure TWorker.Execute;
var
  Iteration: Integer;
{$ifdef UNIX}
  Mask, OldMask: TSigSet;
  I: Integer;
{$endif}
begin
  case Mode of
    0: raise Exception.Create('worker failure');
    1: WorkerSpinLeaf;
    2: begin
      while InterlockedCompareExchange(BusyReady, 0, 0) = 0 do Sleep(1);
      try
        ReportPath := WriteManualReport('busy main');
      finally
        InterlockedExchange(StopBusy, 1);
      end;
    end;
    {$ifdef UNIX}
    3: begin
      FpSigEmptySet(Mask);
      for I := 34 to 64 do FpSigAddSet(Mask, I);
      Require(FpSigProcMask(SIG_BLOCK, @Mask, @OldMask) = 0, 'block sample signal');
      try
        WorkerSpinLeaf;
      finally
        FpSigProcMask(SIG_SETMASK, @OldMask, nil);
      end;
    end;
    {$endif}
    4: begin
      for Iteration := 1 to 1000 do begin
        try
          OriginLeaf;
        except
          Require(Exception(ExceptObject).DiagnosticContext <> nil, 'concurrent context');
        end;
      end;
      try
        OriginLeaf;
      except
        WriteExceptionReport('concurrent worker');
      end;
    end;
  end;
end;

procedure TTermination.Done(Sender: TObject);
begin
  Inc(Count);
end;

procedure RunCaught;
var
  Saved: Exception;
  OriginalContext: TObject;
begin
  Saved := nil;
  try
    try
      OriginParent;
    except
      on E: Exception do begin
        OriginalContext := E.DiagnosticContext;
        Require(OriginalContext <> nil, 'capture before except');
        try
          raise Exception.Create('nested exception');
        except
          Require(Exception(ExceptObject).DiagnosticContext <> OriginalContext, 'nested ownership');
        end;
        Require(E.DiagnosticContext = OriginalContext, 'outer context survives nested');
        WriteLn('REPORT ', WriteExceptionReport('caught'));
        raise;
      end;
    end;
  except
    on E: Exception do begin
      Require(E.DiagnosticContext = OriginalContext, 'reraise keeps original context');
      Saved := Exception(AcquireExceptionObject);
    end;
  end;
  try
    WriteLn('REPORT ', WriteExceptionReport(Saved, 'acquired after except'));
  finally
    Saved.Free;
  end;
end;

procedure RunWorker;
var
  Worker: TWorker;
  Termination: TTermination;
begin
  Termination := TTermination.Create;
  Worker := TWorker.Create(True);
  try
    Worker.Mode := 0;
    Worker.OnTerminate := Termination.Done;
    Worker.Start;
    Worker.WaitFor;
    Require(Worker.FatalException is Exception, 'FatalException retained');
    Require(Exception(Worker.FatalException).Message = 'worker failure', 'worker message');
    Require(Termination.Count = 1, 'OnTerminate exactly once');
  finally
    Worker.Free;
    Termination.Free;
  end;
end;

procedure RunManual(BusyMain: Boolean; BlockSignal: Boolean = False);
var
  Worker: TWorker;
begin
  Worker := TWorker.Create(True);
  try
    If BusyMain then Worker.Mode := 2 else Worker.Mode := 1;
    If BlockSignal then Worker.Mode := 3;
    Worker.Start;
    If BusyMain then begin
      MainBusyLeaf;
      Worker.WaitFor;
      Require(Worker.FatalException = nil, 'reporter worker');
      WriteLn('REPORT ', Worker.ReportPath);
    end else begin
      while InterlockedCompareExchange(BusyReady, 0, 0) = 0 do Sleep(1);
      WriteLn('REPORT ', WriteManualReport('live worker'));
    end;
  finally
    InterlockedExchange(StopBusy, 1);
    Worker.WaitFor;
    Worker.Free;
  end;
end;

procedure DeepRaise(Depth: Integer);
begin
  If Depth = 0 then OriginLeaf;
  DeepRaise(Depth - 1);
  Inc(DepthDigest); { Not a tail call; the stack really has all these frames. }
end;

procedure RunDeep;
begin
  try
    DeepRaise(40);
  except
    WriteExceptionReport('deep stack');
  end;
end;

procedure RunReusable;
var
  I: Integer;
begin
  { SysUtils deliberately reuses one EOutOfMemory instance. No actual OOM. }
  for I := 1 to 20 do begin
    try
      OutOfMemoryError;
    except
      on E: EOutOfMemory do Require(E.DiagnosticContext <> nil, 'reusable exception');
    end;
  end;
  RunDeep;
end;

procedure RunConcurrent;
var
  Workers: array[0..7] of TWorker;
  I: Integer;
begin
  for I := 0 to High(Workers) do begin
    Workers[I] := TWorker.Create(True);
    Workers[I].Mode := 4;
    Workers[I].Start;
  end;
  for I := 0 to High(Workers) do begin
    Workers[I].WaitFor;
    Require(Workers[I].FatalException = nil, 'concurrent worker failed');
    Workers[I].Free;
  end;
end;

procedure RunReportFailure;
begin
  FailData := True;
  try
    Require(WriteManualReport('callback failure retained') <> '', 'partial report returned');
  finally
    FailData := False;
  end;
  WriteManualReport('next report works');
end;

{$ifdef UNIX}
type TNativeThreadFunc = function(Arg: Pointer): Pointer; cdecl;
function pthread_create(out Thread: PtrUInt; Attr: Pointer; Func: TNativeThreadFunc; Arg: Pointer): Integer; cdecl; external 'c';
function pthread_join(Thread: PtrUInt; Value: Pointer): Integer; cdecl; external 'c';
procedure usleep(Microseconds: LongWord); cdecl; external 'c';

function NativeWorker(Arg: Pointer): Pointer; cdecl;
begin
  InterlockedExchange(BusyReady, 1);
  while InterlockedCompareExchange(StopBusy, 0, 0) = 0 do usleep(1000);
  Result := nil;
end;

procedure RunNativeThread;
var
  Thread: PtrUInt;
begin
  Require(pthread_create(Thread, nil, NativeWorker, nil) = 0, 'native thread created');
  try
    while InterlockedCompareExchange(BusyReady, 0, 0) = 0 do Sleep(1);
    WriteManualReport('thread not registered with TThread');
  finally
    InterlockedExchange(StopBusy, 1);
    Require(pthread_join(Thread, nil) = 0, 'native thread joined');
  end;
end;
{$endif}

var
  Mode: string;
begin
  Mode := ParamStr(1);
  If ParamCount >= 4 then Attachment := ParamStr(4);
  InitializeReports(ParamStr(2), AppData, 'diagnostic-test-1');
  If Mode = 'caught' then RunCaught
  else If Mode = 'worker' then RunWorker
  else If Mode = 'manual' then RunManual(False)
  else If Mode = 'busy-main' then RunManual(True)
  else If Mode = 'blocked' then RunManual(False, True)
  else If Mode = 'deep' then RunDeep
  else If Mode = 'reusable' then RunReusable
  else If Mode = 'concurrent' then RunConcurrent
  else If Mode = 'report-failure' then RunReportFailure
  {$ifdef UNIX}else If Mode = 'native-thread' then RunNativeThread{$endif}
  else If Mode = 'unhandled' then OriginParent
  else If Mode = 'software-external' then begin
    try
      raise EAccessViolation.Create('explicit software exception');
    except
      WriteExceptionReport('not a hardware fault');
    end;
  end
  else If Mode = 'hardware' then begin
    try
      HardwareLeaf;
    except
      on E: EAccessViolation do WriteLn('REPORT ', WriteExceptionReport('hardware'));
    end;
  end else raise Exception.Create('Unknown test mode');
  WriteLn('DIAGNOSTICS_TEST_PASS ', Mode);
end.
