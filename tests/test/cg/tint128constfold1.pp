{ %CPU=x86_64 }
program tint128constfold1;

{$mode delphi}

uses
  TypInfo,
  uint128constfold1;

var
  Failures: Integer;

procedure CheckType(const Actual, Expected: ShortString; Code: Byte);
begin
  if Actual <> Expected then
    begin
      WriteLn(Code, ': ', Actual, ' <> ', Expected);
      Inc(Failures);
    end;
end;

function DivideUInt128(A, B: UInt128): UInt128; noinline;
begin
  Result := A div B;
end;

function ModuloUInt128(A, B: UInt128): UInt128; noinline;
begin
  Result := A mod B;
end;

function DivideInt128(A, B: Int128): Int128; noinline;
begin
  Result := A div B;
end;

function ModuloInt128(A, B: Int128): Int128; noinline;
begin
  Result := A mod B;
end;

var
  U: UInt128;
  I: Int128;

begin
  CheckType(PTypeInfo(TypeInfo(UInt128Direct))^.Name, 'UInt128', 1);
  CheckType(PTypeInfo(TypeInfo(UInt128Product))^.Name, 'UInt128', 2);
  CheckType(PTypeInfo(TypeInfo(UInt128Sum))^.Name, 'UInt128', 3);
  CheckType(PTypeInfo(TypeInfo(UInt128Difference))^.Name, 'UInt128', 4);
  CheckType(PTypeInfo(TypeInfo(UInt128Bitwise))^.Name, 'UInt128', 5);
  CheckType(PTypeInfo(TypeInfo(UInt128Division))^.Name, 'UInt128', 6);
  CheckType(PTypeInfo(TypeInfo(UInt128Modulo))^.Name, 'UInt128', 7);
  CheckType(PTypeInfo(TypeInfo(UInt128Shift))^.Name, 'UInt128', 8);
  CheckType(PTypeInfo(TypeInfo(UInt128TopBit))^.Name, 'UInt128', 9);

  CheckType(PTypeInfo(TypeInfo(Int128Direct))^.Name, 'Int128', 10);
  CheckType(PTypeInfo(TypeInfo(Int128Product))^.Name, 'Int128', 11);
  CheckType(PTypeInfo(TypeInfo(Int128Sum))^.Name, 'Int128', 12);
  CheckType(PTypeInfo(TypeInfo(Int128Difference))^.Name, 'Int128', 13);
  CheckType(PTypeInfo(TypeInfo(Int128Division))^.Name, 'Int128', 14);
  CheckType(PTypeInfo(TypeInfo(Int128Modulo))^.Name, 'Int128', 15);
  CheckType(PTypeInfo(TypeInfo(Int128Shift))^.Name, 'Int128', 16);

  CheckType(PTypeInfo(TypeInfo(UntypedProduct))^.Name, 'ShortInt', 17);

  CheckType(PTypeInfo(TypeInfo(UInt128OperandNegation))^.Name, 'Int128', 32);
  CheckType(PTypeInfo(TypeInfo(Int128Negation))^.Name, 'Int128', 33);

  U := UInt128Product;
  if U <> 6 then
    begin
      WriteLn('18: incorrect UInt128 product');
      Inc(Failures);
    end;
  U := UInt128Bitwise;
  if U <> 5 then
    begin
      WriteLn('19: incorrect UInt128 xor');
      Inc(Failures);
    end;
  U := UInt128Division;
  if U <> 5 then
    begin
      WriteLn('20: incorrect UInt128 division');
      Inc(Failures);
    end;
  U := UInt128Modulo;
  if U <> 1 then
    begin
      WriteLn('21: incorrect UInt128 modulo');
      Inc(Failures);
    end;
  U := UInt128Shift;
  if U <> (UInt128(1) shl 100) then
    begin
      WriteLn('22: incorrect UInt128 shift');
      Inc(Failures);
    end;
  U := UInt128TopBit;
  if (U shr 127) <> 1 then
    begin
      WriteLn('23: incorrect UInt128 top bit');
      Inc(Failures);
    end;

  I := Int128Product;
  if I <> -6 then
    begin
      WriteLn('24: incorrect Int128 product');
      Inc(Failures);
    end;
  I := Int128Division;
  if I <> -5 then
    begin
      WriteLn('25: incorrect Int128 division');
      Inc(Failures);
    end;
  I := Int128Modulo;
  if I <> -1 then
    begin
      WriteLn('26: incorrect Int128 modulo');
      Inc(Failures);
    end;
  I := Int128Shift;
  if I <> (Int128(1) shl 100) then
    begin
      WriteLn('27: incorrect Int128 shift');
      Inc(Failures);
    end;

  if DivideUInt128(21, 4) <> 5 then
    begin
      WriteLn('28: incorrect runtime UInt128 division');
      Inc(Failures);
    end;
  if ModuloUInt128(21, 4) <> 1 then
    begin
      WriteLn('29: incorrect runtime UInt128 modulo');
      Inc(Failures);
    end;
  if DivideInt128(-21, 4) <> -5 then
    begin
      WriteLn('30: incorrect runtime Int128 division');
      Inc(Failures);
    end;
  if ModuloInt128(-21, 4) <> -1 then
    begin
      WriteLn('31: incorrect runtime Int128 modulo');
      Inc(Failures);
    end;

  I := UInt128OperandNegation;
  if I <> -6 then
    begin
      WriteLn('34: incorrect negated UInt128 operand');
      Inc(Failures);
    end;
  I := Int128Negation;
  if I <> -6 then
    begin
      WriteLn('35: incorrect Int128 negation');
      Inc(Failures);
    end;

  if Failures <> 0 then
    Halt(1);
end.
