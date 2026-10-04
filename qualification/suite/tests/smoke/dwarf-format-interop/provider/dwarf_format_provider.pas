unit dwarf_format_provider;

{$mode delphi}

interface

type
  IComBase = interface(IUnknown)
    ['{43B16241-C99C-4A32-B256-C3B568CED846}']
    function ComValue: Integer;
  end;
  IEmptyComBase = interface(IUnknown)
    ['{663DC777-B3B0-4672-A589-3386C141DDA0}']
  end;

  IDispatchProbe = dispinterface
    ['{A780D9D2-C4E5-47E9-AB1C-355CFD565311}']
    function DispatchValue: Integer; dispid 1;
  end;

{$interfaces corba}
  ICorbaBase = interface
    function CorbaValue: Integer;
  end;
  IEmptyCorbaBase = interface
  end;

implementation

end.
