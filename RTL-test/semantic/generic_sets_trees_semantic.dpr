program generic_sets_trees_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Generics.Collections;

type
  TTracked = class(TInterfacedObject)
  public
    destructor Destroy; override;
  end;

var
  Destroyed: LongInt;

destructor TTracked.Destroy;
begin
  InterlockedIncrement(Destroyed);
  inherited Destroy;
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('GENERIC_SETS_TREES_FAIL: ' + AMessage);
end;

procedure TestHashSet;
var
  Left, Right: THashSet<Integer>;
  Managed: THashSet<IInterface>;
  Item: IInterface;
  Seen: array[0..9] of Boolean;
  Value, Count: Integer;
begin
  Left := THashSet<Integer>.Create;
  Right := THashSet<Integer>.Create;
  try
    Check(Left.Add(1) and Left.Add(2) and Left.Add(3), 'hash add');
    Check(not Left.Add(2), 'hash duplicate');
    Check(Left.Contains(2) and not Left.Contains(9), 'hash contains');
    Check(Left.Remove(2) and not Left.Remove(2), 'hash remove');
    Check(Left.Extract(3) = 3, 'hash extract');
    Left.AddRange([2, 3, 4]);
    Right.AddRange([3, 4, 5]);
    Left.UnionWith(Right);
    Check((Left.Count = 5) and Left.Contains(5), 'hash union');
    Left.IntersectWith(Right);
    Check((Left.Count = 3) and Left.Contains(3) and Left.Contains(5),
      'hash intersection');
    Left.Add(2);
    Left.ExceptWith(Right);
    Check((Left.Count = 1) and Left.Contains(2), 'hash except');
    Left.SymmetricExceptWith(Right);
    Check((Left.Count = 4) and Left.Contains(2) and Left.Contains(5),
      'hash symmetric except');
    FillChar(Seen, SizeOf(Seen), 0);
    Count := 0;
    for Value in Left do
    begin
      Check((Value >= Low(Seen)) and (Value <= High(Seen)) and
        not Seen[Value], 'hash enumeration value');
      Seen[Value] := True;
      Inc(Count);
    end;
    Check(Count = Left.Count, 'hash enumeration count');
    Left.TrimExcess;
    Check(Left.Contains(2), 'hash trim');
  finally
    Right.Free;
    Left.Free;
  end;

  Destroyed := 0;
  Managed := THashSet<IInterface>.Create;
  try
    Item := TTracked.Create;
    Check(Managed.Add(Item), 'managed hash add');
    Item := nil;
    Check(Destroyed = 0, 'managed hash retain');
    Managed.Clear;
    Check(Destroyed = 1, 'managed hash clear lifetime');
  finally
    Managed.Free;
  end;
end;

procedure TestSortedSets;
var
  Sorted: TSortedSet<Integer>;
  SortedHash: TSortedHashSet<Integer>;
  Value, Previous, Count: Integer;
begin
  Sorted := TSortedSet<Integer>.Create;
  try
    Sorted.AddRange([7, 1, 9, 3, 3, 5]);
    Check((Sorted.Count = 5) and Sorted.Contains(7), 'sorted set add');
    Previous := Low(Integer);
    Count := 0;
    for Value in Sorted do
    begin
      Check(Value > Previous, 'sorted set order');
      Previous := Value;
      Inc(Count);
    end;
    Check(Count = Sorted.Count, 'sorted set enumeration');
    Check(Sorted.Remove(3) and (Sorted.Extract(5) = 5),
      'sorted set remove/extract');
  finally
    Sorted.Free;
  end;

  SortedHash := TSortedHashSet<Integer>.Create;
  try
    SortedHash.AddRange([8, 2, 6, 4, 2]);
    Check((SortedHash.Count = 4) and SortedHash.Contains(6),
      'sorted hash add/contains');
    Previous := Low(Integer);
    Count := 0;
    for Value in SortedHash do
    begin
      Check(Value > Previous, 'sorted hash order');
      Previous := Value;
      Inc(Count);
    end;
    Check(Count = SortedHash.Count, 'sorted hash enumeration');
    Check(SortedHash.Remove(4) and not SortedHash.Contains(4),
      'sorted hash remove');
    SortedHash.TrimExcess;
  finally
    SortedHash.Free;
  end;
end;

procedure TestAVLTrees;
var
  Map: TAVLTreeMap<Integer, UnicodeString>;
  Indexed: TIndexedAVLTree<Integer>;
  Node: TIndexedAVLTree<Integer>.PNode;
  Pair: TPair<Integer, UnicodeString>;
  Key, Previous, Count: Integer;
  Raised: Boolean;
begin
  Map := TAVLTreeMap<Integer, UnicodeString>.Create;
  try
    Map.Add(3, 'three');
    Map.Add(1, 'one');
    Map.Add(4, 'four');
    Map.Add(2, 'two');
    Map.ConsistencyCheck;
    Check((Map.Count = 4) and Map.ContainsKey(2) and
      not Map.ContainsKey(9), 'AVL contains');
    Check(Map[3] = 'three', 'AVL indexed read');
    Map[3] := 'THREE';
    Check(Map[3] = 'THREE', 'AVL indexed write');
    Previous := Low(Integer);
    Count := 0;
    for Pair in Map do
    begin
      Check(Pair.Key > Previous, 'AVL pair order');
      Previous := Pair.Key;
      Inc(Count);
    end;
    Check(Count = Map.Count, 'AVL pair enumeration');
    Check(Map.Remove(2) and not Map.ContainsKey(2), 'AVL remove middle');
    Check(Map.Remove(4) and not Map.Remove(4), 'AVL remove');
    Map.ConsistencyCheck;
  finally
    Map.Free;
  end;

  Indexed := TIndexedAVLTree<Integer>.Create;
  try
    for Key := 9 downto 0 do
      Indexed.Add(Key);
    Indexed.ConsistencyCheck;
    for Key := 0 to 9 do
    begin
      Node := Indexed.GetNodeAtIndex(Key);
      Check((Node <> nil) and (Node^.Key = Key), 'indexed AVL lookup');
      Check(Indexed.NodeToIndex(Node) = Key, 'indexed AVL reverse lookup');
    end;
    Raised := False;
    try
      Indexed.GetNodeAtIndex(-1);
    except
      on EIndexedAVLTree do
        Raised := True;
    end;
    Check(Raised, 'indexed AVL low boundary exception');
    Raised := False;
    try
      Indexed.GetNodeAtIndex(10);
    except
      on EIndexedAVLTree do
        Raised := True;
    end;
    Check(Raised, 'indexed AVL high boundary exception');
  finally
    Indexed.Free;
  end;
end;

begin
  try
    TestHashSet;
    TestSortedSets;
    TestAVLTrees;
    WriteLn('GENERIC_SETS_TREES_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
