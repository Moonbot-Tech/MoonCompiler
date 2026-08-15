program legacy_collections_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  Contnrs;

type
  TTrackedObject = class
  public
    Number: Integer;
    constructor Create(ANumber: Integer);
    destructor Destroy; override;
  end;

  TAdderThread = class(TThread)
  private
    FBase: Integer;
    FList: TThreadList;
  protected
    procedure Execute; override;
  public
    constructor Create(AList: TThreadList; ABase: Integer);
  end;

var
  ObjectsDestroyed: Integer;
  CustomSortCalls: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
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

function ComparePointers(Item1, Item2: Pointer): Integer;
begin
  if PtrUInt(Item1) < PtrUInt(Item2) then
    Result := -1
  else if PtrUInt(Item1) > PtrUInt(Item2) then
    Result := 1
  else
    Result := 0;
end;

function CompareLengthThenOrdinal(List: TStringList;
  Index1, Index2: Integer): Integer;
begin
  Inc(CustomSortCalls);
  Result := Length(List[Index1]) - Length(List[Index2]);
  if Result = 0 then
    Result := CompareStr(List[Index1], List[Index2]);
end;

procedure TestStringList;
var
  I: Integer;
  Item: UnicodeString;
  List: TStringList;
  Raised: Boolean;
begin
  List := TStringList.Create;
  try
    List.Add('beta');
    List.Add('Alpha');
    List.Add('gamma=3');
    List.Sort;
    Check((List[0] = 'Alpha') and (List.IndexOf('beta') >= 0),
      'TStringList sort and search');
    Check(List.Values['gamma'] = '3', 'TStringList Values read');
    List.Values['gamma'] := '33';
    Check(List.Values['gamma'] = '33', 'TStringList Values update');
    List.Values['delta'] := '4';
    Check(List.Values['delta'] = '4', 'TStringList Values add');
    I := 0;
    for Item in List do
      Inc(I, Length(Item));
    Check(I > 0, 'TStringList enumeration');

    List.Clear;
    List.CaseSensitive := False;
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    Check((List.Add('same') = 0) and (List.Add('SAME') = 0) and
      (List.Count = 1), 'TStringList case-insensitive duplicate ignore');
    List.Duplicates := dupError;
    Raised := False;
    try
      List.Add('same');
    except
      on EStringListError do
        Raised := True;
    end;
    Check(Raised, 'TStringList duplicate exception class');
    Raised := False;
    try
      Item := List[List.Count];
    except
      on EStringListError do
        Raised := True;
    end;
    Check(Raised, 'TStringList bounds exception class');

    List.Sorted := False;
    List.Duplicates := dupAccept;
    List.Clear;
    CustomSortCalls := 0;
    List.CustomSort(@CompareLengthThenOrdinal);
    List.Add('единственный');
    List.CustomSort(@CompareLengthThenOrdinal);
    Check((List.Count = 1) and (CustomSortCalls = 0),
      'TStringList CustomSort empty and singleton');
    List.Add('ёж');
    List.Add('alpha');
    List.Add('Бета');
    List.Add('alpha');
    List.CustomSort(@CompareLengthThenOrdinal);
    Check((List.Count = 5) and (CustomSortCalls > 0),
      'TStringList CustomSort Unicode duplicates count');
    for I := 0 to List.Count - 2 do
      Check(CompareLengthThenOrdinal(List, I, I + 1) <= 0,
        'TStringList CustomSort custom comparator order');
  finally
    List.Free;
  end;

  ObjectsDestroyed := 0;
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    List.AddObject('first', TTrackedObject.Create(1));
    List.AddObject('second', TTrackedObject.Create(2));
    List.Delete(0);
    Check(ObjectsDestroyed = 1, 'TStringList Delete owns object');
    List.Clear;
    Check(ObjectsDestroyed = 2, 'TStringList Clear owns object');
  finally
    List.Free;
  end;
  Check(ObjectsDestroyed = 2, 'TStringList exact object lifetime');
end;

procedure TestLegacyList;
var
  I: Integer;
  Item: Pointer;
  List: Classes.TList;
  Previous, Sum, Value: PtrUInt;
  Raised: Boolean;
begin
  List := Classes.TList.Create;
  try
    for I := 32 downto 1 do
      List.Add(Pointer(PtrInt(I)));
    List.Insert(0, Pointer(PtrInt(99)));
    Check((PtrInt(List[0]) = 99) and
      (List.IndexOf(Pointer(PtrInt(16))) >= 0), 'TList insert and search');
    List.Exchange(0, 1);
    List.Move(1, 2);
    List.Delete(0);
    List.Sort(@ComparePointers);
    I := 0;
    Previous := 0;
    Sum := 0;
    for Item in List do
    begin
      Inc(I);
      Value := PtrUInt(Item);
      Check(Value > Previous, 'TList sort and enumeration order');
      Previous := Value;
      Inc(Sum, Value);
    end;
    Check((I = 32) and (Sum = 595), 'TList enumeration count and values');
    Raised := False;
    try
      Item := List[List.Count];
    except
      on EListError do
        Raised := True;
    end;
    Check(Raised, 'TList bounds exception class');
  finally
    List.Free;
  end;
end;

procedure TestObjectListOwnership;
var
  Extracted: TObject;
  List: Contnrs.TObjectList;
begin
  ObjectsDestroyed := 0;
  List := Contnrs.TObjectList.Create(True);
  try
    List.Add(TTrackedObject.Create(1));
    List.Add(TTrackedObject.Create(2));
    List.Add(TTrackedObject.Create(3));
    Extracted := List.Extract(List[1]);
    Check((TTrackedObject(Extracted).Number = 2) and (ObjectsDestroyed = 0),
      'TObjectList Extract transfers ownership');
    Extracted.Free;
    List.Delete(0);
    Check(ObjectsDestroyed = 2, 'TObjectList Delete owns object');
    List.Clear;
    Check(ObjectsDestroyed = 3, 'TObjectList Clear owns object');
  finally
    List.Free;
  end;
  Check(ObjectsDestroyed = 3, 'TObjectList exact object lifetime');
end;

procedure TestThreadList;
var
  I, J: Integer;
  List: TThreadList;
  Locked: Classes.TList;
  Threads: array[0..3] of TAdderThread;
begin
  List := TThreadList.Create;
  try
    for I := 0 to High(Threads) do
    begin
      Threads[I] := TAdderThread.Create(List, I * 1000);
      Threads[I].Start;
    end;
    for I := 0 to High(Threads) do
      Threads[I].WaitFor;
    Locked := List.LockList;
    try
      Check(Locked.Count = 4000, 'TThreadList concurrent Add count');
      for I := 0 to High(Threads) do
        for J := 1 to 1000 do
          Check(Locked.IndexOf(Pointer(PtrInt(I * 1000 + J))) >= 0,
            'TThreadList concurrent Add value');
    finally
      List.UnlockList;
    end;
    List.Clear;
    Locked := List.LockList;
    try
      Check(Locked.Count = 0, 'TThreadList Clear');
    finally
      List.UnlockList;
    end;
  finally
    for I := 0 to High(Threads) do
      Threads[I].Free;
    List.Free;
  end;
end;

begin
  try
    TestStringList;
    TestLegacyList;
    TestObjectListOwnership;
    TestThreadList;
    WriteLn('LEGACY_COLLECTIONS_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
