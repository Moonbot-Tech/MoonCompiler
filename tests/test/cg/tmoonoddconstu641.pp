{ %OPT=-O2 }
program tmoonoddconstu641;

{$mode delphi}

const
  HighBitEven = UInt64($8000000000000000);
  HighBitOdd = UInt64($8000000000000001);

var
  RuntimeValue: UInt64;
begin
  if Odd(HighBitEven) then
    Halt(1);
  if not Odd(HighBitOdd) then
    Halt(2);
  if not Odd(High(UInt64)) then
    Halt(3);
  if Odd(UInt64(0)) then
    Halt(4);
  if not Odd(Int64(-1)) then
    Halt(5);
  if Odd(Int64(-2)) then
    Halt(6);

  RuntimeValue := HighBitOdd;
  if not Odd(RuntimeValue) then
    Halt(7);
end.
