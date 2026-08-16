program collections_hotpaths;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Generics.Defaults,
  Generics.Collections;

type
  ITracked = interface
    ['{67D484C1-D0C1-47BD-A96E-0B31944A4DE3}']
    function Number: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FNumber: Integer;
  public
    constructor Create(ANumber: Integer);
    destructor Destroy; override;
    function Number: Integer;
  end;

  TManagedItem = record
    Text: UnicodeString;
    Bytes: TBytes;
    Item: ITracked;
  end;

  TTrackedArray = array of ITracked;

  TNotifyProbe = class
  public
    Added, Removed: Integer;
    LastAdded, LastRemoved: Integer;
    procedure Notify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
  end;

  TOverrideNotifyList = class(TList<Integer>)
  public
    Added, Removed: Integer;
    procedure ProbePrepareRange(ACount: SizeInt);
  protected
    procedure Notify(const AValue: Integer;
      ACollectionNotification: TCollectionNotification); override;
  end;

  TCaseInsensitiveComparer = class(TInterfacedObject,
    IComparer<UnicodeString>)
  public
    function Compare(const ALeft, ARight: UnicodeString): Integer;
  end;

  TConstantIntegerHashComparer = class(TInterfacedObject,
    IEqualityComparer<Integer>)
  public
    function Equals(const ALeft, ARight: Integer): Boolean; reintroduce;
    function GetHashCode(const AValue: Integer): UInt32; reintroduce;
  end;

var
  Destroyed: Integer;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('COLLECTIONS_HOTPATHS_FAIL: '+AMessage);
end;

constructor TTracked.Create(ANumber: Integer);
begin
  inherited Create;
  FNumber:=ANumber;
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TTracked.Number: Integer;
begin
  Result:=FNumber;
end;

procedure TNotifyProbe.Notify(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  Check(ASender<>nil,'notification sender');
  case AAction of
    cnAdded:
      begin
      Inc(Added);
      LastAdded:=AItem;
      end;
    cnRemoved:
      begin
      Inc(Removed);
      LastRemoved:=AItem;
      end;
  end;
end;

procedure TOverrideNotifyList.Notify(const AValue: Integer;
  ACollectionNotification: TCollectionNotification);
begin
  inherited Notify(AValue,ACollectionNotification);
  case ACollectionNotification of
    cnAdded: Inc(Added);
    cnRemoved: Inc(Removed);
  end;
end;

procedure TOverrideNotifyList.ProbePrepareRange(ACount: SizeInt);
begin
  PrepareAddingRange(ACount);
end;

function TCaseInsensitiveComparer.Compare(const ALeft,
  ARight: UnicodeString): Integer;
begin
  Result:=CompareText(ALeft,ARight);
end;

function TConstantIntegerHashComparer.Equals(const ALeft,
  ARight: Integer): Boolean;
begin
  Result:=ALeft=ARight;
end;

function TConstantIntegerHashComparer.GetHashCode(
  const AValue: Integer): UInt32;
begin
  Result:=$FFFFFFFE;
end;

procedure CheckIntegerList;
var
  I, Seen, Sum, Value: Integer;
  Enumerable: TEnumerable<Integer>;
  Enumerator: TEnumerator<Integer>;
  List: TList<Integer>;
  NotifyProbe: TNotifyProbe;
  Raised: Boolean;
begin
  List:=TList<Integer>.Create;
  NotifyProbe:=TNotifyProbe.Create;
  try
    Seen:=0;
    for Value in List do
      Inc(Seen);
    Check(Seen=0,'empty list enumerator');
    Check(List is TCustomList<Integer>,'list custom-list runtime type');
    for I:=0 to 1023 do
      List.Add(I*3);
    Sum:=0;
    Seen:=0;
    for Value in List do
      begin
      Check(Value=Seen*3,'list enumerator order');
      Inc(Sum,Value);
      Inc(Seen);
      end;
    Check((Seen=1024) and (Sum=1571328),'list enumerator sum');
    Enumerable:=List;
    Enumerator:=Enumerable.GetEnumerator;
    try
      Seen:=0;
      while Enumerator.MoveNext do
        begin
        Check(Enumerator.Current=Seen*3,
          'base-typed virtual enumerator order');
        Inc(Seen);
        end;
      Check(Seen=1024,'base-typed virtual enumerator count');
    finally
      Enumerator.Free;
    end;
    for I:=0 to List.Count-1 do
      Check(List[I]=I*3,'list checked read');

    List.OnNotify:=NotifyProbe.Notify;
    List[17]:=777;
    Check((List[17]=777) and (NotifyProbe.Removed=1) and
      (NotifyProbe.LastRemoved=51) and (NotifyProbe.Added=1) and
      (NotifyProbe.LastAdded=777),'list checked write notification');

    Raised:=False;
    try
      Value:=List[-1];
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'negative list read');
    Raised:=False;
    try
      Value:=List[List.Count];
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'high list read');
    Raised:=False;
    try
      List[-1]:=1;
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'negative list write');
    Raised:=False;
    try
      List[List.Count]:=1;
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'high list write');
  finally
    List.OnNotify:=nil;
    NotifyProbe.Free;
    List.Free;
  end;
end;

procedure CheckListGrowthAndVirtualNotify;
var
  I: Integer;
  List: TOverrideNotifyList;
  Raised: Boolean;
begin
  List:=TOverrideNotifyList.Create;
  try
    for I:=0 to 76 do
      begin
      List.Add(I);
      case List.Count of
        1: Check(List.Capacity=4,'list initial Delphi capacity');
        5: Check(List.Capacity=8,'list small Delphi capacity');
        9: Check(List.Capacity=12,'list boundary Delphi capacity');
        13: Check(List.Capacity=28,'list medium Delphi capacity');
        77: Check(List.Capacity=114,'list large Delphi capacity');
      end;
      end;
    Check(List.Added=77,'overridden Notify receives every Add');
    List.Delete(0);
    Check(List.Removed=1,'overridden Notify receives Delete');
    List.OnNotify:=nil;
    List.Add(1000);
    Check(List.Added=78,'overridden Notify survives nil OnNotify');
    List.Clear;
    Check(List.Removed=78,'overridden Notify receives Clear');
    List.Add(1);
    Raised:=False;
    try
      List.ProbePrepareRange(High(SizeInt));
    except
      on EOutOfMemory do
        Raised:=True;
    end;
    Check(Raised and (List.Count=1) and (List[0]=1),
      'AddRange overflow is rejected before changing the list');
  finally
    List.Free;
  end;
end;

procedure CheckManagedList;
var
  Current, First, Second: ITracked;
  List: TList<ITracked>;
  Seen: Integer;
begin
  Destroyed:=0;
  First:=TTracked.Create(1);
  Second:=TTracked.Create(2);
  List:=TList<ITracked>.Create;
  try
    List.Add(First);
    First:=nil;
    Current:=List[0];
    Check(Current.Number=1,'managed list read');
    Current:=nil;
    List[0]:=Second;
    Check(Destroyed=1,'managed list write releases old value');
    Second:=nil;
    Seen:=0;
    for Current in List do
      begin
      Inc(Seen);
      Check(Current.Number=2,'managed list enumerator value');
      end;
    Current:=nil;
    Check(Seen=1,'managed list enumerator count');
    List.Clear;
    Check(Destroyed=2,'managed list clear');
  finally
    Current:=nil;
    List.Free;
  end;
  Check(Destroyed=2,'managed list exact lifetime');
end;

procedure CheckInterfaceOrder(AList: TList<ITracked>);
begin
  Check((AList[0].Number=3) and (AList[2].Number=1),
    'interface list Exchange order');
  AList.Reverse;
  Check((AList[0].Number=1) and (AList[2].Number=3),
    'interface list Reverse order');
end;

procedure CheckListReordering;
var
  Interfaces: TList<ITracked>;
  Strings: TList<UnicodeString>;
begin
  Strings:=TList<UnicodeString>.Create;
  try
    Strings.Add('alpha');
    Strings.Add('beta');
    Strings.Add('gamma');
    Strings.Exchange(0,2);
    Check((Strings[0]='gamma') and (Strings[1]='beta') and
      (Strings[2]='alpha'),'managed list Exchange order');
    Strings.Reverse;
    Check((Strings[0]='alpha') and (Strings[1]='beta') and
      (Strings[2]='gamma'),'managed list Reverse order');
    Strings.Reverse;
    Strings.Exchange(0,2);
    Check((Strings[0]='alpha') and (Strings[1]='beta') and
      (Strings[2]='gamma'),'managed list repeated reordering');
  finally
    Strings.Free;
  end;

  Destroyed:=0;
  Interfaces:=TList<ITracked>.Create;
  try
    Interfaces.Add(TTracked.Create(1));
    Interfaces.Add(TTracked.Create(2));
    Interfaces.Add(TTracked.Create(3));
    Interfaces.Exchange(0,2);
    CheckInterfaceOrder(Interfaces);
    Check(Destroyed=0,'reordering does not release interface values');
  finally
    Interfaces.Free;
  end;
  Check(Destroyed=3,'reordered interface list exact lifetime');
end;

procedure ExerciseDynamicArrayListReordering;
var
  Current: ITracked;
  Item: TTrackedArray;
  List: TList<TTrackedArray>;
begin
  List:=TList<TTrackedArray>.Create;
  try
    SetLength(Item,1);
    Current:=TTracked.Create(1);
    Item[0]:=Current;
    Current:=nil;
    List.Add(Item);
    Item:=nil;
    SetLength(Item,1);
    Current:=TTracked.Create(2);
    Item[0]:=Current;
    Current:=nil;
    List.Add(Item);
    Item:=nil;
    SetLength(Item,1);
    Current:=TTracked.Create(3);
    Item[0]:=Current;
    Current:=nil;
    List.Add(Item);
    Item:=nil;

    List.Exchange(0,2);
    Check((List[0][0].Number=3) and (List[1][0].Number=2) and
      (List[2][0].Number=1),'dynamic-array list Exchange order');
    List.Reverse;
    Check((List[0][0].Number=1) and (List[1][0].Number=2) and
      (List[2][0].Number=3),'dynamic-array list Reverse order');
    Check(Destroyed=0,'dynamic-array list reordering lifetime');
  finally
    Current:=nil;
    Item:=nil;
    List.Free;
  end;
end;

procedure CheckDynamicArrayListReordering;
begin
  Destroyed:=0;
  ExerciseDynamicArrayListReordering;
  Check(Destroyed=3,'dynamic-array list exact final lifetime: '+
    IntToStr(Destroyed));
end;

procedure CheckCopiedInterfaceList(AList: TList<ITracked>);
begin
  Check((AList.Count=2) and (AList[0].Number=11) and
    (AList[1].Number=22),'copied interface list values');
end;

procedure CheckListCopyConstruction;
var
  InterfaceCopy, InterfaceSource: TList<ITracked>;
  StringCopy, StringSource: TList<UnicodeString>;
begin
  StringSource:=TList<UnicodeString>.Create;
  StringCopy:=nil;
  try
    StringSource.Add('first');
    StringSource.Add('second');
    StringCopy:=TList<UnicodeString>.Create(StringSource);
    StringSource[0]:='changed';
    StringSource.Clear;
    Check((StringCopy.Count=2) and (StringCopy[0]='first') and
      (StringCopy[1]='second'),'copied string list is independent');
  finally
    StringCopy.Free;
    StringSource.Free;
  end;

  Destroyed:=0;
  InterfaceSource:=TList<ITracked>.Create;
  InterfaceCopy:=nil;
  try
    InterfaceSource.Add(TTracked.Create(11));
    InterfaceSource.Add(TTracked.Create(22));
    InterfaceCopy:=TList<ITracked>.Create(InterfaceSource);
    InterfaceSource.Clear;
    Check(Destroyed=0,'copied interface list owns its references');
    CheckCopiedInterfaceList(InterfaceCopy);
  finally
    InterfaceSource.Free;
    InterfaceCopy.Free;
  end;
  Check(Destroyed=2,'copied interface list exact lifetime');
end;

procedure CheckQueueCompaction;
var
  I,Seen: Integer;
  Item: TManagedItem;
  Queue: TQueue<TManagedItem>;
begin
  Destroyed:=0;
  Item:=Default(TManagedItem);
  Queue:=TQueue<TManagedItem>.Create;
  try
    Queue.Capacity:=32;
    for I:=0 to 31 do
      begin
      Item.Text:='item-'+IntToStr(I);
      Item.Bytes:=TBytes.Create(I,I+1);
      Item.Item:=TTracked.Create(I);
      Queue.Enqueue(Item);
      Item:=Default(TManagedItem);
      end;
    for I:=0 to 11 do
      begin
      Item:=Queue.Dequeue;
      Check((Item.Text='item-'+IntToStr(I)) and (Item.Bytes[1]=I+1) and
        (Item.Item.Number=I),'queue prefix');
      Item:=Default(TManagedItem);
      end;
    Check((Queue.Count=20) and (Destroyed=12),'queue prefix lifetime');
    Seen:=12;
    for Item in Queue do
      begin
      Check((Item.Text='item-'+IntToStr(Seen)) and
        (Item.Item.Number=Seen),'queue enumerator with nonzero low');
      Inc(Seen);
      end;
    Item:=Default(TManagedItem);
    Check(Seen=32,'queue enumerator count with nonzero low');
    Item.Text:='item-32';
    Item.Bytes:=TBytes.Create(32,33);
    Item.Item:=TTracked.Create(32);
    Queue.Enqueue(Item);
    Item:=Default(TManagedItem);
    Check(Queue.Count=21,'overlapping queue compaction count');
    for I:=12 to 32 do
      begin
      Item:=Queue.Peek;
      Check((Item.Text='item-'+IntToStr(I)) and (Item.Bytes[0]=I) and
        (Item.Item.Number=I),'queue compacted order');
      Item:=Default(TManagedItem);
      Item:=Queue.Dequeue;
      Item:=Default(TManagedItem);
      end;
    Check((Queue.Count=0) and (Destroyed=33),'queue compacted lifetime');
  finally
    Item:=Default(TManagedItem);
    Queue.Free;
  end;
  Check(Destroyed=33,'queue destruction exact lifetime');
end;

procedure CheckTerminalReads;
var
  Queue: TQueue<Integer>;
  Stack: TStack<Integer>;
  Raised: Boolean;
  Value: Integer;
begin
  Queue:=TQueue<Integer>.Create;
  Stack:=TStack<Integer>.Create;
  try
    Queue.Enqueue(10);
    Queue.Enqueue(20);
    Stack.Push(10);
    Stack.Push(20);
    Check((Queue.Peek=10) and (Queue.Count=2),'queue Peek');
    Check((Stack.Peek=20) and (Stack.Count=2),'stack Peek');
    Queue.Clear;
    Stack.Clear;
    Raised:=False;
    try
      Value:=Queue.Peek;
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'empty queue Peek');
    Raised:=False;
    try
      Value:=Stack.Peek;
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'empty stack Peek');
  finally
    Stack.Free;
    Queue.Free;
  end;
end;

procedure CheckAVLExtraction;
var
  Comparer: IComparer<UnicodeString>;
  Map: TAVLTreeMap<UnicodeString,ITracked>;
  Node: TAVLTreeMap<UnicodeString,ITracked>.PNode;
  Pair: TPair<UnicodeString,ITracked>;
begin
  Destroyed:=0;
  Comparer:=TCaseInsensitiveComparer.Create;
  Map:=TAVLTreeMap<UnicodeString,ITracked>.Create(Comparer);
  try
    Map.Add('Alpha',TTracked.Create(1));
    Map.Add('Beta',TTracked.Create(2));
    Map.Add('Gamma',TTracked.Create(3));
    Pair:=Map.ExtractPair('alpha');
    Check((Pair.Key='alpha') and (Pair.Value.Number=1),
      'key extraction returns search key and stored value');
    Check((Map.Count=2) and not Map.ContainsKey('ALPHA'),
      'key extraction removes comparer match');
    Pair.Value:=nil;
    Check(Destroyed=1,'key extraction managed lifetime');

    Node:=Map.Find('beta');
    Pair:=Map.ExtractPair(Node,False);
    Check((Pair.Key='Beta') and (Pair.Value.Number=2) and (Map.Count=1),
      'node extraction returns stored pair');
    Map.DisposeNode(Node);
    Check(Destroyed=1,'pair owns detached node value');
    Pair.Value:=nil;
    Check(Destroyed=2,'detached node value lifetime');

    Pair:=Map.ExtractPair('missing');
    Check((Pair.Key='') and (Pair.Value=nil),'missing extraction default');
    Map.ConsistencyCheck;
  finally
    Map.Free;
    Comparer:=nil;
  end;
  Check(Destroyed=3,'AVL exact managed lifetime');
end;

procedure CheckDictionaryRehash;
var
  Comparer: IEqualityComparer<Integer>;
  Dictionary: TDictionary<Integer,Integer>;
  I, Value: Integer;
  KeyNotify, ValueNotify: TNotifyProbe;
  Raised: Boolean;
begin
  Comparer:=TConstantIntegerHashComparer.Create;
  Dictionary:=TDictionary<Integer,Integer>.Create(Comparer);
  KeyNotify:=TNotifyProbe.Create;
  ValueNotify:=TNotifyProbe.Create;
  try
    Dictionary.OnKeyNotify:=KeyNotify.Notify;
    Dictionary.OnValueNotify:=ValueNotify.Notify;
    Check(Abs(Dictionary.MaxLoadFactor-0.75)<0.0001,
      'dictionary default load factor is preserved');

    for I:=0 to 383 do
      Dictionary.Add(I,I xor $55AA);
    Check((Dictionary.Count=384) and (Dictionary.Capacity=512),
      'dictionary growth boundaries');
    Check((KeyNotify.Added=384) and (ValueNotify.Added=384),
      'dictionary add notifications exclude rehash');
    for I:=0 to 383 do
      begin
      Check(Dictionary.TryGetValue(I,Value),'dictionary collision lookup');
      Check(Value=(I xor $55AA),'dictionary collision value');
      end;

    Dictionary.Capacity:=2048;
    Check((Dictionary.Count=384) and (Dictionary.Capacity=2048),
      'dictionary explicit rehash capacity');
    Check((KeyNotify.Added=384) and (ValueNotify.Added=384) and
      (KeyNotify.Removed=0) and (ValueNotify.Removed=0),
      'dictionary explicit rehash has no notifications');
    for I:=0 to 383 do
      Check(Dictionary[I]=(I xor $55AA),
        'dictionary explicit rehash preserves pairs');

    I:=0;
    while I<=383 do
      begin
      Dictionary.Remove(I);
      Inc(I,3);
      end;
    Check((Dictionary.Count=256) and (KeyNotify.Removed=128) and
      (ValueNotify.Removed=128),'dictionary remove and notifications');
    for I:=0 to 127 do
      Dictionary.Add(1000+I,I*7);
    Check((Dictionary.Count=384) and (KeyNotify.Added=512) and
      (ValueNotify.Added=512),'dictionary reinsert count');
    for I:=0 to 127 do
      Check(Dictionary[1000+I]=I*7,'dictionary reinsert value');

    Raised:=False;
    try
      Dictionary.Add(1000,1);
    except
      on EListError do
        Raised:=True;
    end;
    Check(Raised and (Dictionary.Count=384),
      'dictionary duplicate rejected without mutation');
  finally
    Dictionary.OnValueNotify:=nil;
    Dictionary.OnKeyNotify:=nil;
    ValueNotify.Free;
    KeyNotify.Free;
    Dictionary.Free;
    Comparer:=nil;
  end;
end;

procedure CheckManagedDictionaryRehash;
var
  Dictionary: TDictionary<UnicodeString,ITracked>;
  I: Integer;
  Item: ITracked;
begin
  Destroyed:=0;
  Dictionary:=TDictionary<UnicodeString,ITracked>.Create;
  try
    for I:=0 to 512 do
      begin
      Item:=TTracked.Create(I);
      Dictionary.Add('managed-'+IntToStr(I),Item);
      Item:=nil;
      end;
    Check((Dictionary.Count=513) and (Destroyed=0),
      'managed dictionary rehash keeps exact ownership');
    for I:=0 to 512 do
      begin
      Check(Dictionary.TryGetValue('managed-'+IntToStr(I),Item),
        'managed dictionary lookup');
      Check(Item.Number=I,'managed dictionary value');
      Item:=nil;
      end;
    Dictionary.Capacity:=2048;
    Check((Dictionary.Count=513) and (Destroyed=0),
      'managed dictionary explicit rehash lifetime');
    Dictionary.Clear;
    Check((Dictionary.Count=0) and (Destroyed=513),
      'managed dictionary clear lifetime');
  finally
    Item:=nil;
    Dictionary.Free;
  end;
  Check(Destroyed=513,'managed dictionary exact final lifetime');
end;

begin
  try
    CheckIntegerList;
    CheckListGrowthAndVirtualNotify;
    CheckManagedList;
    CheckListReordering;
    CheckDynamicArrayListReordering;
    CheckListCopyConstruction;
    CheckQueueCompaction;
    CheckTerminalReads;
    CheckAVLExtraction;
    CheckDictionaryRehash;
    CheckManagedDictionaryRehash;
    WriteLn('COLLECTIONS_HOTPATHS_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
