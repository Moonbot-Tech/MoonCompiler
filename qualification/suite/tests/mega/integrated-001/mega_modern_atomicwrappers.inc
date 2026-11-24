{$define BREADTH_HAS_TYPED_INTERLOCKED}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    {$undef BREADTH_HAS_TYPED_INTERLOCKED}
  {$endif}
{$endif}

{$ifdef BREADTH_HAS_TYPED_INTERLOCKED}
{ The Delphi-facing wrappers lower class and floating values to atomic bits. }

type
  TBreadthAtomicToken = class
    Id: Int64;
  end;

procedure RunBreadthAtomicObjects;
var
  First, Second, Old: TBreadthAtomicToken;
  Slots: array[-1..1] of TBreadthAtomicToken;
  Index: Integer;
begin
  First := TBreadthAtomicToken.Create;
  try
    Second := TBreadthAtomicToken.Create;
    try
      First.Id := OpaqueI(94000000011);
      Second.Id := OpaqueI(-79000000019);
      Slots[-1] := Second;
      Slots[0] := First;
      Slots[1] := nil;
      Index := Integer(OpaqueI(0));
      Old := TInterlocked.CompareExchange<TBreadthAtomicToken>(Slots[Index], nil, Second);
      Check((Old = First) and (Slots[0] = First), 'breadth-interlocked-typed-cas-stale-identity-leaves-slot');
      Old := TInterlocked.CompareExchange<TBreadthAtomicToken>(Slots[Index], Second, First);
      Check((Old = First) and (Slots[0] = Second), 'breadth-interlocked-typed-cas-return-is-previous-object');
      Old := TInterlocked.Exchange<TBreadthAtomicToken>(Slots[Index], nil);
      Check((Old = Second) and (Old.Id = -79000000019) and (Slots[0] = nil) and (Slots[-1] = Second)
        and (Slots[1] = nil), 'breadth-interlocked-typed-exchange-updates-only-selected-slot');
      Mix(UInt64(Old.Id));
    finally
      Second.Free;
    end;
  finally
    First.Free;
  end;
end;

procedure RunBreadthAtomicFloating;
const
  MinusZeroBits = UInt64($8000000000000000);
  NaNBits = UInt64($7FF8000000000071);
var
  Slot, NegativeZero, QuietNaN, Old: Double;
  Bits: UInt64;
begin
  Bits := OpaqueU(MinusZeroBits);
  Move(Bits, NegativeZero, SizeOf(Bits));
  Bits := OpaqueU(NaNBits);
  Move(Bits, QuietNaN, SizeOf(Bits));
  Slot := NegativeZero;
  Old := TInterlocked.CompareExchange(Slot, QuietNaN, OpaqueD(0.0));
  Check((DoubleBits(Old) = MinusZeroBits) and (DoubleBits(Slot) = MinusZeroBits),
    'breadth-interlocked-float-cas-distinguishes-zero-signs');
  Old := TInterlocked.CompareExchange(Slot, QuietNaN, NegativeZero);
  Check((DoubleBits(Old) = MinusZeroBits) and (DoubleBits(Slot) = NaNBits),
    'breadth-interlocked-float-cas-keeps-nan-payload');
  Old := TInterlocked.Exchange(Slot, OpaqueD(2.5));
  Check((DoubleBits(Old) = NaNBits) and (Slot = 2.5), 'breadth-interlocked-float-exchange-returns-original-bits');
  Mix(DoubleBits(Old));
end;
{$endif}
