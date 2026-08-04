{ %CPU=x86_64 }
{ %OPT=-O3 }
program tnarrowimm1;

{$mode delphi}
{$Q-}{$R-}

type
  TOverlap = packed record
    case Byte of
      0: (L: LongWord);
      1: (W: Word);
      2: (B: Byte);
  end;

procedure SubWordMovx(var W: Word); noinline;
begin
  W := Word(UInt32(W) - $10000);
end;

procedure SubByteMovx(var B: Byte); noinline;
begin
  B := Byte(UInt32(B) - $100);
end;

procedure SubWordMov(var V: TOverlap); noinline;
begin
  V.W := Word(V.L - $10000);
end;

procedure SubByteMov(var V: TOverlap); noinline;
begin
  V.B := Byte(V.L - $100);
end;

procedure AddWord(var W: Word); noinline;
begin
  W := Word(UInt32(W) + $10001);
end;

procedure XorByte(var B: Byte); noinline;
begin
  B := Byte(UInt32(B) xor $101);
end;

procedure SubWordMax(var W: Word); noinline;
begin
  W := Word(UInt32(W) - $1ffff);
end;

procedure SubByteMax(var B: Byte); noinline;
begin
  B := Byte(UInt32(B) - $1ff);
end;

procedure SubLongEqualWidth(var V: LongWord); noinline;
begin
  V := V - $10000;
end;

procedure SubWordRegister(var W: Word; Delta: UInt32); noinline;
begin
  W := Word(UInt32(W) - Delta);
end;

procedure SubByteRegister(var B: Byte; Delta: UInt32); noinline;
begin
  B := Byte(UInt32(B) - Delta);
end;

var
  W: Word;
  B: Byte;
  V: LongWord;
  O: TOverlap;

begin
  W := $2345;
  SubWordMovx(W);
  if W <> $2345 then
    Halt(1);

  B := $67;
  SubByteMovx(B);
  if B <> $67 then
    Halt(2);

  O.L := $abcd2345;
  SubWordMov(O);
  if O.L <> $abcd2345 then
    Halt(3);

  O.L := $abcdef67;
  SubByteMov(O);
  if O.L <> $abcdef67 then
    Halt(4);

  W := $2345;
  AddWord(W);
  if W <> $2346 then
    Halt(5);

  B := $66;
  XorByte(B);
  if B <> $67 then
    Halt(6);

  W := $2345;
  SubWordMax(W);
  if W <> $2346 then
    Halt(7);

  B := $66;
  SubByteMax(B);
  if B <> $67 then
    Halt(8);

  V := $12345678;
  SubLongEqualWidth(V);
  if V <> $12335678 then
    Halt(9);

  W := 5;
  SubWordRegister(W, $10001);
  if W <> 4 then
    Halt(10);

  B := 5;
  SubByteRegister(B, $101);
  if B <> 4 then
    Halt(11);
end.
