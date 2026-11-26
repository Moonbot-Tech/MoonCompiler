program resstr_single_char;

{ A resourcestring made of one character outside ASCII is a WideChar
  constant; it used to be rejected with "Illegal expression". }
{$mode unleashed}

resourcestring
  SHangul = '예';
  SLatin = 'é';
  SAscii = 'Y';
  STwo = '예요';

begin
  WriteLn(Length(SHangul), ' ', Ord(SHangul[1]));
  WriteLn(Length(SLatin), ' ', Ord(SLatin[1]));
  WriteLn(Length(SAscii), ' ', Ord(SAscii[1]));
  WriteLn(Length(STwo), ' ', Ord(STwo[1]), ' ', Ord(STwo[2]));
end.
