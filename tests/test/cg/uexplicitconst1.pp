unit uexplicitconst1;

{$mode delphi}

interface

const
  UntypedOne = 1;
  Untyped256 = 256;
  ExplicitByteOne = Byte(1);
  ExplicitSmallIntOne = SmallInt(1);
  UntypedNegOne = -1;
  ExplicitShortNegOne = ShortInt(-1);
  TypedShortNegOne: ShortInt = -1;
  UntypedPlusOne = +1;
  TypedPlusOne: Byte = +1;

implementation

end.
