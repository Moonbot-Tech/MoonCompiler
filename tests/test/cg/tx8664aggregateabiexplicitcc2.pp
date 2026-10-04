{ %CPU=x86_64 }
program tx8664aggregateabiexplicitcc2;

{$mode delphi}

uses
  ux8664aggregateabilegacycc1;

type
  ILocalSysVReader = interface
    ['{9E387539-E950-420B-A014-E3670E9DD10A}']
    function ReadSysV(const Value: TExplicitCcRec8): QWord;
      sysv_abi_default;
  end;
  TDelphiReader = class(TLegacySysVBase, ILocalSysVReader, ILegacyMsReader)
    function ReadMs(const Value: TExplicitCcRec8): QWord; ms_abi_default;
  end;

function TDelphiReader.ReadMs(const Value: TExplicitCcRec8): QWord;
  ms_abi_default;
begin
  Result:=Value.Bits xor 1;
end;

var
  Obj: TDelphiReader;
  SysVReader: ILocalSysVReader;
  MsReader: ILegacyMsReader;
  Value: TExplicitCcRec8;
begin
  Value.Bits:=$7766554433221100;
  Obj:=TDelphiReader.Create;
  SysVReader:=Obj;
  MsReader:=Obj;
  if Obj.ReadSysV(Value)<>Value.Bits then Halt(1);
  if SysVReader.ReadSysV(Value)<>Value.Bits then Halt(2);
  if Obj.ReadMs(Value)<>(Value.Bits xor 1) then Halt(3);
  if MsReader.ReadMs(Value)<>(Value.Bits xor 1) then Halt(4);
  MsReader:=nil;
  SysVReader:=nil;
end.
