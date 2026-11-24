{ A locked numeric Variant array exposes storage whose indices are relative to its first cell. }

procedure RunBreadthLockedVariantArray;
var
  Value, Snapshot: Variant;
  Storage, Inner, Cell: PInteger;
begin
  Value := VarArrayCreate([-2, 0], varInteger);
  Value[-2] := Integer(OpaqueI(912));
  Value[-1] := Integer(OpaqueI(-405));
  Value[0] := Integer(OpaqueI(1301));
  Snapshot := Value;
  Storage := PInteger(VarArrayLock(Value));
  try
    Cell := Storage;
    Inc(Cell, Integer(OpaqueI(1)));
    Check((Storage^ = 912) and (Cell^ = -405),
      'breadth-variant-array-lock-starts-at-logical-low-bound');
    Inner := PInteger(VarArrayLock(Value));
    try
      Check((Inner = Storage) and (Inner^ = 912), 'breadth-variant-array-nested-lock-reuses-base-address');
    finally
      VarArrayUnlock(Value);
    end;
    Cell^ := Integer(OpaqueI(70103));
  finally
    VarArrayUnlock(Value);
  end;
  Check((Integer(Value[-1]) = 70103) and (Integer(Snapshot[-1]) = -405), 'breadth-variant-array-lock-edits-live-storage');
  VarArrayRedim(Value, Integer(OpaqueI(2)));
  Check((VarArrayLowBound(Value, 1) = -2) and (VarArrayHighBound(Value, 1) = 2),
    'breadth-variant-array-unlocked-growth-keeps-low-bound');
  Check((Integer(Value[-2]) = 912) and (Integer(Value[-1]) = 70103) and (Integer(Value[0]) = 1301),
    'breadth-variant-array-growth-keeps-prefix');
  Check((Integer(Value[1]) = 0) and (Integer(Value[2]) = 0), 'breadth-variant-array-growth-zeroes-new-cells');
  VarArrayRedim(Value, Integer(OpaqueI(-1)));
  Check((VarArrayHighBound(Value, 1) = -1) and (Integer(Value[-1]) = 70103),
    'breadth-variant-array-negative-upper-bound-after-shrink');
  Mix(UInt64(Integer(Value[-1])));
end;
