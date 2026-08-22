program tdelphibytestringcast1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

{$if defined(FPC) and defined(UNIX)}
uses
  cwstring;
{$endif}

type
  TCP1251 = type AnsiString(1251);
  TCP866 = type AnsiString(866);

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Native: TCP1251;
  CastUtf8: UTF8String;
  AssignedUtf8: UTF8String;
  Cast866: TCP866;
  Raw: RawByteString;
begin
  SetLength(Native, 2);
  Native[1] := AnsiChar($C6);
  Native[2] := AnsiChar($E8);
  Check(StringCodePage(Native) = 1251, 1);

  CastUtf8 := UTF8String(Native);
  Check(Pointer(CastUtf8) = Pointer(Native), 2);
  Check((Length(CastUtf8) = 2) and
    (Byte(CastUtf8[1]) = $C6) and (Byte(CastUtf8[2]) = $E8), 3);
  Check(StringCodePage(CastUtf8) = 1251, 4);

  Cast866 := TCP866(Native);
  Check(Pointer(Cast866) = Pointer(Native), 5);
  Check((Length(Cast866) = 2) and
    (Byte(Cast866[1]) = $C6) and (Byte(Cast866[2]) = $E8), 6);
  Check(StringCodePage(Cast866) = 1251, 7);

  Raw := RawByteString(Native);
  Check(Pointer(Raw) = Pointer(Native), 8);
  Check((Length(Raw) = 2) and
    (Byte(Raw[1]) = $C6) and (Byte(Raw[2]) = $E8), 9);
  Check(StringCodePage(Raw) = 1251, 10);

  AssignedUtf8 := Native;
  Check(Pointer(AssignedUtf8) <> Pointer(Native), 11);
  Check((Length(AssignedUtf8) = 4) and
    (Byte(AssignedUtf8[1]) = $D0) and (Byte(AssignedUtf8[2]) = $96) and
    (Byte(AssignedUtf8[3]) = $D0) and (Byte(AssignedUtf8[4]) = $B8), 12);
  Check(StringCodePage(AssignedUtf8) = 65001, 13);
end.
