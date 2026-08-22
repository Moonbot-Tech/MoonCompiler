program variant_int_carrier_semantic;

{ dvl-0015: Delphi (DCC64 36.0) picks the Variant carrier type for an
  integer constant by its value - the smallest unsigned type for a
  non-negative value ($11/$12/$13/$14), the smallest signed one otherwise
  ($10/$02/$03/$14).  The rule covers every value-shaped constant form:
  bare literals, parenthesised literals, untyped consts and folded
  constant expressions (even ones containing typed casts, mirroring the
  DCC folder).  A directly cast constant, typed consts and variables keep
  the carrier of their formal type instead. }

{$APPTYPE CONSOLE}

{$ifdef FPC}
{$mode delphi}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif FPC}
  SysUtils, Variants;

const
  CPlain = 5;
  CBig = 70000;
  CTypedInt: Integer = 5;
  CTypedByte: Byte = 5;

procedure Check(const Name: string; const V: Variant; Expected: Word);
begin
  If VarType(V) <> Expected then
    raise Exception.CreateFmt('%s: VarType=$%x expected $%x',
      [Name, VarType(V), Expected]);
end;

procedure CheckLiterals;
var
  V: Variant;
begin
  V := 0;                    Check('lit 0', V, varByte);
  V := 127;                  Check('lit 127', V, varByte);
  V := 128;                  Check('lit 128', V, varByte);
  V := 255;                  Check('lit 255', V, varByte);
  V := 256;                  Check('lit 256', V, varWord);
  V := 32767;                Check('lit 32767', V, varWord);
  V := 32768;                Check('lit 32768', V, varWord);
  V := 65535;                Check('lit 65535', V, varWord);
  V := 65536;                Check('lit 65536', V, varLongWord);
  V := 2147483647;           Check('lit 2^31-1', V, varLongWord);
  V := 2147483648;           Check('lit 2^31', V, varLongWord);
  V := 4294967295;           Check('lit 2^32-1', V, varLongWord);
  V := 4294967296;           Check('lit 2^32', V, varInt64);
  V := 9223372036854775807;  Check('lit 2^63-1', V, varInt64);
  V := -1;                   Check('lit -1', V, varShortInt);
  V := -128;                 Check('lit -128', V, varShortInt);
  V := -129;                 Check('lit -129', V, varSmallInt);
  V := -32768;               Check('lit -32768', V, varSmallInt);
  V := -32769;               Check('lit -32769', V, varInteger);
  V := -2147483648;          Check('lit -2^31', V, varInteger);
  V := -2147483649;          Check('lit -2^31-1', V, varInt64);
  V := -9223372036854775808; Check('lit -2^63', V, varInt64);
end;

procedure CheckValueShapedForms;
var
  V: Variant;
begin
  V := (5);                  Check('paren 5', V, varByte);
  V := 5 + 0;                Check('expr 5+0', V, varByte);
  V := 2 + 3;                Check('expr 2+3', V, varByte);
  V := 5 * 100;              Check('expr 5*100', V, varWord);
  V := -(-5);                Check('expr -(-5)', V, varByte);
  V := ShortInt(5) + 0;      Check('expr ShortInt(5)+0', V, varByte);
  V := Integer(2) + 3;       Check('expr Integer(2)+3', V, varByte);
  V := SizeOf(Int64) * 8;    Check('expr SizeOf*8', V, varByte);
  V := CPlain;               Check('untyped const 5', V, varByte);
  V := CBig;                 Check('untyped const 70000', V, varLongWord);
end;

procedure CheckFormalCasts;
var
  V: Variant;
begin
  { a typed cast keeps the carrier of its formal type, like DCC }
  V := Byte(5);              Check('cast Byte(5)', V, varByte);
  V := Word(5);              Check('cast Word(5)', V, varWord);
  V := Cardinal(5);          Check('cast Cardinal(5)', V, varLongWord);
  V := Integer(5);           Check('cast Integer(5)', V, varInteger);
  V := Int64(5);             Check('cast Int64(5)', V, varInt64);
  V := UInt64(5);            Check('cast UInt64(5)', V, varUInt64);

  { even when the cast type coincides with the minimal def of the value }
  V := ShortInt(5);          Check('cast ShortInt(5)', V, varShortInt);
  V := SmallInt(300);        Check('cast SmallInt(300)', V, varSmallInt);
  V := Integer(70000);       Check('cast Integer(70000)', V, varInteger);
end;

procedure CheckDeclaredTypesWin;
var
  V: Variant;
  B: Byte;
  SI: ShortInt;
  W: Word;
  SM: SmallInt;
  C: Cardinal;
  I: Integer;
  I64: Int64;
  U64: UInt64;
begin
  V := CTypedInt;            Check('typed const Integer', V, varInteger);
  V := CTypedByte;           Check('typed const Byte', V, varByte);
  B := 5;   V := B;          Check('Byte var', V, varByte);
  SI := 5;  V := SI;         Check('ShortInt var', V, varShortInt);
  W := 5;   V := W;          Check('Word var', V, varWord);
  SM := 5;  V := SM;         Check('SmallInt var', V, varSmallInt);
  C := 5;   V := C;          Check('Cardinal var', V, varLongWord);
  I := 5;   V := I;          Check('Integer var', V, varInteger);
  I64 := 5; V := I64;        Check('Int64 var', V, varInt64);
  U64 := 5; V := U64;        Check('UInt64 var', V, varUInt64);
end;

procedure CheckRoundTrip;
var
  V: Variant;
begin
  { the carrier must not distort the value at the range edges }
  V := 255;
  If Integer(V) <> 255 then
    raise Exception.Create('255 round trip');
  V := 4294967295;
  If Int64(V) <> 4294967295 then
    raise Exception.Create('2^32-1 round trip');
  V := -1;
  If Integer(V) <> -1 then
    raise Exception.Create('-1 round trip');
end;

begin
  try
    CheckLiterals;
    CheckValueShapedForms;
    CheckFormalCasts;
    CheckDeclaredTypesWin;
    CheckRoundTrip;
    WriteLn('VARIANT_INT_CARRIER_OK');
  except
    on E: Exception do begin
      WriteLn('VARIANT_INT_CARRIER_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
