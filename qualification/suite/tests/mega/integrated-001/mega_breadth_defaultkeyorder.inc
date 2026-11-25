{ Ordered caches rely on the default comparer to distinguish signed values and unsigned IDs. }

procedure RunBreadthDefaultKeyOrder;
const
  Lowest = Low(Int64) + 7;
  Highest = High(Int64) - 3;
  SignBit = UInt64($8000000000000000);
var
  Times: TList<Int64>;
  IDs: TList<UInt64>;
  Index: NativeInt;
begin
  Times := TList<Int64>.Create;
  IDs := nil;
  try
    Times.AddRange([OpaqueI(Highest), 0, -19, OpaqueI(Lowest), -430000000006, 3]);
    Times.Sort;
    Check((Times.Count = 6) and (Times[0] = Lowest) and (Times[1] = -430000000006) and (Times[2] = -19)
      and (Times[3] = 0) and (Times[4] = 3) and (Times[5] = Highest), 'breadth-default-int64-order-spans-both-extremes');
    Check(Times.BinarySearch(OpaqueI(-19), Index) and (Index = 2), 'breadth-default-int64-search-finds-negative-key');
    Check(not Times.BinarySearch(OpaqueI(-20), Index) and (Index = 2), 'breadth-default-int64-search-finds-insertion-point');

    IDs := TList<UInt64>.Create;
    IDs.AddRange([High(UInt64) - 4, 0, SignBit + 3, SignBit - 1, UInt64(OpaqueI(42)), SignBit]);
    IDs.Sort;
    Check((IDs.Count = 6) and (IDs[0] = 0) and (IDs[1] = 42) and (IDs[2] = SignBit - 1)
      and (IDs[3] = SignBit) and (IDs[4] = SignBit + 3) and (IDs[5] = High(UInt64) - 4),
      'breadth-default-uint64-order-keeps-high-bit-keys-above-ordinary-ids');
    Check(IDs.BinarySearch(SignBit, Index) and (Index = 3), 'breadth-default-uint64-search-finds-first-high-bit-key');
    Check(not IDs.BinarySearch(SignBit + 2, Index) and (Index = 4), 'breadth-default-uint64-search-inserts-between-high-bit-keys');
    Mix(UInt64(Times[0]) xor IDs[4]);
  finally
    FreeAndNil(IDs);
    FreeAndNil(Times);
  end;
end;
