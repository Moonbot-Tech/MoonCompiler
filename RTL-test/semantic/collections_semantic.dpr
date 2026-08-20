program collections_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes,
  Generics.Defaults,
  Generics.Collections;

type
  ITracked = interface
    ['{06360146-E14E-41D8-98D0-8EE999E97071}']
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

  TTrackedObject = class
  public
    Number: Integer;
    constructor Create(ANumber: Integer);
    destructor Destroy; override;
  end;

  TConstantHashComparer = class(TEqualityComparer<Integer>)
  public
    function Equals(const ALeft, ARight: Integer): Boolean; override;
    function GetHashCode(const AValue: Integer): UInt32; override;
  end;

  TDictionaryObserver = class
  public
    Dictionary: TObject;
    AddedKeys: Integer;
    RemovedKeys: Integer;
    AddedValues: Integer;
    RemovedValues: Integer;
    KeyMask: UInt32;
    ValueMask: UInt32;
    procedure KeyNotify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
    procedure ValueNotify(ASender: TObject; const AItem: UnicodeString;
      AAction: TCollectionNotification);
  end;

  TCollectionObserver = class
  public
    Sender: TObject;
    Added: Integer;
    Removed: Integer;
    Extracted: Integer;
    procedure Notify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
  end;

  TAdderThread = class(TThread)
  private
    FList: TThreadList;
    FBase: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AList: TThreadList; ABase: Integer);
  end;

var
  InterfacesDestroyed: Integer;
  ObjectsDestroyed: Integer;

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
  Inc(InterfacesDestroyed);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

constructor TTrackedObject.Create(ANumber: Integer);
begin
  inherited Create;
  Number := ANumber;
end;

destructor TTrackedObject.Destroy;
begin
  Inc(ObjectsDestroyed);
  inherited Destroy;
end;

function TConstantHashComparer.Equals(const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft = ARight;
end;

function TConstantHashComparer.GetHashCode(const AValue: Integer): UInt32;
begin
  Result := 1;
end;

procedure TDictionaryObserver.KeyNotify(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  Check(ASender = Dictionary, 'dictionary key notification sender');
  Check((AItem >= 1) and (AItem <= 3), 'dictionary key notification item');
  case AAction of
    cnAdded:
      Inc(AddedKeys);
    cnRemoved:
      begin
        Inc(RemovedKeys);
        Check(KeyMask and (UInt32(1) shl AItem) = 0,
          'dictionary duplicate key removal notification');
        KeyMask := KeyMask or (UInt32(1) shl AItem);
      end;
  else
    Check(False, 'dictionary unexpected key notification action');
  end;
end;

procedure TDictionaryObserver.ValueNotify(ASender: TObject;
  const AItem: UnicodeString; AAction: TCollectionNotification);
var
  Number: Integer;
begin
  Check(ASender = Dictionary, 'dictionary value notification sender');
  Check(TryStrToInt(AItem, Number) and (Number >= 1) and (Number <= 3),
    'dictionary value notification item');
  case AAction of
    cnAdded:
      Inc(AddedValues);
    cnRemoved:
      begin
        Inc(RemovedValues);
        Check(ValueMask and (UInt32(1) shl Number) = 0,
          'dictionary duplicate value removal notification');
        ValueMask := ValueMask or (UInt32(1) shl Number);
      end;
  else
    Check(False, 'dictionary unexpected value notification action');
  end;
end;

procedure TCollectionObserver.Notify(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  Check(ASender = Sender, 'collection notification sender');
  case AAction of
    cnAdded: Inc(Added);
    cnRemoved: Inc(Removed);
    cnExtracted: Inc(Extracted);
  else
    Check(False, 'collection unexpected notification action');
  end;
end;

constructor TAdderThread.Create(AList: TThreadList; ABase: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FList := AList;
  FBase := ABase;
end;

procedure TAdderThread.Execute;
var
  I: Integer;
begin
  for I := 1 to 1000 do
    FList.Add(Pointer(PtrInt(FBase + I)));
end;

procedure TestListCompleteSurface;
var
  I, Index, Value: Integer;
  Values: TArray<Integer>;
  List: TList<Integer>;
  Observer: TCollectionObserver;
begin
  Observer := TCollectionObserver.Create;
  List := TList<Integer>.Create;
  try
    Observer.Sender := List;
    List.OnNotify := Observer.Notify;
    List.AddRange([4, 1, 3, 2]);
    List.Insert(2, 9);
    Check((List.Count = 5) and (List[2] = 9), 'list AddRange/Insert');
    List.Exchange(0, 4);
    Check((List[0] = 2) and (List[4] = 4), 'list Exchange');
    List.Move(4, 1);
    Check((List[1] = 4) and (List[2] = 1), 'list Move');
    Check(List.Contains(9) and (List.IndexOf(9) = 3),
      'list Contains/IndexOf');
    Check(List.Extract(9) = 9, 'list Extract');
    Check((Observer.Extracted = 1) and (List.Count = 4),
      'list Extract notification');
    Check(List.Remove(12345) = -1, 'list Remove miss');
    Check(List.Remove(1) >= 0, 'list Remove hit');
    List.Sort;
    Check(List.BinarySearch(3, Index) and (List[Index] = 3),
      'list Sort/BinarySearch');
    List.Reverse;
    Values := List.ToArray;
    Check((Length(Values) = 3) and (Values[0] = 4) and
      (Values[2] = 2), 'list Reverse/ToArray');
    I := 0;
    for Value in List do
      Inc(I, Value);
    Check(I = 9, 'list enumerator');
    List.Clear;
    Check((List.Count = 0) and (Observer.Added = 5) and
      (Observer.Removed = 4) and (Observer.Extracted = 1),
      'list notifications/Clear');
  finally
    List.OnNotify := nil;
    List.Free;
    Observer.Free;
  end;
end;

procedure TestDictionaryOperationsAndCollisions;
var
  I, Value, Sum: Integer;
  Raised: Boolean;
  Pair: TPair<Integer, Integer>;
  Dictionary: TDictionary<Integer, Integer>;
  CollisionDictionary: TDictionary<Integer, Integer>;
  Comparer: IEqualityComparer<Integer>;
begin
  Dictionary := TDictionary<Integer, Integer>.Create;
  try
    for I := 0 to 511 do
      Dictionary.Add(I * 17, I);
    Check(Dictionary.Count = 512, 'dictionary growth count');
    for I := 0 to 511 do
      Check(Dictionary.TryGetValue(I * 17, Value) and (Value = I),
        'dictionary grown lookup');
    Check(not Dictionary.TryGetValue(-1, Value), 'dictionary lookup miss');
    Check(Dictionary.ContainsKey(17) and Dictionary.ContainsValue(1),
      'dictionary ContainsKey/ContainsValue');
    Raised := False;
    try
      Dictionary.Add(17, 999);
    except
      on EListError do
        Raised := True;
    end;
    Check(Raised, 'dictionary duplicate exception');
    Check(not Dictionary.TryAdd(17, 999), 'dictionary TryAdd duplicate');
    Check(Dictionary.TryAdd(-17, 7), 'dictionary TryAdd new');
    Dictionary.AddOrSetValue(17, 1001);
    Check(Dictionary[17] = 1001, 'dictionary AddOrSet/indexer');
    Pair := Dictionary.ExtractPair(-17);
    Check((Pair.Key = -17) and (Pair.Value = 7) and
      not Dictionary.ContainsKey(-17), 'dictionary ExtractPair');
    Dictionary.Remove(34);
    Check(not Dictionary.ContainsKey(34), 'dictionary Remove');
    Sum := 0;
    for Pair in Dictionary do
      Inc(Sum, Pair.Value);
    Check(Sum > 0, 'dictionary pair enumerator');
    I := 0;
    for Value in Dictionary.Keys do
      Inc(I);
    Check(I = Dictionary.Count, 'dictionary key enumerator');
    I := 0;
    for Value in Dictionary.Values do
      Inc(I);
    Check(I = Dictionary.Count, 'dictionary value enumerator');
    Dictionary.TrimExcess;
    Check(Dictionary[17] = 1001, 'dictionary TrimExcess preserves items');
  finally
    Dictionary.Free;
  end;

  Comparer := TConstantHashComparer.Create;
  CollisionDictionary := TDictionary<Integer, Integer>.Create(Comparer);
  try
    for I := 0 to 127 do
      CollisionDictionary.Add(I, I xor $55);
    for I := 0 to 127 do
      Check(CollisionDictionary.TryGetValue(I, Value) and
        (Value = (I xor $55)), 'dictionary collision lookup');
    for I := 0 to 63 do
      CollisionDictionary.Remove(I);
    for I := 64 to 127 do
      Check(CollisionDictionary.ContainsKey(I),
        'dictionary collision cluster after removal');
  finally
    CollisionDictionary.Free;
    Comparer := nil;
  end;
end;

procedure TestDictionaryNotificationsAndManagedLifetime;
var
  I: Integer;
  Item: ITracked;
  Dictionary: TDictionary<Integer, UnicodeString>;
  ManagedDictionary: TDictionary<Integer, ITracked>;
  Observer: TDictionaryObserver;
begin
  Observer := TDictionaryObserver.Create;
  Dictionary := TDictionary<Integer, UnicodeString>.Create;
  try
    Observer.Dictionary := Dictionary;
    Dictionary.OnKeyNotify := Observer.KeyNotify;
    Dictionary.OnValueNotify := Observer.ValueNotify;
    for I := 1 to 3 do
      Dictionary.Add(I, IntToStr(I));
    Check((Observer.AddedKeys = 3) and (Observer.AddedValues = 3),
      'dictionary add notifications');
    Dictionary.Clear;
    Check((Observer.RemovedKeys = 3) and (Observer.RemovedValues = 3) and
      (Observer.KeyMask = $0E) and (Observer.ValueMask = $0E),
      'dictionary clear notifications are exact and order-independent');
  finally
    Dictionary.OnKeyNotify := nil;
    Dictionary.OnValueNotify := nil;
    Dictionary.Free;
    Observer.Free;
  end;

  InterfacesDestroyed := 0;
  Item := nil;
  ManagedDictionary := TDictionary<Integer, ITracked>.Create;
  try
    for I := 1 to 8 do
    begin
      Item := TTracked.Create(I);
      ManagedDictionary.Add(I, Item);
      Item := nil;
    end;
    Check(InterfacesDestroyed = 0, 'dictionary retains interface values');
    ManagedDictionary.Remove(4);
    Check(InterfacesDestroyed = 1, 'dictionary Remove releases value');
    ManagedDictionary.Clear;
    Check(InterfacesDestroyed = 8, 'dictionary Clear releases all values');
  finally
    Item := nil;
    ManagedDictionary.Free;
  end;
  Check(InterfacesDestroyed = 8, 'dictionary managed lifetime exact');
end;

procedure TestQueueAndStack;
var
  I, Value: Integer;
  Raised: Boolean;
  Values: TArray<Integer>;
  Queue: TQueue<Integer>;
  Stack: TStack<Integer>;
  QueueObserver, StackObserver: TCollectionObserver;
begin
  QueueObserver := TCollectionObserver.Create;
  StackObserver := TCollectionObserver.Create;
  Queue := TQueue<Integer>.Create;
  Stack := TStack<Integer>.Create;
  try
    QueueObserver.Sender := Queue;
    StackObserver.Sender := Stack;
    Queue.OnNotify := QueueObserver.Notify;
    Stack.OnNotify := StackObserver.Notify;
    for I := 1 to 16 do
    begin
      Queue.Enqueue(I);
      Stack.Push(I);
    end;
    Check((Queue.Peek = 1) and (Stack.Peek = 16), 'queue/stack Peek');
    I := 1;
    for Value in Queue do
    begin
      Check(Value = I, 'queue enumeration order');
      Inc(I);
    end;
    I := 1;
    for Value in Stack do
    begin
      Check(Value = I, 'stack enumeration storage order');
      Inc(I);
    end;
    Values := Queue.ToArray;
    Check((Length(Values) = 16) and (Values[0] = 1) and
      (Values[15] = 16), 'queue ToArray');
    Values := Stack.ToArray;
    Check((Length(Values) = 16) and (Values[0] = 1) and
      (Values[15] = 16), 'stack ToArray');
    Check(Queue.Extract = 1, 'queue Extract');
    Check(Stack.Extract = 16, 'stack Extract');
    for I := 2 to 16 do
      Check(Queue.Dequeue = I, 'queue FIFO');
    for I := 15 downto 1 do
      Check(Stack.Pop = I, 'stack LIFO');
    Check((QueueObserver.Added = 16) and (QueueObserver.Removed = 15) and
      (QueueObserver.Extracted = 1), 'queue notifications');
    Check((StackObserver.Added = 16) and (StackObserver.Removed = 15) and
      (StackObserver.Extracted = 1), 'stack notifications');
    Raised := False;
    try
      Value := Queue.Dequeue;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'queue empty exception');
    Raised := False;
    try
      Value := Stack.Pop;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'stack empty exception');
  finally
    Queue.OnNotify := nil;
    Stack.OnNotify := nil;
    Stack.Free;
    Queue.Free;
    StackObserver.Free;
    QueueObserver.Free;
  end;
end;

procedure TestArrayAlgorithms;
var
  Index: Integer;
  Values: TArray<Integer>;
begin
  Values := TArray<Integer>.Create(9, 7, 5, 3, 1, 8, 6, 4, 2, 0);
  TArray.Sort<Integer>(Values);
  Check((Values[0] = 0) and (Values[9] = 9), 'TArray Sort');
  Check(TArray.BinarySearch<Integer>(Values, 6, Index) and (Index = 6),
    'TArray BinarySearch hit');
  Check(not TArray.BinarySearch<Integer>(Values, 11, Index),
    'TArray BinarySearch miss');

  Values := TArray<Integer>.Create(100, 9, 7, 5, 3, 1, 200);
  TArray.Sort<Integer>(Values, TComparer<Integer>.Default, 1, 5);
  Check((Values[0] = 100) and (Values[1] = 1) and (Values[5] = 9) and
    (Values[6] = 200), 'TArray range Sort boundaries');
  Check(TArray.BinarySearch<Integer>(Values, 5, Index,
    TComparer<Integer>.Default, 1, 5) and (Index = 3),
    'TArray range BinarySearch');
end;

procedure TestOwningCollections;
var
  Extracted: TTrackedObject;
  Key, Value: TTrackedObject;
  List: TObjectList<TTrackedObject>;
  Dictionary: TObjectDictionary<TTrackedObject, TTrackedObject>;
begin
  ObjectsDestroyed := 0;
  List := TObjectList<TTrackedObject>.Create(True);
  try
    List.Add(TTrackedObject.Create(1));
    List.Add(TTrackedObject.Create(2));
    List.Add(TTrackedObject.Create(3));
    Extracted := List.Extract(List[1]);
    Check((Extracted.Number = 2) and (ObjectsDestroyed = 0),
      'TObjectList Extract transfers ownership');
    Extracted.Free;
    List.Delete(0);
    Check(ObjectsDestroyed = 2, 'TObjectList Delete owns object');
    List.Clear;
    Check(ObjectsDestroyed = 3, 'TObjectList Clear owns object');
  finally
    List.Free;
  end;
  Check(ObjectsDestroyed = 3, 'TObjectList exact destruction');

  ObjectsDestroyed := 0;
  Dictionary := TObjectDictionary<TTrackedObject, TTrackedObject>.Create(
    [doOwnsKeys, doOwnsValues]);
  try
    Dictionary.Add(TTrackedObject.Create(1), TTrackedObject.Create(11));
    Dictionary.Add(TTrackedObject.Create(2), TTrackedObject.Create(22));
    for Key in Dictionary.Keys do
      Check((Key.Number = 1) or (Key.Number = 2),
        'TObjectDictionary key enumeration');
    for Value in Dictionary.Values do
      Check((Value.Number = 11) or (Value.Number = 22),
        'TObjectDictionary value enumeration');
    Dictionary.Clear;
    Check(ObjectsDestroyed = 4, 'TObjectDictionary Clear ownership');
  finally
    Dictionary.Free;
  end;
  Check(ObjectsDestroyed = 4, 'TObjectDictionary exact destruction');
end;

procedure TestStringList;
var
  Raised: Boolean;
  Item: TTrackedObject;
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Add('beta');
    List.Add('Alpha');
    List.Add('gamma=3');
    List.Sort;
    Check((List[0] = 'Alpha') and (List.IndexOf('beta') >= 0),
      'TStringList Sort/IndexOf');
    Check(List.Values['gamma'] = '3', 'TStringList Values read');
    List.Values['gamma'] := '33';
    Check(List.Values['gamma'] = '33', 'TStringList Values write');
    List.CaseSensitive := False;
    Check(List.IndexOf('ALPHA') >= 0, 'TStringList case-insensitive lookup');
    List.Clear;
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    Check((List.Add('same') = 0) and (List.Add('same') = 0) and
      (List.Count = 1), 'TStringList duplicate ignore');
    List.Duplicates := dupError;
    Raised := False;
    try
      List.Add('same');
    except
      on Exception do
        Raised := True;
    end;
    Check(Raised, 'TStringList duplicate exception');
  finally
    List.Free;
  end;

  ObjectsDestroyed := 0;
  Item := TTrackedObject.Create(7);
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    List.AddObject('owned', Item);
    Item := nil;
    List.Delete(0);
    Check(ObjectsDestroyed = 1, 'TStringList owns object on Delete');
  finally
    List.Free;
  end;
  Check(ObjectsDestroyed = 1, 'TStringList exact object lifetime');
end;

procedure TestLegacyListAndThreadList;
var
  I, J: Integer;
  Raised: Boolean;
  Locked: Classes.TList;
  List: Classes.TList;
  ThreadList: TThreadList;
  Threads: array[0..3] of TAdderThread;
begin
  List := Classes.TList.Create;
  try
    for I := 1 to 32 do
      List.Add(Pointer(PtrInt(I)));
    List.Insert(0, Pointer(PtrInt(99)));
    Check((PtrInt(List[0]) = 99) and (List.IndexOf(Pointer(PtrInt(16))) >= 0),
      'Classes.TList Insert/IndexOf');
    List.Exchange(0, 1);
    List.Move(1, 2);
    List.Delete(0);
    Check(List.Count = 32, 'Classes.TList Exchange/Move/Delete');
    Raised := False;
    try
      I := PtrInt(List[List.Count]);
    except
      on EListError do
        Raised := True;
    end;
    Check(Raised, 'Classes.TList bounds exception');
  finally
    List.Free;
  end;

  ThreadList := TThreadList.Create;
  try
    for I := 0 to High(Threads) do
    begin
      Threads[I] := TAdderThread.Create(ThreadList, I * 1000);
      Threads[I].Start;
    end;
    for I := 0 to High(Threads) do
      Threads[I].WaitFor;
    Locked := ThreadList.LockList;
    try
      Check(Locked.Count = 4000, 'TThreadList concurrent Add count');
      for I := 0 to High(Threads) do
        for J := 1 to 1000 do
          Check(Locked.IndexOf(Pointer(PtrInt(I * 1000 + J))) >= 0,
            'TThreadList concurrent Add value');
    finally
      ThreadList.UnlockList;
    end;
    ThreadList.Clear;
    Locked := ThreadList.LockList;
    try
      Check(Locked.Count = 0, 'TThreadList Clear');
    finally
      ThreadList.UnlockList;
    end;
  finally
    for I := 0 to High(Threads) do
      Threads[I].Free;
    ThreadList.Free;
  end;
end;

begin
  try
    TestListCompleteSurface;
    TestDictionaryOperationsAndCollisions;
    TestDictionaryNotificationsAndManagedLifetime;
    TestQueueAndStack;
    TestArrayAlgorithms;
    TestOwningCollections;
    TestStringList;
    TestLegacyListAndThreadList;
    WriteLn('COLLECTIONS_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
