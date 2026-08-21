program tobjfpcliteralcastoverload1;

{$mode objfpc}
{$h+}

type
  TCP1251 = type AnsiString(1251);

function CharKind(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function CharKind(const Value: WideChar): Byte; overload;
begin
  Result := 2;
end;

function Pick(const Value: Integer): Byte; overload;
begin
  Result := 1;
end;

function Pick(const Value: Cardinal): Byte; overload;
begin
  Result := 2;
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Native: TCP1251;
  Converted: UTF8String;
  Small: Byte;
begin
  Check(CharKind('a') = 1, 1);
  Small := 7;
  Check(Pick(Small) = 2, 2);

  SetLength(Native, 2);
  Native[1] := AnsiChar($C6);
  Native[2] := AnsiChar($E8);
  Converted := UTF8String(Native);
  Check(Pointer(Converted) <> Pointer(Native), 3);
  Check((Length(Converted) = 4) and
    (Byte(Converted[1]) = $D0) and (Byte(Converted[2]) = $96) and
    (Byte(Converted[3]) = $D0) and (Byte(Converted[4]) = $B8), 4);
  Check(StringCodePage(Converted) = 65001, 5);
end.
