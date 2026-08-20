program inline_is_inlined;
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
function Add3(X: Integer): Integer; inline;
begin
  Result := X + 3;
end;

var
  I, S: Integer;
begin
  S := 0;
  for I := 0 to 9 do
    S := S + Add3(I);
  WriteLn(S);
end.
