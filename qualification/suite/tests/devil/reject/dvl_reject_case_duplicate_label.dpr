program dvl_reject_case_duplicate_label;
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
  I: Integer;
begin
  I := 1;
  case I of
    1: WriteLn('a');
    1: WriteLn('b');
  end;
end.
