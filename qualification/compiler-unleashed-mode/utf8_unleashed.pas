program utf8_unleashed;

{ No BOM and no -Fc: unleashed mode reads the source as UTF-8. }
{$mode unleashed}

var
  S: string = '한글';

begin
  WriteLn(Length(S), ' ', Ord(S[1]), ' ', Ord(S[2]));
end.
