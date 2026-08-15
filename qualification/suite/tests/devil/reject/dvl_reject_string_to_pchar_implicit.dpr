program dvl_reject_string_to_pchar_implicit;
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
  P: PAnsiChar;
  I: Integer;
begin
  I := 5;
  P := I;
  WriteLn(P);
end.
