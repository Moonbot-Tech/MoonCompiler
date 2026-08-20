program dvl_reject_bare_method_into_reference;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
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
    WriteLn(Step());
  finally
    Held.Free;
  end;
end.
