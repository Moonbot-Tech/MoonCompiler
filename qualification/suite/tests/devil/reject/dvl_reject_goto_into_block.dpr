program dvl_reject_goto_into_block;
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
label
  Target;
begin
  goto Target;
  if True then
  begin
Target:
    WriteLn('here');
  end;
end.
