program mon;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
uses SysUtils, Classes;

var
  Lock: TObject;
  Counter: Int64;

type
  TW = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TW.Execute;
begin
  TMonitor.Enter(Lock);
  try
    Inc(Counter, 10);
  finally
    TMonitor.Exit(Lock);
  end;
end;

var
  W: array[0..3] of TW;
  I: Integer;
begin
  Lock := TObject.Create;
  Counter := 0;
  for I := 0 to 3 do
  begin
    W[I] := TW.Create(True);
    W[I].FreeOnTerminate := False;
  end;
  for I := 0 to 3 do W[I].Start;
  for I := 0 to 3 do W[I].WaitFor;
  WriteLn('counter=', Counter, '   expected 40');
  for I := 0 to 3 do W[I].Free;
  Lock.Free;
end.
