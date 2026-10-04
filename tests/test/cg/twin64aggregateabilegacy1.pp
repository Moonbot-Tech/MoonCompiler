{ %CPU=x86_64 }
program twin64aggregateabilegacy1;

{$mode objfpc}

{$ifdef WIN64}
{$asmmode intel}

type
  TArray8 = array[0..7] of Byte;
  TRecord8 = record
    Value: QWord;
  end;

function RawConstArray8(const Value: TArray8): QWord; assembler; nostackframe;
asm
  MOV RAX,[RCX]
end;

function RawConstRecord8(const Value: TRecord8): QWord; assembler; nostackframe;
asm
  MOV RAX,[RCX]
end;

function RawValueRecord8(Value: TRecord8): QWord; assembler; nostackframe;
asm
  MOV RAX,RCX
end;

var
  A8: TArray8;
  R8: TRecord8;
  Bits: QWord;
begin
  Bits:=$8877665544332211;
  Move(Bits,A8,SizeOf(A8));
  R8.Value:=Bits;

  if RawConstArray8(A8)<>Bits then
    Halt(1);
  if RawConstRecord8(R8)<>Bits then
    Halt(2);
  if RawValueRecord8(R8)<>Bits then
    Halt(3);
end.
{$else WIN64}
begin
end.
{$endif WIN64}
