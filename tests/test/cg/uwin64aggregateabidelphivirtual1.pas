unit uwin64aggregateabidelphivirtual1;

{$mode unleashed}

interface

type
  TDelphiRec1 = packed record B0: Byte; end;
  TDelphiRec2 = packed record B: array[0..1] of Byte; end;
  TDelphiRec4 = packed record B: array[0..3] of Byte; end;
  TDelphiRec8 = packed record Bits: QWord; end;
  TDelphiRec16 = packed record First,Second: QWord; end;
  TDelphiArray8 = array[0..7] of Byte;
  TDelphiVirtualReader = class
    function Read1(const Value: TDelphiRec1): QWord; virtual;
    function Read2(const Value: TDelphiRec2): QWord; virtual;
    function Read4(const Value: TDelphiRec4): QWord; virtual;
    function Read8(const Value: TDelphiRec8): QWord; virtual;
    function ReadArray8(const Value: TDelphiArray8): QWord; virtual;
    function Read16(const Value: TDelphiRec16): QWord; virtual;
  end;
  TDelphiInterfaceBase = class(TInterfacedObject)
    function Read8(const Value: TDelphiRec8): QWord; virtual;
  end;

implementation

function TDelphiVirtualReader.Read1(const Value: TDelphiRec1): QWord;
begin
  Result:=0;
end;

function TDelphiVirtualReader.Read2(const Value: TDelphiRec2): QWord;
begin
  Result:=0;
end;

function TDelphiVirtualReader.Read4(const Value: TDelphiRec4): QWord;
begin
  Result:=0;
end;

function TDelphiVirtualReader.Read8(const Value: TDelphiRec8): QWord;
begin
  Result:=0;
end;

function TDelphiVirtualReader.ReadArray8(const Value: TDelphiArray8): QWord;
begin
  Result:=0;
end;

function TDelphiInterfaceBase.Read8(const Value: TDelphiRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TDelphiVirtualReader.Read16(const Value: TDelphiRec16): QWord;
begin
  Result:=0;
end;

end.
