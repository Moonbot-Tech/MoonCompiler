{ %OPT=-O3 }
program tautoinline4;

{$mode delphi}

type
  TByteArray = array[Byte] of Byte;
  THugeIntegerArray = array[0..MaxInt div SizeOf(Integer) - 1] of Integer;

procedure SetBit(var Bits; Index: PtrInt);
begin
  THugeIntegerArray(Bits)[Index shr 5] :=
    THugeIntegerArray(Bits)[Index shr 5] or (1 shl (Index and 31));
end;

var
  Bits: TByteArray;
begin
  FillChar(Bits,SizeOf(Bits),0);
  SetBit(Bits,1);
  if Bits[0]<>2 then
    Halt(1);
end.
