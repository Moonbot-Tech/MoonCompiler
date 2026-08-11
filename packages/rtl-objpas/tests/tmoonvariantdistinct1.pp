{ %OPT=-O2 }
program tmoonvariantdistinct1;

{$mode delphi}

uses
  Variants;

type
  TFirst = type Int64;
  TSecond = type TFirst;

var
  Source: Variant;
  Value: TSecond;
begin
  Source := Int64(42);
  Value := Source;
  if Int64(Value) <> 42 then
    Halt(1);
end.
