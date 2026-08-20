program chr4;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$codepage utf8}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

function Code(const V: AnsiChar): Integer; overload;
begin
  Result := 1000 + Ord(V);
end;

function Code(const V: Char): Integer; overload;
begin
  Result := 2000 + Ord(V);
end;

begin
  WriteLn('a -> ', Code('a'));
  WriteLn('7f -> ', Code(''));
  WriteLn('ff -> ', Code('ÿ'));
  WriteLn('100 -> ', Code('Ā'));
  WriteLn('44f -> ', Code('я'));
end.
