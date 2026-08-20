program procval;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

type
  TStep = reference to function: Integer;

  TBox = class
  public
    Slot: Integer;
    function Make: TStep;
  end;

function TBox.Make: TStep;
begin
  Result :=
    function: Integer
    begin
      Result := Slot;
    end;
end;

var
  Held: TBox;
  Step: TStep;
begin
  Held := TBox.Create;
  try
    Held.Slot := 1;
    Step := Held.Make;
    WriteLn('step = ', Step());
  finally
    Held.Free;
  end;
end.
