program id_mixed;

{ Identity-gate workload: floating point, variant records, nested routines,
  pointers, with-statements, sets. }

{$mode delphi}

type
  TVR = record
    case Byte of
      0: (I: Int64);
      1: (D: Double);
  end;

  TRec = record
    A, B: Integer;
  end;

  TDays = set of 0..30;

function Nested(seed: Integer): Integer;
var
  x: Integer;

  procedure Bump;
  begin
    x := x + seed;
  end;

begin
  x := 1;
  Bump;
  Bump;
  Result := x;
end;

var
  u: TVR;
  r: TRec;
  p: PInteger;
  d: Double;
  s: TDays;
  acc, i: Integer;
begin
  u.D := 2.5;
  d := 0.0;
  for i := 1 to 16 do
    d := d + u.D / i;
  r.A := 3;
  with r do
    B := A * 7;
  p := @r.A;
  p^ := p^ + 1;
  s := [1, 3, 5];
  Include(s, 7);
  acc := 0;
  for i := 0 to 30 do
    if i in s then
      acc := acc + i;
  WriteLn('mixed:', u.I, ':', Round(d * 1000), ':', r.A, ':', r.B, ':',
    acc, ':', Nested(5));
end.
