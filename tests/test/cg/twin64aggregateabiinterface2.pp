{ %CPU=x86_64 }
program twin64aggregateabiinterface2;

{$mode unleashed}

uses
  uwin64aggregateabilegacy1;

type
  TDelphiLegacyReader = class(TInterfacedObject, ILegacyRead8)
    function Read8(const Value: TRec8): QWord;
    function ReadArray8(const Value: TArray8): QWord;
  end;

function TDelphiLegacyReader.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TDelphiLegacyReader.ReadArray8(const Value: TArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

{$ifdef WIN64}
var
  Obj: TDelphiLegacyReader;
  Intf: ILegacyRead8;
  Value: TRec8;
  ArrayValue: TArray8;
begin
  Value.Bits:=$7766554433221100;
  Move(Value.Bits,ArrayValue,SizeOf(ArrayValue));
  Obj:=TDelphiLegacyReader.Create;
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
