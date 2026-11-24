{ Scalar conversion uses a UTF-16 code-unit offset and rejects incomplete pairs. }

procedure RunBreadthUnicodeScalar;
var
  Scalar, Text: UnicodeString;
  Rejected: Boolean;
begin
  Scalar := TCharacter.ConvertFromUtf32(Cardinal(OpaqueI($10FFFF)));
  Check((Length(Scalar) = 2) and (Ord(Scalar[1]) = $DBFF) and (Ord(Scalar[2]) = $DFFF),
    'breadth-unicode-scalar-encodes-maximum-codepoint-as-pair');
  Text := 'A'#0 + Scalar + 'B';
  Check(TCharacter.IsSurrogatePair(Text, 3) and (TCharacter.ConvertToUtf32(Text, 3) = $10FFFF),
    'breadth-unicode-scalar-decodes-pair-after-embedded-nul');
  Check((not TCharacter.IsSurrogatePair(Text, 2)) and (TCharacter.ConvertToUtf32(Text, 2) = 0),
    'breadth-unicode-scalar-treats-embedded-nul-as-one-code-unit');

  Rejected := False;
  try
    Scalar := TCharacter.ConvertFromUtf32(Cardinal(OpaqueI($D800)));
  except
    on EArgumentException do Rejected := True;
  end;
  Check(Rejected and (Scalar = #$DBFF#$DFFF), 'breadth-unicode-scalar-rejects-surrogate-codepoint-before-changing-result');
end;
