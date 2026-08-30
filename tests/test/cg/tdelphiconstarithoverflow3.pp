program tdelphiconstarithoverflow3;

{$mode delphi}
{$Q-}

const
  ExplicitUnsigned = UInt64(High(Int64)) + UInt64(1);

begin
  if ExplicitUnsigned <> UInt64($8000000000000000) then
    Halt(1);
end.
