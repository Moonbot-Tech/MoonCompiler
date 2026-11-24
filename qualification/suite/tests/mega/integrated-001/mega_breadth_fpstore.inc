{ Unaligned FP fields updated across an observer and a rejected second write. }

type
  TBreadthCharge = packed record
    Prefix: Byte;
    Balance: Double;
    Revision: Word;
    Remainder: Single;
    Suffix: Byte;
  end;
  TBreadthChargeReview = procedure(const Charge: TBreadthCharge; var ReviewCode: Integer; Reject: Boolean);

procedure BreadthReviewCharge(const Charge: TBreadthCharge; var ReviewCode: Integer; Reject: Boolean);
begin
  If (DoubleBits(Charge.Balance) = UInt64($4022800000000000)) and (Charge.Remainder = -4.25)
    and (Charge.Revision = $D317) then
    ReviewCode := 73;
  If Reject then
    raise EAbort.Create('charge rejected');
end;

procedure BreadthUpdateCharge(var Charge: TBreadthCharge; Factor: Double; var ReviewCode: Integer; Reject: Boolean;
  Review: TBreadthChargeReview);
var
  NextRemainder: Single;
begin
  NextRemainder := Charge.Remainder + Factor;
  Charge.Balance := Charge.Balance - Factor * 1.5;
  try
    Review(Charge, ReviewCode, Reject);
    Charge.Remainder := NextRemainder;
  finally
    Inc(Charge.Revision);
  end;
end;

procedure RunBreadthPackedFloatStore;
var
  Reject: Boolean;
  Caught: Boolean;
  Charge: TBreadthCharge;
  ReviewCode: Integer;
  RemainderBits: UInt32;
begin
  for Reject := False to True do begin
    Charge.Prefix := $BC;
    Charge.Balance := OpaqueD(13.0);
    Charge.Revision := $D317;
    Charge.Remainder := OpaqueD(-4.25);
    Charge.Suffix := $AC;
    ReviewCode := 0;
    Caught := False;
    try
      BreadthUpdateCharge(Charge, OpaqueD(2.5), ReviewCode, Reject, BreadthReviewCharge);
    except
      on E: EAbort do Caught := E.Message = 'charge rejected';
    end;
    Check((ReviewCode = 73) and (Caught = Reject), 'breadth-packed-float-observer-sees-only-committed-store');
    Check((DoubleBits(Charge.Balance) = UInt64($4022800000000000)) and (Charge.Revision = $D318),
      'breadth-packed-float-charge-and-finally-stores-preserved');
    Move(Charge.Remainder, RemainderBits, SizeOf(RemainderBits));
    If Reject then
      Check(RemainderBits = UInt32($C0880000), 'breadth-packed-float-rejected-update-leaves-prior-single')
    else
      Check(RemainderBits = UInt32($BFE00000), 'breadth-packed-float-successful-update-stores-new-single');
    Check((Charge.Prefix = $BC) and (Charge.Suffix = $AC), 'breadth-packed-float-stores-respect-field-widths');
    Mix(UInt64(RemainderBits));
  end;
end;
