program foundations_extended_semantic;

{$mode delphi}{$H+}{$codepage utf8}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
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
  TShort255 = string[255];
  TIntStatic = array[0..3] of Integer;
  TStringStatic = array[0..2] of UnicodeString;

  IProbe = interface
    ['{7DB6C895-FF96-49CF-A5C0-C766587CFA86}']
    function GetValue: Integer;
  end;

  TProbe = class(TInterfacedObject, IProbe)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function GetValue: Integer;
  end;

  TPlainManaged = record
    Text: UnicodeString;
    Data: TBytes;
    Probe: IProbe;
  end;

  TOperatorManaged = record
  private
    class operator Initialize(var AValue: TOperatorManaged);
    class operator Finalize(var AValue: TOperatorManaged);
    class operator Copy(constref ASource: TOperatorManaged;
      var ADestination: TOperatorManaged);
  public
    Number: Integer;
    Text: UnicodeString;
    Probe: IProbe;
  end;

  TFailingObject = class
  private
    FText: UnicodeString;
    FProbe: IProbe;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  {$M+}
  TDispatchBase = class
  published
    function VirtualValue(AValue: Integer): Integer; virtual;
  end;

  TDispatchChild = class(TDispatchBase)
  published
    function VirtualValue(AValue: Integer): Integer; override;
  end;
  {$M-}

  TCallback = function(AValue: Integer): Integer;

  TStringReadThread = class(TThread)
  private
    FText: UnicodeString;
    FDigest: UInt64;
  protected
    procedure Execute; override;
  public
    constructor Create(const AText: UnicodeString);
    property Digest: UInt64 read FDigest;
  end;

  TInterfaceReadThread = class(TThread)
  private
    FProbe: IProbe;
    FDigest: UInt64;
  protected
    procedure Execute; override;
  public
    constructor Create(const AProbe: IProbe);
    property Digest: UInt64 read FDigest;
  end;

  TSampleEnum = (seZero, seOne, seTwo);

var
  LiveProbes: Integer;
  OperatorInitializes: Integer;
  OperatorCopies: Integer;
  OperatorFinalizes: Integer;
  FailingDestroys: Integer;

procedure Check(ACondition: Boolean; const AMessage: UnicodeString);
begin
  if not ACondition then
    raise Exception.Create('FOUNDATIONS_EXTENDED_FAIL: ' + AMessage);
end;

constructor TProbe.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
  Inc(LiveProbes);
end;

destructor TProbe.Destroy;
begin
  Dec(LiveProbes);
  inherited Destroy;
end;

function TProbe.GetValue: Integer;
begin
  Result := FValue;
end;

class operator TOperatorManaged.Initialize(var AValue: TOperatorManaged);
begin
  Inc(OperatorInitializes);
  AValue.Number := -1;
  AValue.Text := '';
  AValue.Probe := nil;
end;

class operator TOperatorManaged.Finalize(var AValue: TOperatorManaged);
begin
  Inc(OperatorFinalizes);
  AValue.Probe := nil;
  AValue.Text := '';
  AValue.Number := -1;
end;

class operator TOperatorManaged.Copy(constref ASource: TOperatorManaged;
  var ADestination: TOperatorManaged);
begin
  Inc(OperatorCopies);
  ADestination.Number := ASource.Number;
  ADestination.Text := ASource.Text;
  ADestination.Probe := ASource.Probe;
end;

constructor TFailingObject.Create;
begin
  inherited Create;
  FText := 'constructor-managed-field';
  FProbe := TProbe.Create(91);
  raise EAbort.Create('constructor failure');
end;

destructor TFailingObject.Destroy;
begin
  Inc(FailingDestroys);
  inherited Destroy;
end;

function TDispatchBase.VirtualValue(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

function TDispatchChild.VirtualValue(AValue: Integer): Integer;
begin
  Result := AValue + 2;
end;

function CallbackValue(AValue: Integer): Integer;
begin
  Result := AValue * 3;
end;

constructor TStringReadThread.Create(const AText: UnicodeString);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FText := AText;
end;

procedure TStringReadThread.Execute;
var
  I: Integer;
begin
  FDigest := 0;
  for I := 1 to 10000 do
    FDigest := FDigest + UInt64(Length(FText)) + Ord(FText[(I mod Length(FText)) + 1]);
end;

constructor TInterfaceReadThread.Create(const AProbe: IProbe);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FProbe := AProbe;
end;

procedure TInterfaceReadThread.Execute;
var
  I: Integer;
  Local: IProbe;
begin
  FDigest := 0;
  for I := 1 to 10000 do
  begin
    Local := FProbe;
    FDigest := FDigest + UInt64(Local.GetValue);
  end;
end;

function ReturnUnicode(const AValue: UnicodeString): UnicodeString;
begin
  Result := AValue;
end;

function ReturnBytes(const AValue: TBytes): TBytes;
begin
  Result := AValue;
end;

function ReturnPlainManaged(const AValue: TPlainManaged): TPlainManaged;
begin
  Result := AValue;
end;

function SumOpenIntegers(const AValues: array of Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AValues) do
    Inc(Result, AValues[I]);
end;

function JoinOpenStrings(const AValues: array of UnicodeString): UnicodeString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AValues) do
    Result := Result + AValues[I];
end;

function ReturnStatic(const AValue: TIntStatic): TIntStatic;
begin
  Result := AValue;
end;

procedure TestStrings;
var
  Source, AliasValue, UniqueValue, Value: UnicodeString;
  RawSource, RawAlias, InvalidUtf8: RawByteString;
  Encoded: UTF8String;
  FixedValue: TShort255;
  ShortLeft, ShortRight: TShort255;
  Threads: array[0..3] of TStringReadThread;
  I: Integer;
  OverflowRaised: Boolean;
begin
  Source := 'Alpha-Ж-€-😀';
  AliasValue := Source;
  AliasValue[1] := 'a';
  Check((Source = 'Alpha-Ж-€-😀') and (AliasValue = 'alpha-Ж-€-😀'),
    'Unicode shared COW');
  UniqueValue := Copy(Source, 1, MaxInt);
  UniqueValue[2] := 'L';
  Check((Source[2] = 'l') and (UniqueValue[2] = 'L'), 'Unicode unique mutation');
  Check((ReturnUnicode('') = '') and (ReturnUnicode(Source) = Source),
    'Unicode parameter/result');
  Check(('' + Source = Source) and (Source + '' = Source) and
    ('x' + Source + 'y' = 'xAlpha-Ж-€-😀y'), 'Unicode concat 0/1/N');
  Check((Copy(Source, 1, 0) = '') and (Copy(Source, Length(Source) + 1, 5) = '') and
    (Copy(Source, -5, 2) = 'Al') and (Copy(Source, 1, MaxInt) = Source),
    'Unicode Copy boundaries');
  Value := Source;
  Delete(Value, -2, 3);
  Check(Value = Source, 'Unicode Delete negative index');
  Delete(Value, 1, 0);
  Check(Value = Source, 'Unicode Delete zero');
  Delete(Value, 1, MaxInt);
  Check(Value = '', 'Unicode Delete oversize');
  Insert('', Value, 1);
  Insert(Source, Value, 1);
  Check(Value = Source, 'Unicode Insert empty/boundary');
  Value := 'tail';
  Insert('head-', Value, -3);
  Check(Value = 'head-tail', 'Unicode Insert negative index normalization');
  Check((Pos(UnicodeString(''), Source) = 0) and
    (Pos(UnicodeString('Ж-€'), Source) = 7) and
    (Pos(UnicodeString('missing'), Source) = 0), 'Unicode Pos forms');
  Check((CompareStr('', '') = 0) and (CompareStr('a', 'b') < 0) and
    (CompareText('AbC', 'aBc') = 0), 'Unicode compare forms');
  Check((UpperCase('aZ09') = 'AZ09') and (LowerCase('Az09') = 'az09') and
    TCharacter.IsLetter(WideChar($0416)), 'case mapping ASCII/Unicode');

  RawSource := RawByteString(AnsiString('raw-value'));
  SetCodePage(RawSource, 1252, False);
  Check(StringCodePage(RawSource) = 1252, 'RawByteString codepage metadata');
  RawAlias := RawSource;
  RawAlias[1] := 'R';
  Check((RawSource = 'raw-value') and (RawAlias = 'Raw-value') and
    (StringCodePage(RawSource) = 1252) and (StringCodePage(RawAlias) = 1252),
    'RawByteString codepage COW');
  Encoded := UTF8Encode(Source);
  Check(UTF8Decode(Encoded) = Source, 'UTF-8 ASCII/BMP/supplementary roundtrip');
  InvalidUtf8 := RawByteString(AnsiString(#$C3#$28));
  Value := UTF8Decode(InvalidUtf8);
  Check((Value = UnicodeString(WideChar($FFFD)) + '(') and
    (Value = UTF8Decode(InvalidUtf8)),
    'UTF-8 invalid replacement handling');

  FixedValue := StringOfChar('x', 255);
  Check((Length(FixedValue) = 255) and (Copy(FixedValue, 254, 4) = 'xx'),
    'ShortString max/copy boundary');
  FixedValue := '';
  Check((Length(FixedValue) = 0) and (FixedValue + 'a' = 'a'),
    'ShortString empty/concat');
  ShortLeft := StringOfChar('a', 200);
  ShortRight := StringOfChar('b', 100);
  OverflowRaised := False;
  try
    FixedValue := ShortLeft + ShortRight;
  except
    on ERangeError do
      OverflowRaised := True;
  end;
  Check((not OverflowRaised) and (Length(FixedValue) = 255) and
    (FixedValue[255] = 'b'), 'ShortString overflow truncation');

  for I := 0 to High(Threads) do
    Threads[I] := TStringReadThread.Create(Source);
  try
    for I := 0 to High(Threads) do
      Threads[I].Start;
    for I := 0 to High(Threads) do
    begin
      Threads[I].WaitFor;
      Check(Threads[I].Digest <> 0, 'Unicode shared threaded read');
    end;
    Check(Source = 'Alpha-Ж-€-😀', 'Unicode shared lifetime after threads');
  finally
    for I := 0 to High(Threads) do
      Threads[I].Free;
  end;
end;

procedure TestArraysAndManagedLifetime;
var
  Bytes, AliasBytes, CopyBytes: TBytes;
  StaticSource, StaticCopy: TIntStatic;
  StaticStrings: TStringStatic;
  PlainSource, PlainCopy: TPlainManaged;
  ManagedArray: array of TPlainManaged;
  OperatorSource, OperatorCopy: TOperatorManaged;
  I: Integer;
begin
  Bytes := nil;
  SetLength(Bytes, 0);
  Check(Length(Bytes) = 0, 'dynamic array zero');
  SetLength(Bytes, 1);
  Bytes[0] := 7;
  SetLength(Bytes, 1024);
  Check((Bytes[0] = 7) and (Bytes[1023] = 0), 'dynamic array grow/zero');
  AliasBytes := ReturnBytes(Bytes);
  AliasBytes[0] := 9;
  Check(Bytes[0] = 9, 'dynamic array parameter/result sharing');
  CopyBytes := Copy(Bytes, 0, Length(Bytes));
  CopyBytes[0] := 7;
  Check((Bytes[0] = 9) and (CopyBytes[0] = 7), 'dynamic array deep Copy');
  SetLength(Bytes, 1);
  Check((Length(Bytes) = 1) and (Bytes[0] = 9), 'dynamic array shrink');

  for I := 0 to High(StaticSource) do
    StaticSource[I] := I + 1;
  StaticCopy := ReturnStatic(StaticSource);
  StaticCopy[0] := 10;
  Check((StaticSource[0] = 1) and (SumOpenIntegers(StaticCopy) = 19),
    'static array by-value/result and open-array ABI');
  StaticStrings[0] := 'a';
  StaticStrings[1] := 'Ж';
  StaticStrings[2] := 'c';
  Check(JoinOpenStrings(StaticStrings) = 'aЖc', 'managed open/static array');

  LiveProbes := 0;
  PlainSource.Text := 'plain';
  PlainSource.Data := TBytes.Create(2, 4, 6);
  PlainSource.Probe := TProbe.Create(17);
  PlainCopy := ReturnPlainManaged(PlainSource);
  PlainSource.Text[1] := 'P';
  PlainSource.Data[1] := 8;
  Check((PlainCopy.Text = 'plain') and (PlainCopy.Data[1] = 8) and
    (PlainCopy.Probe.GetValue = 17), 'plain managed record copy semantics');
  PlainSource.Probe := nil;
  Check(LiveProbes = 1, 'plain managed result retains interface');
  PlainCopy.Probe := nil;
  Check(LiveProbes = 0, 'plain managed final release');

  SetLength(ManagedArray, 4);
  for I := 0 to High(ManagedArray) do
  begin
    ManagedArray[I].Text := 'item-' + IntToStr(I);
    ManagedArray[I].Probe := TProbe.Create(I);
  end;
  Check(LiveProbes = 4, 'managed value array owns elements');
  SetLength(ManagedArray, 1);
  Check((LiveProbes = 1) and (ManagedArray[0].Text = 'item-0'),
    'managed value array shrink cleanup');
  ManagedArray := nil;
  Check(LiveProbes = 0, 'managed value array final cleanup');

  OperatorSource.Number := 23;
  OperatorSource.Text := 'operator';
  OperatorSource.Probe := TProbe.Create(23);
  OperatorCopy := OperatorSource;
  Check((OperatorCopy.Number = 23) and (OperatorCopy.Text = 'operator') and
    (OperatorCopy.Probe.GetValue = 23) and (OperatorCopies > 0) and
    (OperatorInitializes > 0), 'custom managed record initialize/copy');
  OperatorSource.Probe := nil;
  Check(LiveProbes = 1, 'custom managed copy retains interface');
  OperatorCopy.Probe := nil;
  Check(LiveProbes = 0, 'custom managed release');
end;

procedure TestManagedUnwindAndConstructorFailure;
var
  FinallyCount: Integer;
  Raised: Boolean;

  function ExitThroughFinally: Integer;
  var
    Text: UnicodeString;
    Probe: IProbe;
  begin
    Text := 'exit';
    Probe := TProbe.Create(1);
    try
      Result := Length(Text) + Probe.GetValue;
      Exit;
    finally
      Inc(FinallyCount);
    end;
  end;

  procedure RaiseWithValues;
  var
    Values: array of TPlainManaged;
  begin
    SetLength(Values, 3);
    Values[0].Probe := TProbe.Create(1);
    Values[1].Probe := TProbe.Create(2);
    Values[2].Probe := TProbe.Create(3);
    raise EAbort.Create('managed array unwind');
  end;

begin
  LiveProbes := 0;
  FinallyCount := 0;
  Check((ExitThroughFinally = 5) and (FinallyCount = 1) and (LiveProbes = 0),
    'Exit/finally/managed local cleanup');
  Raised := False;
  try
    RaiseWithValues;
  except
    on E: EAbort do
      Raised := E.Message = 'managed array unwind';
  end;
  Check(Raised and (LiveProbes = 0), 'exception managed array unwind');

  FailingDestroys := 0;
  Raised := False;
  try
    TFailingObject.Create;
  except
    on E: EAbort do
      Raised := E.Message = 'constructor failure';
  end;
  Check(Raised and (FailingDestroys = 1) and (LiveProbes = 0),
    'constructor failure destructor/managed fields');

  try
    try
      raise EConvertError.Create('reraised-object');
    except
      on EConvertError do
        raise;
    end;
  except
    on E: EConvertError do
      Check(E.Message = 'reraised-object', 'typed reraise object/message');
  end;
end;

procedure TestInterfacesVariantsRttiAndDispatch;
var
  Probe, ProbeCopy: IProbe;
  Unknown: IInterface;
  Value, ArrayValue, CopyValue: Variant;
  Context: TRttiContext;
  RttiType: TRttiType;
  RttiValue: TValue;
  Base: TDispatchBase;
  Callback: TCallback;
  Raised: Boolean;
  Threads: array[0..3] of TInterfaceReadThread;
  I: Integer;
begin
  LiveProbes := 0;
  Probe := TProbe.Create(44);
  Unknown := Probe;
  ProbeCopy := nil;
  Check(Supports(Unknown, IProbe, ProbeCopy) and (ProbeCopy.GetValue = 44),
    'interface QueryInterface');
  Probe := nil;
  Unknown := nil;
  Check(LiveProbes = 1, 'interface copy lifetime');
  ProbeCopy := nil;
  Check(LiveProbes = 0, 'interface final release');

  Probe := TProbe.Create(6);
  for I := 0 to High(Threads) do
    Threads[I] := TInterfaceReadThread.Create(Probe);
  try
    for I := 0 to High(Threads) do
      Threads[I].Start;
    for I := 0 to High(Threads) do
    begin
      Threads[I].WaitFor;
      Check(Threads[I].Digest = 60000, 'interface threaded refcount/dispatch');
    end;
  finally
    for I := 0 to High(Threads) do
      Threads[I].Free;
  end;
  Probe := nil;
  Check(LiveProbes = 0, 'interface threaded final release');

  Value := Unassigned;
  Check(VarIsEmpty(Value), 'Variant Empty init');
  Value := Null;
  CopyValue := Value;
  Check(VarIsNull(CopyValue), 'Variant Null copy');
  Value := Int64(High(Integer));
  Value := Value + 1;
  Value := Value + 5;
  Check(Int64(Value) = Int64(High(Integer)) + 6, 'Variant Int64 arithmetic');
  Value := UnicodeString('variant-Ж');
  CopyValue := Value;
  Value := Unassigned;
  Check(VarToWideStr(CopyValue) = 'variant-Ж', 'Variant string copy/clear');
  ArrayValue := VarArrayCreate([1, 2], varVariant);
  ArrayValue[1] := 'x';
  ArrayValue[2] := 9;
  Check((VarArrayLowBound(ArrayValue, 1) = 1) and
    (VarArrayHighBound(ArrayValue, 1) = 2) and (ArrayValue[2] = 9),
    'Variant array boundaries');
  Raised := False;
  try
    Value := VarAsType('bad-number', varInteger);
  except
    on EVariantError do
      Raised := True;
  end;
  Check(Raised, 'Variant conversion exception');

  Check((GetEnumName(TypeInfo(TSampleEnum), 1) = 'seOne') and
    (GetEnumValue(TypeInfo(TSampleEnum), 'seTwo') = 2), 'TypInfo conversion');
  Context := TRttiContext.Create;
  try
    RttiType := Context.GetType(TypeInfo(TDispatchChild));
    Check((RttiType <> nil) and (RttiType.TypeKind = tkClass) and
      (RttiType.AsInstance.MetaclassType = TDispatchChild), 'RTTI class lookup');
    RttiValue := TValue.From<UnicodeString>('managed-rtti');
    Check(RttiValue.AsString = 'managed-rtti', 'RTTI managed TValue conversion');
    RttiValue := TValue.Empty;
  finally
    Context.Free;
  end;

  Base := TDispatchChild.Create;
  try
    Check(Base.VirtualValue(10) = 12, 'virtual polymorphic dispatch');
  finally
    Base.Free;
  end;
  Probe := TProbe.Create(55);
  Check(Probe.GetValue = 55, 'interface dispatch');
  Probe := nil;
  Callback := @CallbackValue;
  Check(Callback(7) = 21, 'callback dispatch');
end;

procedure TestConversionsMathAndDates;
var
  Settings: TFormatSettings;
  SignedValue: Int64;
  IntValue: Longint;
  UnsignedValue: QWord;
  FloatValue: Extended;
  DateValue: TDateTime;
  Year, Month, Day, Hour, Minute, Second, Millisecond: Word;
  Raised: Boolean;
begin
  Settings := TFormatSettings.Create;
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := ',';
  Settings.ShortDateFormat := 'yyyy-mm-dd';
  Settings.DateSeparator := '-';
  Settings.LongTimeFormat := 'hh:nn:ss';
  Settings.TimeSeparator := ':';

  Check((IntToStr(Low(Int64)) = '-9223372036854775808') and
    (IntToStr(High(Int64)) = '9223372036854775807') and
    (UIntToStr(High(QWord)) = '18446744073709551615'), 'integer formatting bounds');
  Check(TryStrToInt64('-9223372036854775808', SignedValue) and
    (SignedValue = Low(Int64)), 'signed parse low');
  Check(TryStrToQWord('18446744073709551615', UnsignedValue) and
    (UnsignedValue = High(QWord)), 'unsigned parse high');
  { Delphi rejects the FPC-only &octal and %binary prefixes in
    StrToInt/TryStrToInt (Val keeps accepting them) }
  Check((StrToInt('$7f') = 127) and (StrToInt('0x10') = 16) and
    not TryStrToInt('&17', IntValue) and not TryStrToInt('%101', IntValue) and
    not TryStrToInt64('12x', SignedValue), 'integer radix/invalid parse');
  Raised := False;
  try
    SignedValue := StrToInt64('9223372036854775808');
  except
    on EConvertError do
      Raised := True;
  end;
  Check(Raised, 'integer overflow exception');

  Check(TryStrToFloat('-1.25e3', FloatValue, Settings) and
    SameValue(FloatValue, -1250.0), 'float exponent parse');
  Check((FloatToStr(Single(1.5), Settings) = '1.5') and
    (FloatToStr(Double(2.5), Settings) = '2.5') and
    (FloatToStr(Extended(3.5), Settings) = '3.5'),
    'Single/Double/Extended formatting');
  Check(not TryStrToFloat('1.2.3', FloatValue, Settings), 'float invalid parse');
  Check((FloatToStr(1.25, Settings) = '1.25') and
    IsNan(StrToFloat('NAN', Settings)) and
    IsInfinite(StrToFloat('INF', Settings)), 'float format/NaN/Inf');
  Check(Format('%1:d:%0:s:%2:8.2f:%p', ['x', 7, 1.25, Pointer(PtrUInt(1))],
    Settings) <> '', 'Format indexes/width/pointer');
  Raised := False;
  try
    Format('%d', ['wrong'], Settings);
  except
    on EConvertError do
      Raised := True;
  end;
  Check(Raised, 'Format type exception');

  Check((Min(-5, 2) = -5) and (Max(-5, 2) = 2) and
    (EnsureRange(8, 1, 5) = 5) and IsNan(NaN) and IsInfinite(Infinity),
    'math scalar boundaries');
  Check((Round(2.5) = 2) and (Round(3.5) = 4) and
    SameValue(Power(2, 10), 1024), 'math rounding/power');

  DateValue := EncodeDateTime(2024, 2, 29, 23, 59, 58, 123);
  DecodeDateTime(DateValue, Year, Month, Day, Hour, Minute, Second, Millisecond);
  Check((Year = 2024) and (Month = 2) and (Day = 29) and (Hour = 23) and
    (Minute = 59) and (Second = 58) and (Millisecond = 123),
    'date/time encode/decode leap boundary');
  Check((IncDay(DateValue, 1) > DateValue) and (DayOfTheYear(DateValue) = 60) and
    (HoursBetween(IncHour(DateValue, 5), DateValue) = 5), 'date/time replace/span');
  Check(TryStrToDate('2024-02-29', DateValue, Settings) and
    (FormatDateTime('yyyy-mm-dd hh:nn:ss', DateValue + EncodeTime(1, 2, 3, 0),
      Settings) = '2024-02-29 01:02:03'), 'date parse/format explicit settings');
  Check(not TryStrToDate('2023-02-29', DateValue, Settings), 'invalid date parse');
  Check(ContainsText('Alpha-Ж', 'ALPHA'), 'StrUtils ContainsText');
  Check(ReplaceText('a-B-a', 'A', 'x') = 'x-B-x', 'StrUtils ReplaceText');
  Check(ReverseString('abc') = 'cba', 'StrUtils ReverseString');
end;

begin
  try
    TestStrings;
    OperatorInitializes := 0;
    OperatorCopies := 0;
    OperatorFinalizes := 0;
    TestArraysAndManagedLifetime;
    Check((OperatorInitializes > 0) and (OperatorCopies > 0) and
      (OperatorFinalizes > 0), 'custom managed record operator lifecycle');
    TestManagedUnwindAndConstructorFailure;
    TestInterfacesVariantsRttiAndDispatch;
    TestConversionsMathAndDates;
    Check(LiveProbes = 0, 'program final live probes');
    WriteLn('FOUNDATIONS_EXTENDED_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
