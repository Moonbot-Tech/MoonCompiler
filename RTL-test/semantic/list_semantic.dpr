program list_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Variants,
  Generics.Collections;

type
  ITracked = interface
    ['{56148D8C-83F0-44D2-8793-D91A2F9E4617}']
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
    Values: TArray<Integer>;
  end;

  TPlainObject = class
  public
    destructor Destroy; override;
  end;

  TNotifyObserver = class
  public
    RemovedCount: Integer;
    AddedCount: Integer;
    RemovedValue: Integer;
    AddedValue: Integer;
    procedure HandleNotify(ASender: TObject; const AItem: Integer;
      AAction: TCollectionNotification);
  end;

var
  Destroyed: Integer;
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
  Inc(Destroyed);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

destructor TPlainObject.Destroy;
begin
  Inc(ObjectsDestroyed);
  inherited Destroy;
end;

procedure TNotifyObserver.HandleNotify(ASender: TObject; const AItem: Integer;
  AAction: TCollectionNotification);
begin
  Check(ASender <> nil, 'notification sender');
  case AAction of
    cnRemoved:
      begin
        Inc(RemovedCount);
        RemovedValue := AItem;
      end;
    cnAdded:
      begin
        Inc(AddedCount);
        AddedValue := AItem;
      end;
  end;
end;

procedure TestIntegerAddIndexAndEnumeration;
var
  I, Sum, Value: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create;
  try
    Check(List.Count = 0, 'new list count');
    for I := 0 to 1023 do
      Check(List.Add(I * 3) = I, 'Add index');
    Check(List.Count = 1024, 'grown list count');
    Sum := 0;
    for I := 0 to List.Count - 1 do
    begin
      Check(List[I] = I * 3, 'checked index value');
      Inc(Sum, List[I]);
    end;
    Check(Sum = 1571328, 'checked index sum');
    Sum := 0;
    I := 0;
    for Value in List do
    begin
      Check(Value = I * 3, 'enumerator order');
      Inc(Sum, Value);
      Inc(I);
    end;
    Check((I = 1024) and (Sum = 1571328), 'enumerator count/sum');
  finally
    List.Free;
  end;
end;

procedure TestBoundsAndEmptyEnumerator;
var
  Raised: Boolean;
  Value, Count: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create;
  try
    Count := 0;
    for Value in List do
      Inc(Count);
    Check(Count = 0, 'empty enumerator');

    Raised := False;
    try
      Value := List[-1];
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'negative index exception');

    List.Add(7);
    Raised := False;
    try
      Value := List[List.Count];
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'high index exception');

    Raised := False;
    try
      List[-1] := 9;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'negative setter index exception');

    Raised := False;
    try
      List[List.Count] := 9;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'high setter index exception');
  finally
    List.Free;
  end;
end;

procedure TestSetterManagedLifetimeAndNotification;
var
  OldItem, NewItem: ITracked;
  InterfaceList: TList<ITracked>;
  IntegerList: TList<Integer>;
  Observer: TNotifyObserver;
begin
  Destroyed := 0;
  OldItem := TTracked.Create(1);
  NewItem := TTracked.Create(2);
  InterfaceList := TList<ITracked>.Create;
  try
    InterfaceList.Add(OldItem);
    OldItem := nil;
    InterfaceList[0] := NewItem;
    Check(Destroyed = 1, 'setter releases displaced interface');
    Check(InterfaceList.List[0].Value = 2, 'setter stores replacement interface');
    NewItem := nil;
    Check(Destroyed = 1, 'list owns replacement reference');
    InterfaceList.Clear;
    Check(Destroyed = 2, 'clear releases setter replacement');
  finally
    InterfaceList.Free;
  end;
  Check(Destroyed = 2, 'setter interface lifetime exact');

  Observer := TNotifyObserver.Create;
  IntegerList := TList<Integer>.Create;
  try
    IntegerList.Add(10);
    IntegerList.OnNotify := Observer.HandleNotify;
    IntegerList[0] := 20;
    Check((Observer.RemovedCount = 1) and (Observer.RemovedValue = 10),
      'setter removed notification');
    Check((Observer.AddedCount = 1) and (Observer.AddedValue = 20),
      'setter added notification');
  finally
    IntegerList.OnNotify := nil;
    IntegerList.Free;
    Observer.Free;
  end;
end;

procedure TestStringCopyOnWrite;
var
  Source: UnicodeString;
  List: TList<UnicodeString>;
begin
  Source := 'shared-value';
  List := TList<UnicodeString>.Create;
  try
    List.Add(Source);
    Source[1] := 'S';
    Check(List[0] = 'shared-value', 'string COW in list');
    Check(Source = 'Shared-value', 'source mutation');
  finally
    List.Free;
  end;
end;

procedure TestInterfaceLifetime;
var
  Item: ITracked;
  List: TList<ITracked>;
begin
  Destroyed := 0;
  Item := TTracked.Create(42);
  List := TList<ITracked>.Create;
  try
    List.Add(Item);
    Item := nil;
    Check(Destroyed = 0, 'list keeps interface alive');
    Item := List[0];
    Check(Item.Value = 42, 'interface value');
    Item := nil;
    Check(Destroyed = 0, 'explicit reader reference released');
    List.Clear;
    Check(Destroyed = 1, 'Clear releases interface once');
  finally
    List.Free;
  end;
  Check(Destroyed = 1, 'free does not double release');
end;

procedure TestManagedRecordAndDynamicArrayLifetime;
var
  Source, ReadBack: TManagedValue;
  List: TList<TManagedValue>;
begin
  Source.Text := 'managed-value';
  Source.Values := TArray<Integer>.Create(10, 20, 30);
  List := TList<TManagedValue>.Create;
  try
    List.Add(Source);
    ReadBack := List[0];
    Check(ReadBack.Text = 'managed-value', 'managed record string read');
    Check((Length(ReadBack.Values) = 3) and (ReadBack.Values[1] = 20),
      'managed record dynamic array read');
    Source.Text[1] := 'M';
    Check(List[0].Text = 'managed-value', 'managed record string COW');
    Source.Values[1] := 99;
    Check(List[0].Values[1] = 99, 'dynamic array shared payload semantics');
    ReadBack.Text := '';
    ReadBack.Values := nil;
    List.Clear;
    Check((Source.Text = 'Managed-value') and (Source.Values[1] = 99),
      'managed record clear preserves other owners');
  finally
    List.Free;
  end;
end;

procedure TestVariantAndObjectPointer;
var
  Item, ReadObject: TPlainObject;
  Value: Variant;
  VariantList: TList<Variant>;
  ObjectList: TList<TPlainObject>;
begin
  VariantList := TList<Variant>.Create;
  try
    VariantList.Add(123456);
    VariantList.Add('variant-text');
    Value := VariantList[0];
    Check(Value = 123456, 'numeric variant read');
    Value := VariantList[1];
    Check(Value = 'variant-text', 'string variant read');
    Value := Unassigned;
    VariantList.Clear;
    Check(VariantList.Count = 0, 'variant clear');
  finally
    VariantList.Free;
  end;

  ObjectsDestroyed := 0;
  Item := TPlainObject.Create;
  ObjectList := TList<TPlainObject>.Create;
  try
    ObjectList.Add(Item);
    ReadObject := ObjectList[0];
    Check(ReadObject = Item, 'object pointer identity');
    ObjectList.Clear;
    Check(ObjectsDestroyed = 0, 'plain TList does not own object');
  finally
    ObjectList.Free;
    Item.Free;
  end;
  Check(ObjectsDestroyed = 1, 'object explicitly freed once');
end;

begin
  try
    TestIntegerAddIndexAndEnumeration;
    TestBoundsAndEmptyEnumerator;
    TestStringCopyOnWrite;
    TestInterfaceLifetime;
    TestSetterManagedLifetimeAndNotification;
    TestManagedRecordAndDynamicArrayLifetime;
    TestVariantAndObjectPointer;
    WriteLn('LIST_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
