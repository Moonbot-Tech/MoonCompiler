{ %CPU=x86_64 }
program twin64aggregateabiinterfaceancestor1;

{$mode objfpc}

uses
  uwin64aggregateabilegacy1;

type
  TCompatibleReader = class(TLegacyInterfaceBase, ILegacyRead8);

{$ifdef WIN64}
var
  Obj: TCompatibleReader;
  Intf: ILegacyRead8;
  Value: TRec8;
  ArrayValue: TArray8;
begin
  Value.Bits:=$7766554433221100;
  Move(Value.Bits,ArrayValue,SizeOf(ArrayValue));
  Obj:=TCompatibleReader.Create;
  Intf:=Obj;
  if Intf.Read8(Value)<>Value.Bits then Halt(1);
  if Intf.ReadArray8(ArrayValue)<>Value.Bits then Halt(2);
  if Obj.Read8(Value)<>Value.Bits then Halt(3);
  if Obj.ReadArray8(ArrayValue)<>Value.Bits then Halt(4);
  Intf:=nil;
end.
{$else WIN64}
begin
end.
{$endif WIN64}
