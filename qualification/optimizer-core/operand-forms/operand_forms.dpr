program operand_forms;

{ The shapes of the operand-forms gate: statements whose code is counted in
  the -O3 object, each with the values it has to give.  See README.md. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TPoint = record
    X, Y: LongInt;
  end;

  TEvent = record
    What: Word;
    Where: TPoint;
  end;

  TStream = record
    NextIn: PByte;
    AvailIn: Cardinal;
    TotalIn: QWord;
  end;

  PInner = ^TInner;
  TInner = record
    Pad: Int64;
    B32: LongInt;
    B64: Int64;
  end;

  POuter = ^TOuter;
  TOuter = record
    Pad: array[0..2] of Int64;
    Inner: PInner;
  end;

  PPlain = ^TPlain;
  TPlain = record
    B32: LongInt;
    B64: Int64;
  end;

  { 40 bytes: 5 * 8 }
  TMark = record
    I: Cardinal;
    Cp: PAnsiChar;
    Pp: Pointer;
    Level: Byte;
    Cl: Cardinal;
    Removed: Cardinal;
  end;

  TState = record
    Pad: array[0..70] of Int64;
    A, B: Int64;
    C: LongInt;
  end;

  TPair = record
    A, B: Int64;
  end;
  PTPair = ^TPair;

  PNode = ^TNode;
  TNode = record
    Next: PNode;
    Value: Int64;
    Other: Int64;
  end;

  PHeader = ^THeader;
  THeader = record
    Ofs: Integer;
    SizeFlags: Cardinal;
    Kind: Cardinal;
  end;

  TServer = class
    Timeout: Cardinal;
  end;

  TTrade = record
    Time: Double;
    Price: Single;
    Qty: Single;
  end;

  TWide = record
    A, B, C: Int64;
  end;

  TBook = class
    Items: array of TTrade;
    Other: array of TTrade;
    Count: Integer;
    Wide: array of TWide;
    Cells: array of Int64;
    function ShapeLoopMaxPrice(Limit: Double): Double;
    function ShapeLoopBuySell(N: Integer): Double;
    function ShapeLoopSumWide: Int64;
    function ShapeLoopSumCells: Int64;
    procedure TakeOther;
    function ShapeLoopCallInside(Limit: Integer): Double;
    function ShapeLoopSwapInside(Limit: Integer): Double;
    function ShapeLoopBumpCells(K: Int64): Int64;
    function ShapeLoopClearItems(Limit: Double): Integer;
  end;

  TView = class
    Origin: TPoint;
    Marks: array[0..24] of TMark;
    Top: Integer;
    fServer: TServer;
    fKeep: Boolean;
    fItems: array of Int64;
    fIndex: Integer;
    fTotal: Int64;
    function Track(const AEvent: TEvent): Int64;
    function ShapeIndexField: Int64;
    function ShapeIndexFields: Int64;
    procedure ShapeDecide(Old: Boolean);
    procedure ShapeStepItem(Index: Integer);
    procedure ShapeStepTotal;
    procedure ShapeStepAtIndex;
  end;

const
  HeaderSize = SizeOf(THeader);

var
  Fails: Integer = 0;
  State: TState;
  Cell: Int64;
  G: TPair;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

{ --- a subtraction whose operands lie in memory, the subtrahend behind more
      pointers than the minuend }

function TView.Track(const AEvent: TEvent): Int64;
var
  E: TEvent;
  Mouse: TPoint;

  procedure ShapeSubNested;
  begin
    Mouse.X := E.Where.X - Origin.X;
    Mouse.Y := E.Where.Y - Origin.Y;
  end;

begin
  E := AEvent;
  ShapeSubNested;
  Result := Int64(Mouse.X) * 1000 + Mouse.Y;
end;

function Blocks(var Z: TStream; Step: Integer): Int64; noinline;
var
  P: PByte;

  procedure ShapeSubReference;
  begin
    Inc(Z.TotalIn, PtrUInt(P) - PtrUInt(Z.NextIn));
    Z.NextIn := P;
  end;

begin
  P := Z.NextIn;
  Inc(P, Step);
  ShapeSubReference;
  Result := Z.TotalIn;
end;

function ShapeSubPointers(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := A^.B64 - B^.Inner^.B64;
end;

function ShapeSubPointers32(A: PPlain; B: POuter): LongInt; noinline;
begin
  Result := A^.B32 - B^.Inner^.B32;
end;

procedure ShapeSubStored(A: PPlain; B: POuter); noinline;
begin
  A^.B64 := A^.B64 - B^.Inner^.B64;
end;

{ --- the element of an array of records of 40 bytes, the index read from
      memory }

function TView.ShapeIndexField: Int64; noinline;
begin
  Result := Marks[Top].Removed;
end;

function TView.ShapeIndexFields: Int64; noinline;
var
  I, Cl: Cardinal;
  Cp: PAnsiChar;
begin
  I := Marks[Top].I;
  Cp := Marks[Top].Cp;
  Cl := Marks[Top].Cl;
  Result := Int64(I) * 1000 + Cl + Ord(Cp^);
end;

function Walk(Base: PAnsiChar; Seed: Cardinal): Int64; noinline;
var
  History: array[0..24] of TMark;
  Top: Integer;
  I, Cl, Removed: Cardinal;
  Cp, Ps: PAnsiChar;
  Pp: Pointer;
  Level: Byte;

  procedure ShapeIndexNested;
  begin
    I := History[Top].I;
    Cp := History[Top].Cp;
    Cl := History[Top].Cl;
    Pp := History[Top].Pp;
    Level := History[Top].Level;
    Removed := History[Top].Removed;
    Ps := Base + (I - 1);
    Dec(Top);
  end;

  procedure Push;
  begin
    Inc(Top);
    History[Top].I := I;
    History[Top].Cp := Cp;
    History[Top].Cl := Cl;
    History[Top].Pp := Pp;
    History[Top].Level := Level;
    History[Top].Removed := Removed;
  end;

var
  K: Integer;
begin
  Top := -1;
  I := Seed;
  Cl := 2;
  Cp := Base;
  Pp := @History;
  Level := 1;
  Removed := 0;
  for K := 1 to 5 do
    begin
      Push;
      Inc(I, 3);
      Inc(Cl);
      Inc(Cp);
      Inc(Level);
      Inc(Removed, 2);
    end;
  ShapeIndexNested;
  ShapeIndexNested;
  Result := Int64(I) * 1000000 + Cl * 10000 + Level * 100 + Removed + (Ps - Base) + (Cp - Base) + Top;
  if Pp <> @History then
    Result := -1;
end;

{ --- the address of a variable of the unit }

procedure ShapeCopyField; noinline;
begin
  State.A := State.B;
end;

procedure ShapeStepField; noinline;
begin
  State.A := State.A + State.B;
end;

procedure ShapeSumFields; noinline;
begin
  State.A := State.B + State.C;
end;

function ShapeOtherName: Int64; noinline;
var
  X, Y: Int64;
begin
  X := Cell;
  G.B := G.B + 5;
  Y := X * 1000;
  Result := Y + G.B;
end;

{ --- an address which is a pointer and a constant }

procedure ShapeHeaderFlag(Fp: PByte; Size: Cardinal); noinline;
var
  Nx: PByte;
begin
  Nx := Fp + Size;
  PHeader(Nx - HeaderSize)^.SizeFlags := PHeader(Nx - HeaderSize)^.SizeFlags or 2;
end;

procedure ShapeStepBack(P: PByte); noinline;
begin
  Dec(P, HeaderSize);
  PHeader(P)^.Kind := 77;
end;

function ShapeLoopSkipNames(PS: PByte): NativeInt; noinline;
begin
  { names with their lengths in front, one behind the other; the last one has
    the length 0 }
  Result := -1;
  while PS^ <> 0 do
    begin
      PS := PS + PS^ + 1;
      Inc(Result);
    end;
end;

function ShapeStepBackRead(P: PByte): Cardinal; noinline;
begin
  Dec(P, HeaderSize);
  Result := PHeader(P)^.Kind;
end;

{ --- a loop of a method over an array which is a field of its object }

function TBook.ShapeLoopMaxPrice(Limit: Double): Double; noinline;
var
  K: Integer;
begin
  Result := 0;
  for K := Count - 1 downto 0 do
    begin
      if Items[K].Time < Limit then
        Break;
      if Items[K].Price > Result then
        Result := Items[K].Price;
    end;
end;

function TBook.ShapeLoopBuySell(N: Integer): Double; noinline;
var
  M: Integer;
  Bv, Sv: Double;
begin
  Bv := 0;
  Sv := 0;
  for M := Count - 1 downto 0 do
    with Items[M] do
      begin
        if Time < N then
          Break;
        if Qty < 0 then
          Sv := Sv + Price * Abs(Qty)
        else
          Bv := Bv + Price * Qty;
      end;
  Result := Bv * 1000 + Sv;
end;

function TBook.ShapeLoopSumWide: Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Wide) do
    Result := Result + Wide[I].A + Wide[I].C * 3;
end;

function TBook.ShapeLoopSumCells: Int64; noinline;
var
  I: NativeInt;
begin
  { an element of 8 bytes at a counter as wide as an address, read in one
    place: the address is the operand, a pointer of its own has nothing to
    take off the iteration }
  Result := 0;
  for I := 0 to High(Cells) do
    Result := Result + Cells[I];
end;

procedure TBook.TakeOther; noinline;
begin
  Items := Other;
end;

function TBook.ShapeLoopCallInside(Limit: Integer): Double; noinline;
var
  I: Integer;
begin
  { a called method gives the field another array }
  Result := 0;
  for I := 0 to Count - 1 do
    begin
      Result := Result + Items[I].Price;
      if I = Limit then
        TakeOther;
    end;
end;

function TBook.ShapeLoopSwapInside(Limit: Integer): Double; noinline;
var
  I: Integer;
begin
  { the body gives the field another array }
  Result := 0;
  for I := 0 to Count - 1 do
    begin
      Result := Result + Items[I].Price;
      if I = Limit then
        Items := Other;
    end;
end;

function TBook.ShapeLoopBumpCells(K: Int64): Int64; noinline;
var
  I: Integer;
begin
  { the element is read and written in one statement: one pointer serves
    both, and the statement stays one instruction }
  for I := 0 to Count - 1 do
    Cells[I] := Cells[I] + K;
  Result := Cells[0];
end;

function TBook.ShapeLoopClearItems(Limit: Double): Integer; noinline;
var
  I: Integer;
begin
  { the element is read in the condition and written under it: the write
    joins the pointer of the read }
  Result := 0;
  for I := Count - 1 downto 0 do
    if Items[I].Time < Limit then
      begin
        Items[I].Time := 0;
        Inc(Result);
      end;
end;

{ --- the target and the value of an assignment have a part in common }

procedure TView.ShapeDecide(Old: Boolean); noinline;
begin
  fKeep := ((fServer = nil) or (fServer.Timeout > 0)) and not Old;
end;

procedure TView.ShapeStepItem(Index: Integer); noinline;
begin
  fItems[Index] := fItems[Index] * 3 + fItems[Index + 1];
end;

procedure TView.ShapeStepTotal; noinline;
begin
  fTotal := fTotal + fItems[fIndex] + Top;
end;

procedure TView.ShapeStepAtIndex; noinline;
begin
  fItems[fIndex] := fItems[fIndex] + fIndex;
end;

procedure ShapeStepNode(P: PNode); noinline;
begin
  P^.Next^.Value := P^.Next^.Value * 2 + P^.Next^.Other;
end;

procedure ShapeTwoNames(A, B: PTPair); noinline;
begin
  A^.B := B^.B + 5;
  B^.A := A^.B * 2;
end;

var
  Book: TBook;
  V: TView;
  Ev: TEvent;
  Z: TStream;
  Data: array[0..63] of Byte;
  Plain: TPlain;
  Inner: TInner;
  Outer: TOuter;
  Text: array[0..31] of AnsiChar = 'abcdefghijklmnopqrstuvwxyz01234';
  N1, N2: TNode;
  Pair: TPair;
  K: Integer;
begin
  V := TView.Create;
  V.Origin.X := 10;
  V.Origin.Y := 27;
  Ev.What := 1;
  Ev.Where.X := 17;
  Ev.Where.Y := 4;
  Check(V.Track(Ev), 6977, 'fields of the record around and of the object');
  Z.NextIn := @Data[8];
  Z.AvailIn := 0;
  Z.TotalIn := 100;
  Check(Blocks(Z, 5), 105, 'pointers of a parameter passed by reference');
  Check(Blocks(Z, -3), 102, 'pointers of a parameter passed by reference, back');
  Outer.Inner := @Inner;
  Plain.B32 := -2000000000;
  Inner.B32 := 2000000000;
  Plain.B64 := -9000000000000000000;
  Inner.B64 := 5;
  Check(ShapeSubPointers(@Plain, @Outer), -9000000000000000005, 'a subtrahend behind two pointers');
  Check(ShapeSubPointers32(@Plain, @Outer), 294967296, 'a subtrahend of 32 bits behind two pointers');
  ShapeSubStored(@Plain, @Outer);
  Check(Plain.B64, -9000000000000000005, 'the difference is stored into the minuend');

  for K := 0 to 24 do
    begin
      V.Marks[K].I := 100 + K;
      V.Marks[K].Cp := @Text[K];
      V.Marks[K].Cl := 200 + K;
      V.Marks[K].Removed := 4000000000 + Cardinal(K);
    end;
  V.Top := 7;
  Check(V.ShapeIndexField, 4000000007, 'a field of the element at an index which is a field');
  Check(V.ShapeIndexFields, 107 * 1000 + 207 + Ord('h'), 'three fields of the element at an index which is a field');
  Check(Walk(@Text[0], 4), 13050423, 'fields of an element in a nested routine');

  State.B := 7;
  ShapeCopyField;
  Check(State.A, 7, 'a field is copied into a field');
  ShapeStepField;
  Check(State.A, 14, 'a field is counted from itself and a field');
  State.C := -100;
  ShapeSumFields;
  Check(State.A, -93, 'a field is the sum of two fields');
  Cell := 7;
  G.A := 1;
  G.B := 2;
  Check(ShapeOtherName, 7007, 'a variable is read, another one is written');

  FillChar(Data, SizeOf(Data), 0);
  PHeader(@Data[20])^.SizeFlags := 5;
  ShapeHeaderFlag(@Data[0], 32);
  Check(PHeader(@Data[20])^.SizeFlags, 7, 'a flag in the header in front of the block');
  ShapeStepBack(@Data[32]);
  Check(PHeader(@Data[20])^.Kind, 77, 'the pointer goes back by the header');
  Check(ShapeStepBackRead(@Data[32]), 77, 'the pointer goes back by the header and is read');
  FillChar(Data, SizeOf(Data), 0);
  Data[0] := 3;
  Data[4] := 2;
  Data[7] := 5;
  Check(ShapeLoopSkipNames(@Data[0]), 2, 'names with their lengths in front');
  Check(ShapeLoopSkipNames(@Data[13]), -1, 'no name');

  V.fServer := TServer.Create;
  V.fServer.Timeout := 5;
  V.ShapeDecide(False);
  Check(Ord(V.fKeep), 1, 'a flag is counted from a field of a field');
  V.ShapeDecide(True);
  Check(Ord(V.fKeep), 0, 'a flag is counted from a parameter');
  SetLength(V.fItems, 8);
  for K := 0 to 7 do
    V.fItems[K] := K + 1;
  V.ShapeStepItem(2);
  Check(V.fItems[2], 13, 'an element is counted from itself and its neighbour');
  V.fIndex := 5;
  V.fTotal := 1000;
  V.ShapeStepTotal;
  Check(V.fTotal, 1000 + 6 + 7, 'a field is counted from itself and an element');
  V.ShapeStepAtIndex;
  Check(V.fItems[5], 11, 'an element at the index which is a field');
  N1.Next := @N2;
  N2.Next := @N1;
  N2.Value := 7;
  N2.Other := 3;
  ShapeStepNode(@N1);
  Check(N2.Value, 17, 'a field behind two pointers');
  Pair.A := 0;
  Pair.B := 1;
  ShapeTwoNames(@Pair, @Pair);
  Check(Pair.B * 100 + Pair.A, 612, 'two names of one record');

  Book := TBook.Create;
  Book.Count := 8;
  SetLength(Book.Items, 8);
  SetLength(Book.Other, 8);
  for K := 0 to 7 do
    begin
      Book.Items[K].Time := 100 + K;
      Book.Items[K].Price := 10 + K;
      Book.Items[K].Qty := K - 3;
      Book.Other[K].Time := 100 + K;
      Book.Other[K].Price := 1000 + K;
      Book.Other[K].Qty := 1;
    end;
  Check(Round(Book.ShapeLoopMaxPrice(103)), 17, 'the largest price of the last trades');
  Check(Round(Book.ShapeLoopMaxPrice(200)), 0, 'no trade is young enough');
  Check(Round(Book.ShapeLoopBuySell(102)), (14 * 1 + 15 * 2 + 16 * 3 + 17 * 4) * 1000 + 12 * 1, 'bought and sold');
  SetLength(Book.Wide, 5);
  for K := 0 to 4 do
    begin
      Book.Wide[K].A := K;
      Book.Wide[K].C := 10 * K;
    end;
  Check(Book.ShapeLoopSumWide, 10 + 3 * 100, 'two fields of an element of 24 bytes');
  SetLength(Book.Cells, 6);
  for K := 0 to 5 do
    Book.Cells[K] := 1000000000000 + K;
  Check(Book.ShapeLoopSumCells, 6000000000015, 'elements of 8 bytes');
  Check(Round(Book.ShapeLoopCallInside(2)), 10 + 11 + 12 + 1003 + 1004 + 1005 + 1006 + 1007,
    'a called method replaces the array');
  Book.Items := nil;
  SetLength(Book.Items, 8);
  for K := 0 to 7 do
    Book.Items[K].Price := 20 + K;
  Check(Round(Book.ShapeLoopSwapInside(5)), 20 + 21 + 22 + 23 + 24 + 25 + 1006 + 1007,
    'the body replaces the array');
  Book.Count := 6;
  Check(Book.ShapeLoopBumpCells(5), 1000000000005, 'an element is read and written in one statement');
  Check(Book.Cells[3], 1000000000008, 'the last element is written too');
  Book.Count := 8;
  SetLength(Book.Items, 8);
  for K := 0 to 7 do
    Book.Items[K].Time := 100 + K;
  Check(Book.ShapeLoopClearItems(104), 4, 'the elements read under a condition are written');
  Check(Round(Book.Items[3].Time * 10 + Book.Items[4].Time), 104, 'the element written and the one behind it');
  Book.Items := nil;
  Book.Count := 0;
  Check(Round(Book.ShapeLoopMaxPrice(0)), 0, 'an array which is empty');

  if Fails = 0 then
    WriteLn('OPERAND_FORMS_PASS')
  else
  begin
    WriteLn('OPERAND_FORMS_FAIL ', Fails);
    Halt(1);
  end;
end.
