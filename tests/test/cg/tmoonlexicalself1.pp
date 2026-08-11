{ %OPT=-O2 }
program tmoonlexicalself1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch inlinevars}

type
  TProc = reference to procedure;
  TProbe = class
    Value: Integer;
    procedure Run;
  end;

procedure TProbe.Run;
var
  Outer: TProc;
begin
  Outer :=
    procedure
    begin
      var Inner: TProc :=
        procedure
        begin
          Inc(Value, 7);
        end;
      Inner();
    end;
  Outer();
end;

var
  Probe: TProbe;
begin
  Probe := TProbe.Create;
  try
    Probe.Run;
    if Probe.Value <> 7 then
      Halt(1);
  finally
    Probe.Free;
  end;
end.
