program avl_extractpair_semantic;

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
    raise Exception.Create('AVL_EXTRACTPAIR_FAIL: ' + AMessage);
end;

procedure TestScalarOverloads;
var
  Map: TAVLTreeMap<Integer, UnicodeString>;
  Node: TAVLTreeMap<Integer, UnicodeString>.PNode;
  Pair: TPair<Integer, UnicodeString>;
begin
  Map := TAVLTreeMap<Integer, UnicodeString>.Create;
  try
    Map.Add(3, 'three');
    Map.Add(1, 'one');
    Map.Add(4, 'four');
    Map.Add(2, 'two');
    Pair := Map.ExtractPair(3);
    Check((Pair.Key = 3) and (Pair.Value = 'three'),
      'key overload returns two-child value');
    Check(not Map.ContainsKey(3) and (Map.Count = 3),
      'key overload removes item');
    Map.ConsistencyCheck;

    Node := Map.Find(2);
    Pair := Map.ExtractPair(Node);
    Check((Pair.Key = 2) and (Pair.Value = 'two'),
      'node overload returns value');
    Check(not Map.ContainsKey(2) and (Map.Count = 2),
      'node overload removes item');
    Pair := Map.ExtractPair(99);
    Check((Pair.Key = 0) and (Pair.Value = ''), 'missing key default pair');
    Map.ConsistencyCheck;
  finally
    Map.Free;
  end;
end;

procedure TestManagedLifetime;
var
  Map: TAVLTreeMap<Integer, IInterface>;
  Node: TAVLTreeMap<Integer, IInterface>.PNode;
  Pair: TPair<Integer, IInterface>;
  Item: IInterface;
begin
  Destroyed := 0;
  Map := TAVLTreeMap<Integer, IInterface>.Create;
  try
    Item := TTracked.Create;
    Map.Add(1, Item);
    Item := nil;
    Pair := Map.ExtractPair(1);
    Check((Pair.Key = 1) and (Pair.Value <> nil),
      'managed key overload result');
    Check(Destroyed = 0, 'managed result retained after disposed node');
    Pair.Value := nil;
    Check(Destroyed = 1, 'managed result final release');

    Item := TTracked.Create;
    Map.Add(2, Item);
    Item := nil;
    Node := Map.Find(2);
    Pair := Map.ExtractPair(Node, False);
    Check((Pair.Key = 2) and (Pair.Value <> nil) and
      not Map.ContainsKey(2), 'managed detached node result');
    Map.DisposeNode(Node);
    Check(Destroyed = 1, 'pair retains value after detached node dispose');
    Pair.Value := nil;
    Check(Destroyed = 2, 'detached managed final release');
  finally
    Map.Free;
  end;
end;

begin
  try
    TestScalarOverloads;
    TestManagedLifetime;
    WriteLn('AVL_EXTRACTPAIR_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
