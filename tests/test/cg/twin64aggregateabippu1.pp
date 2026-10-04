{ %CPU=x86_64 }
program twin64aggregateabippu1;

{$mode objfpc}

uses
  uwin64aggregateabidelphi1;

{$ifdef WIN64}
var
  Bits: QWord;
  R1: TRec1;
  R2: TRec2;
  R4: TRec4;
  R8,Made: TRec8;
  R16: TRec16;
  F: TRead8;
  Reader: TReader;
begin
  Bits:=$8877665544332211;
  R1.B0:=$11;
  Move(Bits,R2,SizeOf(R2));
  Move(Bits,R4,SizeOf(R4));
  R8.Bits:=Bits;
  R16.First:=Bits;
  R16.Second:=not Bits;
  if Read1(R1)<>$11 then Halt(1);
  if Read2(R2)<>$2211 then Halt(2);
  if Read4(R4)<>$44332211 then Halt(3);
  if Read8(R8)<>Bits then Halt(4);
  if Read16(R16)<>Bits then Halt(5);
  F:=GetRead8;
  if F(R8)<>Bits then Halt(6);
  Reader:=TReader.Create;
  try
    if Reader.Read8(R8)<>Bits then Halt(7);
  finally
    Reader.Free;
  end;
  Made:=Make8(Bits);
  if Made.Bits<>Bits then Halt(8);
end.
{$else WIN64}
begin
end.
{$endif WIN64}
