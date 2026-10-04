unit ux8664aggregateabidelphicc1;

{$mode delphi}

interface

type
  TExplicitCcRec8 = record
    Bits: QWord;
  end;
  IDelphiMsReader = interface
    ['{C32F73AA-9865-4FFD-813E-E66575CB64F6}']
    function ReadMs(const Value: TExplicitCcRec8): QWord; ms_abi_default;
  end;
  TDelphiSysVBase = class(TInterfacedObject)
    function ReadSysV(const Value: TExplicitCcRec8): QWord;
      sysv_abi_default; virtual;
  end;

implementation

function TDelphiSysVBase.ReadSysV(const Value: TExplicitCcRec8): QWord;
  sysv_abi_default;
begin
  Result:=Value.Bits;
end;

end.
