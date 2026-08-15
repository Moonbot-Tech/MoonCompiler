program core_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  Math,
  DateUtils,
  StrUtils,
  Character,
  Variants,
  TypInfo,
  Rtti;

type
  TFixedString = string[255];

  ITracked = interface
    ['{77B4C3F4-B1D5-4E08-B2EE-C8FF76F30A6F}']
    function Value: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;

  TManagedValue = record
    Text: UnicodeString;
    Bytes: TBytes;
    Item: ITracked;
  end;

  TSampleEnum = (seFirst, seSecond, seThird);

var
  Destroyed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

procedure TestUnicodeAndRawStrings;
var
  Source, AliasValue, CopyValue, Value: UnicodeString;
  RawSource, RawAlias: RawByteString;
  Encoded: UTF8String;
  FixedValue: TFixedString;
begin
  Source := 'Abc-Ж-€-😀';
  AliasValue := Source;
  AliasValue[1] := 'a';
  Check(Source = 'Abc-Ж-€-😀', 'UnicodeString source COW');
  Check(AliasValue = 'abc-Ж-€-😀', 'UnicodeString alias mutation');
  Check(Source + '' = Source, 'concat empty');
  Check('prefix-' + Source = 'prefix-Abc-Ж-€-😀', 'concat value');

  CopyValue := Copy(Source, 1, 3);
  Check(CopyValue = 'Abc', 'Copy regular');
  Check(Copy(Source, Length(Source) + 1, 10) = '', 'Copy beyond end');
  Check(Copy(Source, 1, 0) = '', 'Copy zero count');
  Value := Source;
  Delete(Value, 1, 4);
  Check(Value = 'Ж-€-😀', 'Delete prefix');
  Insert('new-', Value, 1);
  Check(Value = 'new-Ж-€-😀', 'Insert prefix');
  Check(Pos(UnicodeString('Ж-€'), Source) = 5,
    'Pos non-ASCII result='+IntToStr(Pos(UnicodeString('Ж-€'),Source)));
  Check(Pos('missing', Source) = 0, 'Pos miss');
  Check(CompareStr('abc', 'abc') = 0, 'CompareStr equal');
  Check(CompareStr('abc', 'abd') < 0, 'CompareStr order');
  Check(UpperCase('Abc') = 'ABC', 'UpperCase ASCII');
  Check(LowerCase('AbC') = 'abc', 'LowerCase ASCII');
  Check(TCharacter.IsLetter(WideChar($0416)), 'Character Unicode letter');
  Check(TCharacter.ToUpper('a') = 'A', 'Character uppercase');
  Check(ContainsText('AlphaBeta', 'BETA'), 'StrUtils ContainsText');
  Check(ReplaceText('a-B-a', 'a', 'x') = 'x-B-x', 'StrUtils ReplaceText');

  Encoded := UTF8Encode(Source);
  Check(UTF8ToString(Encoded) = Source, 'UTF-8 roundtrip');
  Check(Length(UTF8Encode('ASCII')) = 5, 'UTF-8 ASCII length');

  RawSource := RawByteString(AnsiString('raw-value'));
  RawAlias := RawSource;
  RawAlias[1] := 'R';
  Check(RawSource = 'raw-value', 'RawByteString source COW');
  Check(RawAlias = 'Raw-value', 'RawByteString alias mutation');

  FixedValue := StringOfChar('x', 255);
  Check(Length(FixedValue) = 255, 'ShortString max length');
  FixedValue := 'short';
  Check(Copy(FixedValue, 2, 3) = 'hor', 'ShortString Copy');
end;

procedure TestConversionsAndFormatting;
var
  Settings: TFormatSettings;
  IntValue: Int64;
  FloatValue: Double;
  Raised: Boolean;
begin
  Settings := TFormatSettings.Create;
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := ',';
  Check(IntToStr(Low(Int64)) = '-9223372036854775808', 'IntToStr low Int64');
  Check(IntToStr(High(Int64)) = '9223372036854775807', 'IntToStr high Int64');
  Check(StrToInt64('-9223372036854775808') = Low(Int64), 'StrToInt64 low');
  Check(StrToInt64('$7f') = 127, 'StrToInt64 hex');
  Check(TryStrToInt64('+42', IntValue) and (IntValue = 42), 'TryStrToInt64');
  Check(not TryStrToInt64('12x', IntValue), 'TryStrToInt64 invalid');
  Raised := False;
  try
    IntValue := StrToInt64('9223372036854775808');
  except
    on EConvertError do
      Raised := True;
  end;
  Check(Raised, 'StrToInt64 overflow exception');

  Check(TryStrToFloat('-12.5e2', FloatValue, Settings), 'TryStrToFloat exponent');
  Check(SameValue(FloatValue, -1250.0), 'StrToFloat exponent value');
  Check(not TryStrToFloat('1,2,3', FloatValue, Settings), 'TryStrToFloat invalid');
  Check(FloatToStr(12.5, Settings) = '12.5', 'FloatToStr settings');
  Check(Format('%d:%s:%.2f', [7, 'x', 1.25], Settings) = '7:x:1.25',
    'Format mixed');
  Raised := False;
  try
    Format('%d', ['not-an-integer'], Settings);
  except
    on EConvertError do
      Raised := True;
  end;
  Check(Raised, 'Format type exception');
end;

procedure TestDynamicArraysAndManagedLifetime;
var
  Source, AliasValue, CopyValue: TBytes;
  Items: array of ITracked;
  ManagedSource, ManagedCopy: TManagedValue;
begin
  Source := TBytes.Create(1, 2, 3, 4);
  AliasValue := Source;
  AliasValue[1] := 99;
  Check(Source[1] = 99, 'dynamic array assignment shares payload');
  CopyValue := Copy(Source);
  CopyValue[1] := 2;
  Check((Source[1] = 99) and (CopyValue[1] = 2), 'dynamic array Copy is deep');
  SetLength(Source, 8);
  Check((Source[0] = 1) and (Source[1] = 99) and (Source[7] = 0),
    'dynamic array grow preserves and zeroes');
  SetLength(Source, 2);
  Check((Length(Source) = 2) and (Source[1] = 99), 'dynamic array shrink');

  Destroyed := 0;
  SetLength(Items, 3);
  Items[0] := TTracked.Create(1);
  Items[1] := TTracked.Create(2);
  Items[2] := TTracked.Create(3);
  SetLength(Items, 1);
  Check(Destroyed = 2, 'array shrink finalizes removed interfaces');
  Items := nil;
  Check(Destroyed = 3, 'array release finalizes retained interface');

  Destroyed := 0;
  ManagedSource.Text := 'managed';
  ManagedSource.Bytes := TBytes.Create(10, 20);
  ManagedSource.Item := TTracked.Create(77);
  ManagedCopy := ManagedSource;
  Check((ManagedCopy.Text = 'managed') and (ManagedCopy.Bytes[1] = 20) and
    (ManagedCopy.Item.Value = 77), 'managed record assignment');
  ManagedSource.Text[1] := 'M';
  ManagedSource.Bytes[1] := 99;
  Check(ManagedCopy.Text = 'managed', 'managed record string COW');
  Check(ManagedCopy.Bytes[1] = 99, 'managed record dynamic array sharing');
  ManagedSource.Item := nil;
  Check(Destroyed = 0, 'managed record copy retains interface');
  ManagedCopy.Item := nil;
  Check(Destroyed = 1, 'managed record final interface release');
end;

procedure TestInterfacesVariantsAndRtti;
var
  Item, CopyItem: ITracked;
  Value, ArrayValue: Variant;
  Context: TRttiContext;
  RttiType: TRttiType;
  Raised: Boolean;
begin
  Destroyed := 0;
  Item := TTracked.Create(41);
  CopyItem := Item;
  Item := nil;
  Check((Destroyed = 0) and (CopyItem.Value = 41), 'interface copy lifetime');
  CopyItem := nil;
  Check(Destroyed = 1, 'interface final release');

  Value := Unassigned;
  Check(VarIsEmpty(Value), 'Variant Empty');
  Value := Null;
  Check(VarIsNull(Value), 'Variant Null');
  Value := 10;
  Value := Value * 3 + 2;
  Check(Value = 32, 'Variant numeric arithmetic');
  Value := 'variant';
  Check(VarToStr(Value) = 'variant', 'Variant string conversion');
  ArrayValue := VarArrayCreate([0, 2], varInteger);
  ArrayValue[0] := 3;
  ArrayValue[1] := 5;
  ArrayValue[2] := 7;
  Check((VarArrayHighBound(ArrayValue, 1) = 2) and (ArrayValue[1] = 5),
    'Variant array');
  Raised := False;
  try
    Value := VarAsType('not-a-number', varInteger);
  except
    on EVariantError do
      Raised := True;
  end;
  Check(Raised, 'Variant conversion exception');

  Check(PTypeInfo(TypeInfo(TSampleEnum))^.Kind = tkEnumeration, 'TypInfo kind');
  Check(GetEnumName(TypeInfo(TSampleEnum), Ord(seSecond)) = 'seSecond',
    'TypInfo enum name');
  Context := TRttiContext.Create;
  try
    RttiType := Context.GetType(TypeInfo(Integer));
    Check((RttiType <> nil) and (RttiType.TypeKind = tkInteger), 'RTTI type');
  finally
    Context.Free;
  end;
end;

procedure TestExceptionsAndFinalization;
var
  Raised: Boolean;

  procedure RaiseWithManagedLocals;
  var
    Text: UnicodeString;
    Bytes: TBytes;
    Item: ITracked;
  begin
    Text := 'temporary';
    Bytes := TBytes.Create(1, 2, 3);
    Item := TTracked.Create(9);
    Check((Text <> '') and (Bytes[0] = 1) and (Item.Value = 9),
      'managed locals initialized');
    raise EAbort.Create('expected');
  end;

begin
  Destroyed := 0;
  Raised := False;
  try
    try
      RaiseWithManagedLocals;
    finally
      Check(Destroyed = 1, 'callee managed local unwound before caller finally');
    end;
  except
    on E: EAbort do
    begin
      Raised := E.Message = 'expected';
      Check(Destroyed = 1, 'exception unwinds interface local');
    end;
  end;
  Check(Raised and (Destroyed = 1), 'typed exception caught once');

  try
    try
      raise EConvertError.Create('reraised');
    except
      on EConvertError do
        raise;
    end;
  except
    on E: EConvertError do
      Check(E.Message = 'reraised', 'reraise preserves exception');
  end;
end;

procedure TestBuffersAndStreams;
var
  Source, Target: array[0..31] of Byte;
  I: Integer;
  Memory, CopyStream: TMemoryStream;
  StringStream: TStringStream;
  ReadValue: Byte;
  Raised: Boolean;
begin
  for I := 0 to High(Source) do
    Source[I] := Byte(I);
  FillChar(Target, SizeOf(Target), $AA);
  Move(Source[0], Target[0], SizeOf(Source));
  Check(CompareByte(Source, Target, SizeOf(Source)) = 0, 'Move buffer');
  Move(Target[0], Target[1], Length(Target) - 1);
  Check((Target[1] = 0) and (Target[31] = 30), 'Move overlap forward');
  Move(Target[1], Target[0], Length(Target) - 1);
  Check((Target[0] = 0) and (Target[30] = 30), 'Move overlap backward');

  Memory := TMemoryStream.Create;
  CopyStream := TMemoryStream.Create;
  try
    Memory.WriteBuffer(Source[0], SizeOf(Source));
    Check((Memory.Size = SizeOf(Source)) and (Memory.Position = SizeOf(Source)),
      'TMemoryStream write');
    Memory.Position := 10;
    Memory.ReadBuffer(ReadValue, SizeOf(ReadValue));
    Check(ReadValue = 10, 'TMemoryStream seek/read');
    Memory.Position := 0;
    CopyStream.CopyFrom(Memory, 0);
    Check(CopyStream.Size = Memory.Size, 'TStream CopyFrom');
    Raised := False;
    try
      Memory.Position := Memory.Size;
      Memory.ReadBuffer(ReadValue, SizeOf(ReadValue));
    except
      on EReadError do
        Raised := True;
    end;
    Check(Raised, 'ReadBuffer short read exception');
  finally
    CopyStream.Free;
    Memory.Free;
  end;

  StringStream := TStringStream.Create('stream-text-Ж');
  try
    Check(StringStream.DataString = 'stream-text-Ж', 'TStringStream data');
    StringStream.Position := 0;
    Check(StringStream.ReadString(6) = 'stream', 'TStringStream read');
  finally
    StringStream.Free;
  end;
end;

procedure TestMathAndDateTime;
var
  Value: TDateTime;
  Year, Month, Day: Word;
  Raised: Boolean;
begin
  Check(IsNan(NaN), 'NaN classification');
  Check(IsInfinite(Infinity), 'Infinity classification');
  Check(SameValue(Sqrt(81), 9), 'Sqrt');
  Check(SameValue(Power(2, 10), 1024), 'Power');
  Check(Round(2.5) = 2, 'banker rounding even');
  Check(Round(3.5) = 4, 'banker rounding odd');

  Value := EncodeDate(2024, 2, 29) + EncodeTime(23, 59, 58, 123);
  DecodeDate(Value, Year, Month, Day);
  Check((Year = 2024) and (Month = 2) and (Day = 29), 'leap date roundtrip');
  Check(DayOfTheYear(Value) = 60, 'DayOfTheYear leap');
  Check(IncDay(Value, 1) > Value, 'IncDay');
  Raised := False;
  try
    Value := EncodeDate(2023, 2, 29);
  except
    on EConvertError do
      Raised := True;
  end;
  Check(Raised, 'invalid date exception');
end;

begin
  try
    TestUnicodeAndRawStrings;
    TestConversionsAndFormatting;
    TestDynamicArraysAndManagedLifetime;
    TestInterfacesVariantsAndRtti;
    TestExceptionsAndFinalization;
    TestBuffersAndStreams;
    TestMathAndDateTime;
    WriteLn('CORE_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
