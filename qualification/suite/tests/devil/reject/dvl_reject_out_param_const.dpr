program dvl_reject_out_param_const;
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
procedure P(out X: Integer);
begin
  X := 1;
end;
const
  C = 5;
begin
  P(C);
end.
