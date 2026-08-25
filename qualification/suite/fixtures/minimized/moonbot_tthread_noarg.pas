program moonbot_tthread_noarg;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef unix}
  cthreads,
{$endif}
  System.Classes;

var
  Executed: Integer;

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWorker.Execute;
begin
  Executed := 1;
end;

var
  Worker: TWorker;

begin
  Executed := 0;
  Worker := TWorker.Create;
  try
    Worker.WaitFor;
    if Executed <> 1 then
      Halt(1);
  finally
    Worker.Free;
  end;
end.
