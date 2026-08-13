program Fpc41678RangechecksOffEnum;

{$mode delphi}
{$rangechecks off}

type
  TEnum = (First, Second, Third);

var
  Value: TEnum;
begin
  for Value := Low(TEnum) to TEnum(10) do
    if Ord(Value) = -1 then
      Break;
end.
