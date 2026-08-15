program dvl_reject_set_element_out_of_range;
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
  TSmall = set of 0..7;
var
  S: TSmall;
begin
  S := [9];
  WriteLn(SizeOf(S));
end.
