program dvl_reject_set_of_too_large;
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
  TBig = set of Integer;
var
  S: TBig;
begin
  S := [1];
  WriteLn(SizeOf(S));
end.
