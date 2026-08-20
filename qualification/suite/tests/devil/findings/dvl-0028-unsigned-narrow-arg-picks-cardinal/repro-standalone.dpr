program sign;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

function Pick(const V: Integer): Integer; overload;
begin
  Result := 1;
end;

function Pick(const V: Cardinal): Integer; overload;
begin
  Result := 2;
end;

var
  B: Byte;
  W: Word;
  S: SmallInt;
begin
  B := 7; W := 7; S := 7;
  WriteLn('byte     -> ', Pick(B));
  WriteLn('word     -> ', Pick(W));
  WriteLn('smallint -> ', Pick(S));
end.
