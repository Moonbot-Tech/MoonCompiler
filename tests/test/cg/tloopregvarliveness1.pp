{ %CPU=x86_64 }
{ %OPT=-O3 }
program tloopregvarliveness1;

{$mode delphi}
{$R-}{$Q-}
{$asmmode intel}

type
  TByteLookup = array[0..255] of Byte;
  PByteLookup = ^TByteLookup;
  TFloatLookup = array[0..15] of Single;
  PFloatLookup = ^TFloatLookup;

{ Clobber the registers which are volatile in both x86-64 ABIs.  Values that
  are genuinely live over an outer-loop backedge must survive this call. }
procedure ClobberVolatile; assembler; nostackframe;
asm
  PXOR XMM0,XMM0
  PXOR XMM1,XMM1
  PXOR XMM2,XMM2
  PXOR XMM3,XMM3
  PXOR XMM4,XMM4
  PXOR XMM5,XMM5
  XOR RAX,RAX
  XOR RCX,RCX
  XOR RDX,RDX
  XOR R8,R8
  XOR R9,R9
  XOR R10,R10
  XOR R11,R11
end;


function NestedReadOnly: Integer; noinline;
var
  Outer, Inner: Integer;
  Shared, Acc: Double;
begin
  Shared:=1.25;
  Acc:=0.0;
  Outer:=0;
  while Outer<4 do
    begin
      Inner:=0;
      while Inner<3 do
        begin
          Acc:=Acc+Shared+Outer;
          Inc(Inner);
        end;
      ClobberVolatile;
      Inc(Outer);
    end;
  Result:=Trunc(Acc*4.0);
end;


function DefiniteNestedScratch: Integer; noinline;
var
  Outer, Inner: Integer;
  Scratch, Acc: Double;
begin
  Acc:=0.0;
  for Outer:=0 to 4 do
    begin
      Scratch:=Outer+0.5;
      for Inner:=0 to 1 do
        Acc:=Acc+Scratch;
      ClobberVolatile;
    end;
  Result:=Trunc(Acc*2.0);
end;


function ConditionalCarrier: Integer; noinline;
var
  Outer, Inner: Integer;
  Carry, Acc: Double;
begin
  Carry:=2.0;
  Acc:=0.0;
  for Outer:=0 to 4 do
    begin
      if (Outer and 1)=0 then
        Carry:=Carry+1.0;
      for Inner:=0 to 0 do
        Acc:=Acc+Carry;
      ClobberVolatile;
    end;
  Result:=Trunc(Acc);
end;


function ContinueAndLatch: Integer; noinline;
var
  Outer, Value, Acc: Integer;
begin
  Outer:=0;
  Value:=1;
  Acc:=0;
  while Outer<6 do
    begin
      Inc(Value,Outer);
      ClobberVolatile;
      Inc(Outer);
      if (Outer and 1)=0 then
        Continue;
      Inc(Acc,Value);
    end;
  Result:=Value*100+Acc;
end;


function RepeatCondition: Integer; noinline;
var
  I, Carry, Acc: Integer;
begin
  I:=0;
  Carry:=10;
  Acc:=0;
  repeat
    Inc(Acc,Carry);
    Inc(Carry,I+1);
    ClobberVolatile;
    Inc(I);
  until I=4;
  Result:=Carry*100+Acc;
end;


function HashNameLike(Name: PByteLookup; Len: PtrUInt): Byte; inline;
begin
  Result:=Len;
  repeat
    Dec(Len);
    if Len=0 then
      Break;
    Inc(Result,Name^[Len] and $df);
  until False;
  Result:=Result and 31;
end;


function NarrowSubregisterCarrier: Integer; noinline;
const
  Name: array[0..4] of Byte=(ord('I'),ord('n'),ord('t'),ord('6'),ord('4'));
begin
  Result:=HashNameLike(PByteLookup(@Name),Length(Name));
end;


function FloatCarrierLike(Values: PFloatLookup; Len: PtrUInt): Double; inline;
var
  Piece: Single;
  Side: Integer;
begin
  Result:=0.5;
  Side:=0;
  repeat
    Result:=Result+1.0;
    Dec(Len);
    if Len=0 then
      Break;
    Piece:=Values^[Len];
    if Piece>0 then
      Inc(Side);
  until False;
  Result:=Result+Side;
end;


function HiddenFloatCarrier: Integer; noinline;
const
  Values: array[0..4] of Single=(0.0,1.0,2.0,3.0,4.0);
begin
  Result:=Trunc(FloatCarrierLike(PFloatLookup(@Values),Length(Values))*2.0);
end;


begin
  if NestedReadOnly<>132 then
    Halt(1);
  if DefiniteNestedScratch<>50 then
    Halt(2);
  if ConditionalCarrier<>19 then
    Halt(3);
  if ContinueAndLatch<>1616 then
    Halt(4);
  if RepeatCondition<>2050 then
    Halt(5);
  if NarrowSubregisterCarrier<>17 then
    Halt(6);
  if HiddenFloatCarrier<>19 then
    Halt(7);
end.
