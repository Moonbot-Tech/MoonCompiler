program tw41827;

{$mode delphi}

uses
  TypInfo;

const
  DirectValue = UInt64(8358680908399640578);
  ProductValue = UInt64(2) * UInt64(4179340454199820289);

begin
  if PTypeInfo(TypeInfo(DirectValue))^.Name <> 'QWord' then
    Halt(1);
  if PTypeInfo(TypeInfo(ProductValue))^.Name <> 'QWord' then
    Halt(2);
end.
