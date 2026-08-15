program queue_movefront_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Generics.Collections;

type
  ITracked = interface
    ['{BA7FA1A4-D9EF-4472-B411-1A8F9C569F15}']
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

  TManagedItem = record
    Text: UnicodeString;
    Values: TArray<Integer>;
    Tracked: ITracked;
  end;

  TOperatorManagedItem = record
  private
    class operator Initialize(var AItem: TOperatorManagedItem);
    class operator Finalize(var AItem: TOperatorManagedItem);
    class operator Copy(constref ASource: TOperatorManagedItem;
      var ADestination: TOperatorManagedItem);
  public
    Number: Integer;
    Tracked: ITracked;
  end;

  TNotifyObserver = class
  public
    Added: Integer;
    Removed: Integer;
    procedure HandleNotify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
  end;

var
  LiveCount: Integer;
  OperatorCopyCount: Integer;
  OperatorFinalizeCount: Integer;
  OperatorInitializeCount: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('QUEUE_MOVEFRONT_LIFETIME_FAIL: ' + MessageText);
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
  Inc(LiveCount);
end;

destructor TTracked.Destroy;
begin
  Dec(LiveCount);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

class operator TOperatorManagedItem.Initialize(
  var AItem: TOperatorManagedItem);
begin
  Inc(OperatorInitializeCount);
  AItem.Number := -1;
  AItem.Tracked := nil;
end;

class operator TOperatorManagedItem.Finalize(var AItem: TOperatorManagedItem);
begin
  Inc(OperatorFinalizeCount);
  AItem.Tracked := nil;
  AItem.Number := -1;
end;

class operator TOperatorManagedItem.Copy(
  constref ASource: TOperatorManagedItem;
  var ADestination: TOperatorManagedItem);
begin
  Inc(OperatorCopyCount);
  ADestination.Number := ASource.Number;
  ADestination.Tracked := ASource.Tracked;
end;

procedure TNotifyObserver.HandleNotify(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  Check(ASender <> nil, 'notification sender');
  case AAction of
    cnAdded: Inc(Added);
    cnRemoved: Inc(Removed);
  end;
end;

procedure TestManagedCompactionLifetimeAndOrder;
var
  I: Integer;
  Item: ITracked;
  Queue: TQueue<ITracked>;
begin
  LiveCount := 0;
  Item := nil;
  Queue := TQueue<ITracked>.Create;
  try
    Queue.Capacity := 8;
    for I := 0 to 7 do
    begin
      Item := TTracked.Create(I);
      Queue.Enqueue(Item);
      Item := nil;
    end;
    Check((Queue.Count = 8) and (LiveCount = 8), 'initial ownership');

    for I := 0 to 5 do
    begin
      Item := Queue.Dequeue;
      Check(Item.Value = I, 'order before compaction');
      Item := nil;
    end;
    Check((Queue.Count = 2) and (LiveCount = 2), 'dequeue releases prefix');

    Item := TTracked.Create(8);
    Queue.Enqueue(Item); // forces MoveToFront at the fixed capacity
    Item := nil;
    Check((Queue.Count = 3) and (LiveCount = 3), 'ownership after compaction');

    for I := 6 to 8 do
    begin
      Item := Queue.Dequeue;
      Check(Item.Value = I, 'order after compaction');
      Item := nil;
    end;
    Check(Queue.Count = 0, 'empty after drain');
    Check(LiveCount = 0, 'logical drain releases every managed item');
  finally
    Item := nil;
    Queue.Free;
  end;
  Check(LiveCount = 0, 'destruction leaves exact lifetime balance');
end;

procedure TestOverlappingManagedRecordCompaction;
var
  I: Integer;
  Item: TManagedItem;
  Queue: TQueue<TManagedItem>;
begin
  LiveCount := 0;
  Item := Default(TManagedItem);
  Queue := TQueue<TManagedItem>.Create;
  try
    Queue.Capacity := 32;
    for I := 0 to 31 do
    begin
      Item.Text := 'item-' + IntToStr(I);
      Item.Values := TArray<Integer>.Create(I, I + 1);
      Item.Tracked := TTracked.Create(I);
      Queue.Enqueue(Item);
      Item := Default(TManagedItem);
    end;
    Check(LiveCount = 32, 'managed records initially owned');
    for I := 0 to 11 do
    begin
      Item := Queue.Dequeue;
      Check((Item.Text = 'item-' + IntToStr(I)) and
        (Item.Values[1] = I + 1) and (Item.Tracked.Value = I),
        'managed record order before overlapping compaction');
      Item := Default(TManagedItem);
    end;
    Check((Queue.Count = 20) and (LiveCount = 20),
      'managed record prefix released');

    Item.Text := 'item-32';
    Item.Values := TArray<Integer>.Create(32, 33);
    Item.Tracked := TTracked.Create(32);
    Queue.Enqueue(Item); // FLow=12, Count=20: source and destination overlap
    Item := Default(TManagedItem);
    Check((Queue.Count = 21) and (LiveCount = 21),
      'overlapping compaction preserves exact ownership');

    for I := 12 to 32 do
    begin
      Item := Queue.Dequeue;
      Check((Item.Text = 'item-' + IntToStr(I)) and
        (Item.Values[0] = I) and (Item.Tracked.Value = I),
        'managed record order after overlapping compaction');
      Item := Default(TManagedItem);
    end;
    Check((Queue.Count = 0) and (LiveCount = 0),
      'overlapping compaction releases managed records');
  finally
    Item := Default(TManagedItem);
    Queue.Free;
  end;
  Check(LiveCount = 0, 'managed record lifetime exact');
end;

procedure TestStringCopyOnWrite;
var
  I: Integer;
  Source, Value: UnicodeString;
  Queue: TQueue<UnicodeString>;
begin
  Queue := TQueue<UnicodeString>.Create;
  try
    Queue.Capacity := 8;
    for I := 0 to 7 do
      Queue.Enqueue('string-' + IntToStr(I));
    for I := 0 to 5 do
      Value := Queue.Dequeue;
    Source := 'shared-string';
    Queue.Enqueue(Source);
    Source[1] := 'S';
    Check(Queue.Dequeue = 'string-6', 'string order first');
    Check(Queue.Dequeue = 'string-7', 'string order second');
    Check(Queue.Dequeue = 'shared-string', 'string COW after compaction');
    Check(Source = 'Shared-string', 'string source COW');
  finally
    Queue.Free;
  end;
end;

procedure TestCustomManagedOperators;
var
  I: Integer;
  Item: TOperatorManagedItem;
  Queue: TQueue<TOperatorManagedItem>;
begin
  LiveCount := 0;
  OperatorCopyCount := 0;
  OperatorFinalizeCount := 0;
  OperatorInitializeCount := 0;
  Queue := TQueue<TOperatorManagedItem>.Create;
  try
    Queue.Capacity := 8;
    for I := 0 to 7 do
    begin
      Item.Number := I;
      Item.Tracked := TTracked.Create(I);
      Queue.Enqueue(Item);
      Item.Tracked := nil;
    end;
    Check((LiveCount = 8) and (OperatorCopyCount > 0),
      'custom Copy stores queue resources');
    for I := 0 to 5 do
    begin
      Item := Queue.Dequeue;
      Check((Item.Number = I) and (Item.Tracked.Value = I),
        'custom managed order before compaction');
      Item.Tracked := nil;
    end;
    Queue.Enqueue(Item); // no resource, but still forces compaction
    Check((Queue.Count = 3) and (LiveCount = 2),
      'custom managed compaction ownership');
    Item := Queue.Dequeue;
    Check(Item.Number = 6, 'custom managed order first');
    Item.Tracked := nil;
    Item := Queue.Dequeue;
    Check(Item.Number = 7, 'custom managed order second');
    Item.Tracked := nil;
    Item := Queue.Dequeue;
    Check(Item.Tracked = nil, 'custom managed default element');
    Check((Queue.Count = 0) and (LiveCount = 0),
      'custom managed drain releases resources');
  finally
    Item.Tracked := nil;
    Queue.Free;
  end;
  Check((LiveCount = 0) and (OperatorInitializeCount > 0) and
    (OperatorFinalizeCount > 0), 'custom managed operators balanced resources');
end;

procedure TestNotificationCount;
var
  I: Integer;
  Observer: TNotifyObserver;
  Queue: TQueue<Integer>;
begin
  Observer := TNotifyObserver.Create;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Capacity := 8;
    Queue.OnNotify := Observer.HandleNotify;
    for I := 0 to 7 do
      Queue.Enqueue(I);
    for I := 0 to 5 do
      Queue.Dequeue;
    Queue.Enqueue(8);
    Check((Observer.Added = 9) and (Observer.Removed = 6),
      'compaction has no synthetic notification');
    Queue.Clear;
    Check((Observer.Added = 9) and (Observer.Removed = 9),
      'clear notification balance');
  finally
    Queue.OnNotify := nil;
    Queue.Free;
    Observer.Free;
  end;
end;

procedure TestEmptyBoundaries;
var
  Item: ITracked;
  Raised: Boolean;
  Queue: TQueue<ITracked>;
begin
  Queue := TQueue<ITracked>.Create;
  try
    Raised := False;
    try
      Item := Queue.Peek;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'Peek on empty queue');

    Raised := False;
    try
      Item := Queue.Dequeue;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'Dequeue on empty queue');
  finally
    Queue.Free;
  end;
end;

begin
  try
    TestManagedCompactionLifetimeAndOrder;
    TestOverlappingManagedRecordCompaction;
    TestStringCopyOnWrite;
    TestCustomManagedOperators;
    TestNotificationCount;
    TestEmptyBoundaries;
    WriteLn('QUEUE_MOVEFRONT_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(E.Message);
      Halt(1);
    end;
  end;
end.
