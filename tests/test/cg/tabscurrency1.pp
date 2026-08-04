{ %OPT=-O2 }
program tabscurrency1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

var
  A, AbsoluteA: Currency;
  State: UInt64;
  Raw, Got, Expected: Int64;
  I: Integer;
begin
  { Abs must operate directly on the scaled currency value: a
    /10000 * 10000 round trip through the fpu is not exact for values
    that have no exact binary representation and breaks Abs(A) = A. }
  A := 3.1415;
  if Abs(-A) <> A then
    Halt(1);
  if Abs(A) <> A then
    Halt(2);
  if Abs(A) <> 3.1415 then
    Halt(3);

  { Near the Currency range boundary the scaled value needs the full
    64-bit mantissa: a detour through Double would already be inexact. }
  A := 922337203685477.0;
  if Abs(-A) <> A then
    Halt(4);

  A := 0;
  if Abs(A) <> 0 then
    Halt(5);

  { Exercise the complete 64-bit representation, not just decimal values
    convenient to write in source. Currency is a signed Int64 scaled by
    10000, so its absolute value has an independent exact integer oracle. }
  State := UInt64($9E3779B97F4A7C15);
  for I := 1 to 100000 do
    begin
      State := State xor (State shl 13);
      State := State xor (State shr 7);
      State := State xor (State shl 17);
      Move(State,Raw,SizeOf(Raw));
      if Raw=Low(Int64) then
        Inc(Raw);
      Move(Raw,A,SizeOf(A));
      AbsoluteA:=Abs(A);
      Move(AbsoluteA,Got,SizeOf(Got));
      if Raw<0 then
        Expected:=-Raw
      else
        Expected:=Raw;
      if Got<>Expected then
        begin
          WriteLn('FAIL iteration=',I,' raw=',Raw,' got=',Got,
            ' expected=',Expected);
          Halt(6);
        end;
    end;
end.
