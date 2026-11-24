{ Packed Comp lanes retain integer precision across a mixed cdecl call and return. }

type
  TBreadthCompDelta = packed record
    Guard: Byte;
    Delta, Remainder: Comp;
  end;
  TBreadthCompCall = function(Left: Comp; Salt: Int64; Right: Comp; Mask: Integer): TBreadthCompDelta; cdecl;

function BreadthCompPacket(Left: Comp; Salt: Int64; Right: Comp; Mask: Integer): TBreadthCompDelta; cdecl;
begin
  Result.Guard := Byte(Salt xor Mask);
  Result.Delta := Left + Right;
  Result.Remainder := Left - Result.Delta;
end;

procedure RunBreadthCompPacket;
type
  TCompCase = record
    LeftBits, RightBits, Salt, Delta, Remainder: Int64;
    Mask: Integer;
    Guard: Byte;
  end;
const
  Cases: array[0..1] of TCompCase = (
    (LeftBits: 1152921504606846993; RightBits: -1152921504606846989; Salt: 177;
      Delta: 4; Remainder: 1152921504606846989; Mask: 11; Guard: 186),
    (LeftBits: -1152921504606847005; RightBits: 1152921504606846987; Salt: -21;
      Delta: -18; Remainder: -1152921504606846987; Mask: 113; Guard: 154));
var
  Transform: TBreadthCompCall;
  Left, Right: Comp;
  Actual: TBreadthCompDelta;
  Raw, DeltaBits, RemainderBits: Int64;
  Sample: TCompCase;
begin
  Check(SizeOf(TBreadthCompDelta) = 17, 'breadth-packed-comp-result-width');
  Transform := BreadthCompPacket;
  for Sample in Cases do begin
    Raw := OpaqueI(Sample.LeftBits);
    Move(Raw, Left, SizeOf(Raw));
    Raw := OpaqueI(Sample.RightBits);
    Move(Raw, Right, SizeOf(Raw));
    Actual := Transform(Left, OpaqueI(Sample.Salt), Right, Integer(OpaqueI(Sample.Mask)));
    Move(Actual.Delta, DeltaBits, SizeOf(DeltaBits));
    Move(Actual.Remainder, RemainderBits, SizeOf(RemainderBits));
    Check(DeltaBits = Sample.Delta, 'breadth-packed-comp-arithmetic-retains-small-cancellation-residue');
    Check((RemainderBits = Sample.Remainder) and (Actual.Guard = Sample.Guard), 'breadth-packed-comp-return-keeps-unrounded-large-lane');
    Mix(UInt64(DeltaBits) xor UInt64(RemainderBits));
  end;
end;
