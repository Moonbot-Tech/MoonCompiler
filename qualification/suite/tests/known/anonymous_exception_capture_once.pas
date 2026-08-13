program anonymous_exception_capture_once;

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

begin
  try
    raise Exception.Create('once');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          WriteLn(E.Message);
        end);
  end;
end.
