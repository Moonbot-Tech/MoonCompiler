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

  TNotifyProbe = class
  public
    Added, Removed: Integer;
    LastAdded, LastRemoved: Integer;
    procedure Notify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
  end;

  TCaseInsensitiveComparer = class(TInterfacedObject,
    IComparer<UnicodeString>)
  public
    function Compare(const ALeft, ARight: UnicodeString): Integer;
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

function TCaseInsensitiveComparer.Compare(const ALeft,
  ARight: UnicodeString): Integer;
begin
  Result:=CompareText(ALeft,ARight);
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

begin
  try
    CheckIntegerList;
    CheckManagedList;
    CheckQueueCompaction;
    CheckTerminalReads;
    CheckAVLExtraction;
    WriteLn('COLLECTIONS_HOTPATHS_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
