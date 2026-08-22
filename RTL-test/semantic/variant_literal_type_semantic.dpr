program variant_literal_type_semantic;

{$APPTYPE CONSOLE}

{$ifdef FPC}
{$mode delphiunicode}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  {$endif FPC}
  SysUtils,
  Variants;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
  begin
    WriteLn('VARIANT_LITERAL_TYPE_SEMANTIC_FAIL ', MessageText);
    Halt(1);
  end;
end;

var
  V, W: Variant;
begin
  { a non-negative literal carries the smallest unsigned Variant type
    (dvl-0015, DCC64 measured) }
  V := 897;
  Check(VarType(V) = varWord, 'untyped bounded literal');
  Check(Integer(V) = 897, 'untyped literal value');

  V := Integer(897);
  Check(VarType(V) = varInteger, 'explicit Integer source');
  Check(Integer(V) = 897, 'explicit Integer value');

  V := SmallInt(897);
  Check(VarType(V) = varSmallInt, 'explicit SmallInt source');
  W := V + Integer(1);
  Check(Integer(W) = 898, 'packed ordinal arithmetic');

  V := Null;
  Check(VarIsNull(V), 'null');
  V := Unassigned;
  Check(VarIsEmpty(V), 'unassigned');

  V := 'managed';
  W := V;
  V := Unassigned;
  Check(string(W) = 'managed', 'managed copy lifetime');
  W := Unassigned;

  WriteLn('VARIANT_LITERAL_TYPE_SEMANTIC_OK');
end.
