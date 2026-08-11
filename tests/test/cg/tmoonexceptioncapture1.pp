{ %OPT=-O2 }
program tmoonexceptioncapture1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils;

type
  TProc = reference to procedure;

procedure Invoke(const AProc: TProc); inline;
begin
  AProc;
end;

begin
  try
    raise Exception.Create('captured');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          if E.Message <> 'captured' then
            Halt(1);
        end);
  end;
end.
