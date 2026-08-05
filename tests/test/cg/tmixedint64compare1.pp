{ %OPT=-O3 }
program tmixedint64compare1;

{$mode delphi}

var
  RuntimeZero: Int64 = 0;

function Signed(Value: Int64): Int64;
begin
  Result := Value xor RuntimeZero;
end;

function Unsigned(Value: UInt64): UInt64;
begin
  Result := Value xor UInt64(RuntimeZero);
end;

var
  I: Int64;
  U: UInt64;
begin
  I := Signed(-1);
  U := Unsigned(UInt64(1) shl 63);
  If not (I < U) then Halt(1);
  If not (U > I) then Halt(2);
  If I = U then Halt(3);
  If not (I <> U) then Halt(4);

  I := Signed(0);
  U := Unsigned(0);
  If I <> U then Halt(5);
  If I < U then Halt(6);
  If I > U then Halt(7);

  I := Signed(High(Int64));
  U := Unsigned(UInt64(High(Int64)) + 1);
  If not (I < U) then Halt(8);
  If not (U > I) then Halt(9);

  I := Signed(-1);
  U := Unsigned(High(UInt64));
  If I = U then Halt(10);
  If not (I < U) then Halt(11);
end.
