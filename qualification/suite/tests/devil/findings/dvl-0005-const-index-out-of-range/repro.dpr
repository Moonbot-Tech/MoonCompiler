program dvl_reject_array_const_index_out_of_range;
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
  A: array[0..3] of Integer;
begin
  A[9] := 1;
  WriteLn(A[0]);
end.
