program dvl_reject_string_index_assign;
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
  S: AnsiString;
begin
  S := 'abc';
  UniqueString(S);
  S[1] := 'z';
  WriteLn(string(S));
end.
