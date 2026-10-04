{ %CPU=x86_64 }
program twin64aggregateabiinterface1;

{$mode objfpc}

uses
  uwin64aggregateabilegacy1,
  uwin64aggregateabidelphiinterface1;

type
  TLegacyDelphiReader = class(TInterfacedObject, IDelphiRead8)
    function Read8(const Value: TRec8): QWord;
    function ReadArray8(const Value: TArray8): QWord;
  end;

function TLegacyDelphiReader.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TLegacyDelphiReader.ReadArray8(const Value: TArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

{$ifdef WIN64}
var
  Obj: TLegacyDelphiReader;
  Intf: IDelphiRead8;
  Value: TRec8;
  ArrayValue: TArray8;
begin
  Value.Bits:=$7766554433221100;
  Move(Value.Bits,ArrayValue,SizeOf(ArrayValue));
  Obj:=TLegacyDelphiReader.Create;
  Intf:=Obj;
  if Intf.Read8(Value)<>Value.Bits then Halt(1);
  if Obj.Read8(Value)<>Value.Bits then Halt(2);
  if Intf.ReadArray8(ArrayValue)<>Value.Bits then Halt(3);
  if Obj.ReadArray8(ArrayValue)<>Value.Bits then Halt(4);
  Intf:=nil;
end.
{$else WIN64}
begin
end.
{$endif WIN64}
