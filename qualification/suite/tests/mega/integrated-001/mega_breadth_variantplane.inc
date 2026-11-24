{ A typed rectangular Variant array keeps nonzero bounds and independent copied cells. }

procedure RunBreadthVariantPlane;
var
  Table, Snapshot: Variant;
  X, Y: Integer;
begin
  Table := VarArrayCreate([-2, -1, 5, 7], varInteger);
  for Y := 5 to 7 do
    for X := -2 to -1 do
      VarArrayPut(Table, Integer(OpaqueI(100 * (X + 3) + Y)), [X, Y]);
  Check((VarArrayDimCount(Table) = 2) and (VarArrayLowBound(Table, 1) = -2) and (VarArrayHighBound(Table, 1) = -1)
    and (VarArrayLowBound(Table, 2) = 5) and (VarArrayHighBound(Table, 2) = 7),
    'breadth-variant-plane-keeps-asymmetric-nonzero-bounds');
  Snapshot := Table;
  VarArrayPut(Table, Integer(OpaqueI(-78019)), [-1, 6]);
  Check((Integer(VarArrayGet(Table, [-1, 6])) = -78019) and (Integer(Table[-2, 6]) = 106) and (Integer(Table[-1, 7]) = 207),
    'breadth-variant-plane-indexed-write-keeps-neighbor-dimension-values');
  Check((VarArrayLowBound(Snapshot, 1) = -2) and (VarArrayHighBound(Snapshot, 2) = 7) and (Integer(Snapshot[-1, 6]) = 206)
    and (Integer(Snapshot[-2, 7]) = 107), 'breadth-variant-plane-typed-copy-keeps-original-bounds-and-values');
end;
