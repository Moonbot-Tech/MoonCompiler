program no_repeated_bounds_check;
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
  I, S: Integer;
begin
  S := 0;
  for I := 0 to 7 do
  begin
    A[I] := I;
    S := S + A[I];
  end;
  WriteLn(S);
end.
