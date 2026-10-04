program block_locals;
{ A local declared inside a block of a routine - for var I, var X := ... - is a local of that routine and lives
  in a register where a local declared in front of the body does (compiler/symsym.pas, setregable).

  The Check calls are the semantic matrix: counters and sums declared where they are used, in nested blocks, in
  the body of a loop, in the branches of a case, with the same name in two blocks; a value an anonymous function
  captures, a value whose address is taken, a value a handler or a cleanup reads, around the loop and inside it,
  a value assigned in a try block and read behind it; integer values of every width, floating point, Boolean,
  character, enumeration, set, pointer, record and string values; many locals at once; for-in over an array and
  a string; Exit, Break and Continue, Exit through a cleanup; methods, a nested routine, a generic routine, a
  routine the compiler puts into its caller and its actual by reference, recursion; the pointer of a with
  statement.
  The Shape routines are counted in the -O3 object by run_block_locals_gate.py.

  Delphi 12.2 compiles the file as well and is the oracle of the values. }
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
  {$MODESWITCH ANONYMOUSFUNCTIONS}
  {$MODESWITCH FUNCTIONREFERENCES}
  {$MODESWITCH INLINEVARS}
  {$ASMMODE INTEL}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$Q-}{$R-}

uses
  SysUtils;

type
  PIntArr = ^TIntArr;
  TIntArr = array[0..15] of Integer;
  TKind = (kNone, kLow, kMid, kHigh);
  TKinds = set of TKind;
  TIntFunc = reference to function(Value: Integer): Integer;
  TInts = array of Integer;

  TPoint2 = record
    X, Y: Integer;
  end;

  TTrade = record
    Time: Double;
    Price: Single;
    Qty: Single;
  end;
  TTradeArr = array of TTrade;

  TBook = class
  public
    Trades: TTradeArr;
    Count: Integer;
    Buy, Sell: Single;
    Vol: Double;
    function Sum(Limit: Double): Double;
    function Levels(Step: Integer): Int64;
  end;

  TBox<T> = class
  public
    Items: array of T;
    function CountIf(const Wanted: T): Integer;
  end;

var
  Failures: Integer;
  Seen: Int64;
  Ints: TIntArr;
  Total: Int64;
  TotalD: Double;

{$IFDEF FPC}
{ every register a called routine may change, of the target's ABI }
procedure Clobber; assembler; nostackframe;
asm
  mov rax, $5A5A5A5A5A5A5A5A
  mov rcx, rax
  mov rdx, rax
  mov r8, rax
  mov r9, rax
  mov r10, rax
  mov r11, rax
  movq xmm0, rax
  movq xmm1, rax
  movq xmm2, rax
  movq xmm3, rax
  movq xmm4, rax
  movq xmm5, rax
{$IFNDEF MSWINDOWS}
  mov rsi, rax
  mov rdi, rax
  movq xmm6, rax
  movq xmm7, rax
  movq xmm8, rax
  movq xmm9, rax
  movq xmm10, rax
  movq xmm11, rax
  movq xmm12, rax
  movq xmm13, rax
  movq xmm14, rax
  movq xmm15, rax
{$ENDIF}
end;
{$ELSE}
procedure Clobber;
begin
end;
{$ENDIF}

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

procedure Sink(V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  Inc(Seen, V);
end;

function GetOrRaise(P: PIntArr; I, Bad: Integer): Integer; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  if I = Bad then
    raise Exception.Create('bad');
  Result := P^[I];
end;

procedure Twice(var V: Integer); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  V := V * 2;
end;

function Apply(const F: TIntFunc; Value: Integer): Integer; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  Result := F(Value);
end;

{ ---- counters and sums declared where they are used ---- }

function SumWhereUsed(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Acc: Int64 := 0;
  for var I := 0 to N - 1 do
  begin
    var V := P^[I];
    Acc := Acc + V;
    Sink(V);
  end;
  Result := Acc;
end;

function NestedBlocks(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  if N > 0 then
  begin
    var Outer: Int64 := N * 3;
    begin
      var Inner := Outer * 2 + P^[1];
      Sink(Inner);
      begin
        var Deep := Inner - Outer;
        Sink(Deep);
        Result := Result + Deep * 100;
      end;
      Result := Result + Inner * 10;
    end;
    Result := Result + Outer;
  end;
end;

function SameNameTwice(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var I := 0 to N - 1 do
  begin
    var T := P^[I] * 2;
    Result := Result + T;
  end;
  Sink(Result);
  for var I := N - 1 downto 0 do
  begin
    var T: Int64 := Int64(P^[I]) * 1000;
    Result := Result + T + I;
  end;
end;

function FreshInLoop(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var I := 1 to N do
  begin
    var Fresh: Integer := 7;
    if Odd(I) then
      Fresh := Fresh + I;
    Sink(Fresh);
    Result := Result * 3 + Fresh;
  end;
end;

{ ---- the values somebody else reaches ---- }

function Captured(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Factor := N + 1;
  var Own: Int64 := 0;
  var F: TIntFunc := function(Value: Integer): Integer
    begin
      Result := Value * Factor;
    end;
  for var I := 0 to N - 1 do
  begin
    Own := Own + Apply(F, P^[I]);
    Factor := Factor + 1;
  end;
  Result := Own * 100 + Factor;
end;

function CapturedWritten(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Sum: Int64 := 0;
  var Own: Int64 := 5;
  var G: TIntFunc := function(Value: Integer): Integer
    begin
      Sum := Sum + Value;
      Result := Integer(Sum);
    end;
  for var I := 0 to N - 1 do
    Own := Own + Apply(G, P^[I]);
  Result := Sum * 100000 + Own;
end;

function AddressTaken(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var A := P^[1];
  var B := P^[2];
  Twice(A);
  var Q: PInteger := @B;
  Q^ := Q^ + N;
  Sink(A);
  Result := Int64(A) * 1000 + B;
end;

function InHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Before: Int64 := Int64(N) * 7 + 1;
  var Acc: Int64 := 0;
  try
    for var I := 0 to N - 1 do
    begin
      var V := GetOrRaise(P, I, Bad);
      Acc := Acc + V;
    end;
  except
    Acc := Acc + Before * 1000;
  end;
  Result := Acc * 10 + Before;
end;

function InCleanup(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Acc: Int64 := 0;
  var Mark: Int64 := Int64(N) * 3 + 1;
  try
    try
      for var I := 0 to N - 1 do
        Acc := Acc + GetOrRaise(P, I, Bad);
    finally
      var Last := Acc + Mark;
      Sink(Last);
    end;
  except
    Acc := -Acc;
  end;
  Result := Acc * 100 + Mark;
end;

function DeclaredInHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  try
    for var I := 0 to N - 1 do
      Result := Result + GetOrRaise(P, I, Bad);
  except
    var Fix: Int64 := Result * 2 + 9;
    Sink(Fix);
    Result := Fix;
  end;
end;

{ ---- the kinds of values ---- }

function Doubles(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Acc: Double := 0;
  var Scale: Single := 0.5;
  for var I := 1 to N do
  begin
    var Term: Double := I * 1.25;
    Acc := Acc + Term * Scale;
    Sink(I);
  end;
  Result := Trunc(Acc * 1000);
end;

function Booleans(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Any := False;
  var All := True;
  var Count := 0;
  for var I := 0 to N - 1 do
  begin
    var Hit := (P^[I] mod 3) = 1;
    Any := Any or Hit;
    All := All and Hit;
    if Hit then
      Inc(Count);
  end;
  Result := Ord(Any) * 100 + Ord(All) * 10 + Count;
end;

function Pointers(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Cur: PInteger := @P^[0];
  var Stop: PInteger := @P^[N];
  var Acc: Int64 := 0;
  while Cur <> Stop do
  begin
    var Next := Cur;
    Inc(Next);
    Acc := Acc * 2 + Cur^;
    Cur := Next;
  end;
  Result := Acc;
end;

function Records(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Pt: TPoint2;
  Pt.X := N;
  Pt.Y := N * 2;
  for var I := 1 to N do
  begin
    var Step: TPoint2;
    Step.X := I;
    Step.Y := -I;
    Pt.X := Pt.X + Step.X;
    Pt.Y := Pt.Y + Step.Y * 3;
  end;
  Result := Int64(Pt.X) * 1000 + Pt.Y;
end;

function Strings(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var S: string := '';
  for var I := 1 to N do
  begin
    var Part := IntToStr(I * 11);
    S := S + Part;
  end;
  var Len := Length(S);
  Result := Int64(Len) * 1000 + Ord(S[Len]);
end;

{ ---- for-in ---- }

function ForInArray(const A: TInts): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var V in A do
  begin
    var Sq := V * V;
    Result := Result + Sq;
  end;
end;

function ForInString(const S: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var C in S do
  begin
    var Code := Ord(C);
    if Code > 64 then
      Result := Result * 2 + Code;
  end;
end;

{ ---- Exit, Break, Continue ---- }

function Leaves(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var Acc: Int64 := 0;
  for var I := 0 to N - 1 do
  begin
    var V := P^[I];
    if V = Stop then
      Exit(Acc * 10 + I);
    if Odd(V) then
      Continue;
    if V > 40 then
      Break;
    Acc := Acc + V;
  end;
  Result := -Acc;
end;

{ ---- methods, a generic routine, a routine put into its caller, recursion ---- }

function TBook.Sum(Limit: Double): Double;
begin
  var bvol: Single := Buy;
  var svol: Single := Sell;
  var tVol: Double := 0;
  for var m := Count - 1 downto 0 do
    with Trades[m] do
    begin
      var BQuantity: Double := Price * Abs(Qty);
      if Qty < 0 then
        svol := svol + Price * Abs(Qty)
      else
        bvol := bvol + Price * Abs(Qty);
      if Time > Limit then
        tVol := tVol + BQuantity;
    end;
  Buy := bvol;
  Sell := svol;
  Vol := tVol;
  Result := Vol + Buy - Sell;
end;

function TBook.Levels(Step: Integer): Int64;
begin
  Result := 0;
  for var s := 0 to Step - 1 do
  begin
    var First := True;
    var Low: Single := 0;
    for var k := s to Count - 1 do
    begin
      var P := Trades[k].Price;
      if First or (P < Low) then
        Low := P;
      First := False;
    end;
    Result := Result * 100 + Round(Low * 4);
  end;
end;

function TBox<T>.CountIf(const Wanted: T): Integer;
begin
  Result := 0;
  for var I := 0 to High(Items) do
  begin
    var Same := CompareMem(@Items[I], @Wanted, SizeOf(T));
    if Same then
      Inc(Result);
  end;
end;

function Clamp(V, Lo, Hi: Integer): Integer; inline;
begin
  var R := V;
  if R < Lo then
    R := Lo;
  if R > Hi then
    R := Hi;
  Result := R;
end;

function Clamped(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var I := 0 to N - 1 do
  begin
    var C := Clamp(P^[I], 5, 20);
    Result := Result * 3 + C;
  end;
end;

function Depth(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  if N <= 0 then
    Exit(1);
  var Mine: Int64 := N * 5;
  var Below := Depth(N - 1);
  Sink(Mine);
  Result := Below * 2 + Mine;
end;

procedure Bump(var V: Int64; By: Integer); inline;
begin
  V := V * 2 + By;
end;

{ ---- more places: a handler inside the loop, a try around the loop, case and repeat, a nested routine, many
  locals at once, the widths, an actual by reference, Exit through a cleanup ---- }

function CounterInHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var I := 0 to N - 1 do
  begin
    var Got: Int64 := -1;
    try
      Got := GetOrRaise(P, I, Bad);
      Result := Result + Got;
    except
      Result := Result + I * 1000 + Got;
    end;
  end;
end;

function AssignedInTry(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := -5;
  if N > 0 then
  begin
    var X: Int64 := 1;
    var Y: Double := 0.5;
    try
      for var I := 0 to N - 1 do
      begin
        X := X + GetOrRaise(P, I, Bad);
        Y := Y + I * 0.25;
      end;
    except
    end;
    Result := X * 1000 + Trunc(Y * 100);
  end;
end;

function CaseBlocks(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  var I := 0;
  repeat
    case P^[I] mod 4 of
      0:
        begin
          var A := P^[I] * 3;
          Result := Result + A;
        end;
      1:
        begin
          var B: Int64 := Int64(P^[I]) shl 4;
          Sink(B);
          Result := Result xor B;
        end;
      else
        begin
          var C := I;
          if Odd(C) then
          begin
            Inc(I);
            Continue;
          end;
          Result := Result * 2 + C;
        end;
    end;
    Inc(I);
  until I >= N;
end;

function InNested(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Base: Int64;

  function Part(From, Till: Integer): Int64;
  begin
    Result := Base;
    for var K := From to Till do
    begin
      var V := P^[K];
      Result := Result + V * (K + 1);
      Sink(V);
    end;
  end;

begin
  Base := N;
  var First := Part(0, N div 2);
  Base := First;
  var Second := Part(N div 2 + 1, N - 1);
  Result := First * 100000 + Second;
end;

function Crowd(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var A0: Int64 := 1;
  var A1: Int64 := 2;
  var A2: Int64 := 3;
  var A3: Int64 := 4;
  var A4: Int64 := 5;
  var A5: Int64 := 6;
  var A6: Int64 := 7;
  var A7: Int64 := 8;
  var D0: Double := 0.5;
  var D1: Double := 1.5;
  var D2: Double := 2.5;
  var D3: Double := 3.5;
  for var I := 0 to N - 1 do
  begin
    var V := P^[I];
    A0 := A0 + V;
    A1 := A1 xor (A0 shl 1);
    A2 := A2 + A1 mod 7;
    A3 := A3 * 3 + V;
    A4 := A4 + A3 mod 11;
    A5 := A5 xor A4;
    A6 := A6 + A5 mod 13;
    A7 := A7 + A6 + I;
    D0 := D0 + V * 0.5;
    D1 := D1 + D0 * 0.25;
    D2 := D2 + D1 * 0.125;
    D3 := D3 + D2;
    Sink(V);
  end;
  Result := (A0 + A1 + A2 + A3 + A4 + A5 + A6 + A7) mod 1000000007 + Trunc(D3 * 16);
end;

function Widths(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  var B: Byte := 250;
  var W: Word := 65530;
  var S: ShortInt := 120;
  var U: UInt64 := $FFFFFFFFFFFFFFF0;
  var C: Char := 'a';
  var K: TKind := kLow;
  var Ks: TKinds := [];
  for var I := 0 to N - 1 do
  begin
    B := B + Byte(P^[I]);
    W := W + Word(P^[I]);
    S := S + ShortInt(I);
    U := U + UInt64(P^[I]);
    C := Chr(Ord(C) + (I and 1));
    if K = High(TKind) then
      K := Low(TKind)
    else
      K := Succ(K);
    Include(Ks, K);
    Sink(B);
  end;
  Result := Int64(B) + Int64(W) * 1000 + Int64(S) * 100000000 + Int64(U and $FFFF) * 7 + Ord(C) * 3 + Ord(K) +
    Byte(Ks) * 1000000;
end;

function ByReference(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := 0;
  for var I := 0 to N - 1 do
  begin
    var Acc: Int64 := I;
    Bump(Acc, P^[I]);
    Bump(Acc, 3);
    Result := Result + Acc;
  end;
end;

function ExitThroughCleanup(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Result := -1;
  var Steps := 0;
  try
    for var I := 0 to N - 1 do
    begin
      var V := P^[I];
      Inc(Steps);
      if V = Stop then
        Exit(V * 100 + Steps);
    end;
    Result := Steps;
  finally
    Sink(Steps);
  end;
end;

{ ---- shapes: the loops of these routines are counted in the object ---- }

function ShapeBlockLoop(const A: array of Int64): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  if Length(A) > 0 then
  begin
    var Acc: Int64 := 0;
    var Odds: Int64 := 0;
    for var I := 0 to High(A) do
    begin
      Acc := Acc + A[I];
      Odds := Odds + (A[I] and 1);
    end;
    Total := Acc * 2 + Odds;
  end;
  Result := Total;
end;

function ShapeTopLoop(const A: array of Int64): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Odds: Int64;
begin
  if Length(A) > 0 then
  begin
    Acc := 0;
    Odds := 0;
    for I := 0 to High(A) do
    begin
      Acc := Acc + A[I];
      Odds := Odds + (A[I] and 1);
    end;
    Total := Acc * 2 + Odds;
  end;
  Result := Total;
end;

function ShapeBlockDouble(const A: array of Double; Scale: Double): Double; {$IFDEF FPC} noinline; {$ENDIF}
begin
  if Length(A) > 0 then
  begin
    var Acc: Double := 0;
    for var I := 0 to High(A) do
    begin
      var Term := A[I] * Scale;
      Acc := Acc + Term;
    end;
    TotalD := Acc;
  end;
  Result := TotalD;
end;

function ShapeTopDouble(const A: array of Double; Scale: Double): Double; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Term: Double;
begin
  if Length(A) > 0 then
  begin
    Acc := 0;
    for I := 0 to High(A) do
    begin
      Term := A[I] * Scale;
      Acc := Acc + Term;
    end;
    TotalD := Acc;
  end;
  Result := TotalD;
end;

var
  I: Integer;
  Book: TBook;
  Box: TBox<Integer>;
  Wide: array[0..15] of Int64;
  Reals: array[0..15] of Double;
  Dyn: TInts;
begin
  for I := 0 to 15 do
  begin
    Ints[I] := I * 3 + 1;
    Wide[I] := I * 5 + 3;
    Reals[I] := I + 0.5;
  end;
  SetLength(Dyn, 6);
  for I := 0 to 5 do
    Dyn[I] := I * 2 + 1;

  Check('sum-where-used', SumWhereUsed(@Ints, 8), 92);
  Check('sum-where-used seen', Seen, 92);
  Check('nested-blocks', NestedBlocks(@Ints, 8), 3344);
  Check('same-name-twice', SameNameTwice(@Ints, 8), 92212);
  Check('fresh-in-loop', FreshInLoop(6), 2887);
  Check('captured', Captured(@Ints, 8), 127617);
  Check('captured-written', CapturedWritten(@Ints, 8), 9200293);
  Check('address-taken', AddressTaken(@Ints, 8), 8015);
  Check('in-handler/none', InHandler(@Ints, 8, -1), 977);
  Check('in-handler/at5', InHandler(@Ints, 8, 5), 570407);
  Seen := 0;
  Check('in-cleanup/none', InCleanup(@Ints, 8, -1), 9225);
  Check('in-cleanup/none seen', Seen, 117);
  Check('in-cleanup/at5', InCleanup(@Ints, 8, 5), -3475);
  Check('in-cleanup/at5 seen', Seen, 177);
  Check('declared-in-handler/none', DeclaredInHandler(@Ints, 8, -1), 92);
  Check('declared-in-handler/at5', DeclaredInHandler(@Ints, 8, 5), 79);
  Check('doubles', Doubles(9), 28125);
  Check('booleans', Booleans(@Ints, 8), 118);
  Check('pointers', Pointers(@Ints, 8), 996);
  Check('records', Records(7), 34930);
  Check('strings', Strings(12), 27050);
  Check('for-in-array', ForInArray(Dyn), 286);
  Check('for-in-string', ForInString('aBc 12 Zz'), 2778);
  Check('leaves/found', Leaves(@Ints, 12, 22), 307);
  Check('leaves/break', Leaves(@Ints, 16, -1), -154);
  Check('leaves/end', Leaves(@Ints, 8, -1), -52);

  Book := TBook.Create;
  SetLength(Book.Trades, 8);
  Book.Count := 8;
  for I := 0 to 7 do
  begin
    Book.Trades[I].Time := I;
    Book.Trades[I].Price := 64 + I / 64;
    if Odd(I) then
      Book.Trades[I].Qty := -(I + 1) / 16
    else
      Book.Trades[I].Qty := (I + 1) / 16;
  end;
  Check('book-sum', Trunc(Book.Sum(3.5) * 4096), 360912);
  Check('book-levels', Book.Levels(3), 2585856);
  Book.Free;

  Box := TBox<Integer>.Create;
  SetLength(Box.Items, 7);
  for I := 0 to 6 do
    Box.Items[I] := I mod 3;
  Check('generic', Box.CountIf(1), 2);
  Box.Free;

  Check('clamped', Clamped(@Ints, 8), 17663);
  Seen := 0;
  Check('depth', Depth(5), 317);
  Check('depth seen', Seen, 75);

  Check('counter-in-handler/none', CounterInHandler(@Ints, 8, -1), 92);
  Check('counter-in-handler/at5', CounterInHandler(@Ints, 8, 5), 5075);
  Check('assigned-in-try/none', AssignedInTry(@Ints, 8, -1), 93750);
  Check('assigned-in-try/at5', AssignedInTry(@Ints, 8, 5), 36300);
  Seen := 0;
  Check('case-blocks', CaseBlocks(@Ints, 12), 2054);
  Seen := 0;
  Check('in-nested', InNested(@Ints, 8), 14300548);
  Check('in-nested seen', Seen, 92);
  Seen := 0;
  Check('crowd', Crowd(@Ints, 12), 2794659);
  Check('crowd seen', Seen, 210);
  Seen := 0;
  Check('widths', Widths(@Ints, 9), -9984887877);
  Check('by-reference', ByReference(@Ints, 8), 320);
  Seen := 0;
  Check('exit-through-cleanup/found', ExitThroughCleanup(@Ints, 8, 10), 1004);
  Check('exit-through-cleanup/found seen', Seen, 4);
  Seen := 0;
  Check('exit-through-cleanup/none', ExitThroughCleanup(@Ints, 8, -1), 8);
  Check('exit-through-cleanup/none seen', Seen, 8);

  Check('shape/block', ShapeBlockLoop(Wide), 1304);
  Check('shape/top', ShapeTopLoop(Wide), 1304);
  Check('shape/block-double', Trunc(ShapeBlockDouble(Reals, 0.5) * 100), 6400);
  Check('shape/top-double', Trunc(ShapeTopDouble(Reals, 0.5) * 100), 6400);

  if Failures = 0 then
    WriteLn('BLOCK_LOCALS_PASS')
  else
  begin
    WriteLn('BLOCK_LOCALS_FAIL ', Failures);
    Halt(1);
  end;
end.
