program diagnostic_delivery;
{$mode delphi}{$H+}{$codepage utf8}

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, Moon.Diagnostics, Moon.Diagnostics.Zip;

var
  Mode: string;
  ZipWrites: Integer;

function NameReport(const Kind, Title: string): string;
begin
  If Mode = 'name-error' then raise Exception.Create('deliberate name failure');
  If Mode = 'unsafe-name' then Exit('../evil\name:<>"|?*' + #10);
  If Mode = 'long-name' then Exit(StringOfChar('Ж', 200));
  Result := 'Бот → [U_42]';
  If Kind = 'manual' then Result := Result + '_XR';
  Result := Result + '_V123';
end;

{$ifdef MOON_DIAGNOSTICS_TEST}
function FailedWrite(Handle: THandle; const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
end;

function ZipWrite(Handle: THandle; const Buffer; Count: LongInt): LongInt;
begin
  Inc(ZipWrites);
  If (Mode = 'zip-failure') or ((Mode = 'zip-failure-after-write') and (ZipWrites > 1)) then Exit(0);
  If (Mode = 'zip-partial-write') and (Count > 257) then Count := 257;
  Result := FileWrite(Handle, Buffer, Count);
end;
{$endif}

procedure Data(Report: TDiagnosticReport);
var
  Found: TSearchRec;
  Existing: TFileStream;
begin
  Report.Add('payload', 'Начало → ' + StringOfChar('x', 50000) + ' ✓ конец');
  Report.AttachFile(ParamStr(6));
  If Mode = 'zip-collision' then begin
    If FindFirst(IncludeTrailingPathDelimiter(ParamStr(2)) + '*.txt', faAnyFile, Found) <> 0 then Halt(11);
    try
      Existing := TFileStream.Create(IncludeTrailingPathDelimiter(ParamStr(2)) +
        ChangeFileExt(Found.Name, '.zip'), fmCreate);
      try
        Existing.WriteByte(42);
      finally
        Existing.Free;
      end;
    finally
      FindClose(Found);
    end;
  end;
  {$ifdef MOON_DIAGNOSTICS_TEST}
  If Mode = 'write-failure' then begin
    DiagnosticTestWrite := FailedWrite;
    Report.Add('must_fail', StringOfChar('y', 20000));
  end;
  {$endif}
end;

procedure Origin;
begin
  raise Exception.Create('delivery original exception');
end;

procedure ReportCaught;
begin
  try
    Origin;
  except
    WriteLn(UTF8Encode(WriteExceptionReport('caught delivery')));
  end;
end;

var
  Options: TDiagnosticOptions;
  One, Two: TThread;
begin
  Mode := ParamStr(1);
  Options := Default(TDiagnosticOptions);
  Options.Directory := ParamStr(2);
  Options.FileName := NameReport;
  Options.PostURL := ParamStr(3);
  Options.PostFieldName := ParamStr(7);
  Options.PostTimeoutMS := StrToInt(ParamStr(4));
  Options.PostSuccessText := ParamStr(5);
  If Options.Directory = '-' then Options.Directory := '';
  If Options.PostURL = '-' then Options.PostURL := '';
  If Options.PostFieldName = '-' then Options.PostFieldName := '';
  If Options.PostSuccessText = '-' then Options.PostSuccessText := '';
  InitializeReports(Options, Data, 'delivery-test-1');
  {$ifdef MOON_DIAGNOSTICS_TEST}
  If Pos('zip-', Mode) = 1 then DiagnosticTestZipWrite := ZipWrite;
  {$endif}
  If Mode = 'unhandled' then Origin;
  If Mode = 'handled' then begin
    try
      Origin;
    except
    end;
  end else If Mode = 'manual' then
    WriteLn(UTF8Encode(WriteManualReport('manual delivery')))
  else If Mode = 'concurrent' then begin
    One := TThread.CreateAnonymousThread(ReportCaught);
    Two := TThread.CreateAnonymousThread(ReportCaught);
    One.FreeOnTerminate := False;
    Two.FreeOnTerminate := False;
    One.Start;
    Two.Start;
    One.WaitFor;
    Two.WaitFor;
    If (One.FatalException <> nil) or (Two.FatalException <> nil) then Halt(9);
    One.Free;
    Two.Free;
  end else If Mode = 'write-failure' then begin
    try
      ReportCaught;
      Halt(10);
    except
      on E: EWriteError do WriteLn('EXPECTED_LOCAL_WRITE_FAILURE');
    end;
  end else
    ReportCaught;
  WriteLn('DIAGNOSTIC_DELIVERY_PASS');
end.
