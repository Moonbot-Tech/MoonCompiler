{ modf returns a floating fraction and writes its integral half into packed storage. }

{$ifdef MSWINDOWS}
function BreadthCModf(Value: Double; out Whole: Double): Double; cdecl; external 'msvcrt.dll' name 'modf';
{$else}
function BreadthCModf(Value: Double; out Whole: Double): Double; cdecl; external 'm' name 'modf';
{$endif}

procedure RunBreadthCFloatSplit;
var
  Frame: packed record
    Before: Byte;
    Whole: Double;
    After: Word;
  end;
  Fraction: Double;
begin
  Frame.Before := $A3;
  Frame.After := $FAC4;
  Frame.Whole := OpaqueD(123.25);
  Fraction := BreadthCModf(OpaqueD(-0.25), Frame.Whole);
  Check((DoubleBits(Fraction) = UInt64($BFD0000000000000)) and (DoubleBits(Frame.Whole) = UInt64($8000000000000000)),
    'breadth-c-modf-preserves-negative-zero-in-packed-out-slot');
  Fraction := BreadthCModf(OpaqueD(18000000000.375), Frame.Whole);
  Check((Fraction = 0.375) and (Frame.Whole = 18000000000.0), 'breadth-c-modf-returns-fraction-and-wide-integral-part');
  Check((Frame.Before = $A3) and (Frame.After = $FAC4), 'breadth-c-modf-width-preserves-packed-neighbors');
end;
