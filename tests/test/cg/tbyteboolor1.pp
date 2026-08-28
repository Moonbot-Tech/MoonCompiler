{ %OPT=-O3 }
program tbyteboolor1;

{$mode delphi}

var
  ByteLeft,
  ByteRight,
  ByteAssigned: ByteBool;
  WordLeft,
  WordRight,
  WordAssigned: WordBool;
  LongLeft,
  LongRight,
  LongAssigned: LongBool;
  ByteRaw,
  WordRaw,
  LongRaw: QWord;
  RuntimeZero: QWord = 0;

function Opaque(Value: QWord): QWord;
begin
  Result := Value xor RuntimeZero;
end;

begin
  Byte(ByteLeft) := Byte(Opaque($C8));
  Byte(ByteRight) := Byte(Opaque($37));
  Word(WordLeft) := Word(Opaque($C800));
  Word(WordRight) := Word(Opaque($3700));
  LongInt(LongLeft) := LongInt(Opaque($12340000));
  LongInt(LongRight) := LongInt(Opaque($00005678));

  If SizeOf(ByteLeft or ByteRight) <> 1 then Halt(1);
  If SizeOf(WordLeft or WordRight) <> 1 then Halt(2);
  If SizeOf(LongLeft or LongRight) <> 1 then Halt(3);
  If Byte(ByteLeft or ByteRight) <> 1 then Halt(4);
  If Word(WordLeft or WordRight) <> 1 then Halt(5);
  If LongInt(LongLeft or LongRight) <> 1 then Halt(6);
  If Byte(ByteLeft and ByteRight) <> 1 then Halt(7);
  If Word(WordLeft and WordRight) <> 1 then Halt(8);
  If LongInt(LongLeft and LongRight) <> 1 then Halt(9);
  If Byte(ByteLeft xor ByteRight) <> 0 then Halt(10);
  If Word(WordLeft xor WordRight) <> 0 then Halt(11);
  If LongInt(LongLeft xor LongRight) <> 0 then Halt(12);

  ByteAssigned := ByteLeft or ByteRight;
  WordAssigned := WordLeft or WordRight;
  LongAssigned := LongLeft or LongRight;
  ByteRaw := Byte(ByteAssigned);
  WordRaw := Word(WordAssigned);
  LongRaw := Cardinal(LongAssigned);
  If ByteRaw <> $FF then Halt(13);
  If WordRaw <> $FFFF then Halt(14);
  If LongRaw <> $FFFFFFFF then Halt(15);
end.
