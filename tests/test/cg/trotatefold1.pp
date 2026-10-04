program trotatefold1;

{$mode delphi}
{$Q-}

function RotateLeft(Value: UInt64; Count: Int64): UInt64; noinline;
begin
  Result:=(Value shl Count) or (Value shr (64-Count));
end;

function RotateRight(Value: UInt64; Count: Int64): UInt64; noinline;
begin
  Result:=(Value shr Count) or (Value shl (64-Count));
end;

begin
  if (RotateLeft($0123456789ABCDEF,1)<>$02468ACF13579BDE) or
     (RotateLeft($0123456789ABCDEF,8)<>$23456789ABCDEF01) or
     (RotateLeft($0123456789ABCDEF,63)<>$8091A2B3C4D5E6F7) then
    Halt(1);
  if (RotateRight($0123456789ABCDEF,1)<>$8091A2B3C4D5E6F7) or
     (RotateRight($0123456789ABCDEF,8)<>$EF0123456789ABCD) or
     (RotateRight($0123456789ABCDEF,63)<>$02468ACF13579BDE) then
    Halt(2);
end.
