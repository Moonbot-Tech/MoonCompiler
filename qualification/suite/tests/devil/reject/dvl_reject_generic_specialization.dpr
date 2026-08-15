program dvl_reject_generic_specialization;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses SysUtils;
type
  TBox<T> = record
    Value: T;
  end;
var
  B: TBox<Integer>;
begin
  B.Value := 7;
  WriteLn(B.Value);
end.
