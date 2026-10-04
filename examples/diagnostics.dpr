program diagnostics;

uses
  System.SysUtils, System.Classes, Moon.Diagnostics;

type
  TConfigWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure ApplicationData(Report: TDiagnosticReport);
begin
  Report.Add('operation', 'diagnostic example');
  { Report.AttachFile('application.log'); }
end;

procedure ExampleFailure;
begin
  raise Exception.Create('Example of a caught exception');
end;

procedure ReadMissingConfig;
var
  Stream: TFileStream;
begin
  { The executable is a file, so it cannot contain settings.ini. }
  Stream := TFileStream.Create(ParamStr(0) + PathDelim + 'settings.ini', fmOpenRead);
  Stream.Free;
end;

procedure TConfigWorker.Execute;
begin
  ReadMissingConfig;
end;

procedure RunWorker;
var
  Worker: TConfigWorker;
begin
  Worker := TConfigWorker.Create(True);
  try
    Worker.Start;
    Worker.WaitFor;
    WriteLn('Worker exception: ', Worker.FatalException.ClassName);
  finally
    Worker.Free;
  end;
end;

procedure ReadFirstItem;
var
  Items: TStringList;
begin
  Items := TStringList.Create;
  try
    WriteLn(Items[0]);
  finally
    Items.Free;
  end;
end;

var
  Mode: string;

begin
  InitializeReports('reports', ApplicationData);
  Mode := ParamStr(1);
  If Mode = 'conversion' then WriteLn(StrToInt('invalid amount'))
  else If Mode = 'file' then ReadMissingConfig
  else If Mode = 'collection' then ReadFirstItem
  else If Mode = 'arithmetic' then WriteLn(100 div StrToInt(ParamStr(2)))
  else If Mode = 'worker' then RunWorker
  else If Mode = '' then begin
    try
      ExampleFailure;
    except
      WriteLn(WriteExceptionReport('caught by the application'));
    end;
    WriteLn(WriteManualReport('all current threads'));
  end else raise Exception.Create('Unknown diagnostics mode: ' + Mode);
end.
