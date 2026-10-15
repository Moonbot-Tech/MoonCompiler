program diagnostic_transfer;
{$mode delphi}{$H+}

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, Moon.Diagnostics;

type
  TForeignContext = class
    destructor Destroy; override;
  end;
  TTransfer = class(TThread)
    Saved: Exception;
    Original: TObject;
    Mode: string;
    procedure Fault;
    procedure Execute; override;
  end;

var
  HookCalls, ForeignDestroyed: LongInt;
  InitialHook: TExceptionContextProc;

destructor TForeignContext.Destroy;
begin
  Inc(ForeignDestroyed);
  inherited;
end;

procedure Require(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create('TEST: ' + Text);
end;

procedure CaptureObserver(Obj: TObject; Addr: CodePointer; Frame: Pointer; FrameCount: LongInt;
  Frames: PCodePointer; Context: Pointer; Hardware: Boolean);
begin
  If Obj <> nil then InterlockedIncrement(HookCalls);
  If Assigned(InitialHook) then InitialHook(Obj, Addr, Frame, FrameCount, Frames, Context, Hardware);
end;

procedure HardwareOrigin;
var
  Address: PByte;
begin
  Address := Pointer(PtrUInt(StrToInt(ParamStr(3))));
  Address^ := 17;
end;

procedure SoftwareOrigin;
begin
  raise Exception.Create('software origin');
end;

procedure TTransfer.Fault;
begin
  try
    If Mode = 'queue-software' then SoftwareOrigin else HardwareOrigin;
  except
    on E: Exception do begin
      Original := E.DiagnosticContext;
      Require(Original <> nil, 'original captured');
      WriteLn('REPORT ', WriteExceptionReport(E, 'origin'));
      raise;
    end;
  end;
end;

procedure TTransfer.Execute;
begin
  If Mode = 'synchronize' then begin
    try
      Synchronize(Fault);
      Require(False, 'synchronize did not throw');
    except
      on E: EAccessViolation do begin
        Require(E.DiagnosticContext = Original, 'synchronize keeps original context');
        WriteLn('REPORT ', WriteExceptionReport(E, 'delivered'));
      end;
    end;
  end else begin
    try
      HardwareOrigin;
    except
      on E: EAccessViolation do begin
        Original := E.DiagnosticContext;
        Require(Original <> nil, 'worker captured');
        Saved := Exception(AcquireExceptionObject);
        WriteLn('REPORT ', WriteExceptionReport(E, 'origin'));
      end;
    end;
  end;
end;

procedure Followup;
begin
  try
    SoftwareOrigin;
  except
    WriteLn('REPORT ', WriteExceptionReport('following software exception'));
  end;
end;

procedure RunTransfer(const Mode: string);
var
  Worker: TTransfer;
  E: Exception;
  Original: TObject;
  BeforeHook, I: LongInt;
begin
  Worker := TTransfer.Create(True);
  try
    Worker.Mode := Mode;
    If (Mode = 'queue-hardware') or (Mode = 'queue-software') then begin
      TThread.ForceQueue(nil, Worker.Fault);
      try
        CheckSynchronize;
        Require(False, 'queue did not throw');
      except
        on Error: Exception do begin
          Require(Worker.Original <> nil, 'callback ran');
          Require(Error.DiagnosticContext = Worker.Original, 'queue keeps original context');
          WriteLn('REPORT ', WriteExceptionReport(Error, 'delivered'));
        end;
      end;
    end else begin
      Worker.Start;
      Worker.WaitFor;
      Require(Worker.FatalException = nil, 'worker succeeded');
      If Mode = 'acquired' then begin
        E := Worker.Saved;
        Worker.Saved := nil;
        Original := Worker.Original;
        BeforeHook := HookCalls;
        for I := 1 to 3 do begin
          try
            If I = 2 then raise E at @RunTransfer else raise E;
          except
            on Error: EAccessViolation do begin
              Require(Error.DiagnosticContext = Original, 'explicit rethrow keeps original context');
              E := Exception(AcquireExceptionObject);
            end;
          end;
        end;
        try
          Require(HookCalls = BeforeHook + 3, 'previous capture notified for each rethrow');
          WriteLn('REPORT ', WriteExceptionReport(E, 'delivered'));
        finally
          E.Free;
        end;
      end;
    end;
    Followup;
    Require(HookCalls >= 3, 'capture hook called');
  finally
    Worker.Free;
  end;
end;

procedure RunLifecycle;
var
  Saved: Exception;
  Original: TObject;
  I: Integer;
begin
  Saved := nil;
  SetThreadReportsEnabled(False);
  try
    try
      SoftwareOrigin;
    except
      Saved := Exception(AcquireExceptionObject);
      Require(Saved.DiagnosticContext = nil, 'disabled capture');
    end;
  finally
    SetThreadReportsEnabled(True);
  end;
  try
    raise Saved;
  except
    on E: Exception do begin
      Require(E.DiagnosticContext <> nil, 'first enabled raise captured');
      Saved := Exception(AcquireExceptionObject);
    end;
  end;
  Original := Saved.DiagnosticContext;
  try
    try
      HardwareOrigin;
    except
      on E: EAccessViolation do Require(E.DiagnosticContext <> Original, 'nested hardware has own context');
    end;
    Require(Saved.DiagnosticContext = Original, 'outer survived hardware fault');
    WriteLn('REPORT ', WriteExceptionReport(Saved, 'enabled origin'));
  finally
    Saved.Free;
  end;
  try
    SoftwareOrigin;
  except
    Saved := Exception(AcquireExceptionObject);
  end;
  Saved.DiagnosticContext := nil;
  try
    raise Saved;
  except
    on E: Exception do Require(E.DiagnosticContext <> nil, 'explicit reset permits new capture');
  end;
  for I := 1 to 20 do begin
    try
      OutOfMemoryError;
    except
      on E: EOutOfMemory do begin
        Require(E.DiagnosticContext <> nil, 'reusable OOM captured');
        Saved := E;
      end;
    end;
    { The RTL singleton survives Destroy, but its owned snapshot must not. }
    Require(Saved.DiagnosticContext = nil, 'OOM destruction clears previous origin');
  end;
  Saved := Exception.Create('foreign context');
  Saved.DiagnosticContext := TForeignContext.Create;
  try
    raise Saved;
  except
    on E: Exception do begin
      Require(ForeignDestroyed = 1, 'foreign context freed once');
      Require(not (E.DiagnosticContext is TForeignContext), 'foreign context replaced');
      WriteLn('REPORT ', WriteExceptionReport(E, 'foreign replaced'));
    end;
  end;
  Followup;
end;

begin
  InitialHook := ExceptionContextProc;
  ExceptionContextProc := @CaptureObserver;
  InitializeReports(ParamStr(2));
  If ParamStr(1) = 'lifecycle' then RunLifecycle else RunTransfer(ParamStr(1));
  WriteLn('DIAGNOSTIC_TRANSFER_PASS ', ParamStr(1));
end.
