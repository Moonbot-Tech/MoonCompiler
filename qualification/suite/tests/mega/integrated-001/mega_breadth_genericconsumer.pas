unit mega_breadth_genericconsumer;

{$ifdef FPC}{$mode delphi}{$endif}

interface

uses mega_breadth_unit;

function BreadthExchangeStamp(const Incoming: TBreadthUnitStamp; var Slot: TBreadthUnitStamp): TBreadthUnitStamp;
function BreadthExchangeStampClass: TClass;

implementation

uses mega_breadth_genericbase;

type
  TLocalStampSlot = TBreadthModuleSlot<TBreadthUnitStamp>;

function BreadthExchangeStamp(const Incoming: TBreadthUnitStamp; var Slot: TBreadthUnitStamp): TBreadthUnitStamp;
begin
  Result := TLocalStampSlot.Exchange(Incoming, Slot);
end;

function BreadthExchangeStampClass: TClass;
begin
  Result := TLocalStampSlot;
end;

end.
