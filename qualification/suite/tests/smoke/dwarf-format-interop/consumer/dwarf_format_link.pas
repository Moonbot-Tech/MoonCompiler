program dwarf_format_link;

{$mode delphi}

uses
  dwarf_format_provider;

type
  IComChild = interface(IComBase)
    ['{55763E56-B8E4-4CA0-A799-7547C935142D}']
  end;
  IEmptyComChild = interface(IEmptyComBase)
    ['{C1612634-0554-49C9-BC92-4E0F973D3A60}']
  end;

{$interfaces corba}
  ICorbaChild = interface(ICorbaBase)
  end;
  IEmptyCorbaChild = interface(IEmptyCorbaBase)
  end;

var
  ComValue: IComChild;
  EmptyComValue: IEmptyComChild;
  CorbaValue: ICorbaChild;
  EmptyCorbaValue: IEmptyCorbaChild;
  DispatchValue: IDispatchProbe;
begin
  ComValue := nil;
  EmptyComValue := nil;
  CorbaValue := nil;
  EmptyCorbaValue := nil;
  DispatchValue := nil;
  If (ComValue <> nil) or (EmptyComValue <> nil) or
     (CorbaValue <> nil) or (EmptyCorbaValue <> nil) or
     (DispatchValue <> nil) then
    Halt(1);
  WriteLn('DWARF_FORMAT_INTEROP_PASS');
end.
