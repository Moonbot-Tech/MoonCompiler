program try_nested;
{ A routine with try and a nested routine - a nested procedure or an anonymous
  function - keeps in registers what its exception paths do not read, as a
  routine without a nested one does (compiler/psub.pas, generate_code).

  The Check calls are the semantic matrix.  What a nested routine reads or
  writes of its parent lives in the frame or in the capturer; everything else
  of the parent is a candidate for a register, and the matrix asks for its
  value where an exception path reads it: in the handler, in the finally
  block, behind a try..except after the exception, with the exception raised
  by the nested routine, by another callee and by the processor (a read
  through nil, a division by zero), with Exit, Break and Continue through
  the cleanup.  Every callee overwrites all volatile registers of the target.
  The Shape routines are counted in the -O3 object by run_try_nested_gate.py.

  Delphi 12.2 compiles the file as well and is the oracle of the values. }
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
  {$MODESWITCH ANONYMOUSFUNCTIONS}
  {$MODESWITCH FUNCTIONREFERENCES}
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
  PDblArr = ^TDblArr;
  TDblArr = array[0..15] of Double;
  TIntFunc = reference to function(Value: Integer): Integer;
  TCompare = reference to function(const Left, Right: Integer): Integer;

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
    Crash: Integer;
    { the shape of the gate: the handler calls a routine of the unit, as the
      crash codes of a trading program do, and reads nothing of the method }
    function Join(Limit: Double; Sort, Bad: Boolean): Double;
    function Locked(Bad: Integer): Int64;
  end;

var
  Cleanups: Integer;
  Seen: Int64;
  Failures: Integer;
  Ints: TIntArr;
  Dbls: TDblArr;
  CrashCode: Integer;
  Total: Int64;

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

procedure Leave; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  Inc(Cleanups);
end;

procedure SetCrash(Code: Integer); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  CrashCode := Code;
end;

function GetOrRaise(P: PIntArr; I, Bad: Integer): Integer; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  if I = Bad then
    raise Exception.Create('bad');
  Result := P^[I];
end;

function Apply(const F: TIntFunc; Value: Integer): Integer; {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  Result := F(Value);
end;

{ ---- the nested procedure raises; the handler and the code behind the try read the parent ---- }

function NestedRaises(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Before: Int64;
  Steps: Integer;

  procedure Step(K: Integer);
  begin
    Clobber;
    if K = Bad then
      raise Exception.Create('step');
    Inc(Steps);
  end;

begin
  Before := Int64(N) * 1000 + 7;
  Acc := 0;
  Steps := 0;
  try
    for I := 0 to N - 1 do
    begin
      Step(I);
      Acc := Acc + P^[I];
    end;
  except
    Acc := Acc + 1000000;
  end;
  Result := Acc * 100 + Steps + Before * 100000000;
end;

{ ---- the nested procedure writes a local of the parent, the parent keeps others to itself ---- }

function NestedWrites(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Shared, Own, Scale: Int64;

  procedure Add(V: Integer);
  begin
    Shared := Shared + V;
    Clobber;
  end;

begin
  Shared := 0;
  Own := 0;
  Scale := Int64(N) + 3;
  try
    for I := 0 to N - 1 do
    begin
      Add(GetOrRaise(P, I, Bad));
      Own := Own + I * Scale;
    end;
  except
    Own := Own + 5;
  end;
  Result := Shared * 1000000 + Own * 100 + Scale;
end;

{ ---- a read through nil with a nested routine around ---- }

function NestedFault(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Keep: Int64;
  Q: PIntArr;

  function Twice(V: Integer): Integer;
  begin
    Result := V * 2;
  end;

begin
  Keep := Twice(N) + 11;
  Acc := 0;
  try
    for I := 0 to N - 1 do
    begin
      if I = 3 then
        Q := nil
      else
        Q := P;
      Acc := Acc + Q^[I];
    end;
  except
    Acc := Acc * 10 + 1;
  end;
  Result := Acc * 1000 + Keep;
end;

function NestedDivFault(A, B, Zero: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;
  R: Integer;

  function Twice(V: Integer): Integer;
  begin
    Result := V * 2;
  end;

begin
  X := Int64(A) * 5 - B;
  Y := Twice(A) + B;
  try
    R := A div Zero;
  except
    R := -2;
  end;
  Result := X * 10000 + Y * 100 + R;
end;

{ ---- straight code: a value written twice in the try block, the exception between the writes ---- }

function StraightHandler(P: PIntArr; A, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;

  function Twice(V: Integer): Integer;
  begin
    Result := V * 2;
  end;

begin
  X := -1;
  Y := -2;
  try
    X := Twice(A) + 1;
    Y := GetOrRaise(P, 1, Bad);
    X := X * 100 + Y;
    Y := GetOrRaise(P, 2, Bad);
    X := X * 100 + Y;
  except
    X := X * 10 + 9;
  end;
  Result := X * 1000 + Y;
end;

function StraightBehind(P: PIntArr; A, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y, Z: Int64;

  function Twice(V: Integer): Integer;
  begin
    Result := V * 2;
  end;

begin
  X := -1;
  Y := -2;
  Z := Twice(A) + 5;
  try
    X := Z + 1;
    Y := GetOrRaise(P, 1, Bad);
    X := X * 100 + Y;
    Y := GetOrRaise(P, 2, Bad);
    X := X * 100 + Y;
  except
    SetCrash(7);
  end;
  Result := X * 1000 + Y * 10 + Z;
end;

function StraightFault(P: PIntArr; A: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;
  Q: PIntArr;

  function Twice(V: Integer): Integer;
  begin
    Result := V * 2;
  end;

begin
  Q := P;
  X := Twice(A);
  Y := 3;
  try
    X := X * 7 + Q^[1];
    if A > 100 then
      Q := nil;
    Y := Y + X;
    X := X + Q^[2];
    Y := Y * 2;
  except
    Y := Y + 1000000;
  end;
  Result := X * 10000000 + Y;
end;

function StraightAnonymous(P: PIntArr; A, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;
  Cmp: TCompare;
begin
  X := -1;
  Y := -2;
  try
    if A < 0 then
      Cmp := function(const Left, Right: Integer): Integer
        begin
          Result := Left - Right;
        end;
    X := Int64(A) * 3 + 1;
    Y := GetOrRaise(P, 1, Bad);
    X := X * 100 + Y;
    Y := GetOrRaise(P, 2, Bad);
    X := X * 100 + Y;
  except
    X := X * 10 + 9;
  end;
  Result := X * 1000 + Y;
end;

{ ---- try..finally: the cleanup reads the parent, a nested routine stands by ---- }

function NestedFinally(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Mark: Int64;

  procedure Note(V: Int64);
  begin
    Clobber;
    Inc(Seen, V);
  end;

begin
  Acc := 0;
  Mark := Int64(N) * 3 + 1;
  try
    try
      for I := 0 to N - 1 do
        Acc := Acc + GetOrRaise(P, I, Bad);
    finally
      Note(Acc + Mark);
      Leave;
    end;
  except
    Acc := -Acc;
  end;
  Result := Acc * 100 + Mark;
end;

function NestedExit(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc: Int64;

  function Wanted(V: Integer): Boolean;
  begin
    Clobber;
    Result := V = Stop;
  end;

begin
  Result := -1;
  Acc := 0;
  try
    for I := 0 to N - 1 do
    begin
      Acc := Acc + P^[I];
      if Wanted(P^[I]) then
        Exit(Acc * 10 + I);
    end;
  finally
    Leave;
  end;
  Result := Acc;
end;

function NestedBreakContinue(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Skipped: Int64;

  function Odd3(V: Integer): Boolean;
  begin
    Clobber;
    Result := (V mod 4) = 1;
  end;

begin
  Acc := 0;
  Skipped := 0;
  for I := 0 to N - 1 do
  begin
    try
      if Odd3(P^[I]) then
      begin
        Inc(Skipped);
        Continue;
      end;
      if I = N - 2 then
        Break;
      Acc := Acc + P^[I];
    finally
      Leave;
    end;
  end;
  Result := Acc * 100 + Skipped;
end;

{ ---- an anonymous function: captures nothing, captures a value, captures what the try writes ---- }

function AnonymousPlain(P: PIntArr; N, Bad: Integer; Sort: Boolean): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Base: Int64;
  Cmp: TCompare;
begin
  Base := Int64(N) * 17;
  Acc := 0;
  try
    if Sort then
      Cmp := function(const Left, Right: Integer): Integer
        begin
          Result := Left - Right;
        end;
    for I := 0 to N - 1 do
      Acc := Acc + GetOrRaise(P, I, Bad);
    if Sort then
      Acc := Acc + Cmp(7, 4);
  except
    SetCrash(142);
  end;
  Result := Acc * 1000 + Base;
end;

function AnonymousCaptures(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Own: Int64;
  Factor: Integer;
  F: TIntFunc;
begin
  Factor := N + 1;
  Own := 0;
  Acc := 0;
  F := function(Value: Integer): Integer
    begin
      Result := Value * Factor;
    end;
  try
    for I := 0 to N - 1 do
    begin
      Acc := Acc + Apply(F, GetOrRaise(P, I, Bad));
      Own := Own + I;
      Factor := Factor + 1;
    end;
  except
    Own := Own + 100;
  end;
  Result := Acc * 10000 + Own * 100 + Factor;
end;

function AnonymousWritten(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Total, Own: Int64;
  G: TIntFunc;
begin
  Total := 0;
  Own := 0;
  G := function(Value: Integer): Integer
    begin
      Total := Total + Value;
      Result := Integer(Total);
    end;
  try
    for I := 0 to N - 1 do
    begin
      Own := Own + Apply(G, GetOrRaise(P, I, Bad));
    end;
  except
    Own := -Own;
  end;
  Result := Total * 100000 + Own;
end;

{ ---- a nested routine with a try of its own reads the parent ---- }

function NestedOwnTry(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Limit: Integer;
  Acc: Int64;

  function Sum(From: Integer): Int64;
  var
    K: Integer;
    Part: Int64;
  begin
    Part := 0;
    try
      for K := From to Limit - 1 do
        Part := Part + GetOrRaise(P, K, Bad);
    except
      Part := Part + 1000 + Limit;
    end;
    Result := Part;
  end;

begin
  Limit := N;
  Acc := Sum(0);
  Limit := N - 2;
  Acc := Acc * 10000 + Sum(1);
  Result := Acc;
end;

function NestedTwoLevels(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Acc, Keep: Int64;
  I: Integer;

  procedure Outer(V: Integer);

    procedure Inner(W: Integer);
    begin
      Clobber;
      if W = Bad then
        raise Exception.Create('inner');
      Acc := Acc + W;
    end;

  begin
    Inner(V);
    Inner(V + 100);
  end;

begin
  Acc := 0;
  Keep := Int64(N) * 9 + 2;
  try
    for I := 0 to N - 1 do
      Outer(P^[I]);
  except
    Keep := Keep + 1;
  end;
  Result := Acc * 1000 + Keep;
end;

{ ---- floating point: what lives across the callees and the handler ---- }

function NestedDouble(P: PDblArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Scale, Keep: Double;

  procedure Probe(K: Integer);
  begin
    Clobber;
    if K = Bad then
      raise Exception.Create('probe');
  end;

begin
  Scale := N * 0.5;
  Keep := N + 0.25;
  Acc := 0;
  try
    for I := 0 to N - 1 do
    begin
      Probe(I);
      Acc := Acc + P^[I] * Scale;
    end;
  except
    Acc := Acc + 0.5;
  end;
  Result := Trunc(Acc * 100) * 1000 + Trunc(Keep * 4);
end;

{ ---- the function result of a routine with a nested one ---- }

function NestedResult(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;

  procedure Probe(K: Integer);
  begin
    Clobber;
    if K = Bad then
      raise Exception.Create('probe');
  end;

begin
  Result := 0;
  try
    for I := 0 to N - 1 do
    begin
      Probe(I);
      Result := Result + P^[I];
    end;
  except
    Result := Result + 500;
  end;
end;

{ ---- the handler reads a value whose last use on the straight path stands before the call that raises:
       its register is free for the next value there ---- }

procedure Sink(V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Clobber;
  Inc(Seen, V);
end;

function HandlerReadsEarlier(P: PIntArr; A, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  V, W, U, T: Int64;

  function Twice(K: Integer): Integer;
  begin
    Result := K * 2;
  end;

begin
  V := Int64(A) * 7 + Twice(A);
  T := Int64(A) * 11 + 5;
  U := 0;
  try
    Sink(V);
    Sink(T);
    W := Int64(A) * 3 + 2;
    U := GetOrRaise(P, 1, Bad) + W;
    Sink(U + W);
    W := W * 5 + GetOrRaise(P, 2, Bad);
    Sink(W);
    U := U + W;
  except
    U := V * 1000 + T;
  end;
  Result := U;
end;

function HandlerReadsEarlierAnonymous(P: PIntArr; A, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  V, W, U, T: Int64;
  Cmp: TCompare;
begin
  V := Int64(A) * 7 + 3;
  T := Int64(A) * 11 + 5;
  U := 0;
  try
    if A < 0 then
      Cmp := function(const Left, Right: Integer): Integer
        begin
          Result := Left - Right;
        end;
    Sink(V);
    Sink(T);
    W := Int64(A) * 3 + 2;
    U := GetOrRaise(P, 1, Bad) + W;
    Sink(U + W);
    W := W * 5 + GetOrRaise(P, 2, Bad);
    Sink(W);
    U := U + W;
  except
    U := V * 1000 + T;
  end;
  Result := U;
end;

{ ---- a cleanup inside a cleanup reads the parent; a nested routine stands by ---- }

function NestedCleanupInCleanup(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Mark, Deep: Int64;

  procedure Note(V: Int64);
  begin
    Clobber;
    Inc(Seen, V);
  end;

begin
  Acc := 0;
  Mark := Int64(N) * 3 + 1;
  Deep := Int64(N) * 7 + 2;
  for I := 1 to 3 do
    Deep := Deep + Mark * I;
  try
    try
      for I := 0 to N - 1 do
        Acc := Acc + GetOrRaise(P, I, Bad);
    finally
      try
        Leave;
      finally
        Note(Acc + Deep);
      end;
    end;
  except
    Acc := -Acc;
  end;
  Result := Acc * 1000 + Mark + Deep;
end;

{ ---- the cleanup and the handler call the nested routine ---- }

function NestedFromFinally(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Shared, Own: Int64;

  procedure Settle(V: Int64);
  begin
    Clobber;
    Shared := Shared * 10 + V;
  end;

begin
  Acc := 0;
  Shared := 1;
  Own := Int64(N) * 11 + 3;
  try
    try
      for I := 0 to N - 1 do
      begin
        Acc := Acc + GetOrRaise(P, I, Bad);
        Own := Own + I;
      end;
    finally
      Settle(Acc mod 10);
    end;
  except
    Settle(7);
  end;
  Result := (Acc * 1000 + Shared) * 1000 + Own;
end;

function NestedFromHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Own, Fixed: Int64;

  function Repair(V: Int64): Int64;
  begin
    Clobber;
    Result := V * 2 + Fixed;
  end;

begin
  Acc := 0;
  Fixed := Int64(N) + 40;
  Own := Fixed * 3;
  try
    for I := 0 to N - 1 do
    begin
      Acc := Acc + GetOrRaise(P, I, Bad);
      Own := Own + 1;
    end;
  except
    Acc := Repair(Acc);
  end;
  Result := Acc * 10000 + Own;
end;

{ ---- an anonymous function made in the handler takes what the try block wrote ---- }

function AnonymousInHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Own: Int64;
  F: TIntFunc;
begin
  Acc := 0;
  Own := Int64(N) * 13;
  F := nil;
  try
    for I := 0 to N - 1 do
    begin
      Acc := Acc + GetOrRaise(P, I, Bad);
      Own := Own + 2;
    end;
  except
    F := function(Value: Integer): Integer
      begin
        Result := Value + Integer(Acc);
      end;
  end;
  if Assigned(F) then
    Acc := Apply(F, 1000);
  Result := Acc * 10000 + Own;
end;

{ ---- the nested routine calls its parent ---- }

function NestedRecursive(P: PIntArr; Depth, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Acc, Keep: Int64;

  function Below: Int64;
  begin
    Clobber;
    Result := NestedRecursive(P, Depth - 1, Bad) + Keep;
  end;

begin
  Keep := Int64(Depth) * 3 + 1;
  Acc := Depth;
  try
    if Depth > 0 then
      Acc := Acc + Below
    else
      Acc := Acc + GetOrRaise(P, 1, Bad);
  except
    Acc := Acc + 100000;
  end;
  Result := Acc * 2 + Keep;
end;

{ ---- methods: the body of a routine of a trading program ---- }

function TBook.Join(Limit: Double; Sort, Bad: Boolean): Double;
var
  m: Integer;
  Cmp: TCompare;
  bvol, svol: Single;
  tVol: Double;
  BQuantity: Double;
begin
  try
    if Sort then
      Cmp := function(const Left, Right: Integer): Integer
        begin
          Result := Left - Right;
        end;
    bvol := Buy;
    svol := Sell;
    tVol := 0;
    for m := Count - 1 downto 0 do
      with Trades[m] do
      begin
        BQuantity := Price * Abs(Qty);
        if Qty < 0 then
          svol := svol + Price * Abs(Qty)
        else
          bvol := bvol + Price * Abs(Qty);
        if Time > Limit then
          tVol := tVol + BQuantity;
        if Bad and (m = 2) then
          raise Exception.Create('join');
      end;
    Buy := bvol;
    Sell := svol;
    Vol := tVol;
  except
    SetCrash(142);
  end;
  Result := Vol + Buy - Sell;
end;

function TBook.Locked(Bad: Integer): Int64;
var
  I: Integer;
  Acc: Int64;

  procedure Probe(K: Integer);
  begin
    Clobber;
    if K = Bad then
      raise Exception.Create('locked');
    Inc(Crash);
  end;

begin
  Acc := 0;
  try
    try
      for I := 0 to Count - 1 do
      begin
        Probe(I);
        Acc := Acc + Round(Trades[I].Price * 64);
      end;
    finally
      Leave;
    end;
  except
    Acc := Acc + 1;
  end;
  Result := Acc * 100 + Crash;
end;

{ ---- shapes: the loops of these routines are counted in the object ----
  The sums go where a routine of a program puts them, into data of the unit, inside the try block: nothing
  behind the try reads the locals of the loop. }

function ShapeNestedLoop(const A: array of Int64; Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Odds: Int64;

  procedure Report(V: Int64);
  begin
    Inc(Seen, V);
  end;

begin
  try
    Acc := 0;
    Odds := 0;
    for I := 0 to High(A) do
    begin
      Acc := Acc + A[I];
      Odds := Odds + (A[I] and 1);
    end;
    if Bad > 0 then
      Report(Acc);
    Total := Acc * 2 + Odds;
  except
    SetCrash(1);
  end;
  Result := Total;
end;

function ShapeAnonymousLoop(const A: array of Int64; Sort: Boolean): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Odds: Int64;
  Cmp: TCompare;
begin
  try
    if Sort then
      Cmp := function(const Left, Right: Integer): Integer
        begin
          Result := Left - Right;
        end;
    Acc := 0;
    Odds := 0;
    for I := 0 to High(A) do
    begin
      Acc := Acc + A[I];
      Odds := Odds + (A[I] and 1);
    end;
    Total := Acc * 2 + Odds;
  except
    SetCrash(2);
  end;
  Result := Total;
end;

function ShapePlainLoop(const A: array of Int64): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
  Acc, Odds: Int64;
begin
  try
    Acc := 0;
    Odds := 0;
    for I := 0 to High(A) do
    begin
      Acc := Acc + A[I];
      Odds := Odds + (A[I] and 1);
    end;
    Total := Acc * 2 + Odds;
  except
    SetCrash(3);
  end;
  Result := Total;
end;

var
  I: Integer;
  Book: TBook;
  Wide: array[0..15] of Int64;
begin
  for I := 0 to 15 do
  begin
    Ints[I] := I * 3 + 1;
    Dbls[I] := I + 0.5;
    Wide[I] := I * 5 + 3;
  end;

  Check('nested-raises/none', NestedRaises(@Ints, 8, -1), (92 * 100 + 8) + 8007 * Int64(100000000));
  Check('nested-raises/at5', NestedRaises(@Ints, 8, 5), ((35 + 1000000) * 100 + 5) + 8007 * Int64(100000000));
  Check('nested-writes/none', NestedWrites(@Ints, 8, -1), Int64(92) * 1000000 + (28 * 11) * 100 + 11);
  Check('nested-writes/at5', NestedWrites(@Ints, 8, 5), Int64(35) * 1000000 + (10 * 11 + 5) * 100 + 11);
  Check('nested-fault', NestedFault(@Ints, 8), ((1 + 4 + 7) * 10 + 1) * 1000 + 27);
  Check('nested-div/ok', NestedDivFault(9, 2, 3), Int64(43) * 10000 + 20 * 100 + 3);
  Check('nested-div/fault', NestedDivFault(9, 2, 0), Int64(43) * 10000 + 20 * 100 - 2);

  Check('straight-handler/none', StraightHandler(@Ints, 5, -1), Int64((11 * 100 + 4) * 100 + 7) * 1000 + 7);
  Check('straight-handler/at1', StraightHandler(@Ints, 5, 1), Int64(11 * 10 + 9) * 1000 - 2);
  Check('straight-handler/at2', StraightHandler(@Ints, 5, 2), Int64((11 * 100 + 4) * 10 + 9) * 1000 + 4);
  CrashCode := 0;
  Check('straight-behind/none', StraightBehind(@Ints, 5, -1), Int64((16 * 100 + 4) * 100 + 7) * 1000 + 70 + 15);
  Check('straight-behind/at1', StraightBehind(@Ints, 5, 1), Int64(16) * 1000 - 20 + 15);
  Check('straight-behind/at2', StraightBehind(@Ints, 5, 2), Int64(16 * 100 + 4) * 1000 + 40 + 15);
  Check('straight-behind/crash', CrashCode, 7);
  Check('straight-fault/none', StraightFault(@Ints, 5), Int64(74 + 7) * 10000000 + (3 + 74) * 2);
  Check('straight-fault/fault', StraightFault(@Ints, 101), Int64(202 * 7 + 4) * 10000000 + (3 + 1418) + 1000000);
  Check('straight-anonymous/none', StraightAnonymous(@Ints, 5, -1), Int64((16 * 100 + 4) * 100 + 7) * 1000 + 7);
  Check('straight-anonymous/at1', StraightAnonymous(@Ints, 5, 1), Int64(16 * 10 + 9) * 1000 - 2);
  Check('straight-anonymous/at2', StraightAnonymous(@Ints, 5, 2), Int64((16 * 100 + 4) * 10 + 9) * 1000 + 4);

  Seen := 0;
  Cleanups := 0;
  Check('nested-finally/none', NestedFinally(@Ints, 8, -1), 92 * 100 + 25);
  Check('nested-finally/none seen', Seen, 92 + 25);
  Check('nested-finally/at5', NestedFinally(@Ints, 8, 5), -35 * 100 + 25);
  Check('nested-finally/at5 seen', Seen, 92 + 25 + 35 + 25);
  Check('nested-finally/cleanups', Cleanups, 2);
  Check('nested-exit/found', NestedExit(@Ints, 8, 10), (1 + 4 + 7 + 10) * 10 + 3);
  Check('nested-exit/none', NestedExit(@Ints, 8, 11), 92);
  Check('nested-break-continue', NestedBreakContinue(@Ints, 8), (4 + 7 + 10 + 16) * 100 + 2);

  CrashCode := 0;
  Check('anonymous-plain/none', AnonymousPlain(@Ints, 8, -1, False), 92 * 1000 + 136);
  Check('anonymous-plain/sorted', AnonymousPlain(@Ints, 8, -1, True), 95 * 1000 + 136);
  Check('anonymous-plain/at5', AnonymousPlain(@Ints, 8, 5, True), 35 * 1000 + 136);
  Check('anonymous-plain/crash', CrashCode, 142);
  Check('anonymous-captures/none', AnonymousCaptures(@Ints, 8, -1),
    Int64(1*9 + 4*10 + 7*11 + 10*12 + 13*13 + 16*14 + 19*15 + 22*16) * 10000 + 28 * 100 + 17);
  Check('anonymous-captures/at5', AnonymousCaptures(@Ints, 8, 5),
    Int64(1*9 + 4*10 + 7*11 + 10*12 + 13*13) * 10000 + (10 + 100) * 100 + 14);
  Check('anonymous-written/none', AnonymousWritten(@Ints, 8, -1),
    Int64(92) * 100000 + (1 + 5 + 12 + 22 + 35 + 51 + 70 + 92));
  Check('anonymous-written/at5', AnonymousWritten(@Ints, 8, 5),
    Int64(35) * 100000 - (1 + 5 + 12 + 22 + 35));

  Check('nested-own-try/none', NestedOwnTry(@Ints, 8, -1), Int64(92) * 10000 + (4 + 7 + 10 + 13 + 16));
  Check('nested-own-try/at5', NestedOwnTry(@Ints, 8, 5),
    Int64(35 + 1000 + 8) * 10000 + (4 + 7 + 10 + 13 + 1000 + 6));
  Check('nested-two-levels/none', NestedTwoLevels(@Ints, 4, -1), Int64(22 * 2 + 400) * 1000 + 38);
  Check('nested-two-levels/at107', NestedTwoLevels(@Ints, 4, 107), Int64(1 + 101 + 4 + 104 + 7) * 1000 + 39);
  Check('nested-double/none', NestedDouble(@Dbls, 8, -1), Trunc(32 * 4.0 * 100) * 1000 + 33);
  Check('nested-double/at5', NestedDouble(@Dbls, 8, 5), Trunc((12.5 * 4.0 + 0.5) * 100) * 1000 + 33);
  Check('nested-result/none', NestedResult(@Ints, 8, -1), 92);
  Check('nested-result/at5', NestedResult(@Ints, 8, 5), 35 + 500);

  Check('handler-reads-earlier/none', HandlerReadsEarlier(@Ints, 5, -1), (4 + 17) + (17 * 5 + 7));
  Check('handler-reads-earlier/at1', HandlerReadsEarlier(@Ints, 5, 1), Int64(45) * 1000 + 60);
  Check('handler-reads-earlier/at2', HandlerReadsEarlier(@Ints, 5, 2), Int64(45) * 1000 + 60);
  Check('handler-reads-earlier-anonymous/none', HandlerReadsEarlierAnonymous(@Ints, 5, -1), (4 + 17) + (17 * 5 + 7));
  Check('handler-reads-earlier-anonymous/at1', HandlerReadsEarlierAnonymous(@Ints, 5, 1), Int64(38) * 1000 + 60);
  Check('handler-reads-earlier-anonymous/at2', HandlerReadsEarlierAnonymous(@Ints, 5, 2), Int64(38) * 1000 + 60);
  Seen := 0;
  Cleanups := 0;
  Check('cleanup-in-cleanup/none', NestedCleanupInCleanup(@Ints, 8, -1), 92 * 1000 + 25 + 208);
  Check('cleanup-in-cleanup/none seen', Seen, 92 + 208);
  Check('cleanup-in-cleanup/at5', NestedCleanupInCleanup(@Ints, 8, 5), -35 * 1000 + 25 + 208);
  Check('cleanup-in-cleanup/at5 seen', Seen, 92 + 208 + 35 + 208);
  Check('cleanup-in-cleanup/cleanups', Cleanups, 2);
  Check('from-finally/none', NestedFromFinally(@Ints, 8, -1), (Int64(92) * 1000 + 12) * 1000 + (91 + 28));
  Check('from-finally/at5', NestedFromFinally(@Ints, 8, 5), (Int64(35) * 1000 + 157) * 1000 + (91 + 10));
  Check('from-handler/none', NestedFromHandler(@Ints, 8, -1), Int64(92) * 10000 + (48 * 3 + 8));
  Check('from-handler/at5', NestedFromHandler(@Ints, 8, 5), Int64(35 * 2 + 48) * 10000 + (48 * 3 + 5));
  Check('anonymous-in-handler/none', AnonymousInHandler(@Ints, 8, -1), Int64(92) * 10000 + (104 + 16));
  Check('anonymous-in-handler/at5', AnonymousInHandler(@Ints, 8, 5), Int64(1000 + 35) * 10000 + (104 + 10));
  Check('recursive/none', NestedRecursive(@Ints, 3, -1), 214);
  Check('recursive/at1', NestedRecursive(@Ints, 3, 1), 1600150);

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
  Check('join/plain', Trunc(Book.Join(3.5, False, False) * 4096), 360912);
  Check('join/sorted', Trunc(Book.Join(3.5, True, False) * 4096), 295248);
  Book.Buy := 0;
  Book.Sell := 0;
  Book.Vol := 0;
  CrashCode := 0;
  Check('join/raise', Trunc(Book.Join(3.5, True, True) * 4096), 0);
  Check('join/crash', CrashCode, 142);
  Book.Crash := 0;
  Cleanups := 0;
  Check('locked/none', Book.Locked(-1), (8 * 4096 + 28) * 100 + 8);
  Check('locked/at5', Book.Locked(5), (5 * 4096 + 10 + 1) * 100 + 13);
  Check('locked/cleanups', Cleanups, 2);
  Book.Free;

  Check('shape/nested', ShapeNestedLoop(Wide, 0), 648 * 2 + 8);
  Check('shape/anonymous', ShapeAnonymousLoop(Wide, False), 648 * 2 + 8);
  Check('shape/plain', ShapePlainLoop(Wide), 648 * 2 + 8);

  if Failures = 0 then
    WriteLn('TRY_NESTED_PASS')
  else
  begin
    WriteLn('TRY_NESTED_FAIL ', Failures);
    Halt(1);
  end;
end.
