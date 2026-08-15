program dvl_reject_overload_ambiguous;
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
procedure P(X: Integer); overload;
begin
  WriteLn('i', X);
end;
procedure P(X: Int64); overload;
begin
  WriteLn('l', X);
end;
var
  C: Cardinal;
begin
  C := 1;
  P(C);
end.
