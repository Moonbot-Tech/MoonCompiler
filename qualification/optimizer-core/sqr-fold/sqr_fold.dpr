program sqr_fold;
{ x*x of a real x without real effects is folded into sqr(x): x is evaluated
  once and squared in the register it was loaded into, so the loop of Variance
  multiplies without a copy (run_sqr_fold_gate.py).  An exception of x is
  raised by its evaluation in both forms; an operand with a real effect - a
  call, a volatile read - is still evaluated twice. }
{$mode delphi}
uses
  SysUtils;

const
  W = 256;

var
  Series: array of Double;
  Calls: Integer;
  Shared: Double;

function Variance(A: Integer; Mean: Double): Double;
var
  I: Integer;
  Sum: Double;
begin
  Sum := 0;
  for I := 0 to W - 1 do begin
    Series[A * W + I] := Series[A * W + I] - Mean;
    Sum := Sum + Series[A * W + I] * Series[A * W + I];
  end;
  Result := Sum;
end;

{$R+}
function CheckedSquare(I: Integer): Double;
begin
  Result := Series[I] * Series[I];
end;
{$R-}

function Next: Double;
begin
  Inc(Calls);
  Result := Calls;
end;

function VolatileSquare: Double;
begin
  Result := Volatile(Shared) * Volatile(Shared);
end;

var
  I: Integer;
  V: Double;
  Raised: Boolean;
begin
  SetLength(Series, 2 * W);
  for I := 0 to High(Series) do
    Series[I] := I and 7;
  { (k - 3.5)^2 over k = 0..7 is 42, 32 times }
  If Variance(1, 3.5) <> 32 * 42.0 then
    Halt(1);
  If CheckedSquare(3) <> 9 then
    Halt(2);
  Raised := False;
  try
    CheckedSquare(2 * W);
  except
    on ERangeError do
      Raised := True;
  end;
  If not Raised then
    Halt(3);
  Calls := 0;
  V := Next * Next;
  If (Calls <> 2) or (V <> 2) then
    Halt(4);
  Shared := 3;
  If VolatileSquare <> 9 then
    Halt(5);
  Writeln('SQR_FOLD_PASS');
end.
