program seh_loop_keeps_frame;
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
  for I := 1 to 10 do
  begin
    try
      S := S + I;
    finally
      S := S + 1;
    end;
  end;
  WriteLn(S);
end.
