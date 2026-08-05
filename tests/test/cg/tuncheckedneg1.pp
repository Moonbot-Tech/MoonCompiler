{ %CPU=x86_64 }
program tuncheckedneg1;

{$mode delphi}
{$Q-}

uses
  uuncheckedneg1;

function NegateUInt64(Value: UInt64): UInt64; noinline;
begin
  Result := -Value;
end;

begin
  if -UInt64($8000000000000000) <> Low(Int64) then
    Halt(1);
  if NegateUInt64($8000000000000000) <> UInt64($8000000000000000) then
    Halt(2);
  if NegateUInt64(High(UInt64)) <> UInt64(1) then
    Halt(3);
  if NegateUInt64(1) <> High(UInt64) then
    Halt(4);
  if -UInt64(0) <> 0 then
    Halt(5);
  if -UInt32($FFFFFFFF) <> Int64(-4294967295) then
    Halt(6);
  if -Byte(255) <> -255 then
    Halt(7);
  if CrossNegateUInt64(High(UInt64)) <> UInt64(1) then
    Halt(8);
end.
