program pulse_rtl_collections;

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
  Generics.Defaults,
  Generics.Collections,
  pulse_harness in '..\common\pulse_harness.pas';

const
  ItemCount = 256;
  BulkItemCount = 4096;

type
  TIntegerArray = array of Integer;
  TStringArray = array of UnicodeString;

  TLargeQueueItem = record
    Words: array[0..15] of UInt64;
  end;

  TConstantHashComparer = class(TInterfacedObject,
    IEqualityComparer<Integer>)
  public
    function Equals(const Left, Right: Integer): Boolean; reintroduce;
    function GetHashCode(const Value: Integer):
      {$ifdef FPC}UInt32{$else}Integer{$endif}; reintroduce;
  end;

  TPulseObject = class
  public
    Value: Integer;
    constructor Create(AValue: Integer);
  end;

var
  Integers: TIntegerArray;
  BulkIntegers: TIntegerArray;
  BulkMiddle: TIntegerArray;
  PackedIntegers: TIntegerArray;
  Strings: TStringArray;
  BulkStrings: TStringArray;
  BulkMiddleStrings: TStringArray;
  PreparedBulkIntegerList: TList<Integer>;
  PreparedIntegerList: TList<Integer>;
  PreparedStringList: TList<UnicodeString>;
  PreparedIntegerDictionary: TDictionary<Integer, Integer>;
  PreparedStringDictionary: TDictionary<UnicodeString, Integer>;

function TConstantHashComparer.Equals(const Left, Right: Integer): Boolean;
begin
  Result := Left = Right;
end;

function TConstantHashComparer.GetHashCode(const Value: Integer):
  {$ifdef FPC}UInt32{$else}Integer{$endif};
begin
  Result := 1;
end;

constructor TPulseObject.Create(AValue: Integer);
begin
  inherited Create;
  Value := AValue;
end;

procedure InitializeData;
var
  I: Integer;
begin
  SetLength(Integers, ItemCount);
  SetLength(BulkIntegers, BulkItemCount);
  SetLength(BulkMiddle, BulkItemCount div 2);
  SetLength(PackedIntegers, BulkItemCount);
  SetLength(Strings, ItemCount);
  SetLength(BulkStrings, BulkItemCount);
  SetLength(BulkMiddleStrings, BulkItemCount div 2);
  PreparedBulkIntegerList := TList<Integer>.Create;
  PreparedIntegerList := TList<Integer>.Create;
  PreparedStringList := TList<UnicodeString>.Create;
  PreparedIntegerDictionary := TDictionary<Integer, Integer>.Create;
  PreparedStringDictionary := TDictionary<UnicodeString, Integer>.Create;
  PreparedIntegerList.Capacity := ItemCount;
  PreparedStringList.Capacity := ItemCount;
  PreparedIntegerDictionary.Capacity := ItemCount;
  PreparedStringDictionary.Capacity := ItemCount;
  PreparedBulkIntegerList.Capacity := BulkItemCount;
  for I := 0 to ItemCount - 1 do begin
    Integers[I] := (I * 197 + 17) and $7fffffff;
    Strings[I] := UnicodeString('item-') + UnicodeString(IntToStr(I * 197 + 17));
    PreparedIntegerList.Add(Integers[I]);
    PreparedStringList.Add(Strings[I]);
    PreparedIntegerDictionary.Add(Integers[I], I);
    PreparedStringDictionary.Add(Strings[I], I);
  end;
  for I := 0 to BulkItemCount - 1 do begin
    BulkIntegers[I] := I + 1;
    PreparedBulkIntegerList.Add(BulkIntegers[I]);
    If Odd(I) then
      PackedIntegers[I] := I + 1
    else
      PackedIntegers[I] := 0;
    If I < Length(BulkMiddle) then
      BulkMiddle[I] := BulkIntegers[BulkItemCount div 4 + I];
    BulkStrings[I] := UnicodeString('bulk-item-') +
      UnicodeString(IntToStr(I + 1));
    If I < Length(BulkMiddleStrings) then
      BulkMiddleStrings[I] := BulkStrings[BulkItemCount div 4 + I];
  end;
end;

procedure FinalizeData;
begin
  PreparedStringDictionary.Free;
  PreparedIntegerDictionary.Free;
  PreparedStringList.Free;
  PreparedIntegerList.Free;
  PreparedBulkIntegerList.Free;
end;

function CaseListStringAddReserved(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<UnicodeString>.Create;
    try
      List.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        List.Add(Strings[J]);
      Result := Result + UInt64(List.Count) + UInt64(Length(List[ItemCount - 1]));
    finally
      List.Free;
    end;
  end;
end;

function CaseListStringRead(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to PreparedStringList.Count - 1 do
      Result := Result + UInt64(Length(PreparedStringList[J]));
end;

function CaseListStringEnumerate(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Value in PreparedStringList do
      Result := Result + UInt64(Length(Value));
end;

function CaseListStringInsertDelete(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<UnicodeString>.Create;
    try
      List.Capacity := ItemCount;
      for J := 0 to ItemCount div 2 - 1 do
        List.Add(Strings[J]);
      for J := 0 to ItemCount div 2 - 1 do
        List.Insert(J * 2, Strings[ItemCount div 2 + J]);
      for J := 1 to ItemCount div 2 do
        List.Delete(List.Count div 2);
      Result := Result + UInt64(List.Count) + UInt64(Length(List[List.Count - 1]));
    finally
      List.Free;
    end;
  end;
end;

function CaseListStringToArray(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TArray<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Values := PreparedStringList.ToArray;
    Result := Result + UInt64(Length(Values)) + UInt64(Length(Values[I and 255]));
  end;
end;

function CaseListExchangeReverse(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create(PreparedIntegerList);
    try
      for J := 0 to 63 do
        List.Exchange(J, ItemCount - 1 - J);
      List.Reverse;
      Result := Result + UInt64(List[0]) + UInt64(List[ItemCount - 1]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerCopyConstruct(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create(PreparedIntegerList);
    try
      Result := Result + UInt64(List.Count) + UInt64(List[0]) +
        UInt64(List[ItemCount - 1]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerEmptyCreate(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create;
    try
      Result := Result + UInt64(List.Count);
    finally
      List.Free;
    end;
  end;
end;

function CaseArrayIntegerCopy(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TIntegerArray;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Values := Copy(Integers);
    Result := Result + UInt64(Length(Values)) + UInt64(Values[0]) +
      UInt64(Values[ItemCount - 1]);
  end;
end;

function CaseListIntegerExchange(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create(PreparedIntegerList);
  try
    for I := 1 to Iterations do
      for J := 0 to 63 do
        List.Exchange(J, ItemCount - 1 - J);
    Result := UInt64(List[0]) + UInt64(List[ItemCount - 1]);
  finally
    List.Free;
  end;
end;

function CaseListIntegerReverse(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create(PreparedIntegerList);
  try
    for I := 1 to Iterations do
      List.Reverse;
    Result := UInt64(List[0]) + UInt64(List[ItemCount - 1]);
  finally
    List.Free;
  end;
end;

function CaseListIntegerAddRange(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create;
    try
      List.AddRange(BulkIntegers);
      Result := Result + UInt64(List.Count) + UInt64(List[0]) +
        UInt64(List[BulkItemCount - 1]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerInsertRangeList(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create(BulkIntegers);
    try
      List.InsertRange(BulkItemCount div 2,
        TEnumerable<Integer>(PreparedBulkIntegerList));
      Result := Result + UInt64(List.Count) +
        UInt64(List[BulkItemCount div 2]) +
        UInt64(List[BulkItemCount + BulkItemCount div 2]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerPackAlternating(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create(PackedIntegers);
    try
      List.Pack;
      Result := Result + UInt64(List.Count) + UInt64(List[0]) +
        UInt64(List[List.Count - 1]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerDeleteInsertRange(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create(BulkIntegers);
  try
    List.Capacity := BulkItemCount + 16;
    for I := 1 to Iterations do begin
      List.DeleteRange(BulkItemCount div 4, BulkItemCount div 2);
      List.InsertRange(BulkItemCount div 4, BulkMiddle);
      Result := Result + UInt64(List.Count) +
        UInt64(List[BulkItemCount div 4]) + UInt64(List[BulkItemCount - 1]);
    end;
  finally
    List.Free;
  end;
end;

function CaseListStringAddRange(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<UnicodeString>.Create;
    try
      List.AddRange(BulkStrings);
      Result := Result + UInt64(List.Count) + UInt64(Length(List[0])) +
        UInt64(Length(List[BulkItemCount - 1]));
    finally
      List.Free;
    end;
  end;
end;

function CaseListStringInsertRange(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<UnicodeString>.Create(BulkStrings);
    try
      List.InsertRange(BulkItemCount div 4, BulkMiddleStrings);
      Result := Result + UInt64(List.Count) +
        UInt64(Length(List[BulkItemCount div 4])) +
        UInt64(Length(List[BulkItemCount + BulkItemCount div 4]));
    finally
      List.Free;
    end;
  end;
end;

function CaseListIntegerClear(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  List := TList<Integer>.Create;
  try
    for I := 1 to Iterations do begin
      List.AddRange(BulkIntegers);
      Result := Result + UInt64(List.Count) + UInt64(List[BulkItemCount - 1]);
      List.Clear;
    end;
  finally
    List.Free;
  end;
end;

function CaseListStringClear(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  List := TList<UnicodeString>.Create;
  try
    for I := 1 to Iterations do begin
      List.AddRange(BulkStrings);
      Result := Result + UInt64(List.Count) +
        UInt64(Length(List[BulkItemCount - 1]));
      List.Clear;
    end;
  finally
    List.Free;
  end;
end;

function CaseListIntegerIndexOf(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do begin
      Result := Result + UInt64(PreparedIntegerList.IndexOf(Integers[J]) + 1);
      Result := Result + UInt64(PreparedIntegerList.IndexOf(-J - 1) + 1);
    end;
end;

function CaseListStringIndexOf(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Result := Result + UInt64(PreparedStringList.IndexOf(Strings[J]) + 1);
end;

function CaseListIntegerSort(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<Integer>.Create(Integers);
    try
      List.Sort;
      Result := Result + UInt64(List[0]) + UInt64(List[ItemCount - 1]);
    finally
      List.Free;
    end;
  end;
end;

function CaseListStringSort(Iterations: Integer): UInt64;
var
  I: Integer;
  List: TList<UnicodeString>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TList<UnicodeString>.Create(Strings);
    try
      List.Sort;
      Result := Result + UInt64(Length(List[0])) +
        UInt64(Length(List[ItemCount - 1]));
    finally
      List.Free;
    end;
  end;
end;

function CaseObjectListOwnedClear(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TObjectList<TPulseObject>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    List := TObjectList<TPulseObject>.Create(True);
    try
      List.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        List.Add(TPulseObject.Create(J + 1));
      Result := Result + UInt64(List.Count) + UInt64(List[ItemCount - 1].Value);
      List.Clear;
    finally
      List.Free;
    end;
  end;
end;

function CaseArrayIntegerSort(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TIntegerArray;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Values := Copy(Integers);
    TArray.Sort<Integer>(Values);
    Result := Result + UInt64(Values[0]) + UInt64(Values[ItemCount - 1]);
  end;
end;

function CaseArrayStringSort(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TStringArray;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Values := Copy(Strings);
    TArray.Sort<UnicodeString>(Values);
    Result := Result + UInt64(Length(Values[0])) + UInt64(Length(Values[ItemCount - 1]));
  end;
end;

function CaseArrayBinarySearch(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
  Found: Boolean;
  Values: TIntegerArray;
begin
  Values := Copy(Integers);
  TArray.Sort<Integer>(Values);
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do begin
      Found := TArray.BinarySearch<Integer>(Values, Integers[J], Index);
      Result := Result + UInt64(Ord(Found)) + UInt64(Index);
    end;
end;

function CaseDictionaryContainsKey(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do begin
      Inc(Result, Ord(PreparedIntegerDictionary.ContainsKey(Integers[J])));
      Inc(Result, Ord(PreparedIntegerDictionary.ContainsKey(-J - 1)));
    end;
end;

function CaseDictionaryContainsValue(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 31 do begin
      Inc(Result, Ord(PreparedIntegerDictionary.ContainsValue(J * 7)));
      Inc(Result, Ord(PreparedIntegerDictionary.ContainsValue(ItemCount + J)));
    end;
end;

function CaseDictionaryTryAdd(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      Dictionary.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        Inc(Result, Ord(Dictionary.TryAdd(Integers[J], J)));
      for J := 0 to ItemCount - 1 do
        Inc(Result, Ord(Dictionary.TryAdd(Integers[J], J)));
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryAddOrSet(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  Dictionary := TDictionary<Integer, Integer>.Create;
  try
    Dictionary.Capacity := ItemCount;
    for J := 0 to ItemCount - 1 do
      Dictionary.Add(Integers[J], J);
    for I := 1 to Iterations do begin
      for J := 0 to ItemCount - 1 do
        Dictionary.AddOrSetValue(Integers[J], I + J);
      Dictionary.TryGetValue(Integers[I and 255], Value);
      Result := Result + UInt64(Value);
    end;
  finally
    Dictionary.Free;
  end;
end;

function CaseDictionaryPairs(Iterations: Integer): UInt64;
var
  I: Integer;
  Pair: TPair<Integer, Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Pair in PreparedIntegerDictionary do
      Result := Result + UInt64(Pair.Key) + UInt64(Pair.Value);
end;

function CaseDictionaryKeys(Iterations: Integer): UInt64;
var
  I, Key: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Key in PreparedIntegerDictionary.Keys do
      Result := Result + UInt64(Key);
end;

function CaseDictionaryValues(Iterations: Integer): UInt64;
var
  I, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Value in PreparedIntegerDictionary.Values do
      Result := Result + UInt64(Value);
end;

function CaseDictionaryStringAdd(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Dictionary: TDictionary<UnicodeString, Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Dictionary := TDictionary<UnicodeString, Integer>.Create;
    try
      Dictionary.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        Dictionary.Add(Strings[J], J);
      Result := Result + UInt64(Dictionary.Count);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryStringContains(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ItemCount - 1 do
      Inc(Result, Ord(PreparedStringDictionary.ContainsKey(Strings[J])));
end;

function CaseDictionaryCollisionChurn(Iterations: Integer): UInt64;
var
  Dictionary: TDictionary<Integer, Integer>;
  I, J, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Dictionary := TDictionary<Integer, Integer>.Create(
      TConstantHashComparer.Create);
    try
      Dictionary.Capacity := 64;
      for J := 0 to 63 do
        Dictionary.Add(J, J * 3);
      for J := 0 to 63 do begin
        If Dictionary.TryGetValue(J, Value) then
          Result := Result + UInt64(Value);
      end;
      for J := 0 to 31 do
        Dictionary.Remove(J * 2);
      Result := Result + UInt64(Dictionary.Count);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseDictionaryStringClear(Iterations: Integer): UInt64;
var
  Dictionary: TDictionary<UnicodeString, Integer>;
  I, J: Integer;
begin
  Result := 0;
  Dictionary := TDictionary<UnicodeString, Integer>.Create;
  try
    for I := 1 to Iterations do begin
      for J := 0 to ItemCount - 1 do
        Dictionary.Add(Strings[J], J);
      Result := Result + UInt64(Dictionary.Count);
      Dictionary.Clear;
    end;
  finally
    Dictionary.Free;
  end;
end;

function CaseQueueStringRoundTrip(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Queue: TQueue<UnicodeString>;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Queue := TQueue<UnicodeString>.Create;
    try
      Queue.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        Queue.Enqueue(Strings[J]);
      for J := 0 to ItemCount - 1 do begin
        Value := Queue.Dequeue;
        Result := Result + UInt64(Length(Value));
      end;
    finally
      Queue.Free;
    end;
  end;
end;

function CaseQueueStringSteady(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Queue: TQueue<UnicodeString>;
  Value: UnicodeString;
begin
  Result := 0;
  Queue := TQueue<UnicodeString>.Create;
  try
    Queue.Capacity := ItemCount;
    for J := 0 to ItemCount - 1 do
      Queue.Enqueue(Strings[J]);
    for I := 1 to Iterations do begin
      Value := Queue.Dequeue;
      Result := Result + UInt64(Length(Value));
      Queue.Enqueue(Value);
    end;
  finally
    Queue.Free;
  end;
end;

function CaseQueueEnumerate(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Queue: TQueue<Integer>;
begin
  Result := 0;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Capacity := ItemCount;
    for J := 0 to ItemCount - 1 do
      Queue.Enqueue(Integers[J]);
    for I := 1 to Iterations do
      for J in Queue do
        Result := Result + UInt64(J);
  finally
    Queue.Free;
  end;
end;

function CaseQueueLargeRecordSteady(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Item: TLargeQueueItem;
  Queue: TQueue<TLargeQueueItem>;
begin
  Result := 0;
  Queue := TQueue<TLargeQueueItem>.Create;
  try
    Queue.Capacity := ItemCount;
    for I := 0 to ItemCount - 1 do begin
      FillChar(Item,SizeOf(Item),0);
      Item.Words[0] := UInt64(I + 1);
      Item.Words[High(Item.Words)] := UInt64(I + 17);
      Queue.Enqueue(Item);
    end;
    for J := 1 to Iterations do begin
      Item := Queue.Dequeue;
      Result := Result + Item.Words[0] + Item.Words[High(Item.Words)];
      Queue.Enqueue(Item);
    end;
  finally
    Queue.Free;
  end;
end;

function CaseQueueStringClear(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Queue: TQueue<UnicodeString>;
begin
  Result := 0;
  Queue := TQueue<UnicodeString>.Create;
  try
    Queue.Capacity := ItemCount;
    for I := 1 to Iterations do begin
      for J := 0 to ItemCount - 1 do
        Queue.Enqueue(Strings[J]);
      Result := Result + UInt64(Queue.Count);
      Queue.Clear;
    end;
  finally
    Queue.Free;
  end;
end;

function CaseQueueIntegerSteady(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
  Queue: TQueue<Integer>;
begin
  Result := 0;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Capacity := ItemCount;
    for J := 0 to ItemCount - 1 do
      Queue.Enqueue(Integers[J]);
    for I := 1 to Iterations do begin
      Value := Queue.Dequeue;
      Result := Result + UInt64(Value);
      Queue.Enqueue(Value);
    end;
  finally
    Queue.Free;
  end;
end;

function CaseStackStringRoundTrip(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Stack: TStack<UnicodeString>;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Stack := TStack<UnicodeString>.Create;
    try
      Stack.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        Stack.Push(Strings[J]);
      for J := 0 to ItemCount - 1 do begin
        Value := Stack.Pop;
        Result := Result + UInt64(Length(Value));
      end;
    finally
      Stack.Free;
    end;
  end;
end;

function CaseStackEnumerate(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Stack: TStack<Integer>;
begin
  Result := 0;
  Stack := TStack<Integer>.Create;
  try
    Stack.Capacity := ItemCount;
    for J := 0 to ItemCount - 1 do
      Stack.Push(Integers[J]);
    for I := 1 to Iterations do
      for J in Stack do
        Result := Result + UInt64(J);
  finally
    Stack.Free;
  end;
end;

function CaseStackStringClear(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Stack: TStack<UnicodeString>;
begin
  Result := 0;
  Stack := TStack<UnicodeString>.Create;
  try
    Stack.Capacity := ItemCount;
    for I := 1 to Iterations do begin
      for J := 0 to ItemCount - 1 do
        Stack.Push(Strings[J]);
      Result := Result + UInt64(Stack.Count);
      Stack.Clear;
    end;
  finally
    Stack.Free;
  end;
end;

function CaseStackIntegerRoundTrip(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Stack: TStack<Integer>;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Stack := TStack<Integer>.Create;
    try
      Stack.Capacity := ItemCount;
      for J := 0 to ItemCount - 1 do
        Stack.Push(Integers[J]);
      for J := 0 to ItemCount - 1 do
        Result := Result + UInt64(Stack.Pop);
    finally
      Stack.Free;
    end;
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_rtl_collections', Profile, SelectedCase);
  InitializeData;
  try
    Found := False;
    PulseRunCase('pulse_rtl_collections', 'list-string-add-reserved', 'rtl+mm',
      'TList<UnicodeString>.Add', @CaseListStringAddReserved, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-read', 'rtl',
      'TList<UnicodeString>.Items', @CaseListStringRead, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-enumerate', 'rtl',
      'TList<UnicodeString>.Enumerator', @CaseListStringEnumerate, ItemCount,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-insert-delete', 'rtl+mm',
      'TList<UnicodeString>.Insert/Delete', @CaseListStringInsertDelete,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-toarray', 'rtl+mm',
      'TList<UnicodeString>.ToArray', @CaseListStringToArray, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-exchange-reverse', 'rtl+mm',
      'TList<Integer>.Exchange/Reverse', @CaseListExchangeReverse, 65, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-copy-construct',
      'rtl+mm', 'TList<Integer>.Create(TList)', @CaseListIntegerCopyConstruct,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-empty-create',
      'rtl+mm', 'TList<Integer>.Create/Free', @CaseListIntegerEmptyCreate, 1,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'array-integer-copy', 'rtl+mm',
      'Copy(TArray<Integer>)', @CaseArrayIntegerCopy, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-exchange', 'rtl',
      'TList<Integer>.Exchange', @CaseListIntegerExchange, 64, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-reverse', 'rtl',
      'TList<Integer>.Reverse', @CaseListIntegerReverse, ItemCount div 2,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-addrange-4096',
      'rtl+mm', 'TList<Integer>.AddRange(array)', @CaseListIntegerAddRange,
      BulkItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-insertrange-list-4096',
      'rtl+mm', 'TList<Integer>.InsertRange(TList)',
      @CaseListIntegerInsertRangeList, BulkItemCount, Profile, SelectedCase,
      Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-pack-alternating-4096',
      'rtl+mm', 'TList<Integer>.Pack', @CaseListIntegerPackAlternating,
      BulkItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections',
      'list-integer-delete-insert-range-4096', 'rtl+mm',
      'TList<Integer>.DeleteRange/InsertRange',
      @CaseListIntegerDeleteInsertRange, BulkItemCount, Profile, SelectedCase,
      Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-addrange-4096',
      'rtl+mm', 'TList<UnicodeString>.AddRange(array)',
      @CaseListStringAddRange, BulkItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-insertrange-2048',
      'rtl+mm', 'TList<UnicodeString>.InsertRange(array)',
      @CaseListStringInsertRange, BulkItemCount div 2, Profile, SelectedCase,
      Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-clear-4096',
      'rtl+mm', 'TList<Integer>.AddRange/Clear', @CaseListIntegerClear,
      BulkItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-clear-4096',
      'rtl+mm', 'TList<UnicodeString>.AddRange/Clear', @CaseListStringClear,
      BulkItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-indexof', 'rtl',
      'TList<Integer>.IndexOf found/missing', @CaseListIntegerIndexOf,
      ItemCount * 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-indexof', 'rtl',
      'TList<UnicodeString>.IndexOf', @CaseListStringIndexOf, ItemCount,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-integer-sort', 'rtl+mm',
      'TList<Integer>.Sort', @CaseListIntegerSort, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'list-string-sort', 'rtl+mm',
      'TList<UnicodeString>.Sort', @CaseListStringSort, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'objectlist-owned-clear', 'rtl+mm',
      'TObjectList<T>.Add/Clear ownership', @CaseObjectListOwnedClear,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'array-integer-sort', 'rtl+mm',
      'TArray.Sort<Integer>', @CaseArrayIntegerSort, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'array-string-sort', 'rtl+mm',
      'TArray.Sort<UnicodeString>', @CaseArrayStringSort, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'array-binarysearch', 'rtl',
      'TArray.BinarySearch<Integer>', @CaseArrayBinarySearch, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-contains-key', 'rtl',
      'TDictionary.ContainsKey', @CaseDictionaryContainsKey, ItemCount * 2,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-contains-value', 'rtl',
      'TDictionary.ContainsValue', @CaseDictionaryContainsValue, 64, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-tryadd', 'rtl+mm',
      'TDictionary.TryAdd', @CaseDictionaryTryAdd, ItemCount * 2, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-addorset', 'rtl',
      'TDictionary.AddOrSetValue', @CaseDictionaryAddOrSet, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-pairs', 'rtl',
      'TDictionary pair enumerator', @CaseDictionaryPairs, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-keys', 'rtl',
      'TDictionary.Keys enumerator', @CaseDictionaryKeys, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-values', 'rtl',
      'TDictionary.Values enumerator', @CaseDictionaryValues, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-string-add', 'rtl+mm',
      'TDictionary<UnicodeString,Integer>.Add', @CaseDictionaryStringAdd,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-string-contains', 'rtl',
      'TDictionary<UnicodeString,Integer>.ContainsKey',
      @CaseDictionaryStringContains, ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-collision-churn',
      'rtl+mm', 'TDictionary constant-hash add/get/remove',
      @CaseDictionaryCollisionChurn, 160, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'dictionary-string-clear',
      'rtl+mm', 'TDictionary<UnicodeString,Integer>.Add/Clear',
      @CaseDictionaryStringClear, ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-string-roundtrip', 'rtl+mm',
      'TQueue<UnicodeString>.Enqueue/Dequeue', @CaseQueueStringRoundTrip,
      ItemCount * 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-string-steady', 'rtl',
      'TQueue<UnicodeString> steady Enqueue/Dequeue', @CaseQueueStringSteady, 2,
      Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-enumerate', 'rtl',
      'TQueue<Integer>.Enumerator', @CaseQueueEnumerate, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-record128-steady', 'rtl',
      'TQueue<record[128]> steady Enqueue/Dequeue',
      @CaseQueueLargeRecordSteady, 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-string-clear', 'rtl+mm',
      'TQueue<UnicodeString>.Enqueue/Clear', @CaseQueueStringClear,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'queue-integer-steady', 'rtl',
      'TQueue<Integer>.steady Enqueue/Dequeue', @CaseQueueIntegerSteady,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'stack-string-roundtrip', 'rtl+mm',
      'TStack<UnicodeString>.Push/Pop', @CaseStackStringRoundTrip,
      ItemCount * 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'stack-enumerate', 'rtl',
      'TStack<Integer>.Enumerator', @CaseStackEnumerate, ItemCount, Profile,
      SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'stack-string-clear', 'rtl+mm',
      'TStack<UnicodeString>.Push/Clear', @CaseStackStringClear,
      ItemCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_rtl_collections', 'stack-integer-roundtrip', 'rtl',
      'TStack<Integer>.Push/Pop', @CaseStackIntegerRoundTrip, ItemCount * 2,
      Profile, SelectedCase, Found);
    PulseFinish('pulse_rtl_collections', SelectedCase, Found);
  finally
    FinalizeData;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
