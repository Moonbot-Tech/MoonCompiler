unit mega_breadth_genericbase;

{$ifdef FPC}{$mode delphi}{$endif}

interface

type
  TBreadthModuleSlot<T> = class
  public
    class var Transfers: Integer;
    class function Exchange(const Incoming: T; var Slot: T): T; static; inline;
  end;

implementation

class function TBreadthModuleSlot<T>.Exchange(const Incoming: T; var Slot: T): T;
begin
  Result := Slot;
  Slot := Incoming;
  Inc(Transfers);
end;

end.
