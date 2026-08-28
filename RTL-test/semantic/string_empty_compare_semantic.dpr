program string_empty_compare_semantic;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}

uses
  SysUtils;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
  begin
    WriteLn('FAIL ', MessageText);
    Halt(1);
  end;
end;

procedure CheckRaw(const Value: RawByteString);
begin
  Check(not (Value = ''), 'RawByteString = empty');
  Check(Value <> '', 'RawByteString <> empty');
  Check(not ('' = Value), 'empty = RawByteString');
  Check('' <> Value, 'empty <> RawByteString');
end;

procedure CheckUtf8(const Value: UTF8String);
begin
  Check(not (Value = ''), 'UTF8String = empty');
  Check(Value <> '', 'UTF8String <> empty');
  Check(not ('' = Value), 'empty = UTF8String');
  Check('' <> Value, 'empty <> UTF8String');
end;

procedure CheckUnicode(const Value: UnicodeString);
begin
  Check(not (Value = ''), 'UnicodeString = empty');
  Check(Value <> '', 'UnicodeString <> empty');
  Check(not ('' = Value), 'empty = UnicodeString');
  Check('' <> Value, 'empty <> UnicodeString');
end;

procedure CheckWide(const Value: WideString);
begin
  Check(not (Value = ''), 'WideString = empty');
  Check(Value <> '', 'WideString <> empty');
  Check(not ('' = Value), 'empty = WideString');
  Check('' <> Value, 'empty <> WideString');
end;

procedure CheckShort(const Value: ShortString);
begin
  Check(not (Value = ''), 'ShortString = empty');
  Check(Value <> '', 'ShortString <> empty');
  Check(not ('' = Value), 'empty = ShortString');
  Check('' <> Value, 'empty <> ShortString');
end;

var
  Raw: RawByteString;
  Utf8: UTF8String;
  Unicode: UnicodeString;
  Wide: WideString;
  Short: ShortString;
begin
  Raw := '';
  Check(Raw = '', 'empty RawByteString');
  Check('' = Raw, 'empty literal = RawByteString');
  SetLength(Raw, 1);
  Raw[1] := #0;
  CheckRaw(Raw);
  SetLength(Raw, 1);
  Raw[1] := AnsiChar($ff);
  CheckRaw(Raw);

  Utf8 := '';
  Check(Utf8 = '', 'empty UTF8String');
  Check('' = Utf8, 'empty literal = UTF8String');
  Utf8 := UTF8String(#$c3#$a9);
  CheckUtf8(Utf8);
  Unicode := '';
  Check(Unicode = '', 'empty UnicodeString');
  Check('' = Unicode, 'empty literal = UnicodeString');
  Unicode := #$0416;
  CheckUnicode(Unicode);
  Wide := '';
  Check(Wide = '', 'empty WideString');
  Check('' = Wide, 'empty literal = WideString');
  Wide := #$0416;
  CheckWide(Wide);
  Short := '';
  Check(Short = '', 'empty ShortString');
  Check('' = Short, 'empty literal = ShortString');
  Short := #$ff;
  CheckShort(Short);
  WriteLn('STRING_EMPTY_COMPARE_OK');
end.
