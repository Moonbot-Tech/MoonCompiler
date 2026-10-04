program encoding_utf8_semantic;

{ TEncoding.UTF8 and the RTL's UTF-8 conversions it rests on.  The decoder is
  the RTL's Utf8ToUnicode on every target, not the code page manager, so the
  answer is the same on Windows and Linux and does not depend on a manager
  being installed.  Checked here: round trips against UTF8Encode/UTF8Decode,
  the exact replacement of every shape of invalid input with U+FFFD (the shape
  Windows' MultiByteToWideChar gave before the decoder changed), GetCharCount
  against the length GetString produces, spans, a BOM as data, GetChars into a
  caller's array leaving the elements behind the text alone, and the encoder's
  plain-ASCII run against text of every length around its four-character step,
  including a destination too small for the text. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif UNIX}
  SysUtils;

var
  Failures: Integer = 0;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
  begin
    Inc(Failures);
    WriteLn(ErrOutput, 'ENCODING_UTF8_FAIL: ', MessageText);
  end;
end;

function BytesOf(const Values: array of Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I] := Values[I];
end;

function Units(const Values: array of Word): UnicodeString;
var
  I: Integer;
begin
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I + 1] := WideChar(Values[I]);
end;

function Raw(const B: TBytes): RawByteString;
begin
  SetLength(Result, Length(B));
  If Length(B) > 0 then
    Move(B[0], Result[1], Length(B));
end;

procedure Invalid(const What: string; const B: TBytes; const Want: UnicodeString);
var
  Got: UnicodeString;
begin
  Got := TEncoding.UTF8.GetString(B);
  Check(Got = Want, 'invalid input: ' + What);
  Check(TEncoding.UTF8.GetCharCount(B) = Length(Got), 'count against decode: ' + What);
end;

procedure CheckRoundTrips;
var
  Samples: array[0..4] of UnicodeString;
  S: UnicodeString;
  B: TBytes;
  I: Integer;
begin
  Samples[0] := '';
  Samples[1] := 'GET /api/v3/ticker?symbol=BTCUSDT';
  Samples[2] := Units([$0411, $0438, $0440, $0436, $0430, $0020, $0416, $0436]);
  Samples[3] := 'price=' + Units([$20AC]) + '42' + Units([$D83D, $DE00]) + 'end';
  Samples[4] := '';
  for I := 1 to 8 do
    Samples[4] := Samples[4] + Samples[1];
  for I := 0 to High(Samples) do
  begin
    S := Samples[I];
    B := TEncoding.UTF8.GetBytes(S);
    Check(Raw(B) = UTF8Encode(S), 'GetBytes against UTF8Encode: ' + S);
    Check(TEncoding.UTF8.GetByteCount(S) = Length(B), 'GetByteCount: ' + S);
    Check(TEncoding.UTF8.GetString(B) = S, 'round trip: ' + S);
    Check(TEncoding.UTF8.GetCharCount(B) = Length(S), 'GetCharCount: ' + S);
    Check(UTF8Decode(Raw(B)) = S, 'UTF8Decode: ' + S);
  end;
end;

procedure CheckInvalidShapes;
const
  R = $FFFD;
begin
  Invalid('truncated 2-byte', BytesOf([$41, $D0]), Units([$41, R]));
  Invalid('truncated 3-byte', BytesOf([$41, $E0, $A4]), Units([$41, R]));
  Invalid('lone continuation', BytesOf([$41, $80, $42]), Units([$41, R, $42]));
  Invalid('overlong 2-byte', BytesOf([$41, $C0, $AF, $42]), Units([$41, R, R, $42]));
  Invalid('surrogate half', BytesOf([$41, $ED, $A0, $80, $42]), Units([$41, R, R, $42]));
  Invalid('above plane 16', BytesOf([$41, $F5, $80, $80, $80, $42]), Units([$41, R, R, R, R, $42]));
  Invalid('FF byte', BytesOf([$41, $FF, $42]), Units([$41, R, $42]));
  Invalid('3-byte cut by ASCII', BytesOf([$41, $E1, $80, $42]), Units([$41, R, $42]));
  Invalid('4-byte cut by ASCII', BytesOf([$41, $F0, $90, $42]), Units([$41, R, $42]));
  Invalid('overlong 3-byte', BytesOf([$41, $E0, $80, $80, $42]), Units([$41, R, R, $42]));
  Invalid('F4 above U+10FFFF', BytesOf([$41, $F4, $90, $80, $80, $42]), Units([$41, R, R, R, $42]));
  Invalid('C2 at the end', BytesOf([$41, $C2]), Units([$41, R]));
  Invalid('F0 at the end', BytesOf([$41, $F0]), Units([$41, R]));
  Invalid('continuation only', BytesOf([$80]), Units([R]));
  Invalid('NUL is data', BytesOf([$41, $00, $42]), Units([$41, $00, $42]));
  Invalid('bad byte after an ASCII run',
    BytesOf([$41, $42, $43, $44, $45, $46, $47, $48, $49, $FF, $4A]),
    Units([$41, $42, $43, $44, $45, $46, $47, $48, $49, R, $4A]));
end;

procedure CheckSpansAndArrays;
var
  B, CB: TBytes;
  Arr: TUnicodeCharArray;
  I: Integer;
  Cyr: UnicodeString;
begin
  Cyr := Units([$0411, $0438, $0440]);
  CB := TEncoding.UTF8.GetBytes(Cyr);
  Check(TEncoding.UTF8.GetString(CB, 0, 2) = Units([$0411]), 'span of one letter');
  Check(TEncoding.UTF8.GetString(CB, 0, 3) = Units([$0411, $FFFD]), 'span cutting a letter');
  Check(TEncoding.UTF8.GetString(CB, 2, 4) = Units([$0438, $0440]), 'span from a letter boundary');
  Check(TEncoding.UTF8.GetString(BytesOf([$EF, $BB, $BF, $41])) = Units([$FEFF, $41]), 'a BOM is data');
  Check(TEncoding.UTF8.GetString(BytesOf([])) = '', 'no bytes');

  B := TEncoding.UTF8.GetBytes(UnicodeString('GET /api'));
  SetLength(Arr, 8);
  for I := 0 to 7 do
    Arr[I] := 'z';
  Check(TEncoding.UTF8.GetChars(B, 0, 3, Arr, 1) = 3, 'GetChars into an array: count');
  Check((Arr[0] = 'z') and (Arr[1] = 'G') and (Arr[2] = 'E') and (Arr[3] = 'T'), 'GetChars into an array: text');
  for I := 4 to 7 do
    Check(Arr[I] = 'z', 'GetChars leaves the caller''s element ' + IntToStr(I) + ' alone');
  for I := 0 to 7 do
    Arr[I] := 'z';
  Check(TEncoding.UTF8.GetChars(CB, 0, 4, Arr, 0) = 2, 'GetChars of letters: count');
  for I := 2 to 7 do
    Check(Arr[I] = 'z', 'GetChars of letters leaves element ' + IntToStr(I) + ' alone');
end;

{ the encoder's plain-ASCII run steps four characters at a time: every length
  around the step, with the text breaking off into a letter at every place }
procedure CheckEncoderRun;
var
  L, K, Room: Integer;
  S: UnicodeString;
  Buf: array[0..63] of AnsiChar;
  Got: SizeUInt;
  Want: RawByteString;
begin
  for L := 0 to 21 do
    for K := 0 to L do
    begin
      S := StringOfChar(WideChar('a'), K) + StringOfChar(WideChar($0436), L - K);
      Check(Raw(TEncoding.UTF8.GetBytes(S)) = UTF8Encode(S),
        'ASCII run of ' + IntToStr(K) + ' in ' + IntToStr(L));
      Check(TEncoding.UTF8.GetByteCount(S) = K + 2 * (L - K),
        'counted ASCII run of ' + IntToStr(K) + ' in ' + IntToStr(L));
    end;
  { a destination too small: whole characters only, then the terminator, and
    nothing behind the room is written }
  for Room := 1 to 12 do
  begin
    FillChar(Buf, SizeOf(Buf), 'Z');
    S := 'abcdefgh' + Units([$0436]) + 'ij';
    Got := UnicodeToUtf8(@Buf[0], Room, PUnicodeChar(S), Length(S));
    Want := Copy(UTF8Encode(S), 1, Room - 1);
    If (Room - 1 = 9) then
      Want := Copy(Want, 1, 8);   { the two-byte letter does not fit a single byte }
    Check(Got = SizeUInt(Length(Want) + 1), 'UnicodeToUtf8 result for room ' + IntToStr(Room));
    Check(CompareMem(@Buf[0], PAnsiChar(Want), Length(Want)) and (Buf[Length(Want)] = #0),
      'UnicodeToUtf8 text for room ' + IntToStr(Room));
    Check(Buf[Room] = 'Z', 'UnicodeToUtf8 writes nothing behind room ' + IntToStr(Room));
  end;
end;

begin
  try
    CheckRoundTrips;
    CheckInvalidShapes;
    CheckSpansAndArrays;
    CheckEncoderRun;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
  If Failures <> 0 then
  begin
    WriteLn(ErrOutput, 'ENCODING_UTF8_FAILURES ', Failures);
    Halt(1);
  end;
  WriteLn('ENCODING_UTF8_PASS');
end.
