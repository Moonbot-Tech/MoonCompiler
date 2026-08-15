program dvl_reject_generic_constraint_violation;
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
  TNeedsClass<T: class> = record
    Value: T;
  end;
var
  R: TNeedsClass<Integer>;
begin
  WriteLn(SizeOf(R));
end.
