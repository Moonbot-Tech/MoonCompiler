program integer_conversion;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

function ReferenceUnsigned(AValue: QWord): string;
var
  Buffer: array[0..19] of Char;
  First: Integer;
begin
  First:=Length(Buffer);
  repeat
    Dec(First);
    Buffer[First]:=Char(Ord('0')+(AValue mod 10));
    AValue:=AValue div 10;
  until AValue=0;
  SetLength(Result,Length(Buffer)-First);
  Move(Buffer[First],Result[1],Length(Result)*SizeOf(Char));
end;

function ReferenceSigned(AValue: Int64): string;
begin
  if AValue<0 then
    Result:='-'+ReferenceUnsigned(QWord(-(AValue+1))+1)
  else
    Result:=ReferenceUnsigned(AValue);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('INTEGER_CONVERSION_FAIL: '+AMessage);
end;

procedure CheckSigned(AValue: Int64);
var
  Actual, Expected: string;
begin
  Actual:=IntToStr(AValue);
  Expected:=ReferenceSigned(AValue);
  Check(Actual=Expected,'signed '+Expected+' got '+Actual);
end;

procedure CheckUnsigned(AValue: QWord);
var
  Actual, Expected: string;
begin
  Actual:=IntToStr(AValue);
  Expected:=ReferenceUnsigned(AValue);
  Check(Actual=Expected,'unsigned '+Expected+' got '+Actual);
  Actual:=UIntToStr(AValue);
  Check(Actual=Expected,'UIntToStr '+Expected+' got '+Actual);
end;

procedure CheckBoundaries;
const
  SignedValues: array[0..20] of Int64 = (
    Low(Int64),Low(Int64)+1,-1000000000000000000,-100000000000000001,
    -10000000000000000,-1000000000000001,-100000000000000,
    -10000000000001,-1000000000000,-100000000001,-10000000000,
    -1000000001,-100000000,-1000001,-100,-99,-10,-9,-1,0,High(Int64));
  UnsignedValues: array[0..15] of QWord = (
    0,1,9,10,11,99,100,101,999,1000,9999,10000,$FFFFFFFF,
    QWord(High(Int64)),QWord(High(Int64))+1,High(QWord));
var
  I: Integer;
  Parsed: Int64;
begin
  for I:=Low(SignedValues) to High(SignedValues) do
    CheckSigned(SignedValues[I]);
  for I:=Low(UnsignedValues) to High(UnsignedValues) do
    CheckUnsigned(UnsignedValues[I]);
  Check(IntToStr(LongInt(Low(LongInt)))='-2147483648','LongInt low');
  Check(IntToStr(LongInt(High(LongInt)))='2147483647','LongInt high');
  Check(UIntToStr(Cardinal(High(Cardinal)))='4294967295','Cardinal high');
  Check(UIntToStr(Int64(-1))='18446744073709551615','Int64 unsigned bits');
  Check(TryStrToInt64('0',Parsed) and (Parsed=0),'Try zero');
  Check(TryStrToInt64('9223372036854775807',Parsed) and
    (Parsed=High(Int64)),'Try signed high');
  Check(TryStrToInt64('-9223372036854775808',Parsed) and
    (Parsed=Low(Int64)),'Try signed low');
  Check(TryStrToInt64('00000000000000000042',Parsed) and (Parsed=42),
    'leading zeroes');
  Check(TryStrToInt64('-0',Parsed) and (Parsed=0),'negative zero');
  Check(TryStrToInt64('$ff',Parsed) and (Parsed=255),'hex fallback');
  Check(TryStrToInt64('+42',Parsed) and (Parsed=42),'plus fallback');
  Check(not TryStrToInt64('9223372036854775808',Parsed),'positive overflow');
  Check(not TryStrToInt64('-9223372036854775809',Parsed),'negative overflow');
  Check(not TryStrToInt64('12x',Parsed),'trailing input');
end;

procedure CheckNullTerminator;
var
  Parsed32: LongInt;
  Parsed64: Int64;
begin
  Check(not TryStrToInt(#0,Parsed32),'NUL alone Int32');
  Check(not TryStrToInt64(#0,Parsed64),'NUL alone Int64');
  Check(TryStrToInt('0'#0,Parsed32) and (Parsed32=0),'zero NUL Int32');
  Check(TryStrToInt64('10'#0,Parsed64) and (Parsed64=10),'ten NUL Int64');
  Check(TryStrToInt('3210'#0'ABFG',Parsed32) and (Parsed32=3210),
    'decimal NUL tail');
  Check(TryStrToInt('$ff'#0'junk',Parsed32) and (Parsed32=255),
    'hex NUL tail');
  Check(not TryStrToInt('+'#0'1',Parsed32),'sign before NUL');
  Check(not TryStrToInt('$'#0'1',Parsed32),'prefix before NUL');
  Check(StrToInt('42'#0'junk')=42,'StrToInt NUL tail');
  Check(StrToInt64('-42'#0'junk')=-42,'StrToInt64 NUL tail');
end;

procedure CheckRandomized;
var
  I: Integer;
  Parsed, SignedValue: Int64;
  State: QWord;
  Text: string;
begin
  State:=$D1B54A32D192ED03;
  for I:=1 to 20000 do
    begin
    State:=State xor (State shl 13);
    State:=State xor (State shr 7);
    State:=State xor (State shl 17);
    CheckUnsigned(State);
    SignedValue:=Int64(State);
    CheckSigned(SignedValue);
    Text:=ReferenceSigned(SignedValue);
    Check(TryStrToInt64(Text,Parsed) and (Parsed=SignedValue),
      'random TryStrToInt64 '+Text);
    Check(StrToInt64(Text)=SignedValue,'random StrToInt64 '+Text);
    end;
end;

begin
  try
    CheckBoundaries;
    CheckNullTerminator;
    CheckRandomized;
    WriteLn('INTEGER_CONVERSION_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
