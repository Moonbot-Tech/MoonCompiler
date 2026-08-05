{ %CPU=x86_64 }
program tuncheckedneg2;

{$mode delphi}
{$Q-}

uses
  uuncheckedneg1;

const
  FoldedInt64: Int64 = -Int64(Low(Int64));
  FoldedInt128: Int128 = -Int128(Low(Int128));

function NegateInt64(Value: Int64): Int64; noinline;
begin
  Result := -Value;
end;

function NegateInt128(Value: Int128): Int128; noinline;
begin
  Result := -Value;
end;

begin
  if -Int64(Low(Int64)) <> Low(Int64) then
    Halt(1);
  if NegateInt64(Low(Int64)) <> Low(Int64) then
    Halt(2);
  if FoldedInt64 <> Low(Int64) then
    Halt(3);

  if -Int64(High(Int64)) <> -High(Int64) then
    Halt(4);
  if -Int64(0) <> 0 then
    Halt(5);

  if -Int128(Low(Int128)) <> Low(Int128) then
    Halt(6);
  if NegateInt128(Low(Int128)) <> Low(Int128) then
    Halt(7);
  if FoldedInt128 <> Low(Int128) then
    Halt(8);
  if CrossFoldedInt64 <> Low(Int64) then
    Halt(9);
  if CrossNegateInt64(Low(Int64)) <> Low(Int64) then
    Halt(10);
  if CrossFoldedInt128 <> Low(Int128) then
    Halt(11);
  if CrossNegateInt128(Low(Int128)) <> Low(Int128) then
    Halt(12);
end.
