program managed_local_finalized_once;
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
procedure Work;
var
  S: AnsiString;
begin
  S := AnsiString(IntToStr(1));
  if Length(S) > 100 then
    Exit;
  S := S + 'x';
end;

begin
  Work;
  WriteLn('done');
end.
