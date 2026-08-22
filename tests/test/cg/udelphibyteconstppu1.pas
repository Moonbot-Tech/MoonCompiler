unit udelphibyteconstppu1;

{$mode delphiunicode}
{$codepage cp1251}

interface

const
  ByteConst = #$85;
  MixedConst = 'X' + #$85 + 'Y';
  ByteTable: array[0..2] of AnsiChar = 'X' + #$85 + 'Y';

implementation

end.
