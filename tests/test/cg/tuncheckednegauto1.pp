{ %CPU=x86_64 }
{ %OPT=-O3 }
program tuncheckednegauto1;

{$mode delphi}
{$Q-}

function NegateUInt64(Value: UInt64): UInt64;
begin
  Result := -Value;
end;

begin
  If NegateUInt64(High(UInt64)) <> UInt64(1) then
    Halt(1);
end.
