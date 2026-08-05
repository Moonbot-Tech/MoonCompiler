{ %OPT=-O3 }
program tfloatminselect1;

{$mode delphi}

uses
  Math;

function DoubleBits(Value: Double): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

var
  PlusZero: Double;
  MinusZero: Double;
  NanValue: Double;
  Chosen: Double;
  Bits: UInt64;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  PlusZero := 0.0;
  Bits := UInt64($8000000000000000);
  Move(Bits, MinusZero, SizeOf(MinusZero));
  Bits := UInt64($7FF8000000000001);
  Move(Bits, NanValue, SizeOf(NanValue));

  If MinusZero <= PlusZero then
    Chosen := MinusZero
  else
    Chosen := PlusZero;
  If DoubleBits(Chosen) <> UInt64($8000000000000000) then Halt(1);

  If MinusZero < PlusZero then
    Chosen := MinusZero
  else
    Chosen := PlusZero;
  If DoubleBits(Chosen) <> 0 then Halt(2);

  If PlusZero >= MinusZero then
    Chosen := PlusZero
  else
    Chosen := MinusZero;
  If DoubleBits(Chosen) <> 0 then Halt(3);

  If PlusZero > MinusZero then
    Chosen := PlusZero
  else
    Chosen := MinusZero;
  If DoubleBits(Chosen) <> UInt64($8000000000000000) then Halt(4);

  If NanValue <= PlusZero then
    Chosen := NanValue
  else
    Chosen := PlusZero;
  If DoubleBits(Chosen) <> 0 then Halt(5);
end.
