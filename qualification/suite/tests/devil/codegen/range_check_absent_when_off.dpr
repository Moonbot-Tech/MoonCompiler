program range_check_absent_when_off;
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
  A: array[0..7] of Integer;
  I: Integer;
begin
  for I := 0 to 7 do
    A[I] := I;
  WriteLn(A[3]);
end.
