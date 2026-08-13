unit exception_capture_initfinal_unit;

{$IFDEF FPC}
{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$ENDIF}

interface

implementation

uses
{$IFDEF FPC}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}

type
  TProc = reference to procedure;

procedure Invoke(const AProc: TProc); inline;
begin
  AProc;
end;

initialization
  try
    raise Exception.Create('unit-init');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          WriteLn(E.Message);
          Flush(Output);
        end);
  end;

finalization
  try
    raise Exception.Create('unit-final');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          WriteLn(E.Message);
          Flush(Output);
        end);
  end;

end.
