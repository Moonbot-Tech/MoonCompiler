{ %CPU=i386,x86_64 }
{ %OPT=-O2 -OoNOREGVAR }

program tconstsnoregvar1;

{$mode objfpc}

type
  TField = array of Double;

function Idx(X, Y, N: Integer): Integer;
begin
  Result := X + (N + 2) * Y;
end;

procedure Advect(var Dst: TField; const Src, VelU, VelV: TField; N: Integer);
var
  X, Y, I0, I1, J0, J1: Integer;
  Fx, Fy, S0, S1, T0, T1: Double;
begin
  for Y := 1 to N do
    for X := 1 to N do
    begin
      Fx := X - VelU[Idx(X, Y, N)];
      Fy := Y - VelV[Idx(X, Y, N)];
      if Fx < 0.5 then
        Fx := 0.5;
      if Fx > N + 0.5 then
        Fx := N + 0.5;
      if Fy < 0.5 then
        Fy := 0.5;
      if Fy > N + 0.5 then
        Fy := N + 0.5;
      I0 := Trunc(Fx);
      I1 := I0 + 1;
      J0 := Trunc(Fy);
      J1 := J0 + 1;
      S1 := Fx - I0;
      S0 := 1 - S1;
      T1 := Fy - J0;
      T0 := 1 - T1;
      Dst[Idx(X, Y, N)] :=
        S0 * (T0 * Src[Idx(I0, J0, N)] + T1 * Src[Idx(I0, J1, N)]) +
        S1 * (T0 * Src[Idx(I1, J0, N)] + T1 * Src[Idx(I1, J1, N)]);
    end;
end;

var
  Dst, Src, Vel: TField;
  I: Integer;
begin
  SetLength(Dst, 100);
  SetLength(Src, 100);
  SetLength(Vel, 100);
  for I := 0 to High(Src) do
    Src[I] := I + 0.25;
  Advect(Dst, Src, Vel, Vel, 8);
  for I := 0 to High(Src) do
    if (I mod 10 >= 1) and (I mod 10 <= 8) and
       (I div 10 >= 1) and (I div 10 <= 8) and
       (Dst[I] <> Src[I]) then
      Halt(1);
end.
