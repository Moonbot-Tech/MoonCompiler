{ %OPT=-O3 -OoAUTOINLINE }
program tautoinline2;

{$mode delphi}
{$Q-}

function MulStep(A, B: UInt64): UInt64;
begin
  Result := A * B;
end;

function AddStep(A, B: UInt64): UInt64;
begin
  Result := A + B;
end;

function SubStep(A, B: UInt64): UInt64;
begin
  Result := A - B;
end;

begin
  if MulStep(UInt64($CBF29CE484222325), UInt64($100000001B3)) <>
     UInt64($AF63BD4C8601B7DF) then
    Halt(1);
  if AddStep(UInt64($FFFFFFFFFFFFFFF0), UInt64($35)) <>
     UInt64($25) then
    Halt(2);
  if SubStep(UInt64($10), UInt64($35)) <>
     UInt64($FFFFFFFFFFFFFFDB) then
    Halt(3);
end.
