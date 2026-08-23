program tdelphirawbyteconst1;

{$ifdef FPC}
  {$mode delphiunicode}
  {$codepage utf8}
{$endif}
{$h+}

const
  ByteEf = AnsiChar($ef);
  ByteBb = AnsiChar($bb);
  ByteBf = AnsiChar($bf);
  Bom: RawByteString =
    AnsiChar($ef) + AnsiChar($bb) + AnsiChar($bf);
  Pair: RawByteString = AnsiChar($80) + AnsiChar($ff);
  NestedLeft: RawByteString =
    (AnsiChar($ef) + AnsiChar($bb)) + AnsiChar($bf);
  NestedRight: RawByteString =
    AnsiChar($ef) + (AnsiChar($bb) + AnsiChar($bf));
  NamedBom: RawByteString = ByteEf + ByteBb + ByteBf;
  MixedBom: RawByteString = #$ef + AnsiChar($bb) + AnsiChar($bf);
  EdgeText: RawByteString =
    AnsiChar('A') + AnsiChar($80) + AnsiChar('Z');

procedure Fail(Code: Integer);
begin
  Halt(Code);
end;

procedure CheckBytes(const Value: RawByteString; const Expected: array of Byte;
  Code: Integer);
var
  I: Integer;
begin
  if Length(Value) <> Length(Expected) then
    Fail(Code);
  for I := 0 to High(Expected) do
    if Byte(Value[I + 1]) <> Expected[I] then
      Fail(Code + I + 1);
end;

begin
  CheckBytes(Bom, [$ef, $bb, $bf], 10);
  CheckBytes(Pair, [$80, $ff], 20);
  CheckBytes(NestedLeft, [$ef, $bb, $bf], 30);
  CheckBytes(NestedRight, [$ef, $bb, $bf], 40);
  CheckBytes(NamedBom, [$ef, $bb, $bf], 50);
  CheckBytes(MixedBom, [$ef, $bb, $bf], 60);
  CheckBytes(EdgeText, [$41, $80, $5a], 70);
  WriteLn('PASS mormot-rawbytestring-bom-const');
end.
