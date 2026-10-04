program inline_managed_getter_chain_semantic;

{ The value of an inlined string or dynamic-array getter whose object another
  inlined getter returned, or whose object or index the inliner kept in a temp
  of its own (a field, a computed index), is read straight from the source when
  its consumer only reads: the object's temp is handed to the consumer instead
  of the result's own reference.  Each read sees the source as it is between a
  change right before the expression and a change right after it.  A routine
  taking the value as an argument, and an operand that replaces the source,
  still get the result's own reference - those reads must survive the replaced
  and reused storage.  The shapes that read the object's temp twice, or read it
  in a call that inlining expands, keep their result temp and must compile. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections;

type
  TIntArray = array of Integer;

  TNode = class
  public
    FName: UnicodeString;
    FValues: TIntArray;
    FChild: TNode;
    FNames: array of UnicodeString;
    FIndex: Integer;
    function GetName: UnicodeString; inline;
    function GetValues: TIntArray; inline;
    function GetChild: TNode; inline;
    function GetNameAt(I: Integer): UnicodeString; inline;
    function GetCurrent: UnicodeString; inline;
    function GetIsLast: Boolean; inline;
    function GetOwnerName: UnicodeString; inline;
    property Name: UnicodeString read GetName;
    property Values: TIntArray read GetValues;
    property Child: TNode read GetChild;
    property NameAt[I: Integer]: UnicodeString read GetNameAt;
    property Current: UnicodeString read GetCurrent;
    property IsLast: Boolean read GetIsLast;
    property OwnerName: UnicodeString read GetOwnerName;
  end;

  TNodeList = TList<TNode>;

  TShelf = class
  public
    FNodes: TNodeList;
    FKeys: TList<UnicodeString>;
    FArray: array of TNode;
    function Reads(const Key, Key17: UnicodeString): Integer; noinline;
    procedure Escapes; noinline;
  end;

  TLabel = record
    FText: UnicodeString;
    function GetText: UnicodeString; inline;
    property Text: UnicodeString read GetText;
  end;

  TLabelHolder = class
  public
    FLabel: TLabel;
    function GetLabel: TLabel; inline;
    property Lbl: TLabel read GetLabel;
  end;

var
  Nodes: TNodeList;
  LastNode: TNode;
  Shelf: TShelf;
  TextTrash: UnicodeString;
  ArrayTrash: TIntArray;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('INLINE_MANAGED_GETTER_CHAIN_FAIL: ' + AMessage);
end;

function TNode.GetName: UnicodeString;
begin
  Result := FName;
end;

function TNode.GetValues: TIntArray;
begin
  Result := FValues;
end;

function TNode.GetChild: TNode;
begin
  Result := FChild;
end;

function TNode.GetNameAt(I: Integer): UnicodeString;
begin
  Result := FNames[I];
end;

function TNode.GetCurrent: UnicodeString;
begin
  Result := FNames[FIndex];
end;

function SameNode(const A, B: TObject): Boolean; inline;
begin
  Result := (A <> nil) and (A = B);
end;

function TNode.GetIsLast: Boolean;
begin
  Result := SameNode(Self, LastNode);
end;

{ reads its parameter three times once it is inlined; a method on Self would
  not do: the tree names its Self twice, and the temp read twice keeps its
  result temp anyway }
function OwnerOf(N: TNode): TNode; inline;
begin
  if N.FIndex = 2 then
    Result := N
  else
    Result := N.FChild;
end;

function TNode.GetOwnerName: UnicodeString;
begin
  Result := OwnerOf(Self).FName;
end;

function TLabel.GetText: UnicodeString;
begin
  Result := FText;
end;

function TLabelHolder.GetLabel: TLabel;
begin
  Result := FLabel;
end;

{ Gives every node fresh storage marked by Seed and fills storage of the same
  sizes with garbage, so that a read through a released source pointer sees 'Z'
  or -1 instead of the value it should have kept. }
procedure Replace(Seed: Integer);
var
  I, J: Integer;
  N: TNode;
begin
  for I := 0 to Nodes.Count - 1 do
  begin
    N := Nodes[I];
    N.FName := StringOfChar(Char(Ord('a') + Seed), 32 + I);
    SetLength(N.FValues, 0);
    SetLength(N.FValues, 32);
    for J := 0 to High(N.FValues) do
      N.FValues[J] := Seed * 1000 + I * 100 + J;
    SetLength(N.FNames, 0);
    SetLength(N.FNames, 4);
    for J := 0 to High(N.FNames) do
      N.FNames[J] := StringOfChar(Char(Ord('a') + Seed), J + 1);
  end;
  for I := 0 to Shelf.FKeys.Count - 1 do
    Shelf.FKeys[I] := StringOfChar(Char(Ord('A') + Seed), 16 + I);
  TextTrash := StringOfChar('Z', 40);
  SetLength(ArrayTrash, 0);
  SetLength(ArrayTrash, 32);
  for I := 0 to High(ArrayTrash) do
    ArrayTrash[I] := -1;
end;

{ consumers that read straight from the source }

function ListReads(L: TNodeList; I: Integer; const Key: UnicodeString): Integer; noinline;
begin
  Result := 0;
  Replace(1);
  if L[I].Name = Key then
    Inc(Result, 1);
  if L[I].Name <> '' then
    Inc(Result, 10);
  Inc(Result, Length(L[I].Name) * 100);
  Inc(Result, Ord(L[I].Name[2]) * 10000);
  Inc(Result, L[I].Values[3] * 1000000);
  Replace(2);
end;

function ChainReads(L: TNodeList; I: Integer; const Key32, Key33: UnicodeString): Integer; noinline;
begin
  Result := 0;
  Replace(1);
  if L[I].Child.Name = Key32 then
    Inc(Result, 1);
  if L[I].Child.Child.Name = Key33 then
    Inc(Result, 10);
  Inc(Result, Length(L[I].Child.Child.Child.Name) * 100);
  Inc(Result, L[I].Child.Values[5] * 10000);
  Replace(2);
end;

function IndexReads(N: TNode; I, J: Integer): Integer; noinline;
begin
  Result := 0;
  Replace(1);
  if N.NameAt[I * 2 + J] = 'bbbb' then
    Inc(Result, 1);
  Inc(Result, Length(N.NameAt[I + J]) * 10);
  Replace(2);
end;

function TShelf.Reads(const Key, Key17: UnicodeString): Integer;
var
  I: Integer;
begin
  Result := 0;
  Replace(1);
  for I := 0 to FNodes.Count - 1 do
  begin
    if FNodes[I].Name = Key then
      Inc(Result, 1);
    if FArray[I].Name = Key then
      Inc(Result, 10);
    Inc(Result, Length(FNodes[I].Values) * 100);
  end;
  for I := 0 to FKeys.Count - 1 do
    if FKeys[I] = Key17 then
      Inc(Result, 10000);
  Replace(2);
end;

function LabelReads(H: TLabelHolder; const Key12: UnicodeString): Integer; noinline;
begin
  Result := 0;
  H.FLabel.FText := StringOfChar('b', 12);
  if H.Lbl.Text = Key12 then
    Inc(Result, 1);
  Inc(Result, Length(H.Lbl.Text) * 10);
  H.FLabel.FText := StringOfChar('c', 3);
end;

{ the shapes that keep the result temp: the object's temp read twice, and read
  in a call that inlining expands - the string of OwnerName, whose temp the
  expanded OwnerOf would read three times after its release (a Boolean such as
  IsLast keeps its temp anyway) }
function KeptShapes(L: TNodeList; I: Integer; const Key32: UnicodeString): Integer; noinline;
begin
  Result := 0;
  Replace(1);
  L[I].FIndex := 2;
  if L[I].Current = 'bbb' then
    Inc(Result, 1);
  if L[I].IsLast then
    Inc(Result, 10);
  if L[I].OwnerName = Key32 then
    Inc(Result, 100);
  Replace(2);
end;

{ consumers that keep the result's own reference }

procedure ConsumeText(const T: UnicodeString; const Expected: UnicodeString); noinline;
begin
  Replace(2);
  Check(T = Expected, 'const text argument');
end;

procedure ConsumeValues(const V: TIntArray; First: Integer); noinline;
begin
  Replace(2);
  Check((Length(V) = 32) and (V[0] = First) and (V[31] = First + 31), 'const array argument');
end;

function MutateText: UnicodeString; noinline;
begin
  Replace(2);
  Result := StringOfChar('d', 8);
end;

procedure TShelf.Escapes;
var
  T: UnicodeString;
begin
  Replace(1);
  ConsumeText(FNodes[1].Name, StringOfChar('b', 33));
  Replace(1);
  ConsumeText(FArray[2].Name, StringOfChar('b', 34));
  Replace(1);
  ConsumeText(Nodes[0].Child.Name, StringOfChar('b', 33));
  Replace(1);
  ConsumeValues(Nodes[1].Values, 1100);
  Replace(1);
  ConsumeText(Nodes[1].NameAt[Nodes.Count - 1], 'bbbb');
  { an operand that replaces the source: whichever state is read, it must not
    be the released storage }
  Replace(1);
  T := Nodes[0].Name + MutateText;
  Check(((Copy(T, 1, 32) = StringOfChar('b', 32)) or
    (Copy(T, 1, 32) = StringOfChar('c', 32))) and
    (Copy(T, 33, 8) = StringOfChar('d', 8)), 'operand that replaces the source');
end;

var
  I: Integer;
  N: TNode;
  Holder: TLabelHolder;
begin
  Nodes := TNodeList.Create;
  Shelf := TShelf.Create;
  Shelf.FNodes := Nodes;
  Shelf.FKeys := TList<UnicodeString>.Create;
  Holder := TLabelHolder.Create;
  try
    for I := 0 to 3 do
    begin
      N := TNode.Create;
      Nodes.Add(N);
      Shelf.FKeys.Add('');
    end;
    for I := 0 to 3 do
      Nodes[I].FChild := Nodes[(I + 1) mod 4];
    LastNode := Nodes[0];
    SetLength(Shelf.FArray, 4);
    for I := 0 to 3 do
      Shelf.FArray[I] := Nodes[I];
    Replace(0);
    Check(ListReads(Nodes, 1, StringOfChar('b', 33)) =
      1 + 10 + 33 * 100 + Ord('b') * 10000 + 1103 * 1000000, 'list element reads');
    Check(ChainReads(Nodes, 3, StringOfChar('b', 32), StringOfChar('b', 33)) =
      1 + 10 + 34 * 100 + 1005 * 10000, 'chain reads');
    Check(IndexReads(Nodes[2], 1, 1) = 1 + 3 * 10, 'computed index reads');
    Check(Shelf.Reads(StringOfChar('b', 34), StringOfChar('B', 17)) = 11 + 4 * 32 * 100 + 10000,
      'field list reads');
    Check(LabelReads(Holder, StringOfChar('b', 12)) = 1 + 12 * 10, 'record getter reads');
    Check(KeptShapes(Nodes, 0, StringOfChar('b', 32)) = 111, 'kept shapes');
    Shelf.Escapes;
  finally
    Holder.Free;
    for I := 0 to Nodes.Count - 1 do
      Nodes[I].Free;
    Nodes.Free;
    Shelf.FKeys.Free;
    Shelf.Free;
  end;
  WriteLn('INLINE_MANAGED_GETTER_CHAIN_SEMANTIC_PASS');
end.
