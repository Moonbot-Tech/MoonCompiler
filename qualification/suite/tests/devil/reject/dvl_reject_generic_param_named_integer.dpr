program dvl_reject_generic_param_named_integer;
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
  TBox<Integer> = record
    function Take: Integer;
  end;

function TBox<Integer>.Take: Integer;
begin
  Result := Default(Integer);
end;

var
  B: TBox<Byte>;
begin
  WriteLn(SizeOf(B.Take));
end.
