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
  Variants,
  variant_literal_type_unit;

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

  { Delphi uses Currency for an untyped decimal literal without an exponent.
    The provenance survives +/- folding and a PPU, but not multiplication,
    division, an exponent, or an explicit floating-point type. }
  V := 1.5;
  Check(VarType(V) = varCurrency, 'plain real literal carrier');
  V := 1.5e0;
  Check(VarType(V) = varDouble, 'exponent real literal carrier');
  V := 1.0 + 0.5;
  Check(VarType(V) = varCurrency, 'plain addition carrier');
  V := 2.0 - 0.5;
  Check(VarType(V) = varCurrency, 'plain subtraction carrier');
  V := 3.0 * 0.5;
  Check(VarType(V) = varDouble, 'plain product carrier');
  V := 3.0 / 2.0;
  Check(VarType(V) = varDouble, 'plain division carrier');
  V := 1.0e0 + 0.5;
  Check(VarType(V) = varDouble, 'mixed exponent carrier');
  V := -1.5;
  Check(VarType(V) = varCurrency, 'negative plain carrier');
  V := Double(1.5);
  Check(VarType(V) = varDouble, 'explicit Double carrier');
  V := PpuPlainReal;
  Check(VarType(V) = varCurrency, 'PPU plain carrier');
  V := PpuExponentReal;
  Check(VarType(V) = varDouble, 'PPU exponent carrier');
  V := PpuFoldedReal;
  Check(VarType(V) = varCurrency, 'PPU folded carrier');
  V := PpuTypedDouble;
  Check(VarType(V) = varDouble, 'PPU typed Double carrier');

  V := 'managed';
  W := V;
  V := Unassigned;
  Check(string(W) = 'managed', 'managed copy lifetime');
  W := Unassigned;

  WriteLn('VARIANT_LITERAL_TYPE_SEMANTIC_OK');
end.
