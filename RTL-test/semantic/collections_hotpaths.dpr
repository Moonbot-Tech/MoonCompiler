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

  TMinusOneIsEmptyComparer = class(TInterfacedObject, IComparer<Integer>)
  public
    function Compare(const ALeft, ARight: Integer): Integer;
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

function TMinusOneIsEmptyComparer.Compare(const ALeft,
  ARight: Integer): Integer;
var
  LeftValue, RightValue: Integer;
begin
  LeftValue:=ALeft;
  RightValue:=ARight;
  if LeftValue=-1 then
    LeftValue:=0;
  if RightValue=-1 then
    RightValue:=0;
  Result:=LeftValue-RightValue;
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
  Values: TArray<Integer>;
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

    SetLength(Values,1000);
    for I:=0 to High(Values) do
      Values[I]:=I*5;
    List.AddRange(Values);
    Check((List.Count=1000) and (List.Capacity=1296) and
      (List[0]=0) and (List[999]=4995),
      'large AddRange preserves Delphi growth and values');
    Check(List.Added=1078,'large AddRange notifies every item');
    List.Clear;
    Check(List.Removed=1078,'large AddRange clear lifetime');

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

procedure CheckBulkInterfaceOrder(AList: TList<ITracked>);
begin
  Check((AList.Count=6) and
    (AList[0].Number=1) and
    (AList[1].Number=1) and
    (AList[2].Number=2) and
    (AList[3].Number=3) and
    (AList[4].Number=2) and
    (AList[5].Number=3),
    'managed bulk constructor and InsertRange order');
end;

procedure CheckBulkListRanges;
var
  I: Integer;
  IntegerSource, IntegerTarget: TList<Integer>;
  InterfaceSource, InterfaceTarget: TList<ITracked>;
  NotifyTarget: TOverrideNotifyList;
begin
  IntegerSource:=TList<Integer>.Create([10,20,30]);
  IntegerTarget:=TList<Integer>.Create([1,2,3]);
  try
    Check((IntegerSource.Count=3) and (IntegerSource.Capacity=4) and
      (IntegerSource[0]=10) and (IntegerSource[2]=30),
      'array constructor bulk values and capacity');

    IntegerTarget.InsertRange(1,TEnumerable<Integer>(IntegerSource));
    Check((IntegerTarget.Count=6) and (IntegerTarget.Capacity=8),
      'other-list bulk InsertRange count and capacity');
    Check((IntegerTarget[0]=1) and (IntegerTarget[1]=10) and
      (IntegerTarget[2]=20) and (IntegerTarget[3]=30) and
      (IntegerTarget[4]=2) and (IntegerTarget[5]=3),
      'other-list bulk InsertRange order');

    IntegerSource.InsertRange(1,TEnumerable<Integer>(IntegerSource));
    Check((IntegerSource.Count=6) and (IntegerSource.Capacity=8),
      'self InsertRange count and capacity');
    Check((IntegerSource[0]=10) and (IntegerSource[1]=10) and
      (IntegerSource[2]=20) and (IntegerSource[3]=30) and
      (IntegerSource[4]=20) and (IntegerSource[5]=30),
      'self InsertRange Delphi order');
  finally
    IntegerTarget.Free;
    IntegerSource.Free;
  end;

  NotifyTarget:=TOverrideNotifyList.Create;
  IntegerSource:=TList<Integer>.Create([7,8,9]);
  try
    NotifyTarget.Add(1);
    NotifyTarget.AddRange(TEnumerable<Integer>(IntegerSource));
    Check((NotifyTarget.Count=4) and (NotifyTarget.Added=4),
      'bulk AddRange preserves virtual notifications');
    Check((NotifyTarget[0]=1) and (NotifyTarget[1]=7) and
      (NotifyTarget[2]=8) and (NotifyTarget[3]=9),
      'bulk AddRange notification target values');
  finally
    IntegerSource.Free;
    NotifyTarget.Free;
  end;

  Destroyed:=0;
  InterfaceSource:=TList<ITracked>.Create;
  InterfaceTarget:=nil;
  try
    for I:=1 to 3 do
      InterfaceSource.Add(TTracked.Create(I));
    InterfaceTarget:=TList<ITracked>.Create(
      TEnumerable<ITracked>(InterfaceSource));
    InterfaceTarget.InsertRange(1,TEnumerable<ITracked>(InterfaceSource));
    CheckBulkInterfaceOrder(InterfaceTarget);
    InterfaceSource.Clear;
    Check(Destroyed=0,'managed bulk ranges retain every reference');
  finally
    InterfaceSource.Free;
    InterfaceTarget.Free;
  end;
  Check(Destroyed=3,'managed bulk ranges exact lifetime');
end;

procedure CheckListPack;
var
  I: Integer;
  IntegerList: TList<Integer>;
  ManagedList: TList<UnicodeString>;
  NotifyList: TOverrideNotifyList;
  NotifyProbe: TNotifyProbe;
  ObjectList: TObjectList<TTracked>;
begin
  IntegerList:=TList<Integer>.Create([0,1,0,2,3,0,4,0]);
  try
    IntegerList.Pack;
    Check((IntegerList.Count=4) and (IntegerList[0]=1) and
      (IntegerList[1]=2) and (IntegerList[2]=3) and
      (IntegerList[3]=4),'unmanaged Pack stable order');

    IntegerList.Clear;
    for I:=1 to 32 do
      IntegerList.Add(I);
    IntegerList.Pack;
    Check((IntegerList.Count=32) and (IntegerList[0]=1) and
      (IntegerList[31]=32),'unmanaged Pack without holes');
  finally
    IntegerList.Free;
  end;

  IntegerList:=TList<Integer>.Create(TMinusOneIsEmptyComparer.Create);
  try
    IntegerList.AddRange([-1,1,0,2,-1,3]);
    IntegerList.Pack;
    Check((IntegerList.Count=3) and (IntegerList[0]=1) and
      (IntegerList[1]=2) and (IntegerList[2]=3),
      'Pack preserves custom comparer semantics');
  finally
    IntegerList.Free;
  end;

  NotifyProbe:=TNotifyProbe.Create;
  IntegerList:=TList<Integer>.Create([0,1,0,2,0]);
  try
    IntegerList.OnNotify:=NotifyProbe.Notify;
    IntegerList.Pack;
    Check((IntegerList.Count=2) and (IntegerList[0]=1) and
      (IntegerList[1]=2) and (NotifyProbe.Removed=3),
      'Pack with OnNotify preserves removal notifications');
  finally
    IntegerList.OnNotify:=nil;
    IntegerList.Free;
    NotifyProbe.Free;
  end;

  NotifyList:=TOverrideNotifyList.Create;
  try
    NotifyList.AddRange([0,1,0,2,0]);
    NotifyList.Pack;
    Check((NotifyList.Count=2) and (NotifyList.Removed=3) and
      (NotifyList[0]=1) and (NotifyList[1]=2),
      'Pack preserves overridden Notify');
  finally
    NotifyList.Free;
  end;

  ManagedList:=TList<UnicodeString>.Create(['','one','','two','']);
  try
    ManagedList.Pack;
    Check((ManagedList.Count=2) and (ManagedList[0]='one') and
      (ManagedList[1]='two'),'managed Pack values and lifetime');
  finally
    ManagedList.Free;
  end;

  Destroyed:=0;
  ObjectList:=TObjectList<TTracked>.Create(True);
  try
    for I:=1 to 4 do
      ObjectList.Add(TTracked.Create(I));
    ObjectList.Pack(
      function(const L, R: TTracked): Boolean
      begin
        Result:=not Odd(L.Number);
      end);
    Check((ObjectList.Count=2) and (ObjectList[0].Number=1) and
      (ObjectList[1].Number=3) and (Destroyed=2),
      'owning object Pack preserves custom predicate and destruction');
  finally
    ObjectList.Free;
  end;
  Check(Destroyed=4,'owning object Pack exact final lifetime');
end;

procedure CheckDeletedInterfaceOrder(AList: TList<ITracked>);
begin
  Check((AList.Count=2) and (AList[0].Number=1) and
    (AList[1].Number=4),'managed DeleteRange order');
end;

procedure CheckListDeleteRange;
var
  I: Integer;
  IntegerList: TList<Integer>;
  InterfaceList: TList<ITracked>;
  NotifyList: TOverrideNotifyList;
  ObjectList: TObjectList<TTracked>;
  Raised: Boolean;
begin
  IntegerList:=TList<Integer>.Create;
  try
    for I:=0 to 9 do
      IntegerList.Add(I);
    IntegerList.DeleteRange(3,4);
    Check((IntegerList.Count=6) and (IntegerList[0]=0) and
      (IntegerList[2]=2) and (IntegerList[3]=7) and
      (IntegerList[5]=9),'unmanaged middle DeleteRange');
    IntegerList.DeleteRange(4,2);
    Check((IntegerList.Count=4) and (IntegerList[3]=7),
      'unmanaged tail DeleteRange');
    IntegerList.DeleteRange(0,IntegerList.Count);
    Check(IntegerList.Count=0,'unmanaged full DeleteRange');

    IntegerList.DeleteRange(-1,0);
    Check(IntegerList.Count=0,'zero DeleteRange preserves established no-op');
    Raised:=False;
    try
      IntegerList.DeleteRange(-1,1);
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised,'negative DeleteRange rejected');
    Raised:=False;
    try
      IntegerList.DeleteRange(0,High(SizeInt));
    except
      on EArgumentOutOfRangeException do
        Raised:=True;
    end;
    Check(Raised and (IntegerList.Count=0),
      'overflowing DeleteRange rejected before mutation');
  finally
    IntegerList.Free;
  end;

  NotifyList:=TOverrideNotifyList.Create;
  try
    NotifyList.AddRange([0,1,2,3,4,5]);
    NotifyList.DeleteRange(1,3);
    Check((NotifyList.Count=3) and (NotifyList[0]=0) and
      (NotifyList[1]=4) and (NotifyList[2]=5) and
      (NotifyList.Removed=3),'DeleteRange preserves overridden Notify');
  finally
    NotifyList.Free;
  end;

  Destroyed:=0;
  InterfaceList:=TList<ITracked>.Create;
  try
    for I:=1 to 4 do
      InterfaceList.Add(TTracked.Create(I));
    InterfaceList.DeleteRange(1,2);
    Check(Destroyed=2,'managed DeleteRange releases removed values');
    CheckDeletedInterfaceOrder(InterfaceList);
  finally
    InterfaceList.Free;
  end;
  Check(Destroyed=4,'managed DeleteRange exact lifetime');

  Destroyed:=0;
  ObjectList:=TObjectList<TTracked>.Create(True);
  try
    for I:=1 to 4 do
      ObjectList.Add(TTracked.Create(I));
    ObjectList.DeleteRange(1,2);
    Check((ObjectList.Count=2) and (ObjectList[0].Number=1) and
      (ObjectList[1].Number=4) and (Destroyed=2),
      'owning object DeleteRange preserves destruction');
  finally
    ObjectList.Free;
  end;
  Check(Destroyed=4,'owning object DeleteRange exact lifetime');
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
  IntegerCopy: TList<Integer>;
  InterfaceCopy, InterfaceSource: TList<ITracked>;
  QueueSource: TQueue<Integer>;
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

  QueueSource:=TQueue<Integer>.Create;
  IntegerCopy:=nil;
  try
    QueueSource.Enqueue(10);
    QueueSource.Enqueue(20);
    QueueSource.Enqueue(30);
    Check(QueueSource.Dequeue=10,'queue source preparation');
    QueueSource.Enqueue(40);
    IntegerCopy:=TList<Integer>.Create(QueueSource);
    Check((IntegerCopy.Count=3) and (IntegerCopy[0]=20) and
      (IntegerCopy[1]=30) and (IntegerCopy[2]=40),
      'non-list custom collection constructor uses logical enumeration');
  finally
    IntegerCopy.Free;
    QueueSource.Free;
  end;
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
    CheckBulkListRanges;
    CheckListPack;
    CheckListDeleteRange;
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
