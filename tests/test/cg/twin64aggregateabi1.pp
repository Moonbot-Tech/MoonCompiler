{ %CPU=x86_64 }
program twin64aggregateabi1;

{$mode unleashed}

{ Delphi-compatible modes pass Win64 small const aggregates in registers. }

{$ifdef WIN64}
{$asmmode intel}

type
  TArray1 = array[0..0] of Byte;
  TArray2 = array[0..1] of Byte;
  TArray4 = array[0..3] of Byte;
  TArray8 = array[0..7] of Byte;
  TArray16 = array[0..15] of Byte;
  PArray16 = ^TArray16;
  TRecord8 = record
    Value: QWord;
  end;
  TRecord16 = record
    First: QWord;
    Second: QWord;
  end;

function RawArray1(const Value: TArray1): QWord; assembler; nostackframe;
asm
  MOVZX RAX,CL
end;

function RawArray2(const Value: TArray2): QWord; assembler; nostackframe;
asm
  MOVZX RAX,CX
end;

function RawArray4(const Value: TArray4): QWord; assembler; nostackframe;
asm
  MOV EAX,ECX
end;

function RawArray8(const Value: TArray8): QWord; assembler; nostackframe;
asm
  MOV RAX,RCX
end;

function RawArray16(const Value: TArray16): QWord; assembler; nostackframe;
asm
  MOV RAX,[RCX]
end;

function RawRecord8(const Value: TRecord8): QWord; assembler; nostackframe;
asm
  MOV RAX,RCX
end;

function RawRecord16(const Value: TRecord16): QWord; assembler; nostackframe;
asm
  MOV RAX,[RCX]
end;

function PascalArray8(Value: TArray8): QWord; noinline;
begin
  Move(Value[0],Result,SizeOf(Result));
end;

function RawCallPascalArray8(Value: QWord): QWord; assembler; nostackframe;
asm
  SUB RSP,40
  CALL PascalArray8
  ADD RSP,40
end;

function MakeArray1: TArray1; noinline;
begin
  Result[0]:=$11;
end;

function MakeArray2: TArray2; noinline;
begin
  Result[0]:=$11;
  Result[1]:=$22;
end;

function MakeArray4: TArray4; noinline;
begin
  Result[0]:=$11;
  Result[1]:=$22;
  Result[2]:=$33;
  Result[3]:=$44;
end;

function MakeArray8: TArray8; noinline;
begin
  Result[0]:=$11;
  Result[1]:=$22;
  Result[2]:=$33;
  Result[3]:=$44;
  Result[4]:=$55;
  Result[5]:=$66;
  Result[6]:=$77;
  Result[7]:=$88;
end;

function RawCallMakeArray1: QWord; assembler; nostackframe;
asm
  SUB RSP,40
  CALL MakeArray1
  ADD RSP,40
end;

function RawCallMakeArray2: QWord; assembler; nostackframe;
asm
  SUB RSP,40
  CALL MakeArray2
  ADD RSP,40
end;

function RawCallMakeArray4: QWord; assembler; nostackframe;
asm
  SUB RSP,40
  CALL MakeArray4
  ADD RSP,40
end;

function RawCallMakeArray8: QWord; assembler; nostackframe;
asm
  SUB RSP,40
  CALL MakeArray8
  ADD RSP,40
end;

var
  A1: TArray1;
  A2: TArray2;
  A4: TArray4;
  A8: TArray8;
  A16: TArray16;
  R8: TRecord8;
  R16: TRecord16;
  Bits: QWord;
begin
  Bits:=$8877665544332211;
  Move(Bits,A1,SizeOf(A1));
  Move(Bits,A2,SizeOf(A2));
  Move(Bits,A4,SizeOf(A4));
  Move(Bits,A8,SizeOf(A8));
  FillChar(A16,SizeOf(A16),0);
  Move(Bits,A16,SizeOf(Bits));
  R8.Value:=Bits;
  R16.First:=Bits;
  R16.Second:=0;

  if RawArray1(A1)<>$11 then Halt(1);
  if RawArray2(A2)<>$2211 then Halt(2);
  if RawArray4(A4)<>$44332211 then Halt(3);
  if RawArray8(A8)<>Bits then Halt(4);
  if RawArray16(A16)<>Bits then Halt(5);
  if RawRecord8(R8)<>Bits then Halt(6);
  if RawRecord16(R16)<>Bits then Halt(7);
  if RawCallPascalArray8(Bits)<>Bits then Halt(8);
  if (RawCallMakeArray1 and $ff)<>$11 then Halt(9);
  if (RawCallMakeArray2 and $ffff)<>$2211 then Halt(10);
  if (RawCallMakeArray4 and $ffffffff)<>$44332211 then Halt(11);
  if RawCallMakeArray8<>Bits then Halt(12);
end.
{$else WIN64}
begin
end.
{$endif WIN64}
