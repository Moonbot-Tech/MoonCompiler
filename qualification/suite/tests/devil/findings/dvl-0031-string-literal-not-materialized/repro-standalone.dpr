program rc5;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

function Fresh: UnicodeString;
begin
  Result := 'poke-me';
end;

var
  U: UnicodeString;
  P: PChar;
begin
  U := 'poke-me';
  P := PChar(U);
  try
    P[0] := 'X';
    WriteLn('poked   = ', U);
    WriteLn('another = ', Fresh);
  except
    on E: Exception do
      WriteLn('poke raised ', E.ClassName);
  end;
end.
