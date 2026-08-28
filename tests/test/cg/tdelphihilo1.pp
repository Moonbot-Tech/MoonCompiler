{ %OPT=-O3 }
program tdelphihilo1;

{$mode delphi}

var
  RuntimeZero: UInt64 = 0;
  W: Word;
  I: Integer;
  C: Cardinal;
  I64: Int64;
  U64: UInt64;

function Pick(Value: Byte): Integer; overload;
begin
  Result := 1;
end;

function Pick(Value: Word): Integer; overload;
begin
  Result := 2;
end;

begin
  W := Word($1234 xor RuntimeZero);
  I := Integer($12345678 xor RuntimeZero);
  C := Cardinal($89ABCDEF xor RuntimeZero);
  I64 := Int64($0123456789ABCDEF xor RuntimeZero);
  U64 := UInt64($FEDCBA9876543210 xor RuntimeZero);

  If Hi(W) <> $12 then Halt(1);
  If Lo(W) <> $34 then Halt(2);
  If Hi(I) <> $56 then Halt(3);
  If Lo(I) <> $78 then Halt(4);
  If Hi(C) <> $CD then Halt(5);
  If Lo(C) <> $EF then Halt(6);
  If Hi(I64) <> $CD then Halt(7);
  If Lo(I64) <> $EF then Halt(8);
  If Hi(U64) <> $32 then Halt(9);
  If Lo(U64) <> $10 then Halt(10);

  If Hi(Integer($12345678)) <> $56 then Halt(11);
  If Lo(UInt64($FEDCBA9876543210)) <> $10 then Halt(12);
  If SizeOf(Hi(U64)) <> 2 then Halt(13);
  If SizeOf(Lo(I)) <> 2 then Halt(14);
  If SizeOf(Hi(UInt64($FEDCBA9876543210))) <> 1 then Halt(15);
  If Pick(Hi(U64)) <> 2 then Halt(16);
  If Pick(Lo(UInt64($FEDCBA9876543210))) <> 1 then Halt(17);
end.
