program lab_003_untyped_var_huge_array_o3;

{$mode delphi}

type
  TByteToByte = array[byte] of byte;
  TIntegerArray = array[0 .. MaxInt div SizeOf(integer) - 1] of integer;

procedure SetBit(var Bits; Index: PtrInt);
begin
  TIntegerArray(Bits)[Index shr 5] :=
    TIntegerArray(Bits)[Index shr 5] or (1 shl (Index and 31));
end;

var
  Bits: TByteToByte;
  Index: integer;

begin
  FillChar(Bits, SizeOf(Bits), 0);
  Index := 1;
  SetBit(Bits, Index);
  if Bits[0] <> 2 then
    Halt(1);
end.
