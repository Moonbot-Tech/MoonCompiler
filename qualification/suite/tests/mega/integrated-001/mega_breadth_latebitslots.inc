{ The slot allocator skips full words, reuses holes and grows when all slots are reserved. }

procedure RunBreadthLateBitSlots;
var
  Slots: TBits;
  I, Slot: Integer;
begin
  Slots := TBits.Create;
  try
    Slots.Size := Integer(OpaqueI(130));
    for I := 0 to Slots.Size - 1 do
      Slots[I] := True;
    Check(Slots.OpenBit = 130, 'breadth-slot-bits-all-full-returns-one-past-end');
    Slots[128] := False;
    Slots[129] := False;
    Slot := Slots.OpenBit;
    Check(Slot = 128, 'breadth-slot-bits-finds-first-hole-after-two-full-words');
    Slots[Slot] := True;
    Check((Slots.OpenBit = 129) and Slots[127], 'breadth-slot-bits-reserving-hole-keeps-other-word');
    Slots[129] := True;
    Slots[Slots.OpenBit] := True;
    Check((Slots.Size = 131) and Slots[130] and (Slots.OpenBit = 131), 'breadth-slot-bits-next-reservation-extends-map');
    Mix(UInt64(Slots.OpenBit));
  finally
    Slots.Free;
  end;
end;
