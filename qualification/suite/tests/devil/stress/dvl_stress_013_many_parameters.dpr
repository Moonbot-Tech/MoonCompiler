program dvl_stress_013_many_parameters;
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
function Wide(A0: Int64; A1: Int64; A2: Int64; A3: Int64; A4: Int64; A5: Int64; A6: Int64; A7: Int64; A8: Int64; A9: Int64; A10: Int64; A11: Int64; A12: Int64; A13: Int64; A14: Int64; A15: Int64; A16: Int64; A17: Int64; A18: Int64; A19: Int64; A20: Int64; A21: Int64; A22: Int64; A23: Int64; A24: Int64): Int64;
begin
  Result := A0 + A1 + A2 + A3 + A4 + A5 + A6 + A7 + A8 + A9 + A10 + A11 + A12 + A13 + A14 + A15 + A16 + A17 + A18 + A19 + A20 + A21 + A22 + A23 + A24;
end;

function WideStd(A0: Int64; A1: Int64; A2: Int64; A3: Int64; A4: Int64; A5: Int64; A6: Int64; A7: Int64; A8: Int64; A9: Int64; A10: Int64; A11: Int64; A12: Int64; A13: Int64; A14: Int64; A15: Int64; A16: Int64; A17: Int64; A18: Int64; A19: Int64; A20: Int64; A21: Int64; A22: Int64; A23: Int64; A24: Int64): Int64; stdcall;
begin
  Result := A0 + A1 + A2 + A3 + A4 + A5 + A6 + A7 + A8 + A9 + A10 + A11 + A12 + A13 + A14 + A15 + A16 + A17 + A18 + A19 + A20 + A21 + A22 + A23 + A24;
end;

var
  Total: Int64;
begin
  Total := Wide(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25);
  Total := Total + WideStd(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25);
  WriteLn(Total);
end.
