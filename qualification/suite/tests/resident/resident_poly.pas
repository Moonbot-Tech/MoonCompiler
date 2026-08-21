unit resident_poly;

{ Многочлены и точные дроби — целочисленная алгебра, где всё проверяется без
  единого допуска.

  Многочлены здесь с целыми коэффициентами, дроби — парой целых. Значит все
  равенства точные, и никакой оговорки «с точностью до» не нужно:

    * деление с остатком: частное на делитель плюс остаток даёт делимое, а
      степень остатка меньше степени делителя;
    * умножение переставимо и распределительно относительно сложения;
    * значение произведения равно произведению значений — в любой точке;
    * производная суммы равна сумме производных, а производная произведения
      подчиняется своему правилу;
    * дроби: приведённая дробь равна исходной, сложение переставимо, а сумма с
      противоположной даёт ноль.

  Способ вычисления значения тоже проверяется двумя путями: по схеме Горнера и
  прямым суммированием степеней. Разные порядки действий — один ответ, потому
  что арифметика целая. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections, resident_core;

implementation

type
  { Коэффициенты от младшего к старшему. }
  TPoly = System.TArray<Int64>;

  { Дробь хранится приведённой и со знаком в числителе. }
  TFraction = record
    Num, Den: Int64;
  end;

  TResidentPolyPocket = class(TResidentPocket)
  private
    FPoly: TPoly;
    FRounds: Int64;
  end;

procedure TrimPoly(var A: TPoly);
var
  N: Integer;
begin
  N := Length(A);
  while (N > 0) and (A[N - 1] = 0) do
    Dec(N);
  SetLength(A, N);
end;

function DegreeOf(const A: TPoly): Integer;
begin
  Result := Length(A) - 1;
end;

function AddPoly(const A, B: TPoly): TPoly;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) > N then
    N := Length(B);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I] := 0;
    if I < Length(A) then
      Result[I] := Result[I] + A[I];
    if I < Length(B) then
      Result[I] := Result[I] + B[I];
  end;
  TrimPoly(Result);
end;

function SubPoly(const A, B: TPoly): TPoly;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) > N then
    N := Length(B);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I] := 0;
    if I < Length(A) then
      Result[I] := Result[I] + A[I];
    if I < Length(B) then
      Result[I] := Result[I] - B[I];
  end;
  TrimPoly(Result);
end;

function MulPoly(const A, B: TPoly): TPoly;
var
  I, J: Integer;
begin
  if (Length(A) = 0) or (Length(B) = 0) then
    Exit(nil);
  SetLength(Result, Length(A) + Length(B) - 1);
  for I := 0 to High(Result) do
    Result[I] := 0;
  for I := 0 to High(A) do
    for J := 0 to High(B) do
      Result[I + J] := Result[I + J] + A[I] * B[J];
  TrimPoly(Result);
end;

{ Деление с остатком. Делитель обязан быть с единичным старшим коэффициентом —
  иначе частное вышло бы дробным, а здесь всё целое. }
procedure DivModPoly(const A, B: TPoly; out Q, R: TPoly);
var
  I, Shift, DegA, DegB: Integer;
  Factor: Int64;
  Work: TPoly;
begin
  Q := nil;
  R := nil;
  DegB := DegreeOf(B);
  if DegB < 0 then
    raise EDivByZero.Create('poly: division by the zero polynomial');

  Work := System.Copy(A, 0, Length(A));
  DegA := DegreeOf(Work);
  if DegA < DegB then
  begin
    R := Work;
    Exit;
  end;

  SetLength(Q, DegA - DegB + 1);
  for I := 0 to High(Q) do
    Q[I] := 0;

  while DegreeOf(Work) >= DegB do
  begin
    Shift := DegreeOf(Work) - DegB;
    Factor := Work[DegreeOf(Work)];
    Q[Shift] := Factor;
    for I := 0 to DegB do
      Work[Shift + I] := Work[Shift + I] - Factor * B[I];
    TrimPoly(Work);
    if Length(Work) = 0 then
      Break;
  end;

  TrimPoly(Q);
  R := Work;
end;

{ Значение по схеме Горнера: свёртка справа налево, наименьшее число
  умножений. }
function ValueByHorner(const A: TPoly; X: Int64): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := High(A) downto 0 do
    Result := Result * X + A[I];
end;

{ То же прямым суммированием степеней: другой порядок действий, тот же ответ. }
function ValueByPowers(const A: TPoly; X: Int64): Int64;
var
  I: Integer;
  Power_: Int64;
begin
  Result := 0;
  Power_ := 1;
  for I := 0 to High(A) do
  begin
    Result := Result + A[I] * Power_;
    Power_ := Power_ * X;
  end;
end;

function Derivative(const A: TPoly): TPoly;
var
  I: Integer;
begin
  if Length(A) <= 1 then
    Exit(nil);
  SetLength(Result, Length(A) - 1);
  for I := 1 to High(A) do
    Result[I - 1] := A[I] * I;
  TrimPoly(Result);
end;

function SamePoly(const A, B: TPoly): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
  Result := True;
end;

function MakePoly(var State: UInt64; Degree: Integer; Monic: Boolean): TPoly;
var
  I: Integer;
begin
  SetLength(Result, Degree + 1);
  for I := 0 to Degree do
    Result[I] := Int64(ResidentNext(State) mod 21) - 10;
  { Старший коэффициент не может быть нулём, иначе степень окажется не той. }
  if Monic then
    Result[Degree] := 1
  else if Result[Degree] = 0 then
    Result[Degree] := 3;
end;

{ ------------------------------------------------------------- дроби ------ }

function GcdI(A, B: Int64): Int64;
var
  T: Int64;
begin
  if A < 0 then
    A := -A;
  if B < 0 then
    B := -B;
  while B <> 0 do
  begin
    T := A mod B;
    A := B;
    B := T;
  end;
  Result := A;
end;

function MakeFraction(Num, Den: Int64): TFraction;
var
  G: Int64;
begin
  if Den = 0 then
    raise EDivByZero.Create('fraction: zero denominator');
  { Знак живёт в числителе, дробь всегда приведена — иначе равенство дробей
    пришлось бы проверять умножением накрест каждый раз. }
  if Den < 0 then
  begin
    Num := -Num;
    Den := -Den;
  end;
  G := GcdI(Num, Den);
  if G = 0 then
    G := 1;
  Result.Num := Num div G;
  Result.Den := Den div G;
end;

function AddFrac(const A, B: TFraction): TFraction;
begin
  Result := MakeFraction(A.Num * B.Den + B.Num * A.Den, A.Den * B.Den);
end;

function MulFrac(const A, B: TFraction): TFraction;
begin
  Result := MakeFraction(A.Num * B.Num, A.Den * B.Den);
end;

function SameFrac(const A, B: TFraction): Boolean;
begin
  Result := (A.Num = B.Num) and (A.Den = B.Den);
end;

{ ------------------------------------------------------------- стадии ----- }

{ Деление многочленов: договор деления и ограничение на степень остатка. }
procedure StagePolyDivision(Carrier: TResidentCarrier);
var
  A, B, Q, R, Back: TPoly;
  State: UInt64;
  I: Integer;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 83 + Carrier.Lap)));
  for I := 1 to 6 do
  begin
    A := MakePoly(State, 3 + (Carrier.Lap mod 5) + I, False);
    B := MakePoly(State, 1 + (I mod 3), True);

    DivModPoly(A, B, Q, R);
    Back := AddPoly(MulPoly(Q, B), R);

    Carrier.Claim(SamePoly(Back, A), 'poly: q*b + r <> a');
    Carrier.Claim(DegreeOf(R) < DegreeOf(B),
                  'poly: remainder degree is not below the divisor');
    Carrier.Feed(UInt64(Cardinal(DegreeOf(A))));
    Carrier.Feed(UInt64(Cardinal(DegreeOf(Q) + 1)));
  end;
end;

{ Значение двумя способами и связь значения с произведением. }
procedure StagePolyValue(Carrier: TResidentCarrier);
var
  A, B, P: TPoly;
  State: UInt64;
  X, VA, VB: Int64;
  I: Integer;
begin
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 29 + 3)));
  A := MakePoly(State, 4 + (Carrier.Lap mod 4), False);
  B := MakePoly(State, 3 + (Carrier.Serial mod 3), False);
  P := MulPoly(A, B);

  for I := -4 to 4 do
  begin
    X := I;
    { Два способа вычислить значение — один ответ. }
    Carrier.Claim(ValueByHorner(A, X) = ValueByPowers(A, X),
                  'poly: Horner and direct powers disagree');
    { Значение произведения равно произведению значений. }
    VA := ValueByHorner(A, X);
    VB := ValueByHorner(B, X);
    Carrier.Claim(ValueByHorner(P, X) = VA * VB,
                  'poly: value of the product is not the product of values');
    { Значение суммы равно сумме значений. }
    Carrier.Claim(ValueByHorner(AddPoly(A, B), X) = VA + VB,
                  'poly: value of the sum is not the sum of values');
    Carrier.Feed(UInt64(VA));
  end;
  Carrier.Feed(UInt64(Cardinal(DegreeOf(P))));
end;

{ Свойства кольца многочленов: переставимость, распределительность, степень
  произведения. }
procedure StagePolyAlgebra(Carrier: TResidentCarrier);
var
  A, B, C: TPoly;
  State: UInt64;
begin
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Serial * 11 + 5)));
  A := MakePoly(State, 3 + (Carrier.Lap mod 4), False);
  B := MakePoly(State, 2 + (Carrier.Lap mod 3), False);
  C := MakePoly(State, 2 + (Carrier.Serial mod 3), False);

  Carrier.Claim(SamePoly(MulPoly(A, B), MulPoly(B, A)),
                'poly: multiplication is not commutative');
  Carrier.Claim(SamePoly(MulPoly(MulPoly(A, B), C), MulPoly(A, MulPoly(B, C))),
                'poly: multiplication is not associative');
  Carrier.Claim(SamePoly(MulPoly(A, AddPoly(B, C)),
                         AddPoly(MulPoly(A, B), MulPoly(A, C))),
                'poly: multiplication does not distribute over addition');
  Carrier.Claim(SamePoly(SubPoly(AddPoly(A, B), B), A),
                'poly: add then subtract lost the polynomial');

  { Степень произведения равна сумме степеней. }
  Carrier.Claim(DegreeOf(MulPoly(A, B)) = DegreeOf(A) + DegreeOf(B),
                'poly: degree of the product is wrong');
  Carrier.Feed(UInt64(Cardinal(DegreeOf(A))));
  Carrier.Feed(UInt64(Cardinal(DegreeOf(MulPoly(A, B)))));

  { Производная: сумма — по слагаемым, произведение — по своему правилу. }
  Carrier.Claim(SamePoly(Derivative(AddPoly(A, B)),
                         AddPoly(Derivative(A), Derivative(B))),
                'poly: derivative of a sum is not the sum of derivatives');
  Carrier.Claim(SamePoly(Derivative(MulPoly(A, B)),
                         AddPoly(MulPoly(Derivative(A), B),
                                 MulPoly(A, Derivative(B)))),
                'poly: derivative of a product breaks the product rule');
  Carrier.Claim(DegreeOf(Derivative(A)) = DegreeOf(A) - 1,
                'poly: derivative did not lower the degree by one');
end;

{ Корни: многочлен, собранный из множителей, обязан обращаться в ноль ровно в
  заданных точках. }
procedure StagePolyRoots(Carrier: TResidentCarrier);
var
  P, Factor: TPoly;
  Roots: System.TArray<Int64>;
  State: UInt64;
  Count, I, J: Integer;
  Ok: Boolean;
begin
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 47 + 13)));
  Count := 3 + (Carrier.Lap mod 4);
  SetLength(Roots, Count);

  { Корни различны: иначе кратность запутала бы проверку «ноль только там». }
  for I := 0 to Count - 1 do
  begin
    Roots[I] := Int64(ResidentNext(State) mod 17) - 8;
    for J := 0 to I - 1 do
      if Roots[J] = Roots[I] then
        Roots[I] := Roots[I] + 17;
  end;

  { Многочлен собирается перемножением множителей вида x минус корень. }
  SetLength(P, 1);
  P[0] := 1;
  SetLength(Factor, 2);
  for I := 0 to Count - 1 do
  begin
    Factor[0] := -Roots[I];
    Factor[1] := 1;
    P := MulPoly(P, Factor);
  end;

  Carrier.Claim(DegreeOf(P) = Count, 'poly: assembled degree is wrong');
  { В каждом корне значение обязано быть нулём. }
  for I := 0 to Count - 1 do
    Carrier.Claim(ValueByHorner(P, Roots[I]) = 0,
                  'poly: assembled polynomial is not zero at its root');

  { И только там: в стороне от корней ноля быть не должно. }
  Ok := True;
  for I := -20 to 20 do
  begin
    var IsRoot := False;
    for J := 0 to Count - 1 do
      if Roots[J] = I then
        IsRoot := True;
    if not IsRoot and (ValueByHorner(P, I) = 0) then
      Ok := False;
  end;
  Carrier.Claim(Ok, 'poly: an unexpected root appeared');

  { Деление на множитель обязано пройти без остатка. }
  Factor[0] := -Roots[0];
  Factor[1] := 1;
  var Q, R: TPoly;
  DivModPoly(P, Factor, Q, R);
  Carrier.Claim(Length(R) = 0, 'poly: dividing by a root factor left a remainder');
  Carrier.Claim(DegreeOf(Q) = Count - 1, 'poly: quotient degree is wrong');
  Carrier.Feed(UInt64(Cardinal(Count)));
end;

{ Точные дроби: приведение, переставимость, обратный элемент. }
procedure StageFractions(Carrier: TResidentCarrier);
var
  A, B, C, Sum, Zero: TFraction;
  State: UInt64;
  I: Integer;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 31 + Carrier.Lap)));
  for I := 1 to 16 do
  begin
    A := MakeFraction(Int64(ResidentNext(State) mod 2000) - 1000,
                      Int64(ResidentNext(State) mod 500) + 1);
    B := MakeFraction(Int64(ResidentNext(State) mod 2000) - 1000,
                      Int64(ResidentNext(State) mod 500) + 1);
    C := MakeFraction(Int64(ResidentNext(State) mod 200) - 100,
                      Int64(ResidentNext(State) mod 50) + 1);

    { Приведённость: числитель и знаменатель взаимно просты, знаменатель
      положителен. }
    Carrier.Claim(A.Den > 0, 'fraction: denominator is not positive');
    Carrier.Claim(GcdI(A.Num, A.Den) = 1, 'fraction: not in lowest terms');

    Carrier.Claim(SameFrac(AddFrac(A, B), AddFrac(B, A)),
                  'fraction: addition is not commutative');
    Carrier.Claim(SameFrac(MulFrac(A, B), MulFrac(B, A)),
                  'fraction: multiplication is not commutative');
    Carrier.Claim(SameFrac(AddFrac(AddFrac(A, B), C), AddFrac(A, AddFrac(B, C))),
                  'fraction: addition is not associative');
    Carrier.Claim(SameFrac(MulFrac(A, AddFrac(B, C)),
                           AddFrac(MulFrac(A, B), MulFrac(A, C))),
                  'fraction: multiplication does not distribute');

    { Сумма с противоположной обязана давать ноль. }
    Sum := AddFrac(A, MakeFraction(-A.Num, A.Den));
    Carrier.Claim((Sum.Num = 0) and (Sum.Den = 1),
                  'fraction: a plus minus a is not zero');

    { Умножение на обратную даёт единицу — если дробь не ноль. }
    if A.Num <> 0 then
    begin
      Zero := MulFrac(A, MakeFraction(A.Den, A.Num));
      Carrier.Claim((Zero.Num = 1) and (Zero.Den = 1),
                    'fraction: a times its reciprocal is not one');
    end;

    Carrier.Feed(UInt64(A.Num));
    Carrier.Feed(UInt64(A.Den));
  end;
end;

{ Многочлен, растущий между оборотами: каждый оборот умножается на очередной
  множитель, и деление на него обязано вернуть предыдущее состояние. }
procedure StageRunningPoly(Carrier: TResidentCarrier);
var
  Pocket: TResidentPolyPocket;
  Factor, Q, R, Was: TPoly;
begin
  Pocket := Carrier.PocketAs<TResidentPolyPocket>('poly-running');
  if Length(Pocket.FPoly) = 0 then
  begin
    SetLength(Pocket.FPoly, 1);
    Pocket.FPoly[0] := 1;
  end;

  Was := System.Copy(Pocket.FPoly, 0, Length(Pocket.FPoly));
  SetLength(Factor, 2);
  Factor[0] := Int64(Carrier.Lap mod 9) - 4;
  Factor[1] := 1;
  Pocket.FPoly := MulPoly(Pocket.FPoly, Factor);

  Carrier.Claim(DegreeOf(Pocket.FPoly) = DegreeOf(Was) + 1,
                'poly: running product did not raise the degree');
  DivModPoly(Pocket.FPoly, Factor, Q, R);
  Carrier.Claim(Length(R) = 0, 'poly: running division left a remainder');
  Carrier.Claim(SamePoly(Q, Was), 'poly: running division lost the previous state');

  Carrier.Feed(UInt64(Cardinal(DegreeOf(Pocket.FPoly))));
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  { Дойдя до высокой степени, многочлен начинается заново: коэффициенты растут
    быстро, и дальше они перестали бы помещаться. }
  if DegreeOf(Pocket.FPoly) > 12 then
  begin
    SetLength(Pocket.FPoly, 1);
    Pocket.FPoly[0] := 1;
    Pocket.FRounds := 0;
  end;
end;

initialization
  ResidentRegisterStage('poly-algebra', @StagePolyAlgebra);
  ResidentRegisterStage('poly-division', @StagePolyDivision);
  ResidentRegisterStage('poly-fractions', @StageFractions);
  ResidentRegisterStage('poly-roots', @StagePolyRoots);
  ResidentRegisterStage('poly-running', @StageRunningPoly);
  ResidentRegisterStage('poly-value', @StagePolyValue);

end.
