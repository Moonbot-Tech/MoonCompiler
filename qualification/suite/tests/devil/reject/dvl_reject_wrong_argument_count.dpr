program dvl_reject_wrong_argument_count;
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
procedure P(A, B: Integer);
begin
  WriteLn(A + B);
end;
begin
  P(1);
end.
