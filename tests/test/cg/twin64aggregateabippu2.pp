{ %CPU=x86_64 }
program twin64aggregateabippu2;

{$mode unleashed}

uses
  uwin64aggregateabilegacy1;

type
  TDerivedUntypedWriter = class(TUntypedWriter)
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;
  TDelphiDerivedReader = class(TLegacyVirtualReader)
    function Read1(const Value: TRec1): QWord; override;
    function Read2(const Value: TRec2): QWord; override;
    function Read4(const Value: TRec4): QWord; override;
    function Read8(const Value: TRec8): QWord; override;
    function ReadArray8(const Value: TArray8): QWord; override;
    function Read16(const Value: TRec16): QWord; override;
  end;

function TDerivedUntypedWriter.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result:=Count+PByte(@Buffer)^;
end;

function TDelphiDerivedReader.Read1(const Value: TRec1): QWord;
begin
  Result:=Value.B0;
end;

function TDelphiDerivedReader.Read2(const Value: TRec2): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TDelphiDerivedReader.Read4(const Value: TRec4): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TDelphiDerivedReader.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TDelphiDerivedReader.ReadArray8(const Value: TArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TDelphiDerivedReader.Read16(const Value: TRec16): QWord;
begin
  Result:=Value.First;
end;

procedure CheckLegacyVirtualReader(Reader: TLegacyVirtualReader;
  const R1: TRec1; const R2: TRec2; const R4: TRec4;
  const R8: TRec8; const A8: TArray8; const R16: TRec16;
  Bits: QWord; Base: Integer);
begin
  if Reader.Read1(R1)<>$11 then Halt(Base+1);
  if Reader.Read2(R2)<>$2211 then Halt(Base+2);
  if Reader.Read4(R4)<>$44332211 then Halt(Base+3);
  if Reader.Read8(R8)<>Bits then Halt(Base+4);
  if Reader.ReadArray8(A8)<>Bits then Halt(Base+5);
  if Reader.Read16(R16)<>Bits then Halt(Base+6);
end;

procedure TestUntypedOverride;
var
  Writer: TUntypedWriter;
  B: Byte;
begin
  B:=7;
  Writer:=TDerivedUntypedWriter.Create;
  try
    if Writer.Write(B,11)<>18 then Halt(9);
  finally
    Writer.Free;
  end;
end;

{$ifdef WIN64}
var
  Bits: QWord;
  R1: TRec1;
  R2: TRec2;
  R4: TRec4;
  R8,Made: TRec8;
  A8: TArray8;
  R16: TRec16;
  F: TRead8;
  Reader: TReader;
  LegacyReader: TLegacyVirtualReader;
  DelphiReader: TDelphiDerivedReader;
begin
  Bits:=$8877665544332211;
  R1.B0:=$11;
  Move(Bits,R2,SizeOf(R2));
  Move(Bits,R4,SizeOf(R4));
  R8.Bits:=Bits;
  Move(Bits,A8,SizeOf(A8));
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
  TestUntypedOverride;
  DelphiReader:=TDelphiDerivedReader.Create;
  try
    LegacyReader:=DelphiReader;
    CheckLegacyVirtualReader(LegacyReader,R1,R2,R4,R8,A8,R16,Bits,20);
    CheckLegacyVirtualReader(DelphiReader,R1,R2,R4,R8,A8,R16,Bits,30);
  finally
    DelphiReader.Free;
  end;
end.
{$else WIN64}
begin
  TestUntypedOverride;
end.
{$endif WIN64}
