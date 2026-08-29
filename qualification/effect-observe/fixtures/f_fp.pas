unit f_fp;

{ Real arithmetic: the FP environment is observable (masks and MXCSR flags),
  so no real operation is unconditionally trap-free - including the
  zero-trip loop body form. }

interface

function FpAdd(a, b: Double): Double;
function FpZeroTrip(n: Integer; x: Double): Double;

implementation

// EXPECT: proc=FpAdd r=L w=L ie=t reason=fp_environment
function FpAdd(a, b: Double): Double;
begin
  Result := a + b;
end;

// EXPECT: proc=FpZeroTrip ie=t reason=fp_environment
function FpZeroTrip(n: Integer; x: Double): Double;
var
  s: Double;
  i: Integer;
begin
  s := 0.0;
  i := 0;
  while i < n do
    begin
      s := s + x * x;
      i := i + 1;
    end;
  Result := s;
end;

end.
