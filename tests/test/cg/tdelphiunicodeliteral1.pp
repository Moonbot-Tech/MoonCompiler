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
  ByteSet: set of AnsiChar = ['a', #10, #$85];
  ByteTable: array[0..3] of AnsiChar = ('a', #10, '$', #$85);
var
  ByteChar: AnsiChar;
  ByteString: AnsiString;
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
end.
