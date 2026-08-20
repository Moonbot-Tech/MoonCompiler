program bounds_check_present_when_on;
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
{$R+}
var
  A: array[0..7] of Integer;
  I: Integer;
begin
  I := Length(ParamStr(0));
  A[I] := 1;
  WriteLn(A[0]);
end.
