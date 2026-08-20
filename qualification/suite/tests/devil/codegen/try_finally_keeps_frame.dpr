program try_finally_keeps_frame;
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
  S: AnsiString;
  I, R: Integer;
begin
  R := 0;
  for I := 0 to 9 do
  begin
    S := AnsiString(IntToStr(I));
    try
      R := R + Length(S);
    finally
      S := '';
    end;
  end;
  WriteLn(R);
end.
