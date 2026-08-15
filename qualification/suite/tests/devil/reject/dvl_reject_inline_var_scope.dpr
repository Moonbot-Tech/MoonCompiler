program dvl_reject_inline_var_scope;
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
begin
  if Random(1) = 0 then
  begin
    var Inner := 42;
    WriteLn(Inner);
  end;
end.
