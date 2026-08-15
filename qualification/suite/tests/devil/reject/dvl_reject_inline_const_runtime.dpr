program dvl_reject_inline_const_runtime;
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
  Base: Integer;
begin
  Base := 3;
  const Derived = 2 * Base + 1;
  WriteLn(Derived);
end.
