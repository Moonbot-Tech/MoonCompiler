{ TVarRec borrows the variant and scalar cells through a cdecl open array. }

function BreadthReadDecimalVarRecs(Left: Int64; Pad: Double; const Items: array of const; Right: Int64): Int64;
  {$ifdef FPC}{$if FPC_FULLVERSION >= 30301}cdecl;{$endif}{$else}cdecl;{$endif}
var
  CurrencyBits: Int64;
  TagsMatch: Boolean;
begin
  Check((Left = 81000000008) and (Pad = 1.25) and (Right = -73000000009) and (Length(Items) = 5),
    'breadth-decimal-varrecs-cdecl-keeps-scalars-around-open-array');
  Result := 0;
  If Length(Items) <> 5 then
    Exit;
  TagsMatch := (Items[0].VType = vtVariant) and (Items[1].VType = vtCurrency) and (Items[2].VType = vtPointer)
    and (Items[3].VType = vtExtended) and (Items[4].VType = vtUnicodeString);
  Check(TagsMatch, 'breadth-decimal-varrecs-use-correct-tags');
  If not TagsMatch then
    Exit;
  Move(Items[1].VCurrency^, CurrencyBits, SizeOf(CurrencyBits));
  Check((CurrencyBits = -57219) and (Items[2].VPointer = nil) and (Items[3].VExtended^ = -8.125)
    and (UnicodeString(Items[4].VUnicodeString) = 'decimal'#0'carrier'), 'breadth-decimal-varrecs-dereference-exact-payloads');
  Check(VarType(Items[0].VVariant^) = varInt64, 'breadth-decimal-varrecs-keeps-borrowed-variant-type');
  Result := Int64(Items[0].VVariant^) + CurrencyBits;
end;

procedure RunBreadthDecimalVarRecs;
var
  Value: Variant;
  Rate: Currency;
  RawRate: Int64;
  Fraction: Double;
  LabelText: UnicodeString;
begin
  Value := OpaqueI(65000000117);
  RawRate := OpaqueI(-57219);
  Move(RawRate, Rate, SizeOf(Rate));
  Fraction := OpaqueD(-8.125);
  LabelText := 'decimal'#0'carrier';
  Check(BreadthReadDecimalVarRecs(OpaqueI(81000000008), OpaqueD(1.25), [Value, Rate, Pointer(nil), Fraction, LabelText],
    OpaqueI(-73000000009)) = 64999942898, 'breadth-decimal-varrecs-computes-from-exact-variant-and-currency');
  Check((VarType(Value) = varInt64) and (Int64(Value) = 65000000117) and (LabelText = 'decimal'#0'carrier'),
    'breadth-decimal-varrecs-leaves-managed-caller-values-intact');
end;
