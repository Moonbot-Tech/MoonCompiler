program math_random_overloads_semantic;

{$mode delphiunicode}

uses
  Math;

var
  D: Double;
  I: Integer;
  I64: Int64;
  W: Word;
  RandomD: array[0..2] of Double;
  RandomI: array[0..2] of Integer;
  RandomI64: array[0..2] of Int64;
  RandomW: array[0..2] of Word;

begin
  RandomD[0] := 1.5;
  RandomD[1] := 2.5;
  RandomD[2] := 3.5;
  RandomI[0] := 1;
  RandomI[1] := 2;
  RandomI[2] := 3;
  RandomI64[0] := 4;
  RandomI64[1] := 5;
  RandomI64[2] := 6;
  RandomW[0] := 7;
  RandomW[1] := 8;
  RandomW[2] := 9;
  D := RandomFrom(RandomD);
  I := RandomFrom(RandomI);
  I64 := RandomFrom(RandomI64);
  W := RandomFrom(RandomW);
  If not ((D >= 1.5) and (D <= 3.5) and
    (I >= 1) and (I <= 3) and
    (I64 >= 4) and (I64 <= 6) and
    (W >= 7) and (W <= 9)) then
    Halt(1);
  WriteLn('MATH_RANDOM_OVERLOADS_PASS');
end.
