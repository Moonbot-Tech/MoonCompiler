{ %OPT=-Mdelphiunicode -O2 }
program tmoonunicodehotpaths1;

procedure Check(Condition: Boolean; Code: Byte);
begin
  if not Condition then
    Halt(Code);
end;

procedure CheckBytes(const Actual: RawByteString;
  const Expected: array of Byte; Code: Byte);
var
  I: SizeInt;
begin
  Check(Length(Actual) = Length(Expected), Code);
  for I := 0 to High(Expected) do
    Check(Byte(Actual[I + 1]) = Expected[I], Code);
end;

procedure CheckDecode;
var
  Bytes: RawByteString;
  Text: UnicodeString;
begin
  Check(UTF8Decode('') = '', 1);
  Check(UTF8Decode('plain ASCII') = 'plain ASCII', 2);

  Bytes := 'A' + #0 + 'B';
  Text := UTF8Decode(Bytes);
  Check((Length(Text) = 3) and (Text[1] = 'A') and
    (Text[2] = #0) and (Text[3] = 'B'), 3);

  Bytes := #$C2#$A2#$E2#$82#$AC#$F0#$9F#$98#$80;
  Text := UTF8Decode(Bytes);
  Check((Length(Text) = 4) and (Ord(Text[1]) = $00A2) and
    (Ord(Text[2]) = $20AC) and (Ord(Text[3]) = $D83D) and
    (Ord(Text[4]) = $DE00), 4);

  Bytes := 'prefix' + #$C3#$A9 + 'suffix';
  Check(UTF8Decode(Bytes) = 'prefix' + UnicodeChar($00E9) + 'suffix', 5);

  Check(UTF8Decode('1') = '1', 6);
  Check(UTF8Decode('12') = '12', 7);
  Check(UTF8Decode('123') = '123', 8);
  Check(UTF8Decode('1234') = '1234', 9);
  Check(UTF8Decode('12345') = '12345', 20);

  Bytes := #$C3#$A9 + 'abcde';
  Check(UTF8Decode(Bytes) = UnicodeChar($00E9) + 'abcde', 21);
  Bytes := 'abc' + #$C3#$A9 + 'de';
  Check(UTF8Decode(Bytes) = 'abc' + UnicodeChar($00E9) + 'de', 22);
  Bytes := 'abcde' + #$C3#$A9;
  Check(UTF8Decode(Bytes) = 'abcde' + UnicodeChar($00E9), 23);
end;

procedure CheckEncode;
var
  Text: UnicodeString;
  Bytes: RawByteString;
begin
  CheckBytes(UTF8Encode(UnicodeString('')), [], 30);
  CheckBytes(UTF8Encode(UnicodeString('1')), [$31], 31);
  CheckBytes(UTF8Encode(UnicodeString('12')), [$31, $32], 32);
  CheckBytes(UTF8Encode(UnicodeString('123')), [$31, $32, $33], 33);
  CheckBytes(UTF8Encode(UnicodeString('1234')), [$31, $32, $33, $34], 34);
  CheckBytes(UTF8Encode(UnicodeString('12345')),
    [$31, $32, $33, $34, $35], 35);

  Text := 'A' + UnicodeChar(#0) + 'B';
  Bytes := UTF8Encode(Text);
  Check((Length(Bytes) = 3) and (Bytes[1] = 'A') and
    (Bytes[2] = #0) and (Bytes[3] = 'B'), 36);

  Text := UnicodeChar($00A2) + UnicodeChar($20AC) +
    UnicodeChar($D83D) + UnicodeChar($DE00);
  CheckBytes(UTF8Encode(Text),
    [$C2, $A2, $E2, $82, $AC, $F0, $9F, $98, $80], 37);

  Text := UnicodeChar($00E9) + 'abcde';
  CheckBytes(UTF8Encode(Text), [$C3, $A9, $61, $62, $63, $64, $65], 38);
  Text := 'abc' + UnicodeChar($00E9) + 'de';
  CheckBytes(UTF8Encode(Text), [$61, $62, $63, $C3, $A9, $64, $65], 39);
  Text := 'abcde' + UnicodeChar($00E9);
  CheckBytes(UTF8Encode(Text), [$61, $62, $63, $64, $65, $C3, $A9], 40);
end;

procedure CheckPos;
var
  Source: UnicodeString;
begin
  Check(Pos('', 'abc') = 0, 10);
  Check(Pos('abcd', 'abc') = 0, 11);
  Check(Pos('a', 'abc', 0) = 0, 12);
  Check(Pos('a', 'abc', 2) = 0, 13);
  Check(Pos('b', 'abc', 2) = 2, 14);
  Check(Pos('aba', 'ababa') = 1, 15);
  Check(Pos('aba', 'ababa', 2) = 3, 16);

  Source := 'needle-1 needle-2 needle-3 needle-target';
  Check(Pos('needle-target', Source) = 28, 17);
  Check(Pos('needle-target', Source, 29) = 0, 18);

  Source := 'A' + UnicodeChar($03A9) + 'B' + UnicodeChar($03A9) + 'C';
  Check(Pos(UnicodeChar($03A9) + 'C', Source) = 4, 19);
end;

begin
  CheckEncode;
  CheckDecode;
  CheckPos;
end.
