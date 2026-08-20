program string_concat_not_quadratic;
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
  I: Integer;
begin
  S := '';
  for I := 1 to 4 do
    S := S + 'ab';
  WriteLn(Length(S));
end.
