{ %OPT=-O3 }
program tfpchilo1;

{$mode objfpc}

var
  RuntimeZero: QWord = 0;
  W: Word;
  L: LongWord;
  Q: QWord;

begin
  W := Word($D8AF xor RuntimeZero);
  L := LongWord($1234ABCD xor RuntimeZero);
  Q := QWord($12345678ABCDEF90 xor RuntimeZero);

  If Lo(W) <> $AF then Halt(1);
  If Hi(W) <> $D8 then Halt(2);
  If Lo(W) shr 4 <> $0A then Halt(3);
  If Hi(W) shr 4 <> $0D then Halt(4);
  If Lo(L) <> $ABCD then Halt(5);
  If Hi(L) <> $1234 then Halt(6);
  If Lo(Q) <> $ABCDEF90 then Halt(7);
  If Hi(Q) <> $12345678 then Halt(8);

  If SizeOf(Lo(W)) <> 1 then Halt(9);
  If SizeOf(Hi(W)) <> 1 then Halt(10);
  If SizeOf(Lo(L)) <> 2 then Halt(11);
  If SizeOf(Hi(L)) <> 2 then Halt(12);
  If SizeOf(Lo(Q)) <> 4 then Halt(13);
  If SizeOf(Hi(Q)) <> 4 then Halt(14);
end.
