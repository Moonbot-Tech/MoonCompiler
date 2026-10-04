{ %CPU=x86_64 }
program tx8664aggregateabiexplicitcc1;

{$mode objfpc}

uses
  ux8664aggregateabidelphicc1;

type
  ILocalSysVReader = interface
    ['{81EEC6F3-4AEC-439B-B12B-EFE6C332CCAF}']
    function ReadSysV(const Value: TExplicitCcRec8): QWord;
      sysv_abi_default;
  end;
  TLegacyReader = class(TDelphiSysVBase, ILocalSysVReader, IDelphiMsReader)
    function ReadMs(const Value: TExplicitCcRec8): QWord; ms_abi_default;
  end;

function TLegacyReader.ReadMs(const Value: TExplicitCcRec8): QWord;
  ms_abi_default;
begin
  Result:=Value.Bits xor 1;
end;

var
  Obj: TLegacyReader;
  SysVReader: ILocalSysVReader;
  MsReader: IDelphiMsReader;
  Value: TExplicitCcRec8;
begin
  Value.Bits:=$7766554433221100;
  Obj:=TLegacyReader.Create;
  SysVReader:=Obj;
  MsReader:=Obj;
  if Obj.ReadSysV(Value)<>Value.Bits then Halt(1);
  if SysVReader.ReadSysV(Value)<>Value.Bits then Halt(2);
  if Obj.ReadMs(Value)<>(Value.Bits xor 1) then Halt(3);
  if MsReader.ReadMs(Value)<>(Value.Bits xor 1) then Halt(4);
  MsReader:=nil;
  SysVReader:=nil;
end.
