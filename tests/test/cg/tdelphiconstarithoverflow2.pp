{ %FAIL }
program tdelphiconstarithoverflow2;

{$mode delphi}
{$Q-}

var
  Value: UInt64;

begin
  Value := High(Int64) + 1;
  if Value = 0 then
    Halt(1);
end.
