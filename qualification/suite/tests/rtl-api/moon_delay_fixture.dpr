library moon_delay_fixture;
{$mode delphi}{$H+}
type
  TFour = record A, B, C, D: Int64; end;
function Weighted(A, B, C, D, E, F: Int64): Int64; stdcall;
begin
  Result := A + B * 2 + C * 3 + D * 4 + E * 5 + F * 6;
end;
function Mixed(A: Double; B: Int64; C: Double; D: Int64; E: Double): Double; stdcall;
begin
  Result := A + B * 2 + C * 3 + D * 4 + E * 5;
end;
function Four(A, B, C, D: Int64): TFour; stdcall;
begin
  Result.A := A; Result.B := B; Result.C := C; Result.D := D;
end;
function Race(A, B, C, D, E, F: Int64): Int64; stdcall;
begin
  Result := Weighted(A, B, C, D, E, F);
end;
exports
  Weighted name 'Weighted', Mixed name 'Mixed', Four name 'Four', Race name 'Race',
  Weighted index 7 name 'ByOrdinal';
begin
end.
