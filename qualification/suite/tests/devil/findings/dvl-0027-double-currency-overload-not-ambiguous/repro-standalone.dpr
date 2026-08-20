program cat1;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

const
  Part = 'a';
  Whole = 'a' + 'b';

function Take(const V: AnsiString): Integer; overload;
begin
  Result := 1;
end;

function Take(const V: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

begin
  WriteLn('plain       -> ', Take('ab'));
  WriteLn('concat      -> ', Take('a' + 'b'));
  WriteLn('const parts -> ', Take(Part + 'b'));
  WriteLn('named const -> ', Take(Whole));
  WriteLn('escaped     -> ', Take(#$0061#$0062));
  WriteLn('esc+quoted  -> ', Take(#$0061 + 'b'));
end.
