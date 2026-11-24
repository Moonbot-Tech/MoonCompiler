{ A specialization created in an implementation section shares its class
  identity and storage with the same specialization in the application. }

procedure RunBreadthSharedGeneric;
type
  TStampSlot = TBreadthModuleSlot<TBreadthUnitStamp>;
  TIntSlot = TBreadthModuleSlot<Int64>;
var
  Slot, Incoming, Old: TBreadthUnitStamp;
  Counter, Saved: Int64;
begin
  Check(BreadthExchangeStampClass = TStampSlot, 'breadth-generic-cross-unit-uses-one-class-identity');
  TStampSlot.Transfers := 0;
  TIntSlot.Transfers := 0;
  Slot.Data := OpaqueI(81000000007);
  Slot.LabelText := AnsiString(IntToStr(OpaqueI(64))) + '-old';
  Incoming.Data := OpaqueI(-97000000011);
  Incoming.LabelText := 'new';
  Old := BreadthExchangeStamp(Incoming, Slot);
  Check((Old.Data = 81000000007) and (Old.LabelText = '64-old') and (Slot.Data = -97000000011)
    and (Slot.LabelText = 'new'), 'breadth-generic-cross-unit-returns-previous-managed-slot');
  Check(TStampSlot.Transfers = 1, 'breadth-generic-cross-unit-observes-transfer-count-in-caller');
  Incoming.LabelText := 'third';
  Incoming.Data := 42;
  Old := TStampSlot.Exchange(Incoming, Slot);
  Check((Old.Data = -97000000011) and (Old.LabelText = 'new') and (Slot.Data = 42) and (Slot.LabelText = 'third'),
    'breadth-generic-caller-specialization-uses-same-managed-signature');
  Counter := 3;
  Saved := TIntSlot.Exchange(OpaqueI(82000000009), Counter);
  Check((Saved = 3) and (Counter = 82000000009) and (TIntSlot.Transfers = 1) and (TStampSlot.Transfers = 2),
    'breadth-generic-cross-unit-keeps-other-specializations-isolated');
  Mix(UInt64(TStampSlot.Transfers * 10 + TIntSlot.Transfers));
end;
