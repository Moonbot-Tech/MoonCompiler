{ %CPU=x86_64 }
program twin64aggregateabioverride1;

{$mode objfpc}

uses
  uwin64aggregateabidelphivirtual1;

type
  TLegacyDerivedReader = class(TDelphiVirtualReader)
    function Read1(const Value: TDelphiRec1): QWord; override;
    function Read2(const Value: TDelphiRec2): QWord; override;
    function Read4(const Value: TDelphiRec4): QWord; override;
    function Read8(const Value: TDelphiRec8): QWord; override;
    function ReadArray8(const Value: TDelphiArray8): QWord; override;
    function Read16(const Value: TDelphiRec16): QWord; override;
  end;

function TLegacyDerivedReader.Read1(const Value: TDelphiRec1): QWord;
begin
  Result:=Value.B0;
end;

function TLegacyDerivedReader.Read2(const Value: TDelphiRec2): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TLegacyDerivedReader.Read4(const Value: TDelphiRec4): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TLegacyDerivedReader.Read8(const Value: TDelphiRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TLegacyDerivedReader.ReadArray8(const Value: TDelphiArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function TLegacyDerivedReader.Read16(const Value: TDelphiRec16): QWord;
begin
  Result:=Value.First;
end;

procedure CheckReader(Reader: TDelphiVirtualReader;
  const R1: TDelphiRec1; const R2: TDelphiRec2; const R4: TDelphiRec4;
  const R8: TDelphiRec8; const A8: TDelphiArray8;
  const R16: TDelphiRec16; Bits: QWord;
  Base: Integer);
begin
  if Reader.Read1(R1)<>$11 then Halt(Base+1);
  if Reader.Read2(R2)<>$2211 then Halt(Base+2);
  if Reader.Read4(R4)<>$44332211 then Halt(Base+3);
  if Reader.Read8(R8)<>Bits then Halt(Base+4);
  if Reader.ReadArray8(A8)<>Bits then Halt(Base+5);
  if Reader.Read16(R16)<>Bits then Halt(Base+6);
end;

{$ifdef WIN64}
var
  Bits: QWord;
  R1: TDelphiRec1;
  R2: TDelphiRec2;
  R4: TDelphiRec4;
  R8: TDelphiRec8;
  A8: TDelphiArray8;
  R16: TDelphiRec16;
  BaseReader: TDelphiVirtualReader;
  DerivedReader: TLegacyDerivedReader;
begin
  Bits:=$8877665544332211;
  R1.B0:=$11;
  Move(Bits,R2,SizeOf(R2));
  Move(Bits,R4,SizeOf(R4));
  R8.Bits:=Bits;
  Move(Bits,A8,SizeOf(A8));
  R16.First:=Bits;
  R16.Second:=not Bits;
  DerivedReader:=TLegacyDerivedReader.Create;
  try
    BaseReader:=DerivedReader;
    CheckReader(BaseReader,R1,R2,R4,R8,A8,R16,Bits,10);
    CheckReader(DerivedReader,R1,R2,R4,R8,A8,R16,Bits,20);
  finally
    DerivedReader.Free;
  end;
end.
{$else WIN64}
begin
end.
{$endif WIN64}
