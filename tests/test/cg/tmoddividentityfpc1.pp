{ %OPT=-O3 }
program tmoddividentityfpc1;

{$mode objfpc}

function Kind(Value: Byte): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: NativeInt): Byte; overload;
begin
  Result := 2;
end;

var
  B: Byte;
begin
  B := 7;
  If Kind(B div 1) <> 1 then Halt(1);
  If Kind(B mod 1) <> 1 then Halt(2);
  If (B div 1) <> 7 then Halt(3);
  If (B mod 1) <> 0 then Halt(4);
end.
