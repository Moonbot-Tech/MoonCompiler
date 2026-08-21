unit resident_eth;

{ Keccak-256 и арифметика на эллиптической кривой secp256k1 — то, на чём стоит
  Ethereum.

  Два тяжёлых расчёта с настоящими внешними ответами:

    * **Keccak-256** — перестановка на состоянии в тысячу шестьсот бит, двадцать
      четыре раунда по пять шагов, с таблицами сдвигов и раундовых констант. Это
      снова та самая форма — табличные преобразования внутри повторяющихся
      проходов, — на которой уже нашёлся дефект оптимизатора. Ответ известен:
      свёртка пустой строки и строки `abc` записана в любой документации по
      Ethereum и не выводится из нашего кода;

    * **secp256k1** — сложение и удвоение точек в поле по модулю простого числа
      из двухсот пятидесяти шести бит. Каждая операция тянет за собой умножение
      и деление длинных чисел, поэтому одно умножение точки на скаляр стоит
      тысячи длинных делений.

  Оракулы кривой не требуют эталона вовсе, потому что задаются самой кривой:
  точка либо лежит на ней, либо нет; сложение подчиняется закону группы; точка,
  сложенная со своей противоположностью, даёт нейтральный элемент. Плюс к этому
  известны координаты удвоенной образующей — внешний ответ. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections,
  resident_core, resident_bignum;

implementation

const
  { Раундовые константы Keccak. }
  RoundConst: array[0 .. 23] of UInt64 = (
    $0000000000000001, $0000000000008082, $800000000000808A, $8000000080008000,
    $000000000000808B, $0000000080000001, $8000000080008081, $8000000000008009,
    $000000000000008A, $0000000000000088, $0000000080008009, $000000008000000A,
    $000000008000808B, $800000000000008B, $8000000000008089, $8000000000008003,
    $8000000000008002, $8000000000000080, $000000000000800A, $800000008000000A,
    $8000000080008081, $8000000000008080, $0000000080000001, $8000000080008008);

  { Величины циклических сдвигов. }
  RotOff: array[0 .. 24] of Integer = (
     0,  1, 62, 28, 27,
    36, 44,  6, 55, 20,
     3, 10, 43, 25, 39,
    41, 45, 15, 21,  8,
    18,  2, 61, 56, 14);

  { Известные ответы Keccak-256 — из документации Ethereum. }
  KeccakEmpty =
    'C5D2460186F7233C927E7DB2DCC703C0E500B653CA82273B7BFAD8045D85A470';
  KeccakAbc =
    '4E03657AEA45A94FC7D47BA826C8D667C0D1E6E33A64A036EC44F58FA12D6C45';

  { Поле и образующая secp256k1. }
  FieldHex = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F';
  OrderHex = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141';
  GxHex = '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798';
  GyHex = '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8';
  { Удвоенная образующая — тоже внешний ответ. }
  G2xHex = 'C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5';
  G2yHex = '1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A';

type
  TKeccakState = array[0 .. 24] of UInt64;

  { Точка на кривой в обычных координатах; признак бесконечности отдельно. }
  TPoint = record
    X, Y: TLimbs;
    Infinity: Boolean;
  end;

  TResidentEthPocket = class(TResidentPocket)
  private
    FAcc: TPoint;
    FSteps: Int64;
    FRounds: Int64;
  end;

var
  FieldP, CurveOrder: TLimbs;
  BaseG: TPoint;

function RotL64(V: UInt64; N: Integer): UInt64; inline;
begin
  Result := (V shl N) or (V shr (64 - N));
end;

{ ------------------------------------------------------------ Keccak ------ }

procedure KeccakF(var A: TKeccakState);
var
  Round_, X, Y, I: Integer;
  C: array[0 .. 4] of UInt64;
  D: array[0 .. 4] of UInt64;
  B: TKeccakState;
begin
  for Round_ := 0 to 23 do
  begin
    { Шаг перемешивания столбцов. }
    for X := 0 to 4 do
      C[X] := A[X] xor A[X + 5] xor A[X + 10] xor A[X + 15] xor A[X + 20];
    for X := 0 to 4 do
      D[X] := C[(X + 4) mod 5] xor RotL64(C[(X + 1) mod 5], 1);
    for Y := 0 to 4 do
      for X := 0 to 4 do
        A[X + 5 * Y] := A[X + 5 * Y] xor D[X];

    { Сдвиги и перестановка. }
    for Y := 0 to 4 do
      for X := 0 to 4 do
      begin
        I := X + 5 * Y;
        if RotOff[I] = 0 then
          B[Y + 5 * ((2 * X + 3 * Y) mod 5)] := A[I]
        else
          B[Y + 5 * ((2 * X + 3 * Y) mod 5)] := RotL64(A[I], RotOff[I]);
      end;

    { Нелинейный шаг. }
    for Y := 0 to 4 do
      for X := 0 to 4 do
        A[X + 5 * Y] := B[X + 5 * Y] xor
                        ((not B[((X + 1) mod 5) + 5 * Y]) and
                         B[((X + 2) mod 5) + 5 * Y]);

    A[0] := A[0] xor RoundConst[Round_];
  end;
end;

{ Свёртка с шириной поглощения в 136 байт и дополнением, принятым в Ethereum. }
function Keccak256(const Data: TBytes): string;
const
  Rate = 136;
var
  A: TKeccakState;
  Block: array[0 .. Rate - 1] of Byte;
  Pos_, Taken, I, J: Integer;
begin
  FillChar(A, SizeOf(A), 0);
  Pos_ := 0;
  while Pos_ + Rate <= Length(Data) do
  begin
    for I := 0 to Rate div 8 - 1 do
    begin
      var Word_: UInt64 := 0;
      for J := 7 downto 0 do
        Word_ := (Word_ shl 8) or UInt64(Data[Pos_ + I * 8 + J]);
      A[I] := A[I] xor Word_;
    end;
    KeccakF(A);
    Inc(Pos_, Rate);
  end;

  { Хвост с дополнением: единица сразу после данных, единица в старшем бите
    последнего байта блока. }
  FillChar(Block, SizeOf(Block), 0);
  Taken := Length(Data) - Pos_;
  for I := 0 to Taken - 1 do
    Block[I] := Data[Pos_ + I];
  Block[Taken] := $01;
  Block[Rate - 1] := Block[Rate - 1] or $80;

  for I := 0 to Rate div 8 - 1 do
  begin
    var Word_: UInt64 := 0;
    for J := 7 downto 0 do
      Word_ := (Word_ shl 8) or UInt64(Block[I * 8 + J]);
    A[I] := A[I] xor Word_;
  end;
  KeccakF(A);

  Result := '';
  for I := 0 to 3 do
    for J := 0 to 7 do
      Result := Result + IntToHex(Byte((A[I] shr (J * 8)) and $FF), 2);
end;

function TextBytes(const S: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(S));
  for I := 1 to Length(S) do
    Result[I - 1] := Byte(Word(S[I]) and $FF);
end;

{ --------------------------------------------------------- secp256k1 ------ }

function ModP(const A: TLimbs): TLimbs;
var
  Q: TLimbs;
begin
  DivMod(A, FieldP, Q, Result);
end;

function AddP(const A, B: TLimbs): TLimbs;
begin
  Result := ModP(Add(A, B));
end;

function SubP(const A, B: TLimbs): TLimbs;
begin
  { Вычитание в поле: если уменьшаемое меньше, добавляется модуль. }
  if Compare(A, B) >= 0 then
    Result := Sub(A, B)
  else
    Result := Sub(Add(A, FieldP), B);
  Result := ModP(Result);
end;

function MulP(const A, B: TLimbs): TLimbs;
begin
  Result := ModP(Mul(A, B));
end;

{ Обратный элемент по малой теореме Ферма: a в степени p-2. Тяжелее прямого
  расширенного алгоритма, зато короче и без ветвлений со знаками. }
function InvP(const A: TLimbs): TLimbs;
begin
  Result := PowMod(A, Sub(FieldP, FromCardinal(2)), FieldP);
end;

function OnCurve(const P: TPoint): Boolean;
var
  Left, Right: TLimbs;
begin
  if P.Infinity then
    Exit(True);
  Left := MulP(P.Y, P.Y);
  Right := AddP(MulP(MulP(P.X, P.X), P.X), FromCardinal(7));
  Result := Compare(Left, Right) = 0;
end;

function Negate(const P: TPoint): TPoint;
begin
  Result := P;
  if not P.Infinity then
    Result.Y := SubP(FieldP, P.Y);
end;

function SamePoint(const A, B: TPoint): Boolean;
begin
  if A.Infinity or B.Infinity then
    Exit(A.Infinity = B.Infinity);
  Result := (Compare(A.X, B.X) = 0) and (Compare(A.Y, B.Y) = 0);
end;

function AddPoints(const P, Q: TPoint): TPoint;
var
  Slope, Tmp: TLimbs;
begin
  if P.Infinity then
    Exit(Q);
  if Q.Infinity then
    Exit(P);

  if Compare(P.X, Q.X) = 0 then
  begin
    if Compare(P.Y, Q.Y) <> 0 then
    begin
      { Точка и её противоположность дают нейтральный элемент. }
      Result.Infinity := True;
      Result.X := nil;
      Result.Y := nil;
      Exit;
    end;
    { Удвоение: наклон касательной. }
    Tmp := MulP(FromCardinal(3), MulP(P.X, P.X));
    Slope := MulP(Tmp, InvP(MulP(FromCardinal(2), P.Y)));
  end
  else
    Slope := MulP(SubP(Q.Y, P.Y), InvP(SubP(Q.X, P.X)));

  Result.Infinity := False;
  Result.X := SubP(SubP(MulP(Slope, Slope), P.X), Q.X);
  Result.Y := SubP(MulP(Slope, SubP(P.X, Result.X)), P.Y);
end;

{ Умножение точки на число: удвоение с прибавлением, слева направо. }
function MulPoint(const P: TPoint; const K: TLimbs): TPoint;
var
  Bits, I: Integer;
begin
  Result.Infinity := True;
  Result.X := nil;
  Result.Y := nil;
  Bits := BitLength(K);
  for I := Bits - 1 downto 0 do
  begin
    Result := AddPoints(Result, Result);
    if (K[I div 32] shr (I mod 32)) and 1 = 1 then
      Result := AddPoints(Result, P);
  end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Известные ответы Keccak-256 и чувствительность свёртки. }
procedure StageKeccakVectors(Carrier: TResidentCarrier);
var
  Empty: TBytes;
  Long_: TBytes;
  I: Integer;
begin
  SetLength(Empty, 0);
  Carrier.Claim(Keccak256(Empty) = KeccakEmpty, 'keccak: vector for empty input');
  Carrier.Claim(Keccak256(TextBytes('abc')) = KeccakAbc, 'keccak: vector for abc');
  Carrier.FeedWide(Keccak256(TextBytes('abc')));

  { Один изменённый символ обязан менять свёртку целиком. }
  Carrier.Claim(Keccak256(TextBytes('abc')) <> Keccak256(TextBytes('abd')),
                'keccak: one changed byte did not change the digest');

  { Длина ровно в блок и на байт больше: там живут ошибки дополнения. }
  SetLength(Long_, 136);
  for I := 0 to 135 do
    Long_[I] := Byte(I);
  Carrier.FeedWide(Keccak256(Long_));
  Carrier.Claim(Length(Keccak256(Long_)) = 64, 'keccak: digest is not 32 bytes');

  SetLength(Long_, 137);
  for I := 0 to 136 do
    Long_[I] := Byte(I);
  Carrier.FeedWide(Keccak256(Long_));

  SetLength(Long_, 135);
  for I := 0 to 134 do
    Long_[I] := Byte(I);
  Carrier.FeedWide(Keccak256(Long_));
end;

{ Тяжёлая свёртка: размер меняется от оборота, чтобы дополнение каждый раз
  попадало в другое место блока. }
procedure StageKeccakHeavy(Carrier: TResidentCarrier);
var
  Data: TBytes;
  Size, I: Integer;
  State: UInt64;
  Digest: string;
begin
  Size := 4096 + (Carrier.Lap mod 13) * 517;
  SetLength(Data, Size);
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 13 + Carrier.Lap)));
  for I := 0 to Size - 1 do
    Data[I] := Byte(ResidentNext(State) and $FF);

  Digest := Keccak256(Data);
  Carrier.FeedWide(Digest);
  Carrier.Feed(UInt64(Cardinal(Size)));
  Carrier.Claim(Length(Digest) = 64, 'keccak: digest length changed');
  { Повторный счёт того же входа обязан дать тот же ответ. }
  Carrier.Claim(Keccak256(Data) = Digest, 'keccak: not repeatable on the same input');
end;

{ Образующая и её кратные: всё обязано лежать на кривой, а удвоенная —
  совпасть с известными координатами. }
procedure StageCurveBasics(Carrier: TResidentCarrier);
var
  G2, G3, Sum, Neg, Zero: TPoint;
begin
  Carrier.Claim(OnCurve(BaseG), 'secp256k1: generator is not on the curve');

  G2 := AddPoints(BaseG, BaseG);
  Carrier.Claim(OnCurve(G2), 'secp256k1: doubled generator is not on the curve');
  Carrier.Claim(Compare(G2.X, FromHex(G2xHex)) = 0,
                'secp256k1: doubled generator x differs from the known value');
  Carrier.Claim(Compare(G2.Y, FromHex(G2yHex)) = 0,
                'secp256k1: doubled generator y differs from the known value');
  Carrier.FeedWide(ToHex(G2.X));

  { Сложение и удвоение обязаны сойтись: G+G, посчитанное как удвоение, и 2*G,
    посчитанное умножением на число. }
  G3 := MulPoint(BaseG, FromCardinal(2));
  Carrier.Claim(SamePoint(G2, G3), 'secp256k1: doubling disagrees with scalar 2');

  { Закон группы: точка плюс её противоположность даёт нейтральный элемент. }
  Neg := Negate(BaseG);
  Carrier.Claim(OnCurve(Neg), 'secp256k1: negated point left the curve');
  Zero := AddPoints(BaseG, Neg);
  Carrier.Claim(Zero.Infinity, 'secp256k1: P + (-P) is not the neutral element');

  { Нейтральный элемент ничего не меняет. }
  Sum := AddPoints(BaseG, Zero);
  Carrier.Claim(SamePoint(Sum, BaseG), 'secp256k1: adding neutral changed the point');

  { Переставимость сложения. }
  Sum := AddPoints(G2, BaseG);
  Carrier.Claim(SamePoint(Sum, AddPoints(BaseG, G2)),
                'secp256k1: addition is not commutative');
  Carrier.Claim(OnCurve(Sum), 'secp256k1: sum left the curve');
end;

{ Умножение на число: законы, которые обязаны выполняться при любом верном
  ответе, и на числах, разных на каждом заходе. }
procedure StageCurveScalar(Carrier: TResidentCarrier);
var
  K, M, Sum_: TLimbs;
  P1, P2, P3, Left, Right: TPoint;
  State: UInt64;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 5 + Carrier.Lap)));
  { Числа небольшие: каждое умножение точки — уже тысячи длинных делений, и
    полноразмерный скаляр сделал бы стадию непомерно тяжёлой. Кольцо считает
    цену каждой стадии на каждом обороте каждого носителя, поэтому вес держится
    в пределах десятых долей секунды, а не секунд. }
  K := FromCardinal(2 + Cardinal(ResidentNext(State) mod 24));
  M := FromCardinal(2 + Cardinal(ResidentNext(State) mod 24));

  P1 := MulPoint(BaseG, K);
  P2 := MulPoint(BaseG, M);
  Carrier.Claim(OnCurve(P1), 'secp256k1: k*G left the curve');
  Carrier.Claim(OnCurve(P2), 'secp256k1: m*G left the curve');

  { Распределительный закон: (k+m)*G = k*G + m*G. }
  Sum_ := Add(K, M);
  P3 := MulPoint(BaseG, Sum_);
  Left := AddPoints(P1, P2);
  Carrier.Claim(SamePoint(P3, Left), 'secp256k1: (k+m)*G <> k*G + m*G');
  Carrier.Feed(UInt64(Cardinal(BitLength(Sum_))));

  { Умножение на число, взятое дважды, даёт ту же точку. }
  Right := MulPoint(BaseG, K);
  Carrier.Claim(SamePoint(P1, Right), 'secp256k1: k*G is not repeatable');

  { Противоположная точка получается сменой знака числа относительно порядка.
    Скаляр здесь полноразмерный — двести пятьдесят шесть бит, — поэтому проверка
    идёт не каждый оборот: одно такое умножение стоит дороже всей остальной
    стадии вместе взятой. }
  if Carrier.Lap mod 8 = 0 then
  begin
    Left := MulPoint(BaseG, Sub(CurveOrder, K));
    Carrier.Claim(SamePoint(Left, Negate(P1)),
                  'secp256k1: (n-k)*G is not the negation of k*G');
    Carrier.Claim(AddPoints(P1, Left).Infinity,
                  'secp256k1: k*G + (n-k)*G is not the neutral element');
  end;
end;

{ Точка, накапливающаяся между оборотами: к ней прибавляется образующая, и на
  каждом обороте она обязана оставаться на кривой. }
procedure StageCurveRunning(Carrier: TResidentCarrier);
var
  Pocket: TResidentEthPocket;
begin
  Pocket := Carrier.PocketAs<TResidentEthPocket>('eth-running');
  if Pocket.FSteps = 0 then
  begin
    Pocket.FAcc.Infinity := True;
    Pocket.FAcc.X := nil;
    Pocket.FAcc.Y := nil;
  end;

  Pocket.FAcc := AddPoints(Pocket.FAcc, BaseG);
  Inc(Pocket.FSteps);

  Carrier.Claim(OnCurve(Pocket.FAcc), 'secp256k1: running point left the curve');
  { Накопленное сложение обязано совпасть с умножением на число шагов. }
  Carrier.Claim(SamePoint(Pocket.FAcc,
                          MulPoint(BaseG, FromUInt64(UInt64(Pocket.FSteps)))),
                'secp256k1: repeated addition disagrees with scalar multiply');
  Carrier.Feed(UInt64(Pocket.FSteps));
  if not Pocket.FAcc.Infinity then
    Carrier.FeedWide(ToHex(Pocket.FAcc.X));

  Inc(Pocket.FRounds);
  if Pocket.FSteps > 20 then
    Pocket.FSteps := 0;
end;

initialization
  FieldP := FromHex(FieldHex);
  CurveOrder := FromHex(OrderHex);
  BaseG.X := FromHex(GxHex);
  BaseG.Y := FromHex(GyHex);
  BaseG.Infinity := False;
  ResidentRegisterStage('eth-curve-basics', @StageCurveBasics);
  ResidentRegisterStage('eth-curve-running', @StageCurveRunning);
  ResidentRegisterStage('eth-curve-scalar', @StageCurveScalar);
  ResidentRegisterStage('eth-keccak-heavy', @StageKeccakHeavy);
  ResidentRegisterStage('eth-keccak-vectors', @StageKeccakVectors);

end.
