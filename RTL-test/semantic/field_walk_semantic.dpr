program field_walk_semantic;
{ Loops of a method over an array which is a field of its object.  The pointer of the array may be read once in
  front of the loop only where the body and what it calls cannot replace the array: the values with the array
  replaced by an assignment, by SetLength, by a called method, through a second reference to the object and
  through a pointer to the field; with the object of the loop replaced; with the array written, empty, with an
  object which is nil and a loop which does not run, with the access behind a condition. }
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$Q-}{$R-}

uses
  SysUtils;

type
  TTrade = record
    Time: Double;
    Price: Single;
    Qty: Single;
  end;
  TTrades = array of TTrade;

  TWide = record
    A, B, C: Int64;
  end;

  TBook = class
  public
    Items: TTrades;
    Count: Integer;
    Other: TTrades;
    Wide: array of TWide;
    Fixed: array[0..15] of TWide;
    Total: Double;
    Seen: Integer;
    Cells: array of Int64;
    function MaxPrice(Limit: Double): Double;
    function MaxPriceUp(Limit: Double): Double;
    function BuySell(N: Integer): Double;
    function SumWide: Int64;
    function SumFixed: Int64;
    procedure Scale(K: Single);
    procedure FillFixed(K: Int64);
    function SwapInside(Limit: Integer): Double;
    function GrowInside: Integer;
    function IntoField: Double;
    function Conditional(Flag: Boolean): Double;
    function ShortCircuit(Limit: Integer): Double;
    function TwoArrays: Double;
    function WithContinue: Double;
    function Nested(Rows: Integer): Int64;
    procedure TakeOther;
    function CallInside(Limit: Integer): Double;
    function RawSwapInside(Limit: Integer): Double;
    function AliasInside(Alias: TBook; Limit: Integer): Double;
    function PointerInside(Field: Pointer; Limit: Integer): Double;
    function DivBeforeField(D, N: Integer): Double;
    function SumCells: Int64;
    function SumCellsNarrow: Int64;
    function SumCellsTwice(Limit: Int64): Int64;
    procedure ClearCells(First, Last: NativeInt);
  end;

var
  Failures: Integer;

procedure Check(const Name: string; Got, Want: Double); overload;
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got:0:4, ' <> ', Want:0:4);
    Inc(Failures);
  end;
end;

procedure CheckInt(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

{ the routine of the product: the last trades, from the end, until one is too old }
function TBook.MaxPrice(Limit: Double): Double;
var
  k: Integer;
begin
  Result := 0;
  for k := Count - 1 downto 0 do begin
    If Items[k].Time < Limit then
      Break;
    If Items[k].Price > Result then
      Result := Items[k].Price;
  end;
end;

function TBook.MaxPriceUp(Limit: Double): Double;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to Count - 1 do begin
    If Items[k].Time > Limit then
      Break;
    If Items[k].Price > Result then
      Result := Items[k].Price;
  end;
end;

function TBook.BuySell(N: Integer): Double;
var
  m: Integer;
  bv, sv: Double;
begin
  bv := 0;
  sv := 0;
  for m := Count - 1 downto 0 do
    with Items[m] do begin
      If Time < N then
        Break;
      If Qty < 0 then
        sv := sv + Price * Abs(Qty)
      else
        bv := bv + Price * Qty;
    end;
  Result := bv * 1000 + sv;
end;

function TBook.SumWide: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Wide) do
    Result := Result + Wide[i].A + Wide[i].C * 3;
end;

function TBook.SumFixed: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := Low(Fixed) to High(Fixed) do
    Result := Result + Fixed[i].B;
end;

{ the elements are written }
procedure TBook.Scale(K: Single);
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    Items[i].Price := Items[i].Price * K;
end;

procedure TBook.FillFixed(K: Int64);
var
  i: Integer;
begin
  for i := 0 to 15 do begin
    Fixed[i].A := K + i;
    Fixed[i].B := K * 2 + i;
    Fixed[i].C := 0;
  end;
end;

{ the body gives the field another array }
function TBook.SwapInside(Limit: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do begin
    Result := Result + Items[i].Price;
    If i = Limit then
      Items := Other;
  end;
end;

{ the body makes the array longer: the memory of the array moves }
function TBook.GrowInside: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to 7 do begin
    If Items[i].Price > 0 then
      Inc(Result);
    If i = 3 then
      SetLength(Items, Length(Items) + 4096);
  end;
end;

{ the sum goes into a field of the same object }
function TBook.IntoField: Double;
var
  i: Integer;
begin
  Total := 0;
  Seen := 0;
  for i := 0 to Count - 1 do begin
    Total := Total + Items[i].Price;
    Inc(Seen);
  end;
  Result := Total + Seen;
end;

{ the access stands behind a condition: an empty array is never read }
function TBook.Conditional(Flag: Boolean): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to 3 do
    If Flag then
      Result := Result + Items[i].Price
    else
      Result := Result + 1;
end;

function TBook.ShortCircuit(Limit: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to 7 do
    If (i < Limit) and (Items[i].Price > 0) then
      Result := Result + Items[i].Price;
end;

function TBook.TwoArrays: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do
    Result := Result + Items[i].Price * 2 + Other[i].Price;
end;

function TBook.WithContinue: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do begin
    If Items[i].Qty < 0 then
      Continue;
    Result := Result + Items[i].Price;
  end;
end;

function TBook.Nested(Rows: Integer): Int64;
var
  r, i: Integer;
begin
  Result := 0;
  for r := 1 to Rows do begin
    for i := 0 to High(Wide) do
      Result := Result + Wide[i].B * r;
    { the next pass walks another array }
    If r = 2 then
      SetLength(Wide, 3);
  end;
end;

procedure TBook.TakeOther; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Items := Other;
end;

{ a called method gives the field another array }
function TBook.CallInside(Limit: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do begin
    Result := Result + Items[i].Price;
    If i = Limit then
      TakeOther;
  end;
end;

{ the field gets another array as a pointer: no managed assignment }
function TBook.RawSwapInside(Limit: Integer): Double;
var
  i: Integer;
  Keep: Pointer;
begin
  Result := 0;
  Keep := Pointer(Items);
  for i := 0 to Count - 1 do begin
    Result := Result + Items[i].Price;
    If i = Limit then
      Pointer(Items) := Pointer(Other);
  end;
  Pointer(Items) := Keep;
end;

{ a second reference to the object of the loop writes the field }
function TBook.AliasInside(Alias: TBook; Limit: Integer): Double;
var
  i: Integer;
  Keep: Pointer;
begin
  Result := 0;
  Keep := Pointer(Items);
  for i := 0 to Count - 1 do begin
    Result := Result + Items[i].Price;
    If i = Limit then
      Pointer(Alias.Items) := Pointer(Alias.Other);
  end;
  Pointer(Items) := Keep;
end;

{ a pointer to the field writes it }
function TBook.PointerInside(Field: Pointer; Limit: Integer): Double;
var
  i: Integer;
  Keep: Pointer;
begin
  Result := 0;
  Keep := Pointer(Items);
  for i := 0 to Count - 1 do begin
    Result := Result + Items[i].Price;
    If i = Limit then
      PPointer(Field)^ := Pointer(Other);
  end;
  Pointer(Items) := Keep;
end;

{ elements of 8 bytes: the counter as wide as an address, one place }
function TBook.SumCells: Int64;
var
  i: NativeInt;
begin
  Result := 0;
  for i := 0 to High(Cells) do
    Result := Result + Cells[i];
end;

function TBook.DivBeforeField(D, N: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to N - 1 do
    Result := 10 div D + Items[i].Price;
end;

{ the counter narrower than an address }
function TBook.SumCellsNarrow: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Cells) do
    Result := Result + Cells[i];
end;

{ two places }
function TBook.SumCellsTwice(Limit: Int64): Int64;
var
  i: NativeInt;
begin
  Result := 0;
  for i := 0 to High(Cells) do begin
    If Cells[i] > Limit then
      Break;
    Result := Result + Cells[i];
  end;
end;

procedure TBook.ClearCells(First, Last: NativeInt);
var
  i: NativeInt;
begin
  for i := First to Last do
    Cells[i] := 0;
end;

{ the object of the loop is replaced in the body }
function SumOfTwo(First, Second: TBook; N, Limit: Integer): Double; {$IFDEF FPC} noinline; {$ENDIF}
var
  i: Integer;
  B: TBook;
begin
  Result := 0;
  B := First;
  for i := 0 to N - 1 do begin
    Result := Result + B.Items[i].Price;
    If i = Limit then
      B := Second;
  end;
end;

{ a routine which is no method: the object may be nil where the loop does not run }
function SumOf(B: TBook; N: Integer): Double; {$IFDEF FPC} noinline; {$ENDIF}
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + B.Items[i].Price;
end;

function SumIfThere(B: TBook; N: Integer): Double; {$IFDEF FPC} noinline; {$ENDIF}
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to N - 1 do
    If B <> nil then
      Result := Result + B.Items[i].Price
    else
      Result := Result + 1;
end;

var
  Book, Second: TBook;
  i: Integer;
  Raised: Boolean;
begin
  Book := TBook.Create;
  SetLength(Book.Items, 8);
  SetLength(Book.Other, 8);
  SetLength(Book.Wide, 5);
  Book.Count := 8;
  for i := 0 to 7 do begin
    Book.Items[i].Time := 100 + i;
    Book.Items[i].Price := 10 + i;
    If Odd(i) then
      Book.Items[i].Qty := -(i + 1)
    else
      Book.Items[i].Qty := i + 1;
    Book.Other[i].Time := 200 + i;
    Book.Other[i].Price := 1000 + i;
    Book.Other[i].Qty := 1;
  end;
  for i := 0 to 4 do begin
    Book.Wide[i].A := i + 1;
    Book.Wide[i].B := 10 * (i + 1);
    Book.Wide[i].C := 100 * (i + 1);
  end;

  Check('max price', Book.MaxPrice(104), 17);
  Check('max price, all', Book.MaxPrice(0), 17);
  Check('max price, none', Book.MaxPrice(1000), 0);
  Check('max price up', Book.MaxPriceUp(103), 13);
  Check('buy and sell', Book.BuySell(104), (14 * 5 + 16 * 7) * 1000 + (15 * 6 + 17 * 8));
  CheckInt('sum wide', Book.SumWide, 15 + 1500 * 3);
  Book.FillFixed(5);
  CheckInt('sum fixed', Book.SumFixed, 16 * 10 + 120);
  CheckInt('fixed, the first', Book.Fixed[0].A, 5);
  CheckInt('fixed, the last', Book.Fixed[15].A, 20);
  Book.Scale(2);
  Check('scaled', Book.Items[3].Price, 26);
  Book.Scale(0.5);
  Check('scaled back', Book.Items[3].Price, 13);
  Check('into a field', Book.IntoField, (10 + 17) * 4 + 8);
  Check('into a field, the field', Book.Total, 108);
  Check('two arrays', Book.TwoArrays, 108 * 2 + 8000 + 28);
  Check('with continue', Book.WithContinue, 10 + 12 + 14 + 16);
  CheckInt('nested', Book.Nested(3), 150 * 1 + 150 * 2 + 60 * 3);
  CheckInt('nested, the array', Length(Book.Wide), 3);
  Check('short circuit', Book.ShortCircuit(3), 10 + 11 + 12);
  Check('conditional', Book.Conditional(True), 10 + 11 + 12 + 13);

  { the array is replaced by what the body calls and through other names of the field }
  Check('call inside', Book.CallInside(2), 10 + 11 + 12 + 1003 + 1004 + 1005 + 1006 + 1007);
  Book.Items := nil;
  SetLength(Book.Items, 8);
  for i := 0 to 7 do begin
    Book.Items[i].Time := 100 + i;
    Book.Items[i].Price := 10 + i;
    If Odd(i) then
      Book.Items[i].Qty := -(i + 1)
    else
      Book.Items[i].Qty := i + 1;
  end;
  Check('raw swap inside', Book.RawSwapInside(2), 10 + 11 + 12 + 1003 + 1004 + 1005 + 1006 + 1007);
  Check('alias inside', Book.AliasInside(Book, 4), 10 + 11 + 12 + 13 + 14 + 1005 + 1006 + 1007);
  Check('pointer inside', Book.PointerInside(@Book.Items, 0), 10 + 1001 + 1002 + 1003 + 1004 + 1005 + 1006 + 1007);
  Check('after the swaps', Book.MaxPrice(0), 17);
  Second := TBook.Create;
  SetLength(Second.Items, 8);
  for i := 0 to 7 do
    Second.Items[i].Price := 500 + i;
  Check('object replaced', SumOfTwo(Book, Second, 8, 1), 10 + 11 + 502 + 503 + 504 + 505 + 506 + 507);
  Second.Free;
  SetLength(Book.Cells, 6);
  for i := 0 to 5 do
    Book.Cells[i] := (i + 1) * 100;
  CheckInt('cells', Book.SumCells, 2100);
  CheckInt('cells, narrow counter', Book.SumCellsNarrow, 2100);
  CheckInt('cells, two places', Book.SumCellsTwice(450), 1000);
  Book.ClearCells(2, 3);
  CheckInt('cells cleared', Book.SumCells, 100 + 200 + 500 + 600);
  Book.ClearCells(4, 3);
  CheckInt('cells, a loop which does not run', Book.SumCells, 100 + 200 + 500 + 600);

  { the array is replaced in the middle of the loop }
  Check('swap inside', Book.SwapInside(2), 10 + 11 + 12 + 1003 + 1004 + 1005 + 1006 + 1007);
  Book.Items := nil;
  SetLength(Book.Items, 8);
  for i := 0 to 7 do
    Book.Items[i].Price := 1;
  CheckInt('grow inside', Book.GrowInside, 8);
  CheckInt('grow inside, the length', Length(Book.Items), 8 + 4096);

  { an empty array behind a condition, an object which is nil and a loop which does not run }
  Book.Items := nil;
  Book.Count := 0;
  Check('conditional, empty', Book.Conditional(False), 4);
  Check('short circuit, empty', Book.ShortCircuit(0), 0);
  Check('max price, empty', Book.MaxPrice(0), 0);
  Check('no object, no loop', SumOf(nil, 0), 0);
  Check('no object behind a condition', SumIfThere(nil, 3), 3);
  Raised := False;
  try
    Check('no object', SumOf(nil, 2), 0);
  except
    on E: Exception do
      Raised := True;
  end;
  CheckInt('no object and a loop which runs raises', Ord(Raised), 1);
  Second := nil;
  Raised := False;
  try
    Second.DivBeforeField(0, 3);
  except
    on E: Exception do
      Raised := E is EDivByZero;
  end;
  CheckInt('division before field raises first', Ord(Raised), 1);
  Book.Free;
  if Failures = 0 then
    WriteLn('FIELD_WALK_PASS')
  else
  begin
    WriteLn('FIELD_WALK_FAIL ', Failures);
    Halt(1);
  end;
end.
