program tdelphithreadcreate1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef unix}
  cthreads,
{$endif}
  Classes;

var
  ExecutionCount: Integer;

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWorker.Execute;
begin
  Inc(ExecutionCount);
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure WaitAndFree(Worker: TWorker; ErrorCode: Byte);
begin
  try
    Worker.WaitFor;
    Check(ExecutionCount = 1, ErrorCode);
  finally
    Worker.Free;
  end;
end;

var
  Worker: TWorker;

begin
  { Delphi's parameterless constructor delegates to Create(False). }
  ExecutionCount := 0;
  WaitAndFree(TWorker.Create, 1);

  { Keep both existing constructor forms unambiguous and operational. }
  ExecutionCount := 0;
  WaitAndFree(TWorker.Create(False), 2);

  ExecutionCount := 0;
  Worker := TWorker.Create(True);
  try
    Check(ExecutionCount = 0, 3);
    Worker.Start;
    Worker.WaitFor;
    Check(ExecutionCount = 1, 4);
  finally
    Worker.Free;
  end;
end.
