unit uuncheckedneg1;

{$mode delphi}
{$Q-}

interface

const
  CrossFoldedInt64: Int64 = -Int64(Low(Int64));
  CrossFoldedInt128: Int128 = -Int128(Low(Int128));

function CrossNegateUInt64(Value: UInt64): UInt64; noinline;
function CrossNegateInt64(Value: Int64): Int64; noinline;
function CrossNegateInt128(Value: Int128): Int128; noinline;

implementation

function CrossNegateUInt64(Value: UInt64): UInt64;
begin
  Result := -Value;
end;

function CrossNegateInt64(Value: Int64): Int64;
begin
  Result := -Value;
end;

function CrossNegateInt128(Value: Int128): Int128;
begin
  Result := -Value;
end;

end.
