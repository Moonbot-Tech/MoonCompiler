unit ux8664aggregateabilegacycc1;

{$mode objfpc}

interface

type
  TExplicitCcRec8 = record
    Bits: QWord;
  end;
  ILegacyMsReader = interface
    ['{312EAEC2-E7F6-46BF-AB06-B0CD5C25E172}']
    function ReadMs(const Value: TExplicitCcRec8): QWord; ms_abi_default;
  end;
  TLegacySysVBase = class(TInterfacedObject)
    function ReadSysV(const Value: TExplicitCcRec8): QWord;
      sysv_abi_default; virtual;
  end;

implementation

function TLegacySysVBase.ReadSysV(const Value: TExplicitCcRec8): QWord;
  sysv_abi_default;
begin
  Result:=Value.Bits;
end;

end.
