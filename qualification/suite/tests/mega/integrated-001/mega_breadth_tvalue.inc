{ A typed TValue owns an interface and can address a boxed static array by relative index. }

procedure BreadthHoldBoxedInterface;
var
  Ref: IBreadthTaggedOwner;
  Recovered: IInterface;
  Boxed, CopyBox: TValue;
begin
  Ref := TBreadthTaggedOwner.Create;
  Boxed := TValue.From<IBreadthTaggedOwner>(Ref);
  Ref := nil;
  Check((Boxed.Kind = tkInterface) and (TBreadthTaggedOwner.Destroyed = 0), 'breadth-tvalue-boxed-interface-keeps-owner');
  CopyBox := Boxed;
  Boxed := TValue.Empty;
  Recovered := CopyBox.AsInterface;
  CopyBox := TValue.Empty;
  Ref := Recovered as IBreadthTaggedOwner;
  Check((Ref <> nil) and (Ref.Tag = 74000000051) and (TBreadthTaggedOwner.Destroyed = 0),
    'breadth-tvalue-unboxed-interface-outlives-both-boxes');
end;

procedure RunBreadthBoxedValues;
type
  TWords = array[-2..1] of Cardinal;
  PWords = ^TWords;
var
  Source: TWords;
  Boxed, Element: TValue;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthHoldBoxedInterface;
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-tvalue-owned-interface-releases-after-scope');

  Source[-2] := 41;
  Source[-1] := Cardinal(OpaqueI(3221225473));
  Source[0] := 242;
  Source[1] := 73;
  Boxed := TValue.From<TWords>(Source);
  Source[-1] := 211;
  Element := Boxed.GetArrayElement(Integer(OpaqueI(1)));
  Check((Boxed.GetArrayLength = 4) and (Element.AsOrdinal = 3221225473),
    'breadth-tvalue-static-array-copies-data-and-uses-relative-index');
  Boxed.SetArrayElement(Integer(OpaqueI(1)), TValue.From<Cardinal>(Cardinal(OpaqueI(4000000421))));
  Check((Element.AsOrdinal = 3221225473) and (Source[-1] = 211), 'breadth-tvalue-array-edit-leaves-element-and-source-copies');
  Check((Boxed.GetArrayElement(0).AsOrdinal = 41) and (Boxed.GetArrayElement(3).AsOrdinal = 73)
    and (PWords(Boxed.GetReferenceToRawData)^[-1] = 4000000421), 'breadth-tvalue-array-edit-maps-relative-index-to-storage');
  Mix(UInt64(Boxed.GetArrayElement(1).AsOrdinal));
end;

procedure RunBreadthBoxedFloatKinds;
var
  Fixed: Currency;
  Real: Double;
  Seed, FixedBits, RealBits: Int64;
  FixedBox, RealBox: TValue;
begin
  Seed := OpaqueI(Low(Int64));
  Move(Seed, Fixed, SizeOf(Fixed));
  Move(Seed, Real, SizeOf(Real));
  FixedBox := TValue.From<Currency>(Fixed);
  RealBox := TValue.From<Double>(Real);
  Check((FixedBox.Kind = tkFloat) and (RealBox.Kind = tkFloat)
    and (FixedBox.TypeInfo = TypeInfo(Currency)) and (RealBox.TypeInfo = TypeInfo(Double)),
    'breadth-tvalue-boxed-float-preserves-specific-type-metadata');
  Move(FixedBox.GetReferenceToRawData^, FixedBits, SizeOf(FixedBits));
  Move(RealBox.GetReferenceToRawData^, RealBits, SizeOf(RealBits));
  Check((FixedBits = Low(Int64)) and (RealBits = Low(Int64)), 'breadth-tvalue-boxed-float-preserves-equal-bits-of-distinct-types');
  Mix(UInt64(RealBits));
end;
