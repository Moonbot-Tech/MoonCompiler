program diagnostic_quota;
{$mode delphi}{$H+}
uses {$ifdef UNIX}cthreads, cwstring,{$endif} SysUtils, Classes, Moon.Diagnostics;
type
  TManualWorker = class(TThread)
    Saved: string;
    procedure Execute; override;
  end;
var
  Options: TDiagnosticOptions;
  CallbackCount, I: Integer;
  Names: TStringList;
  Name: string;
  E: Exception;
  Workers: array[0..3] of TManualWorker;
  FailWrites, Failed: Boolean;
procedure TManualWorker.Execute;
begin
  Saved := WriteManualReport('concurrent manual after exhaustion');
end;
procedure Check(B: Boolean; const Text: string);
begin
  If not B then raise Exception.Create(Text);
end;
procedure AppData(Report: TDiagnosticReport);
begin
  Inc(CallbackCount);
  Report.Add('quota_test', 'present');
  Check(WriteManualReport('recursive') = '', 'recursion stays blocked');
end;
procedure Remember(const FileName: string);
begin
  Check((FileName <> '') and FileExists(FileName), 'manual report must exist');
  Check(Names.IndexOf(FileName) < 0, 'filename must be unique');
  Names.Add(FileName);
end;
function WritePart(Handle: THandle; const Buffer; Count: LongInt): LongInt;
begin
  If FailWrites then Exit(0);
  Result := FileWrite(Handle, Buffer, Count);
end;
begin
  Options := Default(TDiagnosticOptions);
  Options.Directory := ParamStr(1);
  Options.MaxReportsPerRun := 2;
  InitializeReports(Options, AppData, 'quota-test');
  Names := TStringList.Create;
  E := Exception.Create('quota exception');
  try
    If ParamStr(2) = 'failure' then begin
      DiagnosticTestWrite := WritePart;
      FailWrites := True;
      for I := 1 to 2 do begin
        Failed := False;
        try WriteExceptionReport(E, 'failed automatic'); except on X: EWriteError do Failed := True; end;
        Check(Failed, 'write failure propagates');
      end;
      Check(WriteExceptionReport(E, 'failed attempts exhaust quota') = '', 'failed automatic consumes quota');
      Failed := False;
      try WriteManualReport('failed manual'); except on X: EWriteError do Failed := True; end;
      Check(Failed, 'manual admitted despite exhausted automatic budget');
      FailWrites := False;
      Remember(WriteManualReport('manual recovery'));
      Check(WriteExceptionReport(E, 'still exhausted') = '', 'failure recovery preserves quota');
      Writeln('DIAGNOSTIC_QUOTA_FAILURE_PASS');
      Exit;
    end;
    for I := 1 to 3 do Remember(WriteManualReport('before automatic'));
    Remember(WriteExceptionReport(E, 'automatic one'));
    Remember(WriteManualReport('between automatic'));
    Remember(WriteExceptionReport(E, 'automatic two'));
    Check(WriteExceptionReport(E, 'exhausted') = '', 'automatic quota enforced');
    for I := 1 to 3 do Remember(WriteManualReport('after automatic'));
    Check(WriteExceptionReport(E, 'still exhausted') = '', 'manual does not reset quota');
    Check(CallbackCount = 9, 'only accepted requests invoke callbacks');
    SetReportsEnabled(False);
    Check(WriteManualReport('disabled') = '', 'manual honors enable switch');
    SetReportsEnabled(True);
    Remember(WriteManualReport('enabled again'));
    Check(CallbackCount = 10, 'switch preserves policy');
    for I := 0 to High(Workers) do Workers[I] := TManualWorker.Create(True);
    for I := 0 to High(Workers) do Workers[I].Start;
    for I := 0 to High(Workers) do begin
      Workers[I].WaitFor;
      Check(Workers[I].FatalException = nil, 'concurrent manual report failed');
      Remember(Workers[I].Saved);
      Workers[I].Free;
    end;
    Check(CallbackCount = 14, 'concurrent manual quota bypass');
    Writeln('DIAGNOSTIC_QUOTA_PASS');
  finally
    E.Free;
    Names.Free;
  end;
end.
