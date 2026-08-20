program dvl_stress_011_deep_expression;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
var
  R: Integer;
begin
  R := (((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((1 + 1) * 2) - 3) - 4) or 5) * 6) + 7) xor 1) * 2) * 3) - 4) + 5) - 6) + 7) * 1) + 2) + 3) * 4) or 5) * 6) xor 7) * 1) xor 2) * 3) + 4) + 5) or 6) + 7) or 1) or 2) + 3) * 4) + 5) + 6) xor 7) + 1) - 2) - 3) + 4) xor 5) xor 6) + 7) xor 1) xor 2) - 3) or 4) or 5) xor 6) - 7) * 1) * 2) - 3) - 4) - 5) + 6) - 7) xor 1) - 2) - 3) * 4) xor 5) * 6) xor 7) + 1) * 2) + 3) or 4) xor 5) xor 6) - 7) or 1) xor 2) or 3) xor 4) xor 5) or 6) + 7) xor 1) + 2) or 3) - 4) or 5) or 6) xor 7) xor 1) xor 2) - 3) + 4) + 5) xor 6) or 7) xor 1) or 2) + 3) or 4) - 5) * 6) * 7) xor 1) or 2) or 3) - 4) + 5) xor 6) or 7) xor 1) - 2) + 3) + 4) xor 5) * 6) + 7) * 1) or 2) or 3) xor 4) or 5) - 6) * 7) or 1) - 2) xor 3) + 4) xor 5) * 6) xor 7) * 1) + 2) - 3) xor 4) * 5) * 6) or 7) - 1) * 2) or 3) * 4) xor 5) xor 6) or 7) - 1) * 2) - 3) xor 4) + 5) - 6) xor 7) xor 1) - 2) + 3) * 4) or 5) + 6) or 7) - 1) - 2) or 3) or 4) xor 5) xor 6) or 7) + 1) - 2) * 3) * 4) - 5) + 6) xor 7) xor 1) or 2) * 3) xor 4) * 5) xor 6) * 7) or 1) xor 2) or 3) - 4) + 5) or 6) or 7) + 1) + 2) - 3) + 4) - 5) * 6) - 7) xor 1) xor 2) xor 3) * 4) + 5) - 6) + 7) - 1) * 2) xor 3) or 4) xor 5) or 6) xor 7) xor 1) xor 2) + 3) + 4) + 5) + 6) + 7) xor 1) - 2) + 3) - 4) xor 5) * 6) xor 7) * 1) - 2) * 3) + 4) + 5) * 6) or 7) * 1) + 2) * 3) * 4) * 5) xor 6) xor 7) - 1) xor 2) or 3) or 4) - 5) * 6) - 7) * 1) * 2) + 3) * 4) or 5) xor 6) - 7) * 1) + 2) + 3) - 4) or 5) - 6) + 7) or 1) or 2) - 3) xor 4) - 5) - 6) * 7) * 1) or 2) xor 3) xor 4) + 5) - 6) xor 7) + 1) + 2) - 3) or 4) xor 5) or 6) + 7) xor 1) xor 2) - 3) xor 4) * 5) + 6) * 7) + 1) xor 2) + 3) + 4) - 5) - 6) - 7) + 1) xor 2) * 3) xor 4) * 5) or 6) * 7) * 1) - 2) or 3) - 4) or 5) - 6) xor 7) xor 1) + 2) - 3) or 4) - 5) xor 6) xor 7) - 1) + 2) or 3) or 4) xor 5) + 6) + 7) xor 1) * 2) or 3) + 4) + 5) + 6) xor 7) + 1) xor 2) * 3) + 4) - 5) - 6) + 7) or 1) xor 2) or 3) xor 4) + 5) * 6) - 7) + 1) xor 2) - 3) or 4) xor 5) + 6) * 7) + 1) or 2) xor 3) + 4) xor 5) or 6) + 7) + 1) or 2) + 3);
  WriteLn(R);
end.
