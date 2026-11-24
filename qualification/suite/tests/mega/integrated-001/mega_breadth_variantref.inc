{ A Variant reference chain observes a live Int64 cell while an extracted scalar keeps its old value. }

procedure RunBreadthByRefInt64Variant;
var
  Counter, Snapshot: Int64;
  Inner, Outer, Total: Variant;
begin
  Counter := OpaqueI(-55000000017);
  TVarData(Inner).VType := varInt64 or varByRef;
  TVarData(Inner).VPointer := @Counter;
  TVarData(Outer).VType := varVariant or varByRef;
  TVarData(Outer).VPointer := @Inner;

  Snapshot := Int64(Outer);
  Check((Snapshot = -55000000017) and (Int64(Inner) = -55000000017), 'breadth-variant-byref-chain-reads-full-negative-int64');
  Counter := OpaqueI(72000000039);
  Total := Outer + OpaqueI(-32000000007);
  Check((VarType(Total) = varInt64) and (Int64(Total) = 40000000032) and (Snapshot = -55000000017),
    'breadth-variant-byref-chain-arithmetic-sees-live-int64');
  VarClear(Outer);
  Check(VarIsEmpty(Outer) and (Int64(Inner) = 72000000039), 'breadth-variant-byref-clear-keeps-underlying-descriptor');
  VarClear(Inner);
  Check(VarIsEmpty(Inner) and (Counter = 72000000039), 'breadth-variant-byref-clear-does-not-write-target-cell');
  Mix(UInt64(Int64(Total)) xor UInt64(Snapshot));
end;
