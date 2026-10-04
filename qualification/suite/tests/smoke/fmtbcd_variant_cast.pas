program fmtbcd_variant_cast;

{$ifdef FPC}
{$mode delphi}
{$else}
{$APPTYPE CONSOLE}
{$endif}

uses
{$ifdef FPC}
  SysUtils,
  Variants,
  FmtBcd;
{$else}
  System.SysUtils,
  System.Variants,
  Data.FMTBcd;
{$endif}

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ', Name);
  Halt(1);
end;

procedure CheckCast(const Source: Variant; const Expected, Name: AnsiString);
var
  Actual: Variant;
begin
  Actual := VarAsType(Source, VarFmtBCD);
  If BCDCompare(VarToBCD(Actual), StrToBCD(Expected)) <> 0 then
    Fail(Name);
end;

procedure CheckInPlace;
var
  Value: Variant;
begin
  Value := AnsiString('42.125');
  VarCast(Value, Value, VarFmtBCD);
  If BCDCompare(VarToBCD(Value), StrToBCD('42.125')) <> 0 then
    Fail('in-place');
end;

procedure CheckByRef;
var
  SourceValue: Integer;
  SourceText: Variant;
  SourceData: TVarData;
  Actual: Variant;
begin
  SourceValue := -73;
  FillChar(SourceData, SizeOf(SourceData), 0);
  SourceData.VType := varInteger or varByRef;
  SourceData.VPointer := @SourceValue;
  VarCast(Actual, PVariant(@SourceData)^, VarFmtBCD);
  If BCDCompare(VarToBCD(Actual), StrToBCD('-73')) <> 0 then
    Fail('by-ref-integer');

  SourceText := UnicodeString('12345678901234567890.125');
  SourceData.VType := varVariant or varByRef;
  SourceData.VPointer := @TVarData(SourceText);
  VarCast(Actual, PVariant(@SourceData)^, VarFmtBCD);
  If BCDCompare(VarToBCD(Actual), StrToBCD('12345678901234567890.125')) <> 0 then
    Fail('by-ref-variant-unicode-string');
end;

procedure CheckExactOutput;
var
  Value: Variant;
  AnsiValue: AnsiString;
  WideValue: WideString;
  UnicodeValue: UnicodeString;
  IntegerValue: Int64;
begin
  Value := VarFMTBCDCreate('12345678901234567890.125');
  AnsiValue := Value;
  WideValue := Value;
  UnicodeValue := Value;
  If AnsiValue <> '12345678901234567890.125' then
    Fail('output-ansi-precision');
  If WideValue <> '12345678901234567890.125' then
    Fail('output-wide-precision');
  If UnicodeValue <> '12345678901234567890.125' then
    Fail('output-unicode-precision');

  Value := VarFMTBCDCreate('9007199254740993');
  IntegerValue := Value;
  If IntegerValue <> 9007199254740993 then
    Fail('output-int64-precision');
end;

procedure CheckInt64CastRejected(const TextValue: string);
var
  IntegerValue: Int64;
  Value: Variant;
begin
  Value := VarFMTBCDCreate(TextValue);
  try
    IntegerValue := Value;
    Fail('output-int64-accepted-' + IntToStr(IntegerValue));
  except
    on EVariantTypeCastError do
      Exit;
  end;
  Fail('output-int64-reject-' + TextValue);
end;

procedure CheckIntegerOutputMatrix;
var
  ByteValue: Byte;
  CardinalValue: Cardinal;
  Int64Value: Int64;
  QWordValue: QWord;
  SmallIntValue: SmallInt;
  Value: Variant;
begin
  Value := VarFMTBCDCreate('9007199254740993');
  QWordValue := Value;
  If QWordValue <> QWord(9007199254740993) then
    Fail('output-qword-precision');

  Value := VarFMTBCDCreate('4294967295');
  CardinalValue := Value;
  If CardinalValue <> High(Cardinal) then
    Fail('output-cardinal-high');

  Value := VarFMTBCDCreate('-32768');
  SmallIntValue := Value;
  If SmallIntValue <> Low(SmallInt) then
    Fail('output-smallint-low');

  Value := VarFMTBCDCreate('255.000');
  ByteValue := Value;
  If ByteValue <> 255 then
    Fail('output-byte-integral-scale');

  Value := VarFMTBCDCreate('-9223372036854775808');
  Int64Value := Value;
  If Int64Value <> Low(Int64) then
    Fail('output-int64-low');
end;

procedure CheckIntegerCastRejected(const TextValue, Name: string;
  TargetType: TVarType);
var
  Actual,
  Value: Variant;
begin
  Value := VarFMTBCDCreate(TextValue);
  try
    Actual := VarAsType(Value, TargetType);
    Fail(Name + '-accepted-' + VarToStr(Actual));
  except
    on EVariantError do
      Exit;
  end;
  Fail(Name + '-not-rejected');
end;

procedure CheckCustomByRefCopy;
var
  Source, Snapshot: Variant;
  Reference: TVarData;
begin
  Source := VarFMTBCDCreate('12345678901234567890.125');
  FillChar(Reference, SizeOf(Reference), 0);
  Reference.VType := VarFmtBCD or varByRef;
  Reference.VPointer := @TVarData(Source).VPointer;
  VarCopyNoInd(Snapshot, PVariant(@Reference)^);
  Reference.VType := varEmpty;
  Source := VarFMTBCDCreate('7');
  If BCDToStr(VarToBCD(Snapshot)) <> '12345678901234567890.125' then
    Fail('custom-by-ref-copy');
end;

begin
  CheckCast(Integer(42), '42', 'integer');
  CheckCast(Int64(-123456789), '-123456789', 'int64');
  CheckCast(Currency(123.4567), '123.4567', 'currency');
  CheckCast(Double(12.5), '12.5', 'double');
  CheckCast(AnsiString('987.125'), '987.125', 'ansi-string');
  CheckCast(UnicodeString('12345678901234567890.125'),
    '12345678901234567890.125', 'unicode-string-precision');
  CheckInPlace;
  CheckByRef;
  CheckExactOutput;
  CheckIntegerOutputMatrix;
  CheckInt64CastRejected('1.5');
  CheckInt64CastRejected('9223372036854775808');
  CheckIntegerCastRejected('1.5', 'qword-fraction', varQWord);
  CheckIntegerCastRejected('-1', 'qword-negative', varQWord);
  CheckIntegerCastRejected('18446744073709551615', 'qword-above-int64', varQWord);
  CheckIntegerCastRejected('256', 'byte-overflow', varByte);
  CheckIntegerCastRejected('32768', 'smallint-overflow', varSmallInt);
{$ifdef FPC}
  CheckCustomByRefCopy;
{$endif}
  WriteLn('FMTBCD_VARIANT_CAST_OK');
end.
