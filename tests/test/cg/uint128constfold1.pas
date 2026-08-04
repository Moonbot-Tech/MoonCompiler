unit uint128constfold1;

{$mode delphi}

interface

const
  UInt128Direct = UInt128(6);
  UInt128Product = UInt128(2) * UInt128(3);
  UInt128Sum = UInt128(2) + UInt128(4);
  UInt128Difference = UInt128(9) - UInt128(3);
  UInt128Bitwise = UInt128(6) xor UInt128(3);
  UInt128Division = UInt128(21) div UInt128(4);
  UInt128Modulo = UInt128(21) mod UInt128(4);
  UInt128Shift = UInt128(1) shl 100;
  UInt128TopBit = UInt128(1) shl 127;

  Int128Direct = Int128(-6);
  Int128Product = Int128(-2) * Int128(3);
  Int128Sum = Int128(-8) + Int128(2);
  Int128Difference = Int128(-3) - Int128(3);
  Int128Division = Int128(-21) div Int128(4);
  Int128Modulo = Int128(-21) mod Int128(4);
  Int128Shift = Int128(1) shl 100;

  UntypedProduct = 2 * 3;

  UInt128OperandNegation = -UInt128(6);
  Int128Negation = -Int128(6);

implementation

end.
