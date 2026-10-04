program unicode_equality_codegen;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils;

function EqualStrings(const Left, Right: UnicodeString): Boolean;
  noinline;
begin
  Result:=Left=Right;
end;

function DifferentStrings(const Left, Right: UnicodeString): Boolean;
  noinline;
begin
  Result:=Left<>Right;
end;

var
  Left, Right: UnicodeString;
begin
  Left:=StringOfChar('x',64);
  Right:=Copy(Left,1,Length(Left));
  UniqueString(Right);
  if not EqualStrings(Left,Right) then
    Halt(1);
  Right[Length(Right)]:='y';
  if not DifferentStrings(Left,Right) then
    Halt(2);
  WriteLn('UNICODE_EQUALITY_CODEGEN_PASS');
end.
