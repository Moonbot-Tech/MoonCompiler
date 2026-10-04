{ %CPU=x86_64 }
{ %OPT=-O3 }
program tdivmodpair1;

{$mode delphi}

uses
  SysUtils;

var
  NumCalls,
  DenCalls: LongInt;

procedure Fail(Code: LongInt);
begin
  Halt(Code);
end;

procedure Signed64DivMod(X, Y: Int64; out Q, R: Int64); noinline;
begin
  Q := X div Y;
  R := X mod Y;
end;

procedure Signed64ModDiv(X, Y: Int64; out Q, R: Int64); noinline;
begin
  R := X mod Y;
  Q := X div Y;
end;

procedure Unsigned64DivMod(X, Y: QWord; out Q, R: QWord); noinline;
begin
  Q := X div Y;
  R := X mod Y;
end;

procedure Unsigned64ModDiv(X, Y: QWord; out Q, R: QWord); noinline;
begin
  R := X mod Y;
  Q := X div Y;
end;

procedure Signed32DivMod(X, Y: LongInt; out Q, R: LongInt); noinline;
begin
  Q := X div Y;
  R := X mod Y;
end;

procedure Signed32ModDiv(X, Y: LongInt; out Q, R: LongInt); noinline;
begin
  R := X mod Y;
  Q := X div Y;
end;

procedure Unsigned32DivMod(X, Y: LongWord; out Q, R: LongWord); noinline;
begin
  Q := X div Y;
  R := X mod Y;
end;

procedure Unsigned32ModDiv(X, Y: LongWord; out Q, R: LongWord); noinline;
begin
  R := X mod Y;
  Q := X div Y;
end;

procedure AliasNumerator(var X: Int64; Y: Int64; out R: Int64); noinline;
begin
  X := X div Y;
  R := X mod Y;
end;

procedure AliasDivisor(X: Int64; var Y: Int64; out R: Int64); noinline;
begin
  Y := X div Y;
  R := X mod Y;
end;

function NextNumerator: Int64; noinline;
begin
  Inc(NumCalls);
  Result := 101;
end;

function NextDenominator: Int64; noinline;
begin
  Inc(DenCalls);
  Result := 13;
end;

procedure SideEffectingOperands(out Q, R: Int64); noinline;
begin
  Q := NextNumerator div NextDenominator;
  R := NextNumerator mod NextDenominator;
end;

procedure TestSigned64;
const
  Xs: array[0..7] of Int64 =
    (17, -17, 17, -17, High(Int64), Low(Int64), 0, 1);
  Ys: array[0..7] of Int64 =
    (5, 5, -5, -5, 97, 97, -7, High(Int64));
var
  I: LongInt;
  Q, R: Int64;
begin
  for I := Low(Xs) to High(Xs) do
  begin
    Signed64DivMod(Xs[I], Ys[I], Q, R);
    if (Q * Ys[I] + R <> Xs[I]) or
       (Abs(R) >= Abs(Ys[I])) then
      Fail(10 + I);
    Signed64ModDiv(Xs[I], Ys[I], Q, R);
    if (Q * Ys[I] + R <> Xs[I]) or
       (Abs(R) >= Abs(Ys[I])) then
      Fail(20 + I);
  end;
end;

procedure TestUnsigned64;
const
  Xs: array[0..4] of QWord =
    (17, High(QWord), High(QWord), 0, 1);
  Ys: array[0..4] of QWord =
    (5, 97, High(QWord), 7, High(QWord));
var
  I: LongInt;
  Q, R: QWord;
begin
  for I := Low(Xs) to High(Xs) do
  begin
    Unsigned64DivMod(Xs[I], Ys[I], Q, R);
    if (Q * Ys[I] + R <> Xs[I]) or (R >= Ys[I]) then
      Fail(30 + I);
    Unsigned64ModDiv(Xs[I], Ys[I], Q, R);
    if (Q * Ys[I] + R <> Xs[I]) or (R >= Ys[I]) then
      Fail(40 + I);
  end;
end;

procedure Test32;
var
  SQ, SR: LongInt;
  UQ, UR: LongWord;
begin
  Signed32DivMod(-2147483647, 97, SQ, SR);
  if (SQ <> -22139006) or (SR <> -65) then
    Fail(50);
  Signed32ModDiv(2147483647, -97, SQ, SR);
  if (SQ <> -22139006) or (SR <> 65) then
    Fail(51);
  Unsigned32DivMod(High(LongWord), 97, UQ, UR);
  if (UQ <> 44278013) or (UR <> 34) then
    Fail(52);
  Unsigned32ModDiv(High(LongWord), 65537, UQ, UR);
  if (UQ <> 65535) or (UR <> 0) then
    Fail(53);
end;

procedure TestNegativeControls;
var
  X, Y, Q, R: Int64;
  Raised: Boolean;
begin
  X := 101;
  AliasNumerator(X, 13, R);
  if (X <> 7) or (R <> 7) then
    Fail(60);

  Y := 13;
  AliasDivisor(101, Y, R);
  if (Y <> 7) or (R <> 3) then
    Fail(61);

  NumCalls := 0;
  DenCalls := 0;
  SideEffectingOperands(Q, R);
  if (Q <> 7) or (R <> 10) or
     (NumCalls <> 2) or (DenCalls <> 2) then
    Fail(62);

  X := 17;
  Y := 0;
  Raised := False;
  try
    Q := X div Y;
    R := X mod Y;
  except
    on EDivByZero do
      Raised := True;
  end;
  if not Raised then
    Fail(63);

  X := Low(Int64);
  Y := -1;
  Raised := False;
  try
    Q := X div Y;
    R := X mod Y;
  except
    { x86 reports the same IDIV trap for zero divisors and the one signed
      overflow case.  The OS exception mapping may therefore select either
      concrete EIntError descendant; the optimizer contract is that the
      arithmetic exception remains observable. }
    on EIntError do
      Raised := True;
  end;
  if not Raised then
    Fail(64);
end;

begin
  TestSigned64;
  TestUnsigned64;
  Test32;
  TestNegativeControls;
  WriteLn('DIVMOD-PAIR:PASS');
end.
