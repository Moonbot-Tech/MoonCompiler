program getter_borrow;
{ The value of an inlined string or dynamic-array getter is read straight from
  its source when its consumer finishes reading before any code can run that
  could change the source (compiler/optcall.pas, mark_funcret_borrow): an
  element or a character by an index without calls, a comparison, the empty
  test, Length/High, the step of Inc, including the consumers that appear
  only when an enclosing inline routine is expanded, and a getter whose object
  another inlined getter returned or whose list is a field (the object's temp
  goes to the consumer with the value).  A routine taking the value as an
  argument, or an index that calls a routine, keeps the result's own
  reference.  A record with managed fields read through the getter that
  returns it by value (L[I].Price of a TList<TQuote>) is read in place
  instead of copied, and keeps its copy where it goes to a routine.  Run at
  -O2 and -O3: values; run_getter_borrow_gate.py counts the instructions and
  calls of every routine in the -O3 object. }
{$mode delphi}
{$R-}
{$Q-}
uses
  SysUtils, Generics.Collections;

type
  TBox = class
  private
    FName: string;
    FData: TArray<Integer>;
    FChild: TBox;
    function GetName: string; inline;
    function GetData: TArray<Integer>; inline;
    function GetChild: TBox; inline;
  public
    property Name: string read GetName;
    property Data: TArray<Integer> read GetData;
    property Child: TBox read GetChild;
  end;

  TQuote = record
    Id: Int64;
    Price: Double;
    Symbol: string;
    Tags: TArray<Integer>;
  end;

  TShelf = class
  private
    FNames: TList<string>;
    FBoxes: TList<TBox>;
  public
    function FieldListFind(const Key: string): Integer; noinline;
    function FieldChainElement(I, J: Integer): Integer; noinline;
  end;

var
  Box: TBox;
  List: TList<string>;
  Boxes: TList<TBox>;
  Shelf: TShelf;
  Quotes: TList<TQuote>;
  Sunk: Integer;

function TBox.GetName: string;
begin
  Result := FName;
end;

function TBox.GetData: TArray<Integer>;
begin
  Result := FData;
end;

function TBox.GetChild: TBox;
begin
  Result := FChild;
end;

procedure Sink(const S: string); noinline;
begin
  Inc(Sunk, Length(S));
end;

function Two: Integer; noinline;
begin
  Result := 2;
end;

function IsNamed(B: TBox): Boolean; inline;
begin
  Result := B.Name <> '';
end;

function NameLength(B: TBox): Integer; inline;
begin
  Result := Length(B.Name);
end;

function DataSum(B: TBox): Integer; inline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(B.Data) do
    Inc(Result, B.Data[I]);
end;

function GetterLength(B: TBox): Integer; noinline;
begin
  Result := Length(B.Name);
end;

function GetterChar(B: TBox; I: Integer): Char; noinline;
begin
  Result := B.Name[I];
end;

function GetterCompare(B: TBox): Boolean; noinline;
begin
  Result := B.Name = 'abc';
end;

function GetterEmpty(B: TBox): Boolean; noinline;
begin
  Result := B.Name <> '';
end;

function GetterElement(B: TBox; I: Integer): Integer; noinline;
begin
  Result := B.Data[I];
end;

function GetterLoop(B: TBox): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(B.Data) do
    Inc(Result, B.Data[I]);
end;

function ListFind(L: TList<string>; const Key: string): Integer; noinline;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to L.Count - 1 do
    If L[I] = Key then
      Exit(I);
end;

function ListLengths(L: TList<string>): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do
    Inc(Result, Length(L[I]));
end;

function ListFirstChars(L: TList<string>): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do
    If L[I] <> '' then
      Inc(Result, Ord(L[I][1]));
end;

function NestedEmpty(B: TBox): Boolean; noinline;
begin
  Result := IsNamed(B);
end;

function NestedLength(B: TBox): Integer; noinline;
begin
  Result := NameLength(B);
end;

function NestedSum(B: TBox): Integer; noinline;
begin
  Result := DataSum(B);
end;

function ChainCompare(L: TList<TBox>; I: Integer; const Key: string): Boolean; noinline;
begin
  Result := L[I].Name = Key;
end;

function ChainLength(B: TBox): Integer; noinline;
begin
  Result := Length(B.Child.Name);
end;

function TShelf.FieldListFind(const Key: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FNames.Count - 1 do
    If FNames[I] = Key then
      Exit(I);
end;

function TShelf.FieldChainElement(I, J: Integer): Integer;
begin
  Result := FBoxes[I].Data[J];
end;

function RecordField(L: TList<TQuote>; I: Integer): Double; noinline;
begin
  Result := L[I].Price;
end;

function RecordCompare(L: TList<TQuote>; I: Integer; const Key: string): Boolean; noinline;
begin
  Result := L[I].Symbol = Key;
end;

function RecordElement(L: TList<TQuote>; I, J: Integer): Integer; noinline;
begin
  Result := L[I].Tags[J];
end;

{ the value goes to a routine: the result keeps its own reference }
procedure KeepToCall(B: TBox); noinline;
begin
  Sink(B.Name);
end;

procedure KeepChainToCall(L: TList<TBox>; I: Integer); noinline;
begin
  Sink(L[I].Name);
end;

procedure KeepRecordToCall(L: TList<TQuote>; I: Integer); noinline;
begin
  Sink(L[I].Symbol);
end;

{ an index that calls a routine: the result keeps its own reference }
function KeepIndexCall(B: TBox): Char; noinline;
begin
  Result := B.Name[Two];
end;

var
  Quote: TQuote;

procedure Check(Condition: Boolean; const What: string);
begin
  If not Condition then
  begin
    WriteLn('GETTER_BORROW_FAIL ', What);
    Halt(1);
  end;
end;

begin
  Box := TBox.Create;
  Box.FName := 'abc';
  Box.FData := [3, 5, 7, 11];
  List := TList<string>.Create;
  List.Add('alpha');
  List.Add('');
  List.Add('key');
  Box.FChild := Box;
  Boxes := TList<TBox>.Create;
  Boxes.Add(Box);
  Shelf := TShelf.Create;
  Shelf.FNames := List;
  Shelf.FBoxes := Boxes;
  Quotes := TList<TQuote>.Create;
  Quote.Id := 5;
  Quote.Price := 2.5;
  Quote.Symbol := 'quote';
  Quote.Tags := [4, 6, 8];
  Quotes.Add(Quote);
  Check(GetterLength(Box) = 3, 'length');
  Check(GetterChar(Box, 2) = 'b', 'char');
  Check(GetterCompare(Box), 'compare');
  Check(GetterEmpty(Box), 'empty');
  Check(GetterElement(Box, 3) = 11, 'element');
  Check(GetterLoop(Box) = 26, 'loop');
  Check(ListFind(List, 'key') = 2, 'list find');
  Check(ListLengths(List) = 8, 'list lengths');
  Check(ListFirstChars(List) = Ord('a') + Ord('k'), 'list first chars');
  Check(NestedEmpty(Box), 'nested empty');
  Check(NestedLength(Box) = 3, 'nested length');
  Check(NestedSum(Box) = 26, 'nested sum');
  Check(ChainCompare(Boxes, 0, 'abc'), 'chain compare');
  Check(ChainLength(Box) = 3, 'chain length');
  Check(Shelf.FieldListFind('key') = 2, 'field list find');
  Check(Shelf.FieldChainElement(0, 2) = 7, 'field chain element');
  KeepToCall(Box);
  Check(Sunk = 3, 'to call');
  KeepChainToCall(Boxes, 0);
  Check(Sunk = 6, 'chain to call');
  Check(KeepIndexCall(Box) = 'b', 'index call');
  Check(RecordField(Quotes, 0) = 2.5, 'record field');
  Check(RecordCompare(Quotes, 0, 'quote'), 'record compare');
  Check(RecordElement(Quotes, 0, 2) = 8, 'record element');
  KeepRecordToCall(Quotes, 0);
  Check(Sunk = 11, 'record to call');
  Quotes.Free;
  Shelf.Free;
  Boxes.Free;
  List.Free;
  Box.Free;
  WriteLn('GETTER_BORROW_PASS');
end.
