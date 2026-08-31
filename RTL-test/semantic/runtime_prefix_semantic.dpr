program runtime_prefix_semantic;

{$mode delphi}

{ The product runtime units are intentionally absent from this uses clause.
  The installed MoonCompiler profile must inject them before SysUtils and
  Classes. }
uses
  SysUtils,
  Classes;

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  LockObject: TObject;
  Worker: TWorker;

procedure TWorker.Execute;
begin
end;

begin
  LockObject := TObject.Create;
  try
    TMonitor.Enter(LockObject);
    TMonitor.Exit(LockObject);
    Worker := TWorker.Create;
    try
      Worker.Start;
      Worker.WaitFor;
    finally
      Worker.Free;
    end;
  finally
    LockObject.Free;
  end;
  WriteLn('RUNTIME_PREFIX_OK');
end.
