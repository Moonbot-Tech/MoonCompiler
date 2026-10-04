{ %CPU=x86_64 }
program twin64aggregateabidelegatedinterface2;

{$mode unleashed}

uses
  uwin64aggregateabidelphivirtual1,
  uwin64aggregateabilegacyinterface1;

type
  TMethodRead8 = function(const Value: TDelphiRec8): QWord of object;
  ILocalRead8 = interface
    ['{561D08B2-0A86-4E28-97FC-92A6C6407D45}']
    function Read8(const Value: TDelphiRec8): QWord;
  end;
  TDelegate = class(TInterfacedObject, ILegacyDelphiRead8)
    function Read8(const Value: TDelphiRec8): QWord;
  end;
  TProxy = class(TInterfacedObject, ILegacyDelphiRead8, ILocalRead8)
  private
    FReader: ILegacyDelphiRead8;
    property Reader: ILegacyDelphiRead8 read FReader
      implements ILegacyDelphiRead8;
  public
    constructor Create(const AReader: ILegacyDelphiRead8);
    function Read8(const Value: TDelphiRec8): QWord;
  end;

function TDelegate.Read8(const Value: TDelphiRec8): QWord;
begin
  Result:=Value.Bits;
end;

constructor TProxy.Create(const AReader: ILegacyDelphiRead8);
begin
  inherited Create;
  FReader:=AReader;
end;

function TProxy.Read8(const Value: TDelphiRec8): QWord;
begin
  Result:=Value.Bits xor 1;
end;

{$ifdef WIN64}
var
  Obj: TProxy;
  Intf: ILegacyDelphiRead8;
  LocalIntf: ILocalRead8;
  Callback: TMethodRead8;
  Value: TDelphiRec8;
begin
  Value.Bits:=$7766554433221100;
  Obj:=TProxy.Create(TDelegate.Create);
  Intf:=Obj;
  LocalIntf:=Obj;
  Callback:=@Obj.Read8;
  if Callback(Value)<>(Value.Bits xor 1) then Halt(1);
  if Intf.Read8(Value)<>Value.Bits then Halt(2);
  if LocalIntf.Read8(Value)<>(Value.Bits xor 1) then Halt(3);
  LocalIntf:=nil;
  Intf:=nil;
end.
{$else WIN64}
begin
end.
{$endif WIN64}
