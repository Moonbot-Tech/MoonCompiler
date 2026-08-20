program small_loop_unrolled;
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
  A: array[0..3] of Integer;
  I, S: Integer;
begin
  for I := 0 to 3 do
    A[I] := I;
  S := 0;
  for I := 0 to 3 do
    S := S + A[I];
  WriteLn(S);
end.
