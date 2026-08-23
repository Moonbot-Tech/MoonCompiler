program unicode_conversion;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
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
  Result:=ScalarString(CodePoint);
end;

procedure CheckAscii;
var
  I,J: Integer;
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
  for I:=0 to 33 do
    begin
    SetLength(Raw,I);
    SetLength(Text,I);
    for J:=1 to I do
      begin
      Text[J]:=UnicodeChar(32+((J*37) mod 95));
      Raw[J]:=AnsiChar(Byte(Text[J]));
      end;
    Check(UTF8Encode(Text)=Raw,'ASCII vector boundary '+IntToStr(I));
    end;
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
  Check(UTF8Encode(Text)='A'+RawBytes([$ef,$bf,$bd])+'B'+
    RawBytes([$ef,$bf,$bd])+'C','unpaired surrogates use replacement character');
end;

procedure CheckInvalidUtf8;
begin
  Check(UTF8Decode(RawBytes([$80]))=UnicodeChar($fffd),
    'isolated continuation');
  Check(UTF8Decode(RawBytes([$c0,$af]))=UnicodeChar($fffd)+UnicodeChar($fffd),
    'overlong two-byte form');
  Check(UTF8Decode(RawBytes([$e0,$80,$80]))=
    UnicodeChar($fffd)+UnicodeChar($fffd),'overlong three-byte form');
  Check(UTF8Decode(RawBytes([$ed,$a0,$80]))=
    UnicodeChar($fffd)+UnicodeChar($fffd),'encoded surrogate');
  Check(UTF8Decode(RawBytes([$f4,$90,$80,$80]))=
    UnicodeChar($fffd)+UnicodeChar($fffd)+UnicodeChar($fffd),
    'above Unicode range');
  Check(UTF8Decode(RawBytes([$e2,$82]))=UnicodeChar($fffd),
    'incomplete sequence');
  Check(UTF8Decode('A'+RawBytes([$80])+'B')='A'+UnicodeChar($fffd)+'B',
    'invalid byte in text');
end;

procedure CheckMixedFallback;
var
  Expected: RawByteString;
  I: Integer;
  Prefix: UnicodeString;
  Text: UnicodeString;
begin
  Text:='ascii-prefix-'+ScalarString($1f680)+'-ascii-suffix';
  Expected:=RawByteString('ascii-prefix-')+ScalarUtf8($1f680)+
    RawByteString('-ascii-suffix');
  Check(UTF8Encode(Text)=Expected,'mixed fallback encode');
  Check(UTF8Decode(Expected)=Text,'mixed fallback decode');
  Check(StringCodePage(UTF8Encode(Text))=CP_UTF8,
    'mixed fallback code page');

  for I:=0 to 17 do
    begin
    Prefix:=StringOfChar('a',I);
    Text:=Prefix+UnicodeChar($20ac)+'z';
    Expected:=RawByteString(Prefix)+RawBytes([$e2,$82,$ac])+'z';
    Check(UTF8Encode(Text)=Expected,'chunk boundary encode '+IntToStr(I));
    Check(UTF8Decode(Expected)=Text,'chunk boundary decode '+IntToStr(I));
    end;

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

procedure CheckInvariantCase;
var
  Converted, ExpectedLower, ExpectedUpper, Mixed, Original, Source,
    Unchanged: UnicodeString;
  I: Integer;
begin
  Check(LowerCase('')='','empty lowercase');
  Check(UpperCase('')='','empty uppercase');
  Mixed:='aAzZ09'+UnicodeChar($0100)+UnicodeChar($042F);
  Check(LowerCase(Mixed)='aazz09'+UnicodeChar($0100)+UnicodeChar($042F),
    'lowercase changes ASCII only');
  Check(UpperCase(Mixed)='AAZZ09'+UnicodeChar($0100)+UnicodeChar($042F),
    'uppercase changes ASCII only');
  Unchanged:=UnicodeChar($0100)+UnicodeChar($042F)+'-09';
  Check(LowerCase(Unchanged)=Unchanged,'lowercase unchanged Unicode');
  Check(UpperCase(Unchanged)=Unchanged,'uppercase unchanged Unicode');

  SetLength(Source,65536);
  SetLength(ExpectedLower,65536);
  SetLength(ExpectedUpper,65536);
  for I:=0 to 65535 do
    begin
    Source[I+1]:=UnicodeChar(I);
    if (I>=Ord('A')) and (I<=Ord('Z')) then
      ExpectedLower[I+1]:=UnicodeChar(I xor $20)
    else
      ExpectedLower[I+1]:=UnicodeChar(I);
    if (I>=Ord('a')) and (I<=Ord('z')) then
      ExpectedUpper[I+1]:=UnicodeChar(I xor $20)
    else
      ExpectedUpper[I+1]:=UnicodeChar(I);
    end;
  Check(LowerCase(Source)=ExpectedLower,'lowercase exhaustive UTF-16');
  Check(UpperCase(Source)=ExpectedUpper,'uppercase exhaustive UTF-16');

  Original:='already-lowercase-0123';
  Converted:=LowerCase(Original);
  Check(Pointer(Converted)<>Pointer(Original),'lowercase owns its result');
  PWideChar(Converted)^:='X';
  Check(Original[1]='a','lowercase result does not alias its input');

  Check(CompareText('aZ','Az')=0,'CompareText ASCII case folding');
  Check(CompareText('a','aa')<0,'CompareText shorter prefix');
  Check(CompareText('aa','a')>0,'CompareText longer prefix');
  Check(CompareText(UnicodeChar($0100),UnicodeChar($0200))<0,
    'CompareText preserves high Unicode byte');
  Check(CompareText(UnicodeChar($0200),UnicodeChar($0100))>0,
    'CompareText preserves reverse high Unicode byte');
  Check(CompareText(UnicodeChar($0141)+'a',UnicodeChar($0141)+'A')=0,
    'CompareText folds ASCII after non-ASCII');
end;

procedure CheckOrdinalComparison;
var
  A, B: UnicodeString;
begin
  Check(UnicodeCompareStr('','')=0,'ordinal both empty');
  Check(UnicodeCompareStr('','a')<0,'ordinal empty first');
  Check(UnicodeCompareStr('a','')>0,'ordinal empty second');
  Check(UnicodeCompareStr('prefix','prefix')=0,'ordinal equal');
  Check(UnicodeCompareStr('prefix','prefix-a')<0,'ordinal shorter prefix');
  Check(UnicodeCompareStr('prefix-a','prefix')>0,'ordinal longer prefix');
  Check(UnicodeCompareStr('abcdX','abcdY')<0,'ordinal qword mismatch');
  Check(UnicodeCompareStr('abcdefX','abcdefY')<0,'ordinal tail mismatch');
  Check(UnicodeCompareStr(UnicodeChar($00ff),UnicodeChar($0100))<0,
    'ordinal compares UTF-16 code units');
  Check(UnicodeCompareStr(UnicodeChar($d800),UnicodeChar($e000))<0,
    'ordinal compares surrogate code units');

  A:='ab'+UnicodeChar(0)+'x';
  B:='ab'+UnicodeChar(0)+'y';
  Check(UnicodeCompareStr(A,B)<0,'ordinal embedded NUL');
  Check(not UnicodeSameStr(A,B),'same-str embedded NUL mismatch');
  B:=A;
  Check(UnicodeSameStr(A,B),'same-str embedded NUL equal');
end;

function ExplicitAnsiConcatSeed(Seed: Integer): AnsiString;
begin
  { Keep the explicit ASCII literal conversion next to a non-constant
    conversion.  On POSIX this used to ask the compiler host for a reverse
    Unicode map even though ASCII needs no mapping, and crashed the compiler
    before code generation. }
  Result:=AnsiString('a')+AnsiString(IntToStr(Seed));
end;

begin
  try
    CheckAscii;
    CheckBoundaries;
    CheckInvalidUtf8;
    CheckMixedFallback;
    CheckRandomScalars;
    CheckInvariantCase;
    CheckOrdinalComparison;
    Check(ExplicitAnsiConcatSeed(7)='a7',
      'explicit ANSI literal and runtime concat');
    WriteLn('UNICODE_CONVERSION_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
