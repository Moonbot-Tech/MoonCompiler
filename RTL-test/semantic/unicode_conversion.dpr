program unicode_conversion;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('UNICODE_CONVERSION_FAIL: '+AMessage);
end;

function RawBytes(const Values: array of Byte): RawByteString;
var
  I: Integer;
begin
  SetLength(Result,Length(Values));
  for I:=0 to High(Values) do
    Result[I+1]:=AnsiChar(Values[I]);
end;

function ScalarString(CodePoint: Cardinal): UnicodeString;
begin
  if CodePoint<=$ffff then
    begin
    SetLength(Result,1);
    Result[1]:=UnicodeChar(CodePoint);
    end
  else
    begin
    Dec(CodePoint,$10000);
    SetLength(Result,2);
    Result[1]:=UnicodeChar($d800+(CodePoint shr 10));
    Result[2]:=UnicodeChar($dc00+(CodePoint and $3ff));
    end;
end;

function ScalarUtf8(CodePoint: Cardinal): RawByteString;
begin
  if CodePoint<=$7f then
    Result:=RawBytes([CodePoint])
  else if CodePoint<=$7ff then
    Result:=RawBytes([$c0 or (CodePoint shr 6),
      $80 or (CodePoint and $3f)])
  else if CodePoint<=$ffff then
    Result:=RawBytes([$e0 or (CodePoint shr 12),
      $80 or ((CodePoint shr 6) and $3f),$80 or (CodePoint and $3f)])
  else
    Result:=RawBytes([$f0 or (CodePoint shr 18),
      $80 or ((CodePoint shr 12) and $3f),
      $80 or ((CodePoint shr 6) and $3f),$80 or (CodePoint and $3f)]);
end;

function DecodedScalar(CodePoint: Cardinal): UnicodeString;
begin
  if (CodePoint=$fffe) or (CodePoint=$ffff) then
    Result:='?'
  else
    Result:=ScalarString(CodePoint);
end;

procedure CheckAscii;
var
  I: Integer;
  Raw: RawByteString;
  Text: UnicodeString;
begin
  SetLength(Raw,128);
  SetLength(Text,128);
  for I:=0 to 127 do
    begin
    Raw[I+1]:=AnsiChar(I);
    Text[I+1]:=UnicodeChar(I);
    end;
  Check(UTF8Encode('')='','empty encode');
  Check(UTF8Decode('')='','empty decode');
  Check(UTF8Encode(Text)=Raw,'all ASCII encode including NUL');
  Check(UTF8Decode(Raw)=Text,'all ASCII decode including NUL');
  Check(StringCodePage(UTF8Encode(Text))=CP_UTF8,'UTF-8 code page');
end;

procedure CheckBoundaries;
const
  Scalars: array[0..14] of Cardinal = (
    0,$7f,$80,$7ff,$800,$d7ff,$e000,$ffff,$10000,$10001,$1ffff,$fffff,
    $10fffd,$10fffe,$10ffff);
var
  I: Integer;
  Encoded, Expected: RawByteString;
  Text: UnicodeString;
begin
  for I:=Low(Scalars) to High(Scalars) do
    begin
    Text:=ScalarString(Scalars[I]);
    Expected:=ScalarUtf8(Scalars[I]);
    Encoded:=UTF8Encode(Text);
    Check(Encoded=Expected,'boundary encode '+IntToHex(Scalars[I],6));
    Check(UTF8Decode(Encoded)=DecodedScalar(Scalars[I]),
      'boundary decode '+IntToHex(Scalars[I],6));
    end;
  Text:='A'+UnicodeChar($d800)+'B'+UnicodeChar($dc00)+'C';
  Check(UTF8Encode(Text)='ABC','unpaired surrogates are omitted');
end;

procedure CheckInvalidUtf8;
begin
  Check(UTF8Decode(RawBytes([$80]))='?','isolated continuation');
  Check(UTF8Decode(RawBytes([$c0,$af]))='?','overlong two-byte form');
  Check(UTF8Decode(RawBytes([$e0,$80,$80]))='?','overlong three-byte form');
  Check(UTF8Decode(RawBytes([$ed,$a0,$80]))='?','encoded surrogate');
  Check(UTF8Decode(RawBytes([$f4,$90,$80,$80]))='?','above Unicode range');
  Check(UTF8Decode(RawBytes([$e2,$82]))='?','incomplete sequence');
  Check(UTF8Decode('A'+RawBytes([$80])+'B')='A?B','invalid byte in text');
end;

procedure CheckMixedFallback;
var
  Expected: RawByteString;
  I: Integer;
  Text: UnicodeString;
begin
  Text:='ascii-prefix-'+ScalarString($1f680)+'-ascii-suffix';
  Expected:=RawByteString('ascii-prefix-')+ScalarUtf8($1f680)+
    RawByteString('-ascii-suffix');
  Check(UTF8Encode(Text)=Expected,'mixed fallback encode');
  Check(UTF8Decode(Expected)=Text,'mixed fallback decode');
  Check(StringCodePage(UTF8Encode(Text))=CP_UTF8,
    'mixed fallback code page');

  SetLength(Text,4096);
  for I:=1 to Length(Text) do
    Text[I]:=UnicodeChar(32+(I mod 95));
  Check(UTF8Decode(UTF8Encode(Text))=Text,'long ASCII round trip');
end;

procedure CheckRandomScalars;
var
  CodePoint: Cardinal;
  Encoded, Expected: RawByteString;
  I: Integer;
  State: QWord;
  Text: UnicodeString;
begin
  State:=$9e3779b97f4a7c15;
  for I:=1 to 20000 do
    begin
    State:=State xor (State shl 13);
    State:=State xor (State shr 7);
    State:=State xor (State shl 17);
    CodePoint:=State mod $110000;
    if (CodePoint>=$d800) and (CodePoint<=$dfff) then
      Inc(CodePoint,$800);
    if CodePoint>$10ffff then
      Dec(CodePoint,$110000);
    Text:=ScalarString(CodePoint);
    Expected:=ScalarUtf8(CodePoint);
    Encoded:=UTF8Encode(Text);
    Check(Encoded=Expected,'random encode '+IntToHex(CodePoint,6));
    Check(UTF8Decode(Encoded)=DecodedScalar(CodePoint),
      'random decode '+IntToHex(CodePoint,6));
    end;
end;

begin
  try
    CheckAscii;
    CheckBoundaries;
    CheckInvalidUtf8;
    CheckMixedFallback;
    CheckRandomScalars;
    WriteLn('UNICODE_CONVERSION_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
