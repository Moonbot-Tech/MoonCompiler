program anonymous_exception_capture_twice;

{$IFDEF FPC}
{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$ENDIF}

uses
  SysUtils;

type
  TProc = reference to procedure;

procedure Invoke(const AProc: TProc);
begin
  AProc;
end;

procedure Run;
begin
  try
    raise Exception.Create('first');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          WriteLn(E.Message);
        end);
  end;

  try
    raise Exception.Create('second');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          WriteLn(E.Message);
        end);
  end;
end;

begin
  Run;
end.
