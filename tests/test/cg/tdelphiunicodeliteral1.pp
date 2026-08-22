program tdelphiunicodeliteral1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

function CharKind(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function CharKind(const Value: Char): Byte; overload;
begin
  Result := 2;
end;

function StringKind(const Value: AnsiString): Byte; overload;
begin
  Result := 1;
end;

function StringKind(const Value: UnicodeString): Byte; overload;
begin
  Result := 2;
end;

function CharOrRaw(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function CharOrRaw(const Value: RawByteString): Byte; overload;
begin
  Result := 2;
end;

function CharOrUnicode(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function CharOrUnicode(const Value: UnicodeString): Byte; overload;
begin
  Result := 2;
end;

function WideOrRaw(const Value: WideChar): Byte; overload;
begin
  Result := 1;
end;

function WideOrRaw(const Value: RawByteString): Byte; overload;
begin
  Result := 2;
end;

function ReturnWide(Value: WideChar): WideChar;
begin
  Result := Value;
end;

function VarRecKind(const Values: array of const): Byte;
begin
  Result := Values[0].VType;
end;

function ByteClass(Value: AnsiChar): Byte;
begin
  case Value of
    'a'..'z': Result := 1;
    '_', '$': Result := 2;
  else
    Result := 0;
  end;
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

const
  Part = 'a';
  WidePart = #$2603;
  ByteSet: set of AnsiChar = ['a', #10, #$85];
  ByteTable: array[0..3] of AnsiChar = ('a', #10, '$', #$85);
var
  ByteChar: AnsiChar;
  ByteString: AnsiString;
  Wide: WideChar;
begin
  Check(CharKind('a') = 2, 1);
  Check(CharKind(Chr(97)) = 2, 2);
  Check(CharKind(#$0061) = 2, 3);
  Check(CharKind(#$044F) = 2, 14);
  Check(StringKind('ab') = 2, 4);
  Check(StringKind('a' + 'b') = 2, 5);
  Check(StringKind(Part + 'b') = 2, 6);
  Check(VarRecKind(['a']) = vtWideChar, 7);
  Check(('a' in ByteSet) and (#10 in ByteSet) and (#$85 in ByteSet), 8);
  ByteChar := AnsiChar('a');
  ByteString := AnsiString('ab');
  Check(CharKind(ByteChar) = 1, 9);
  Check(StringKind(ByteString) = 1, 10);
  Check(ByteClass('a') = 1, 11);
  Check(ByteClass('$') = 2, 12);
  Check(ByteClass(AnsiChar(#$E0)) = 0, 13);
  Check((ByteTable[0] = 'a') and (ByteTable[1] = #10) and
    (ByteTable[2] = '$') and (ByteTable[3] = #$85), 15);
  Check(CharOrRaw(#0) = 1, 16);
  Check(CharOrRaw('A') = 1, 17);
  Check(CharOrRaw(#$FF) = 1, 18);
  Check(CharOrRaw(#$100) = 1, 19);
  Check(CharOrRaw(#$2603) = 1, 20);
  Check(CharOrRaw(WidePart) = 1, 21);
  Check(CharOrRaw(Chr(65)) = 1, 22);
  Check(CharOrUnicode(#0) = 1, 23);
  Check(CharOrUnicode(#$2603) = 1, 24);
  Check(WideOrRaw(#0) = 1, 25);
  Check(WideOrRaw(#$2603) = 1, 26);
  Wide := #$2603;
  Check(CharOrRaw(Wide) = 2, 27);
  Check(CharOrRaw(ReturnWide(Wide)) = 2, 28);
  Check(WideOrRaw(Wide) = 1, 29);
end.
