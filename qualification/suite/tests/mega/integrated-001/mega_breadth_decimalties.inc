{ Settlement and display use different rules for an exact decimal half. }

procedure RunBreadthDecimalTiePolicy;
var
  Previous: TFPURoundingMode;
  HalfCent, HalfHundred: Double;
  Settled, Displayed: Int64;
begin
  Previous := SetRoundMode(rmNearest);
  try
    HalfCent := OpaqueD(1.125);
    Settled := Round(RoundTo(HalfCent, -2) * 100);
    Displayed := Round(SimpleRoundTo(HalfCent, -2) * 100);
    Check((Settled = 112) and (Displayed = 113), 'breadth-decimal-ties-positive-even-and-away-are-distinct');
    Check((Round(RoundTo(-HalfCent, -2) * 100) = -112) and (Round(SimpleRoundTo(-HalfCent, -2) * 100) = -113),
      'breadth-decimal-ties-negative-even-and-away-are-distinct');
    Check((Round(RoundTo(OpaqueD(1.375), -2) * 100) = 138) and (Round(SimpleRoundTo(OpaqueD(1.375), -2) * 100) = 138),
      'breadth-decimal-ties-half-even-rounds-up-when-lower-neighbor-is-odd');
    HalfHundred := OpaqueD(1250);
    Check((RoundTo(HalfHundred, 2) = 1200) and (Round(SimpleRoundTo(HalfHundred, 2)) = 1300),
      'breadth-decimal-ties-positive-scale-selects-distinct-hundred-buckets');
    Mix(UInt64(Settled * 1000 + Displayed));
  finally
    SetRoundMode(Previous);
  end;
end;
