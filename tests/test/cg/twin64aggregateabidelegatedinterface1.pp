{ %CPU=x86_64 }
program twin64aggregateabidelegatedinterface1;

{$mode objfpc}

uses
  uwin64aggregateabilegacy1,
  uwin64aggregateabidelphiinterface1;

type
  TMethodRead8 = function(const Value: TRec8): QWord of object;
  ILocalRead8 = interface
    ['{D94BE05C-3FA0-4261-A8A7-A622807C1BC7}']
    function Read8(const Value: TRec8): QWord;
  end;
  TDelegate = class(TInterfacedObject, IDelphiRead8)
    function Read8(const Value: TRec8): QWord;
    function ReadArray8(const Value: TArray8): QWord;
  end;
  TProxy = class(TInterfacedObject, IDelphiRead8, ILocalRead8)
  private
    FReader: IDelphiRead8;
    property Reader: IDelphiRead8 read FReader implements IDelphiRead8;
  public
    constructor Create(const AReader: IDelphiRead8);
    function Read8(const Value: TRec8): QWord;
  end;

function TDelegate.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TDelegate.ReadArray8(const Value: TArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

constructor TProxy.Create(const AReader: IDelphiRead8);
begin
  inherited Create;
  FReader:=AReader;
end;

function TProxy.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits xor 1;
end;

{$ifdef WIN64}
var
  Obj: TProxy;
  Intf: IDelphiRead8;
  LocalIntf: ILocalRead8;
  Callback: TMethodRead8;
  Value: TRec8;
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
