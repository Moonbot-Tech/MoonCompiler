program tw41827;

{ The Delphi 12.2 domain of folded UInt64 arithmetic, measured through an
  overload probe: an explicit cast keeps the unsigned type, but arithmetic
  over two explicitly typed UInt64 constants folds into the signed Int64
  domain - DCC resolves the UInt64*UInt64 product to the Int64 overload.
  An earlier repair preserved UInt64 through folding in every mode and this
  test pinned that; the DCC probe refuted it, the preservation was removed
  again for the 64-bit types (it stays for Int128/UInt128, which have no
  Delphi domain to disagree with), and this test now pins the restored
  Delphi behavior. }

{$mode delphi}

uses
  TypInfo;

const
  DirectValue = UInt64(8358680908399640578);
  ProductValue = UInt64(2) * UInt64(4179340454199820289);

begin
  if PTypeInfo(TypeInfo(DirectValue))^.Name <> 'QWord' then
    Halt(1);
  if PTypeInfo(TypeInfo(ProductValue))^.Name <> 'Int64' then
    Halt(2);
end.
