program empty_loop_removed;
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
  I, S: Integer;
begin
  S := 0;
  for I := 0 to 999 do
    ;
  WriteLn(S);
end.
