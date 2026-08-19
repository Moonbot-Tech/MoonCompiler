program pulse_rtl;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Classes,
  DateUtils,
  Generics.Collections,
  pulse_harness in '..\common\pulse_harness.pas';

type
  TIntegerArray = array of Integer;

  TPulseObject = class
  private
    FValue: UInt64;
  public
    constructor Create(AValue: UInt64);
    function Mix(AValue: UInt64): UInt64; virtual;
  end;

  TPlainPulseObject = class
  end;

var
  SearchText: UnicodeString;
  SearchUtf8: UTF8String;
  ByteData: TBytes;
  IntegerData: TIntegerArray;
  IntegerText: array[0..1023] of UnicodeString;
  FloatText: array[0..1023] of UnicodeString;
  StringKeys: array[0..127] of UnicodeString;
  PaddedKeys: array[0..127] of UnicodeString;
  CsvLine: UnicodeString;
  PulseFormatSettings: TFormatSettings;

constructor TPulseObject.Create(AValue: UInt64);
begin
  inherited Create;
  FValue := AValue;
end;

function TPulseObject.Mix(AValue: UInt64): UInt64;
begin
  Result := (FValue xor AValue) * UInt64($9E3779B185EBCA87);
end;

function CaseUnicodePos(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(Pos('needle-255', SearchText));
end;

function CaseUnicodeCopy(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Copy(SearchText, 1024 + (I and 31), 96);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseUnicodeConcat32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := '';
    for J := 0 to 31 do
      Value := Value + UnicodeString('part-') + UnicodeString(IntToStr(J));
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseUtf8EncodeDecode(Iterations: Integer): UInt64;
var
  I: Integer;
  Raw: UTF8String;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Raw := UTF8Encode(SearchText);
    Text := UTF8ToString(Raw);
    Result := Result + UInt64(Length(Raw)) + UInt64(Length(Text));
  end;
end;

function CaseUnicodeCompareText(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(CompareText(StringKeys[I and 127],
      StringKeys[(I * 37) and 127]) + 2);
end;

function CaseUnicodeLowerCase(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := LowerCase(SearchText);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseUnicodeUpperCase(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := UpperCase(SearchText);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseUtf8Encode(Iterations: Integer): UInt64;
var
  I: Integer;
  Raw: UTF8String;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Raw := UTF8Encode(SearchText);
    Result := Result + UInt64(Length(Raw)) + UInt64(Byte(Raw[1]));
  end;
end;

function CaseUtf8Decode(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Text := UTF8ToString(SearchUtf8);
    Result := Result + UInt64(Length(Text)) + UInt64(Ord(Text[1]));
  end;
end;

function CaseIntToStr32(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := IntToStr(Integer(I * 1009 - 7000001));
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseIntToStr64(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := IntToStr(Int64(I) * 1000003 + Int64(5000000000));
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseStrToInt(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(StrToInt64(IntegerText[I and High(IntegerText)]));
end;

function CaseFloatToStr(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := FloatToStr(I * 0.125, PulseFormatSettings);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseStrDoubleGeneral(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: ShortString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Str(I * 0.125:22, Value);
    Result := Result + UInt64(Length(Value)) + UInt64(Byte(Value[1]));
  end;
end;

function CaseStrToFloat(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Double;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := StrToFloat(FloatText[I and High(FloatText)], PulseFormatSettings);
    Result := Result + UInt64(Trunc(Value * 1000));
  end;
end;

function CaseFormat(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('%d:%.3f', [I, I * 0.125], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseFormatInteger(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('%d', [I], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseFormatLiteral(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('market-value', [], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseFormatString(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('%s', [StringKeys[I and High(StringKeys)]], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseFormatFloat(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('%.3f', [I * 0.125], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseStringListAdd(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TStringList;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TStringList.Create;
    try
      for I := 127 downto 0 do
        List.Add(StringKeys[I]);
      Result := Result + UInt64(List.Count) + UInt64(Length(List[0]));
    finally
      List.Free;
    end;
  end;
end;

function CaseStringListSort(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TStringList;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TStringList.Create;
    try
      for I := 127 downto 0 do
        List.Add(StringKeys[I]);
      List.Sort;
      Result := Result + UInt64(Length(List[0])) + UInt64(Length(List[127]));
    finally
      List.Free;
    end;
  end;
end;

function CaseStringListFind(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TStringList;
begin
  Result := 0;
  List := TStringList.Create;
  try
    for I := 127 downto 0 do
      List.Add(StringKeys[I]);
    List.Sort;
    for Iteration := 1 to Iterations do
      for I := 0 to 127 do
        Result := Result + UInt64(List.IndexOf(StringKeys[(I * 37) and 127]));
  finally
    List.Free;
  end;
end;

function CaseStringListNameValue(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TStringList;
  Value: UnicodeString;
begin
  Result := 0;
  List := TStringList.Create;
  try
    for I := 0 to 127 do
      List.Add(StringKeys[I] + '=' + IntToStr(I * 17));
    for I := 1 to Iterations do
    begin
      Value := List.Values[StringKeys[(I * 37) and 127]];
      Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
    end;
  finally
    List.Free;
  end;
end;

function CaseMemoryStream(Iterations: Integer): UInt64;
var
  Iteration: Integer;
  Stream: TMemoryStream;
  Value: Byte;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(ByteData[0], Length(ByteData));
      Stream.Position := Length(ByteData) div 2;
      Stream.ReadBuffer(Value, SizeOf(Value));
      Result := Result + UInt64(Value) + UInt64(Stream.Size);
    finally
      Stream.Free;
    end;
  end;
end;

function CaseGenericListGrowth(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      for I := 0 to 511 do
        List.Add(I xor Iteration);
      for I := 0 to List.Count - 1 do
        Result := Result + UInt64(List[I]);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListCreateFree(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    Result := Result + UInt64(List.Count);
    List.Free;
  end;
end;

function CaseGenericListCapacity(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 512;
      Result := Result + UInt64(List.Capacity);
    finally
      List.Free;
    end;
  end;
end;

function CaseDynamicArrayCapacity(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TIntegerArray;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    SetLength(Values, 512);
    Values[511] := I;
    Result := Result + UInt64(Values[511]) + UInt64(Length(Values));
    Values := nil;
  end;
end;

function CaseDynamicArrayCopy(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TIntegerArray;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Values := Copy(IntegerData, 128 + (I and 31), 512);
    Result := Result + UInt64(Length(Values)) + UInt64(Values[0]) +
      UInt64(Values[High(Values)]);
  end;
end;

function CaseGenericListAddReserved(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    List.Capacity := Iterations;
    for I := 1 to Iterations do
      Result := Result + UInt64(List.Add(I));
  finally
    List.Free;
  end;
end;

function CaseGenericListReserved(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 512;
      for I := 0 to 511 do
        List.Add(I xor Iteration);
      Result := Result + UInt64(List.Count) + UInt64(List[511]);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListIndex(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    List.Capacity := 512;
    for I := 0 to 511 do
      List.Add(I xor $55AA);
    for Iteration := 1 to Iterations do
      for I := 0 to 511 do
        Result := Result + UInt64(List[I]);
  finally
    List.Free;
  end;
end;

function CaseGenericListEnumerator(Iterations: Integer): UInt64;
var
  Iteration, I, Value: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    List.Capacity := 512;
    for I := 0 to 511 do
      List.Add(I xor $55AA);
    for Iteration := 1 to Iterations do
      for Value in List do
        Result := Result + UInt64(Value);
  finally
    List.Free;
  end;
end;

function CaseGenericListIndexOf(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    List.Capacity := 512;
    for I := 0 to 511 do
      List.Add(I * 17);
    for I := 1 to Iterations do
      Result := Result + UInt64(List.IndexOf(((I * 37) and 511) * 17));
  finally
    List.Free;
  end;
end;

function CaseGenericListDeleteTail(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 512;
      for I := 0 to 511 do
        List.Add(I xor Iteration);
      for I := 511 downto 0 do
        List.Delete(I);
      Result := Result + UInt64(List.Count);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListDeleteFront(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 128;
      for I := 0 to 127 do
        List.Add(I xor Iteration);
      for I := 127 downto 0 do
        List.Delete(0);
      Result := Result + UInt64(List.Count);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListRemove(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 128;
      for I := 0 to 127 do
        List.Add(I * 17);
      for I := 127 downto 0 do
        Result := Result + UInt64(List.Remove(I * 17) + 1);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListSort(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      List.Capacity := 512;
      for I := 0 to 511 do
        List.Add(((I * 313) xor Iteration) and $FFFF);
      List.Sort;
      Result := Result + UInt64(List[0]) + UInt64(List[511]);
    finally
      List.Free;
    end;
  end;
end;

function CaseGenericListBinarySearch(Iterations: Integer): UInt64;
var
  Found: Boolean;
  I, Index: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    List.Capacity := 512;
    for I := 0 to 511 do
      List.Add(I * 17);
    for I := 1 to Iterations do
    begin
      Found := List.BinarySearch(((I * 37) and 511) * 17, Index);
      If Found then
        Result := Result + UInt64(Index);
    end;
  finally
    List.Free;
  end;
end;

function CaseDictionary(Iterations: Integer): UInt64;
var
  Iteration, I, Value: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      for I := 0 to 511 do
        Dictionary.Add(I * 17, I xor $55AA);
      for I := 0 to 511 do
        If Dictionary.TryGetValue(I * 17, Value) then
          Result := Result + UInt64(Value);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryAdd(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      for I := 0 to 511 do
        Dictionary.Add(I * 17, I xor Iteration);
      Result := Result + UInt64(Dictionary.Count);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryAddReserved(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      Dictionary.Capacity := 1024;
      for I := 0 to 511 do
        Dictionary.Add(I * 17, I xor Iteration);
      Result := Result + UInt64(Dictionary.Count);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryCreateFree(Iterations: Integer): UInt64;
var
  I: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    Result := Result + UInt64(Dictionary.Count);
    Dictionary.Free;
  end;
end;

function CaseDictionaryCapacity(Iterations: Integer): UInt64;
var
  I: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      Dictionary.Capacity := 1024;
      Result := Result + UInt64(Ord(Dictionary.Capacity >= 1024));
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryGet(Iterations: Integer): UInt64;
var
  I, Value: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  Dictionary := TDictionary<Integer, Integer>.Create;
  try
    for I := 0 to 511 do
      Dictionary.Add(I * 17, I xor $55AA);
    for I := 1 to Iterations do
      If Dictionary.TryGetValue(((I * 37) and 511) * 17, Value) then
        Result := Result + UInt64(Value);
  finally
    Dictionary.Free;
  end;
end;

function CaseDictionaryUpdateRemove(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      for I := 0 to 255 do
        Dictionary.Add(I * 17, I);
      for I := 0 to 255 do
        Dictionary.AddOrSetValue(I * 17, I xor Iteration);
      for I := 0 to 255 do
      begin
        Dictionary.Remove(I * 17);
        Result := Result + UInt64(Dictionary.Count);
      end;
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseStringDictionaryGet(Iterations: Integer): UInt64;
var
  I, Value: Integer;
  Dictionary: TDictionary<UnicodeString, Integer>;
begin
  Result := 0;
  Dictionary := TDictionary<UnicodeString, Integer>.Create;
  try
    for I := 0 to 127 do
      Dictionary.Add(StringKeys[I], I xor $55AA);
    for I := 1 to Iterations do
      If Dictionary.TryGetValue(StringKeys[(I * 37) and 127], Value) then
        Result := Result + UInt64(Value);
  finally
    Dictionary.Free;
  end;
end;

function CaseQueue(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Queue: TQueue<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Queue := TQueue<Integer>.Create;
    try
      for I := 0 to 511 do
        Queue.Enqueue(I xor Iteration);
      while Queue.Count <> 0 do
        Result := Result + UInt64(Queue.Dequeue);
    finally
      Queue.Free;
    end;
  end;
end;

function CaseQueueReserved(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Queue: TQueue<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Queue := TQueue<Integer>.Create;
    try
      Queue.Capacity := 512;
      for I := 0 to 511 do
        Queue.Enqueue(I xor Iteration);
      while Queue.Count <> 0 do
        Result := Result + UInt64(Queue.Dequeue);
    finally
      Queue.Free;
    end;
  end;
end;

function CaseStack(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Stack: TStack<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Stack := TStack<Integer>.Create;
    try
      Stack.Capacity := 512;
      for I := 0 to 511 do
        Stack.Push(I xor Iteration);
      while Stack.Count <> 0 do
        Result := Result + UInt64(Stack.Pop);
    finally
      Stack.Free;
    end;
  end;
end;

function CaseObjectLifecycle(Iterations: Integer): UInt64;
var
  I: Integer;
  Instance: TPulseObject;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Instance := TPulseObject.Create(UInt64(I));
    try
      Result := Result xor Instance.Mix(UInt64(I * 17));
    finally
      Instance.Free;
    end;
  end;
end;

procedure InitializeData;
var
  I: Integer;
begin
  PulseFormatSettings := TFormatSettings.Create;
  PulseFormatSettings.DecimalSeparator := '.';
  SearchText := '';
  for I := 0 to 255 do
    SearchText := SearchText + UnicodeString('market-') + UnicodeString(IntToStr(I)) +
      UnicodeString(':needle-') + UnicodeString(IntToStr(I)) + UnicodeString(';');
  SearchUtf8 := UTF8Encode(SearchText);
  for I := 0 to High(StringKeys) do
  begin
    StringKeys[I] := UnicodeString('key-') + UnicodeString(IntToStr(10000 + I));
    PaddedKeys[I] := UnicodeString('  ') + StringKeys[I] + UnicodeString('   ');
  end;
  for I := 0 to High(IntegerText) do
  begin
    IntegerText[I] := IntToStr(Int64(I) * 1000003 - 500000000);
    FloatText[I] := IntToStr(I - 512) + '.125';
  end;
  CsvLine := '';
  for I := 0 to 15 do
  begin
    If I > 0 then
      CsvLine := CsvLine + UnicodeString(',');
    CsvLine := CsvLine + UnicodeString('field-') + UnicodeString(IntToStr(I * 31));
  end;
  SetLength(ByteData, 65536);
  for I := 0 to High(ByteData) do
    ByteData[I] := Byte(I * 17 + 29);
  SetLength(IntegerData, 1024);
  for I := 0 to High(IntegerData) do
    IntegerData[I] := I * 17 + 29;
end;

function CaseObjectAllocZeroFree(Iterations: Integer): UInt64;
var
  I: Integer;
  P: Pointer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    P := AllocMem(TPlainPulseObject.InstanceSize);
    Result := Result + UInt64(Ord(P <> nil));
    FreeMem(P);
  end;
end;

function CaseObjectNewFreeInstance(Iterations: Integer): UInt64;
var
  I: Integer;
  Instance: TPlainPulseObject;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Instance := TPlainPulseObject(TPlainPulseObject.NewInstance);
    Result := Result + UInt64(Ord(Instance <> nil));
    Instance.FreeInstance;
  end;
end;

function CaseObjectCreateFree(Iterations: Integer): UInt64;
var
  I: Integer;
  Instance: TPlainPulseObject;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Instance := TPlainPulseObject.Create;
    Result := Result + UInt64(Ord(Instance <> nil));
    Instance.Free;
  end;
end;

function CaseObjectVirtualCall(Iterations: Integer): UInt64;
var
  I: Integer;
  Instance: TPulseObject;
begin
  Result := 0;
  Instance := TPulseObject.Create(17);
  try
    for I := 1 to Iterations do
      Result := Result xor Instance.Mix(UInt64(I));
  finally
    Instance.Free;
  end;
end;

{ === RTL audit block 3: streams, stringlist depth, short strings === }

function CaseMemoryStreamWriteSmall(Iterations: Integer): UInt64;
var
  I, J: Integer;
  MS: TMemoryStream;
  Packet: array[0..15] of Byte;
begin
  Result := 0;
  for J := 0 to High(Packet) do
    Packet[J] := Byte(J * 31 + 7);
  MS := TMemoryStream.Create;
  try
    for I := 1 to Iterations do
    begin
      MS.Position := 0;
      for J := 1 to 64 do
        MS.Write(Packet, SizeOf(Packet));
      Result := Result + UInt64(MS.Position);
    end;
  finally
    MS.Free;
  end;
end;

function CaseStringStreamBuild(Iterations: Integer): UInt64;
var
  I, J: Integer;
  SS: TStringStream;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    SS := TStringStream.Create('');
    try
      for J := 0 to 31 do
        SS.WriteString(StringKeys[J]);
      Result := Result + UInt64(Length(SS.DataString));
    finally
      SS.Free;
    end;
  end;
end;

function CaseStringListDelimited(Iterations: Integer): UInt64;
var
  I: Integer;
  SL: TStringList;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Delimiter := ',';
    SL.StrictDelimiter := True;
    for I := 1 to Iterations do
    begin
      SL.DelimitedText := 'BTCUSDT,3.14159,buy,1024,0x1F,true,ETHUSDT,2.71828';
      Result := Result + UInt64(SL.Count) + UInt64(Length(SL[3]));
    end;
  finally
    SL.Free;
  end;
end;

function CaseStringListValues(Iterations: Integer): UInt64;
var
  I: Integer;
  SL: TStringList;
  V: string;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    for I := 0 to 31 do
      SL.Add(StringKeys[I] + '=' + IntegerText[I]);
    for I := 1 to Iterations do
    begin
      V := SL.Values[StringKeys[I and 31]];
      Result := Result + UInt64(Length(V));
    end;
  finally
    SL.Free;
  end;
end;

function CaseLowerCaseShort(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Text := LowerCase(StringKeys[I and 127]);
    Result := Result + UInt64(Length(Text)) + UInt64(Ord(Text[1]));
  end;
end;

{ === RTL audit block: DateTime, hex, trim, replace, try-parse === }

function CaseDateTimeNow(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  { the wall clock is nondeterministic: the oracle counts calls that
    returned a plausible value, the timing measures the call itself }
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(Ord(Now > 45000.0));
end;

function CaseDateTimeEncodeDecode(Iterations: Integer): UInt64;
var
  I: Integer;
  DT: TDateTime;
  Y, Mo, D, H, Mi, S, MS: Word;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    DT := EncodeDate(2026, 1 + (I mod 12), 1 + (I mod 28)) +
      EncodeTime(I mod 24, I mod 60, (I * 7) mod 60, (I * 13) mod 1000);
    DecodeDate(DT, Y, Mo, D);
    DecodeTime(DT, H, Mi, S, MS);
    Result := Result + UInt64(Y) + UInt64(Mo) + UInt64(D) +
      UInt64(H) + UInt64(Mi) + UInt64(S) + UInt64(MS);
  end;
end;

function CaseDateTimeFormat(Iterations: Integer): UInt64;
var
  I: Integer;
  DT: TDateTime;
  Text: string;
begin
  Result := 0;
  DT := EncodeDate(2026, 8, 18) + EncodeTime(13, 45, 59, 250);
  for I := 1 to Iterations do
  begin
    Text := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', DT + (I and 255) * (1.0 / 86400.0));
    Result := Result + UInt64(Length(Text)) + UInt64(Ord(Text[18]));
  end;
end;

function CaseDateTimeMsArith(Iterations: Integer): UInt64;
var
  I: Integer;
  A, B: TDateTime;
begin
  Result := 0;
  A := EncodeDate(2026, 8, 18) + EncodeTime(13, 45, 59, 250);
  for I := 1 to Iterations do
  begin
    B := IncMilliSecond(A, I and 1023);
    Result := Result + UInt64(MilliSecondsBetween(A, B));
  end;
end;

function CaseIntToHex64(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Text := IntToHex(UInt64(I) * $9E3779B185EBCA87, 16);
    Result := Result + UInt64(Length(Text)) + UInt64(Ord(Text[1]));
  end;
end;

function CaseTrimString(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Text := Trim(PaddedKeys[I and 127]);
    Result := Result + UInt64(Length(Text));
  end;
end;

{ === RTL remainder audit: TStringHelper facades === }

function CaseHelperStartsWith(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result + UInt64(Ord(StringKeys[I and 127].StartsWith(UnicodeString('key-101'))));
    Result := Result + UInt64(Ord(StringKeys[I and 127].StartsWith(UnicodeString('nope'))));
  end;
end;

function CaseHelperStartsWithNoCase(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result + UInt64(Ord(StringKeys[I and 127].StartsWith(UnicodeString('KEY-101'), True)));
    Result := Result + UInt64(Ord(StringKeys[I and 127].StartsWith(UnicodeString('NOPE'), True)));
  end;
end;

function CaseHelperEndsWithNoCase(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result + UInt64(Ord(StringKeys[I and 127].EndsWith(UnicodeString('27'), True)));
    Result := Result + UInt64(Ord(StringKeys[I and 127].EndsWith(UnicodeString('ZZ'), True)));
  end;
end;

function CaseHelperIndexOfString(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(SearchText.IndexOf(UnicodeString('needle-') +
      UnicodeString(IntToStr(I and 255))) + 2);
end;

function CaseHelperCompareTo(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(StringKeys[I and 127].CompareTo(StringKeys[(I * 37) and 127]) + 1000);
end;

function CaseHelperSplit(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Parts: TArray<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Parts := CsvLine.Split([WideChar(',')]);
    Result := Result + UInt64(Length(Parts));
    for J := 0 to High(Parts) do
      Result := Result + UInt64(Length(Parts[J]));
  end;
end;

function CaseSameTextShort(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Result := Result + UInt64(Ord(SameText(StringKeys[I and 127], StringKeys[I and 127])));
    Result := Result + UInt64(Ord(SameText(StringKeys[I and 127], StringKeys[(I + 1) and 127])));
  end;
end;

function CaseStringReplaceAll(Iterations: Integer): UInt64;
var
  I: Integer;
  Text: string;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Text := StringReplace(
      '{"px":"0.00","qty":"0.00","side":"buy","px2":"0.00"}',
      '0.00', IntegerText[I and 1023], [rfReplaceAll]);
    Result := Result + UInt64(Length(Text));
  end;
end;

function CaseTryStrToIntLoop(Iterations: Integer): UInt64;
var
  I, V: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    if TryStrToInt(IntegerText[I and 1023], V) then
      Result := Result + UInt64(Cardinal(V));
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_rtl', Profile, SelectedCase);
  InitializeData;
  Found := False;
  PulseRunCase('pulse_rtl', 'unicode-pos-4k', 'rtl', 'UnicodeString',
    @CaseUnicodePos, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-copy-96', 'rtl+mm', 'UnicodeString',
    @CaseUnicodeCopy, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-concat-32', 'rtl+mm', 'UnicodeString',
    @CaseUnicodeConcat32, 32, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-comparetext', 'rtl', 'CompareText',
    @CaseUnicodeCompareText, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-lowercase-4k', 'rtl+mm', 'LowerCase',
    @CaseUnicodeLowerCase, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-uppercase-4k', 'rtl+mm', 'UpperCase',
    @CaseUnicodeUpperCase, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'utf8-encode-decode-4k', 'rtl+mm', 'UTF8String',
    @CaseUtf8EncodeDecode, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'utf8-encode-4k', 'rtl+mm', 'UTF8Encode',
    @CaseUtf8Encode, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'utf8-decode-4k', 'rtl+mm', 'UTF8ToString',
    @CaseUtf8Decode, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'memorystream-write-small', 'rtl+mm',
    'TMemoryStream.Write(16b)', @CaseMemoryStreamWriteSmall, 64, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringstream-build', 'rtl+mm',
    'TStringStream.WriteString', @CaseStringStreamBuild, 32, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-delimited', 'rtl+mm',
    'TStringList.DelimitedText', @CaseStringListDelimited, 8, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-values', 'rtl+mm',
    'TStringList.Values', @CaseStringListValues, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'lowercase-short', 'rtl+mm', 'LowerCase(short)',
    @CaseLowerCaseShort, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'datetime-now', 'rtl', 'Now',
    @CaseDateTimeNow, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'datetime-encode-decode', 'rtl',
    'EncodeDate/DecodeTime', @CaseDateTimeEncodeDecode, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'datetime-format', 'rtl+mm', 'FormatDateTime',
    @CaseDateTimeFormat, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'datetime-ms-arith', 'rtl',
    'IncMilliSecond/MilliSecondsBetween', @CaseDateTimeMsArith, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'inttohex-int64', 'rtl+mm', 'IntToHex',
    @CaseIntToHex64, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-startswith', 'rtl', 'TStringHelper.StartsWith',
    @CaseHelperStartsWith, 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-startswith-nocase', 'rtl+mm', 'TStringHelper.StartsWith(IgnoreCase)',
    @CaseHelperStartsWithNoCase, 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-endswith-nocase', 'rtl+mm', 'TStringHelper.EndsWith(IgnoreCase)',
    @CaseHelperEndsWithNoCase, 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-indexof-string', 'rtl+mm', 'TStringHelper.IndexOf',
    @CaseHelperIndexOfString, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-compareto', 'rtl', 'TStringHelper.CompareTo',
    @CaseHelperCompareTo, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'helper-split-16', 'rtl+mm', 'TStringHelper.Split',
    @CaseHelperSplit, 16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'sametext-short', 'rtl', 'SameText',
    @CaseSameTextShort, 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'trim-string', 'rtl+mm', 'Trim',
    @CaseTrimString, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'string-replace-all', 'rtl+mm', 'StringReplace',
    @CaseStringReplaceAll, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'trystrtoint', 'rtl', 'TryStrToInt',
    @CaseTryStrToIntLoop, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'inttostr-int32', 'rtl+mm', 'IntToStr(Integer)',
    @CaseIntToStr32, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'inttostr-int64', 'rtl+mm', 'IntToStr(Int64)', @CaseIntToStr64,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'strtoint-int64', 'rtl+mm', 'StrToInt64', @CaseStrToInt,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'floattostr-double', 'rtl+mm', 'FloatToStr',
    @CaseFloatToStr, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'str-double-general', 'rtl',
    'Str(Double general, ShortString)', @CaseStrDoubleGeneral, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'strtofloat-double', 'rtl+mm', 'StrToFloat',
    @CaseStrToFloat, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-mixed', 'rtl+mm', 'Format', @CaseFormat, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-integer', 'rtl+mm', 'Format integer',
    @CaseFormatInteger, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-literal', 'rtl+mm', 'Format literal',
    @CaseFormatLiteral, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-string', 'rtl+mm', 'Format string',
    @CaseFormatString, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-float', 'rtl+mm', 'Format float',
    @CaseFormatFloat, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-add-128', 'rtl+mm', 'TStringList.Add',
    @CaseStringListAdd, 128, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-add-sort-128', 'rtl+mm',
    'TStringList.Sort', @CaseStringListSort, 128, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-indexof-128', 'rtl',
    'TStringList.IndexOf', @CaseStringListFind, 128, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-namevalue', 'rtl',
    'TStringList.Values', @CaseStringListNameValue, 1, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_rtl', 'memorystream-64k', 'rtl+mm', 'TMemoryStream',
    @CaseMemoryStream, Length(ByteData), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-growth-512', 'rtl+mm',
    'TList<Integer>.Add growth', @CaseGenericListGrowth, 512, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-create-free', 'rtl+mm',
    'TList<Integer>.Create/Free', @CaseGenericListCreateFree, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-capacity-512', 'rtl+mm',
    'TList<Integer>.Capacity', @CaseGenericListCapacity, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dynamic-array-capacity-512', 'rtl+mm',
    'SetLength(Integer array)', @CaseDynamicArrayCapacity, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dynamic-array-copy-512', 'rtl+mm',
    'Copy(Integer array)', @CaseDynamicArrayCopy, 512, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_rtl', 'generic-list-add-reserved', 'rtl',
    'TList<Integer>.Add preallocated', @CaseGenericListAddReserved, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-reserved-512', 'rtl+mm',
    'TList<Integer>.Add reserved', @CaseGenericListReserved, 512, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-index-512', 'rtl',
    'TList<Integer>.Items', @CaseGenericListIndex, 512, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_rtl', 'generic-list-enumerator-512', 'rtl',
    'TList<Integer>.Enumerator', @CaseGenericListEnumerator, 512, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-indexof', 'rtl',
    'TList<Integer>.IndexOf', @CaseGenericListIndexOf, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-delete-tail-512', 'rtl',
    'TList<Integer>.Delete tail', @CaseGenericListDeleteTail, 512, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-delete-front-128', 'rtl',
    'TList<Integer>.Delete front', @CaseGenericListDeleteFront, 128, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-remove-128', 'rtl',
    'TList<Integer>.Remove', @CaseGenericListRemove, 128, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-sort-512', 'rtl',
    'TList<Integer>.Sort', @CaseGenericListSort, 1, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_rtl', 'generic-list-binarysearch', 'rtl',
    'TList<Integer>.BinarySearch', @CaseGenericListBinarySearch, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-512', 'rtl+mm',
    'TDictionary<Integer,Integer>', @CaseDictionary, 1024, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-add-512', 'rtl+mm',
    'TDictionary<Integer,Integer>.Add', @CaseDictionaryAdd, 512, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-add-reserved-512', 'rtl+mm',
    'TDictionary<Integer,Integer>.Add preallocated',
    @CaseDictionaryAddReserved, 512, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-create-free', 'rtl+mm',
    'TDictionary<Integer,Integer>.Create/Free', @CaseDictionaryCreateFree, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-capacity-1024', 'rtl+mm',
    'TDictionary<Integer,Integer>.Capacity', @CaseDictionaryCapacity, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-get', 'rtl',
    'TDictionary<Integer,Integer>.TryGetValue', @CaseDictionaryGet, 1, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-update-remove-256', 'rtl+mm',
    'TDictionary<Integer,Integer>.Update/Remove', @CaseDictionaryUpdateRemove,
    512, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-string-get', 'rtl',
    'TDictionary<UnicodeString,Integer>.TryGetValue', @CaseStringDictionaryGet,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'queue-512', 'rtl+mm', 'TQueue<Integer>', @CaseQueue,
    1024, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'queue-reserved-512', 'rtl',
    'TQueue<Integer> reserved', @CaseQueueReserved, 1024, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stack-512', 'rtl', 'TStack<Integer>', @CaseStack,
    1024, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'object-create-virtual-free', 'rtl+mm', 'TObject',
    @CaseObjectLifecycle, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'object-alloc-zero-free', 'mm',
    'AllocMem/FreeMem object-sized block', @CaseObjectAllocZeroFree, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'object-new-freeinstance', 'rtl+mm',
    'TObject.NewInstance/FreeInstance', @CaseObjectNewFreeInstance, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'object-create-free', 'rtl+mm',
    'TObject.Create/Free', @CaseObjectCreateFree, 1, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_rtl', 'object-virtual-call', 'rtl',
    'virtual method dispatch', @CaseObjectVirtualCall, 1, Profile,
    SelectedCase, Found);
  PulseFinish('pulse_rtl', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
