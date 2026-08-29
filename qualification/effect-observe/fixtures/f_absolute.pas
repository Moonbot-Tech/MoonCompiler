unit f_absolute;

{ absolute/variant-record overlays: the frontend does NOT mark the overlay
  target as address-taken, so the model itself must resolve the overlay to
  the target symbol - both classify as the same exact local. }

interface

function AbsOverlay(v: Integer): Integer;
function VarRec(d: Double): Int64;

implementation

// the overlay resolves to X: reads and writes stay exact-local (the same
// symbol on both names - conflicts are exact sym-vs-sym), no refusal reason
// EXPECT: proc=AbsOverlay r=L w=L reasons=-
function AbsOverlay(v: Integer): Integer;
var
  X: Integer;
  B: array[0..3] of Byte absolute X;
begin
  X := v;
  B[0] := 1;
  Result := B[3] + X;
end;

// variant-record fields share one base symbol: exact sym-vs-sym conflict,
// no special reason needed
// EXPECT: proc=VarRec r=L w=L reasons=-
function VarRec(d: Double): Int64;
var
  u: record
    case Byte of
      0: (I: Int64);
      1: (D: Double);
  end;
begin
  u.D := d;
  Result := u.I;
end;

end.
