program diagnostic_resilience;
{$mode delphi}{$H+}{$codepage utf8}
{$ifndef MOON_DIAGNOSTICS_TEST}{$fatal Test hooks must be enabled}{$endif}

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes, Moon.Diagnostics;

var
  FailLookup, FailDuringData, FailBeforeClose, FailWrites, Reenter, MissingAttachment: Boolean;
  ResolveCalls, WriteCalls: Integer;
  WriteLimit: LongInt = MaxInt;
  ReportDirectory, Version: string;

procedure Require(Value: Boolean; const Message: string);
begin
  If not Value then raise Exception.Create('TEST: ' + Message);
end;

procedure BeforeResolve;
var
  Search: TSearchRec;
  Text: TStringList;
  Stream: TFileStream;
begin
  Inc(ResolveCalls);
  If FailLookup then begin
    FailLookup := False;
    { The original context must already be on disk before risky lookup begins. }
    Require(FindFirst(IncludeTrailingPathDelimiter(ReportDirectory) + '*.txt', faAnyFile, Search) = 0,
      'raw report file exists');
    Text := TStringList.Create;
    try
      Stream := TFileStream.Create(IncludeTrailingPathDelimiter(ReportDirectory) + Search.Name,
        fmOpenRead or fmShareDenyNone);
      try
        Text.LoadFromStream(Stream, TEncoding.UTF8);
      finally
        Stream.Free;
      end;
      Require(Pos('pc[$', Text.Text) > 0, 'raw PCs persisted before lookup');
      Require(Pos('RIP=$', Text.Text) > 0, 'registers persisted before lookup');
      WriteLn('RAW_CONTEXT_ALREADY_ON_DISK');
    finally
      Text.Free;
      FindClose(Search);
    end;
    raise Exception.Create('deliberate symbol lookup failure');
  end;
end;

function WritePart(Handle: THandle; const Buffer; Count: LongInt): LongInt;
begin
  Inc(WriteCalls);
  If FailWrites then Exit(0);
  If Count > WriteLimit then Count := WriteLimit;
  Result := FileWrite(Handle, Buffer, Count);
end;

procedure AppData(Report: TDiagnosticReport);
begin
  If Reenter then Require(WriteManualReport('must not recurse') = '', 'same-thread recursion blocked');
  If FailDuringData then FailWrites := True;
  Report.Add('payload', 'Начало → ' + StringOfChar('x', 50000) + ' ✓ конец');
  Report.Add('after_payload', 'present');
  If MissingAttachment then begin
    Report.AttachFile(IncludeTrailingPathDelimiter(ReportDirectory) + 'does-not-exist.bin');
    Report.Add('after_missing_attachment', 'must not appear');
  end;
  If FailBeforeClose then FailWrites := True;
end;

procedure Origin;
begin
  raise Exception.Create('resilience original exception');
end;

procedure ReportOrigin;
begin
  try
    Origin;
  except
    WriteExceptionReport('resilience report');
  end;
end;

procedure SymbolFailure;
begin
  FailLookup := True;
  try
    Origin;
  except
    WriteExceptionReport('symbol failure');
    Require(ResolveCalls = 1, 'failed reader is not retried for every frame');
    WriteExceptionReport('reader recovers in next report');
    Require(ResolveCalls > 1, 'failure does not disable later reports');
  end;
end;

procedure WriterFailure(FinalFlush: Boolean);
var
  Failed: Boolean;
begin
  FailDuringData := not FinalFlush;
  FailBeforeClose := FinalFlush;
  Failed := False;
  try
    ReportOrigin;
  except
    on E: EWriteError do Failed := True;
  end;
  Require(Failed, 'output error propagates from callback or final buffer flush');
  FailDuringData := False;
  FailBeforeClose := False;
  FailWrites := False;
  ReportOrigin;
end;

var
  Mode: string;
begin
  Mode := ParamStr(1);
  ReportDirectory := ParamStr(2);
  Version := 'resilience-build-1';
  InitializeReports(ReportDirectory, AppData, Version);
  Version := 'changed-after-initialization';
  DiagnosticTestBeforeResolve := BeforeResolve;
  DiagnosticTestWrite := WritePart;
  If Mode = 'symbols' then SymbolFailure
  else If Mode = 'partial-write' then begin
    WriteLimit := 73;
    ReportOrigin;
    Require(WriteCalls > 100, 'short writes exercised across multiple buffers');
  end
  else If Mode = 'write-failure' then WriterFailure(False)
  else If Mode = 'close-failure' then WriterFailure(True)
  else If Mode = 'missing-attachment' then begin
    MissingAttachment := True;
    ReportOrigin;
  end
  else If Mode = 'reentry' then begin
    Reenter := True;
    ReportOrigin;
  end
  else If Mode = 'unhandled-write-failure' then begin
    FailDuringData := True;
    Origin;
  end
  else raise Exception.Create('unknown mode');
  WriteLn('DIAGNOSTIC_RESILIENCE_PASS ', Mode);
end.
