program dvl_reject_for_counter_not_ordinal;
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
var
  D: Double;
begin
  for D := 1.0 to 2.0 do
    WriteLn(D);
end.
