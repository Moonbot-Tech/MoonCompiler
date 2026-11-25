{ Form validation needs Unicode scalar categories at UTF-16 offsets. }

procedure RunBreadthUnicodeFormValue;
const
  Input: UnicodeString = 'x' + #$D801#$DC00 + #$D835#$DFE0 + #$0301 + #$00A0 + '!';
var
  UpperIndex, DigitIndex: Integer;
  Number: Double;
begin
  UpperIndex := Integer(OpaqueI(2));
  DigitIndex := Integer(OpaqueI(4));
  Check(TCharacter.IsLetter(Input, UpperIndex) and TCharacter.IsUpper(Input, UpperIndex)
    and (TCharacter.GetUnicodeCategory(Input, UpperIndex) = TUnicodeCategory.ucUppercaseLetter),
    'breadth-unicode-form-recognizes-supplementary-letter-at-high-surrogate');
  Number := TCharacter.GetNumericValue(Input, DigitIndex);
  Check(TCharacter.IsDigit(Input, DigitIndex) and (Number = 8),
    'breadth-unicode-form-decodes-supplementary-decimal-digit');
  Check((TCharacter.GetUnicodeCategory(Input, 6) = TUnicodeCategory.ucNonSpacingMark)
    and not TCharacter.IsLetter(Input, 6), 'breadth-unicode-form-classifies-combining-mark-separately-from-letters');
  Check(TCharacter.IsWhiteSpace(Input, 7) and not TCharacter.IsWhiteSpace(Input, 8),
    'breadth-unicode-form-detects-nonbreaking-space-before-punctuation');
  Mix(UInt64(Trunc(Number)));
end;
