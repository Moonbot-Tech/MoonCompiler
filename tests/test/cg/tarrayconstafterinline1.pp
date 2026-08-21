{ %OPT=-O3 }
program tarrayconstafterinline1;

{$mode delphi}

function GuardedLookup(V: Integer): Integer;
const
  Primes: array[0..15] of Integer =
    (101, 103, 107, 109, 113, 127, 131, 137,
     139, 149, 151, 157, 163, 167, 173, 179);
begin
  if (V >= 0) and (V <= 15) then
    Result := Primes[V]
  else
    Result := -1;
end;

function Expected(V: Integer): Integer;
begin
  case V of
    0: Result := 101;
    1: Result := 103;
    2: Result := 107;
    3: Result := 109;
    4: Result := 113;
    5: Result := 127;
    6: Result := 131;
    7: Result := 137;
    8: Result := 139;
    9: Result := 149;
    10: Result := 151;
    11: Result := 157;
    12: Result := 163;
    13: Result := 167;
    14: Result := 173;
    15: Result := 179;
  else
    Result := -1;
  end;
end;

var
  V: Integer;
begin
  for V := -1100 to 1100 do
    if GuardedLookup(V) <> Expected(V) then
      Halt(1);
end.
