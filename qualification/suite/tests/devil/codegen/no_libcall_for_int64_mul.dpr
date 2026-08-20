program no_libcall_for_int64_mul;
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
  A, B, R: Int64;
begin
  A := StrToInt64(ParamStr(0) + '1');
  B := 7;
  R := A * B;
  WriteLn(R);
end.
