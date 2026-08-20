program shift_is_shift_not_div;
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
  A, R: Integer;
begin
  A := Length(ParamStr(0));
  R := A div 8;
  WriteLn(R);
end.
