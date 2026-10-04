program inline_var_aliasing;

{$mode delphiunicode}
{$Q-}{$R-}

var
  RtZero: UInt64 = 0;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor RtZero);
end;

procedure Check(Condition: Boolean; const Name: AnsiString);
begin
  If not Condition then
  begin
    Writeln('FAIL ', Name);
    Halt(1);
  end;
end;

procedure Mangle(var A, B: Integer); inline;
begin
  A := A + B;
  B := B * 3;
  A := A - 1;
end;

procedure Tri(var A, B, C: Integer); inline;
begin
  A := A + 1;
  B := B * 2;
  C := C + A;
end;

var
  A: array[0..1] of Integer;
  P: PInteger;
  X, Y, Z: Integer;
begin
  X := Integer(OpaqueI(5));
  Mangle(X, X);
  Check(X = 29, 'pair');

  X := Integer(OpaqueI(3));
  Tri(X, X, X);
  Check(X = 16, 'triple');

  X := Integer(OpaqueI(3));
  Y := Integer(OpaqueI(5));
  Tri(X, Y, X);
  Check((X = 8) and (Y = 10), 'first-third');

  X := Integer(OpaqueI(3));
  Y := Integer(OpaqueI(5));
  Tri(X, X, Y);
  Check((X = 8) and (Y = 13), 'first-second');

  X := Integer(OpaqueI(3));
  Y := Integer(OpaqueI(5));
  Z := Integer(OpaqueI(7));
  Tri(X, Y, Z);
  Check((X = 4) and (Y = 10) and (Z = 11), 'distinct');

  A[1] := Integer(OpaqueI(3));
  Tri(A[1], A[1], A[1]);
  Check(A[1] = 16, 'array-element');

  X := Integer(OpaqueI(3));
  P := @X;
  Tri(P^, P^, P^);
  Check(X = 16, 'pointer-target');

  Writeln('INLINE_VAR_ALIASING_OK');
end.
