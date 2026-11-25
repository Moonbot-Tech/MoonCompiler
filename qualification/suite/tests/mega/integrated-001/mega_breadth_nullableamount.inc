{ Nullable amounts retain their kind and their last fixed-point digit during comparison. }

procedure RunBreadthNullableAmountOrder;
var
  Quota, Prior, Missing, Unset: Variant;
  Raw: Int64;
  Amount: Currency;
begin
  Raw := OpaqueI(9007199254740993);
  Move(Raw, Amount, SizeOf(Amount));
  Quota := Amount;
  Dec(Raw);
  Move(Raw, Amount, SizeOf(Amount));
  Prior := Amount;
  Check((VarType(Quota) = varCurrency) and (VarType(Prior) = varCurrency),
    'breadth-nullable-amount-order-keeps-both-values-fixed-point');
  Check(not VarSameValue(Quota, Prior) and (VarCompareValue(Quota, Prior) = vrGreaterThan)
    and (VarCompareValue(Prior, Quota) = vrLessThan), 'breadth-nullable-amount-order-distinguishes-final-decimal-digit');
  Missing := Null;
  Unset := Unassigned;
  Check(VarSameValue(Missing, Null) and not VarSameValue(Missing, Unset),
    'breadth-nullable-amount-order-distinguishes-database-null-from-unset');
  Check(VarCompareValue(Missing, Quota) = vrNotEqual, 'breadth-nullable-amount-order-leaves-null-unordered-with-currency');
  Mix(UInt64(Ord(VarCompareValue(Quota, Prior))));
end;

procedure RunBreadthFixedPointConversion;
var
  Amount: Currency;
  Previous: TFPURoundingMode;
  Raw: Int64 absolute Amount;
begin
  Previous := SetRoundMode(rmNearest);
  try
    Check(TryFloatToCurr(OpaqueD(0.03125), Amount) and (Raw = 312),
      'breadth-fixed-point-conversion-tie-rounds-down-to-even');
    Check(TryFloatToCurr(OpaqueD(0.09375), Amount) and (Raw = 938),
      'breadth-fixed-point-conversion-tie-rounds-up-to-even');
    Check(TryFloatToCurr(OpaqueD(-0.03125), Amount) and (Raw = -312),
      'breadth-fixed-point-conversion-keeps-signed-even-tie');
    Mix(UInt64(Raw));
    Check(not TryFloatToCurr(OpaqueD(1E15), Amount), 'breadth-fixed-point-conversion-rejects-out-of-range-value');
  finally
    SetRoundMode(Previous);
  end;
end;
