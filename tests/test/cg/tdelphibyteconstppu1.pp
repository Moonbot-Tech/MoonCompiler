program tdelphibyteconstppu1;

{$mode delphiunicode}
{$codepage cp1251}

uses
  udelphibyteconstppu1;

type
  TAnsi1251 = type AnsiString(1251);
  TUtf8 = type AnsiString(65001);

procedure CheckBytes(const Value: RawByteString;
  const Expected: array of Byte; Code: Byte);
var
  I: Integer;
begin
  if Length(Value) <> Length(Expected) then
    Halt(Code);
  for I := 0 to High(Expected) do
    if Byte(Value[I + 1]) <> Expected[I] then
      Halt(Code);
end;

var
  A1251: TAnsi1251;
  U8: TUtf8;
  Raw: RawByteString;
begin
  CheckBytes(RawByteString(ByteConst), [$85], 1);
  CheckBytes(RawByteString(MixedConst), [$58, $85, $59], 2);
  CheckBytes(RawByteString('X' + #$85 + 'Y'), [$58, $85, $59], 3);

  Raw := MixedConst;
  CheckBytes(Raw, [$58, $85, $59], 4);

  A1251 := MixedConst;
  CheckBytes(A1251, [$58, $85, $59], 5);

  U8 := MixedConst;
  CheckBytes(U8, [$58, $E2, $80, $A6, $59], 6);

  if (Byte(ByteTable[0]) <> $58) or
     (Byte(ByteTable[1]) <> $85) or
     (Byte(ByteTable[2]) <> $59) then
    Halt(7);
end.
