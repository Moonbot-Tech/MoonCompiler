{ %OPT=-O3 }
program tbyteboolor1;

{$mode delphi}

var
  LeftValue: ByteBool;
  RightValue: ByteBool;
  RuntimeZero: Byte = 0;

function Opaque(Value: Byte): Byte;
begin
  Result := Value xor RuntimeZero;
end;

begin
  Byte(LeftValue) := Opaque($C8);
  Byte(RightValue) := Opaque($37);
  If Byte(LeftValue or RightValue) <> 1 then Halt(1);
end.
