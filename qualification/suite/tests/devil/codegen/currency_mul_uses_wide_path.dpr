program currency_mul_uses_wide_path;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
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
  A, B, R: Currency;
begin
  A := Length(ParamStr(0));
  B := 2.5;
  R := A * B;
  WriteLn(R:0:4);
end.
