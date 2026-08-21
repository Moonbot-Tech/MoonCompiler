unit resident_bignum;

{ Длинная целая арифметика — и как тяжёлый расчёт, и как груз для кольца.

  Зачем она здесь. Прочие семейства спрашивают у компилятора короткие вопросы:
  два-три действия, и ответ. Тут вопрос длинный: умножение столбиком и деление
  с восстановлением — это тысячи зависимых операций с переносами, заёмами,
  нормализацией и коррекцией пробного частного. У оптимизатора появляется повод
  переставлять, разворачивать, держать в регистрах и выталкивать на стек — а
  значит появляется и место для ошибки, которого в коротком коде просто нет.

  Оракулы здесь не нуждаются в эталоне: их даёт сама математика.

    * `(a * b) div b = a` и остаток ноль;
    * `(a div b) * b + (a mod b) = a` — договор деления, самый строгий из всех:
      он завязывает частное, остаток и делимое разом;
    * `0 <= a mod b < b` — остаток обязан лежать в берегах;
    * `a * b = b * a`;
    * `(a + b) - b = a`;
    * малая теорема Ферма: `a^(p-1) mod p = 1` для простого `p`, не делящего
      `a`. Это оракул на возведение в степень по модулю, который проверяет
      тысячи умножений и делений одним равенством.

  Ни одно число не берётся из таблицы «правильных ответов»: каждый заход считает
  ДРУГОЕ — разрядность, значения и делители зависят от оборота и от носителя.
  Повторять одну задачу тысячу раз бессмысленно, задача должна быть новой.

  Реализация своя целиком. Чужой код принёс бы чужие ошибки, а слой, который
  сам неисправен, не имеет права обвинять компилятор. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{ Проверка границ здесь включена нарочно, в отличие от прочих юнитов слоя.
  Длинная арифметика — самое густое место по индексам во всей программе:
  окна деления, переносы через край лимба, сдвиги через границу. Тихий выход за
  край дал бы неверное число вместо отказа, а отказ стадии кольцо переживает и
  называет виновную. }
{$Q-}{$R+}

interface

uses
  SysUtils, Classes, Generics.Collections, resident_core;

type
  { Число хранится лимбами по 32 бита, младший первым. Промежуток умножения и
    деления считается в 64 битах — там, где перенос обязан помещаться целиком. }
  TLimbs = System.TArray<Cardinal>;

{ Арифметика открыта наружу нарочно: длинное деление — самый ветвистый кусок во
  всём слое, и его нужно уметь допрашивать отдельно от кольца, подавая ровно тот
  вход, на котором что-то пошло не так. }
function IsZero(const A: TLimbs): Boolean;
function FromCardinal(Value: Cardinal): TLimbs;
function FromUInt64(Value: UInt64): TLimbs;
function Compare(const A, B: TLimbs): Integer;
function Add(const A, B: TLimbs): TLimbs;
function Sub(const A, B: TLimbs): TLimbs;
function Mul(const A, B: TLimbs): TLimbs;
function ShlBits(const A: TLimbs; Bits: Integer): TLimbs;
function ShrBits(const A: TLimbs; Bits: Integer): TLimbs;
function BitLength(const A: TLimbs): Integer;
procedure DivMod(const A, B: TLimbs; out Q, R: TLimbs);
function PowMod(const Base, Exp_, Modulus: TLimbs): TLimbs;
function ToHex(const A: TLimbs): string;
function FromHex(const S: string): TLimbs;

implementation

type
  TResidentBigPocket = class(TResidentPocket)
  private
    FRunning: TLimbs;      { накопитель, живущий между оборотами }
    FSteps: Int64;
    FRounds: Int64;
  end;

{ Убрать ведущие нули: у числа обязано быть единственное представление, иначе
  сравнение и проверки на ноль перестают работать. }
procedure Trim(var A: TLimbs);
var
  N: Integer;
begin
  N := Length(A);
  while (N > 0) and (A[N - 1] = 0) do
    Dec(N);
  SetLength(A, N);
end;

function IsZero(const A: TLimbs): Boolean;
begin
  Result := Length(A) = 0;
end;

function FromCardinal(Value: Cardinal): TLimbs;
begin
  if Value = 0 then
    Exit(nil);
  SetLength(Result, 1);
  Result[0] := Value;
end;

function FromUInt64(Value: UInt64): TLimbs;
begin
  if Value = 0 then
    Exit(nil);
  if Value <= $FFFFFFFF then
  begin
    SetLength(Result, 1);
    Result[0] := Cardinal(Value);
  end
  else
  begin
    SetLength(Result, 2);
    Result[0] := Cardinal(Value and $FFFFFFFF);
    Result[1] := Cardinal(Value shr 32);
  end;
end;

{ Сравнение: сперва по длине, потом со старшего лимба. }
function Compare(const A, B: TLimbs): Integer;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
  begin
    if Length(A) < Length(B) then
      Exit(-1)
    else
      Exit(1);
  end;
  for I := High(A) downto 0 do
    if A[I] <> B[I] then
    begin
      if A[I] < B[I] then
        Exit(-1)
      else
        Exit(1);
    end;
  Result := 0;
end;

function Add(const A, B: TLimbs): TLimbs;
var
  I, N: Integer;
  Carry, Sum: UInt64;
begin
  N := Length(A);
  if Length(B) > N then
    N := Length(B);
  SetLength(Result, N + 1);
  Carry := 0;
  for I := 0 to N - 1 do
  begin
    Sum := Carry;
    if I < Length(A) then
      Sum := Sum + A[I];
    if I < Length(B) then
      Sum := Sum + B[I];
    Result[I] := Cardinal(Sum and $FFFFFFFF);
    Carry := Sum shr 32;
  end;
  Result[N] := Cardinal(Carry);
  Trim(Result);
end;

{ Вычитание в предположении A >= B: вызывающая сторона обязана это обеспечить,
  и обеспечивает — иначе заём ушёл бы за край. }
function Sub(const A, B: TLimbs): TLimbs;
var
  I: Integer;
  Borrow, Left, Right: UInt64;
begin
  SetLength(Result, Length(A));
  Borrow := 0;
  for I := 0 to High(A) do
  begin
    Left := A[I];
    Right := Borrow;
    if I < Length(B) then
      Right := Right + B[I];
    if Left >= Right then
    begin
      Result[I] := Cardinal(Left - Right);
      Borrow := 0;
    end
    else
    begin
      Result[I] := Cardinal((Left + UInt64($100000000)) - Right);
      Borrow := 1;
    end;
  end;
  Trim(Result);
end;

{ Умножение столбиком: каждый лимб на каждый, перенос идёт вверх по колонке. }
function Mul(const A, B: TLimbs): TLimbs;
var
  I, J: Integer;
  Carry, Cur: UInt64;
begin
  if IsZero(A) or IsZero(B) then
    Exit(nil);
  SetLength(Result, Length(A) + Length(B));
  { Обнуление обязательно и не является перестраховкой. Столбик копит суммы
    прямо в Result, то есть читает его перед записью; а результат функции
    компилятор вправе разместить в переменной, которая уже что-то содержала —
    в приёмнике присваивания или в переиспользованной временной. SetLength
    старые элементы не стирает, и накопление пошло бы поверх чужих данных. }
  for I := 0 to High(Result) do
    Result[I] := 0;
  for I := 0 to High(A) do
  begin
    Carry := 0;
    for J := 0 to High(B) do
    begin
      Cur := UInt64(A[I]) * UInt64(B[J]) + Result[I + J] + Carry;
      Result[I + J] := Cardinal(Cur and $FFFFFFFF);
      Carry := Cur shr 32;
    end;
    { Хвостовой перенос обязан дойти до конца, сколько бы лимбов ни занял. }
    J := I + Length(B);
    while Carry <> 0 do
    begin
      Cur := Result[J] + Carry;
      Result[J] := Cardinal(Cur and $FFFFFFFF);
      Carry := Cur shr 32;
      Inc(J);
    end;
  end;
  Trim(Result);
end;

function ShlLimbs(const A: TLimbs; Count: Integer): TLimbs;
var
  I: Integer;
begin
  if IsZero(A) or (Count = 0) then
    Exit(System.Copy(A, 0, Length(A)));
  SetLength(Result, Length(A) + Count);
  for I := 0 to High(A) do
    Result[I + Count] := A[I];
  Trim(Result);
end;

{ Сдвиг влево на неполный лимб: биты переезжают через границу, и это то место,
  где легче всего потерять старший разряд. }
function ShlBits(const A: TLimbs; Bits: Integer): TLimbs;
var
  I: Integer;
  Carry, Cur: UInt64;
begin
  if IsZero(A) or (Bits = 0) then
    Exit(System.Copy(A, 0, Length(A)));
  SetLength(Result, Length(A) + 1);
  Carry := 0;
  for I := 0 to High(A) do
  begin
    Cur := (UInt64(A[I]) shl Bits) or Carry;
    Result[I] := Cardinal(Cur and $FFFFFFFF);
    Carry := Cur shr 32;
  end;
  Result[High(Result)] := Cardinal(Carry);
  Trim(Result);
end;

function ShrBits(const A: TLimbs; Bits: Integer): TLimbs;
var
  I: Integer;
  Carry, Cur: UInt64;
begin
  if IsZero(A) or (Bits = 0) then
    Exit(System.Copy(A, 0, Length(A)));
  SetLength(Result, Length(A));
  Carry := 0;
  for I := High(A) downto 0 do
  begin
    Cur := (Carry shl 32) or A[I];
    Result[I] := Cardinal(Cur shr Bits);
    Carry := Cur and ((UInt64(1) shl Bits) - 1);
  end;
  Trim(Result);
end;

function BitLength(const A: TLimbs): Integer;
var
  Top: Cardinal;
begin
  if IsZero(A) then
    Exit(0);
  Result := (Length(A) - 1) * 32;
  Top := A[High(A)];
  while Top <> 0 do
  begin
    Inc(Result);
    Top := Top shr 1;
  end;
end;

{ Деление с остатком, столбиком по лимбам.

  Схема классическая: делимое нормализуется сдвигом так, чтобы старший лимб
  делителя был не меньше половины основания — тогда пробное частное ошибается
  не более чем на единицу, и одной коррекции достаточно. Именно здесь живут
  самые злые ветвления во всём семействе: оценка по двум старшим лимбам,
  проверка на переоценку, вычитание со сдвигом и возврат заёма. }
procedure DivMod(const A, B: TLimbs; out Q, R: TLimbs);
var
  Shift, N, M, I, J: Integer;
  Dividend, Divisor, U, V, Part, Trial: TLimbs;
  Top, Guess, Rem: UInt64;
begin
  { Свои копии входа берутся ДО того, как тронуты выходные ссылки. Вызывающая
    сторона вправе передать ту же переменную и входом, и выходом — так короче
    пишется возведение в степень по модулю, — а обнуление `out`-параметра
    съело бы вход прямо перед чтением. Копия снимает вопрос целиком. }
  Dividend := System.Copy(A, 0, Length(A));
  Divisor := System.Copy(B, 0, Length(B));
  Q := nil;
  R := nil;
  if IsZero(Divisor) then
    raise EDivByZero.Create('resident: division by zero');
  if Compare(Dividend, Divisor) < 0 then
  begin
    R := Dividend;
    Exit;
  end;

  { Однолимбовый делитель: длинная схема тут ни к чему, и короткая дорога тоже
    обязана быть проверена. }
  if Length(Divisor) = 1 then
  begin
    SetLength(Q, Length(Dividend));
    Rem := 0;
    for I := High(Dividend) downto 0 do
    begin
      Rem := (Rem shl 32) or Dividend[I];
      Q[I] := Cardinal(Rem div Divisor[0]);
      Rem := Rem mod Divisor[0];
    end;
    Trim(Q);
    R := FromUInt64(Rem);
    Exit;
  end;

  { Нормализация: старший лимб делителя загоняется в верхнюю половину. }
  Shift := 0;
  Top := Divisor[High(Divisor)];
  while (Top and $80000000) = 0 do
  begin
    Top := Top shl 1;
    Inc(Shift);
  end;
  U := ShlBits(Dividend, Shift);
  V := ShlBits(Divisor, Shift);

  N := Length(V);
  M := Length(U) - N;
  if M < 0 then
    M := 0;
  SetLength(U, Length(U) + 1);
  SetLength(Q, M + 1);

  for J := M downto 0 do
  begin
    { Пробное частное по двум старшим лимбам текущего окна. }
    Top := (UInt64(U[J + N]) shl 32) or U[J + N - 1];
    Guess := Top div V[N - 1];
    if Guess > $FFFFFFFF then
      Guess := $FFFFFFFF;

    { Уточнение: пока произведение больше окна, частное уменьшается. Больше
      двух шагов здесь не бывает — это и обеспечила нормализация. }
    repeat
      SetLength(Trial, 1);
      Trial[0] := Cardinal(Guess);
      Trim(Trial);
      Part := Mul(V, Trial);

      { Окно делимого: N+1 лимб, начиная с J. }
      SetLength(R, N + 1);
      for I := 0 to N do
        R[I] := U[J + I];
      Trim(R);

      if Compare(Part, R) > 0 then
        Dec(Guess)
      else
        Break;
    until Guess = 0;

    if Guess > 0 then
    begin
      { Part и окно уже посчитаны уточняющим циклом ровно для этого Guess. }
      R := Sub(R, Part);
      { Остаток окна возвращается на место, старшие позиции обнуляются. }
      for I := 0 to N do
        if I < Length(R) then
          U[J + I] := R[I]
        else
          U[J + I] := 0;
    end;
    Q[J] := Cardinal(Guess);
  end;

  Trim(Q);
  { Остаток — то, что осталось в делимом, со снятой нормализацией. }
  Trim(U);
  R := ShrBits(U, Shift);
end;

{ Возведение в степень по модулю: квадрат-и-умножение слева направо. Каждый шаг
  тянет за собой полное умножение и полное деление, поэтому одно такое
  вычисление — это уже десятки тысяч операций с переносами. }
function PowMod(const Base, Exp_, Modulus: TLimbs): TLimbs;
var
  Acc, B, Q, Rest: TLimbs;
  Bits, I: Integer;
begin
  if IsZero(Modulus) then
    raise EDivByZero.Create('resident: modulus is zero');
  Acc := FromCardinal(1);
  DivMod(Base, Modulus, Q, B);
  Bits := BitLength(Exp_);
  for I := Bits - 1 downto 0 do
  begin
    { Остаток забирается в ОТДЕЛЬНУЮ переменную и только потом становится
      накопителем. Передать одну переменную и входом, и выходом нельзя:
      обнуляет её перед вызовом, то есть вход исчезает раньше, чем процедура
      успевает его прочитать. Это свойство самого способа передачи, а не чья-то
      небрежность, и обойти его изнутри процедуры невозможно. }
    Acc := Mul(Acc, Acc);
    DivMod(Acc, Modulus, Q, Rest);
    Acc := Rest;
    if (Exp_[I div 32] shr (I mod 32)) and 1 = 1 then
    begin
      Acc := Mul(Acc, B);
      DivMod(Acc, Modulus, Q, Rest);
      Acc := Rest;
    end;
  end;
  Result := Acc;
end;

function ToHex(const A: TLimbs): string;
var
  I: Integer;
begin
  if IsZero(A) then
    Exit('0');
  Result := '';
  for I := High(A) downto 0 do
    if I = High(A) then
      Result := IntToHex(A[I], 1)
    else
      Result := Result + IntToHex(A[I], 8);
end;

function FromHex(const S: string): TLimbs;
var
  I, Digit, Bit: Integer;
  Value: Cardinal;
begin
  Result := nil;
  SetLength(Result, (Length(S) + 7) div 8);
  for I := 0 to High(Result) do
    Result[I] := 0;
  Bit := 0;
  for I := Length(S) downto 1 do
  begin
    case S[I] of
      '0' .. '9': Digit := Ord(S[I]) - Ord('0');
      'A' .. 'F': Digit := Ord(S[I]) - Ord('A') + 10;
      'a' .. 'f': Digit := Ord(S[I]) - Ord('a') + 10;
    else
      Digit := 0;
    end;
    Value := Cardinal(Digit) shl ((Bit mod 8) * 4);
    Result[Bit div 8] := Result[Bit div 8] or Value;
    Inc(Bit);
  end;
  Trim(Result);
end;

{ Число, зависящее от носителя и оборота: каждый заход считает ДРУГОЕ. }
function MakeNumber(Carrier: TResidentCarrier; Salt, Limbs: Integer): TLimbs;
var
  State: UInt64;
  I: Integer;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 31 + Carrier.Lap * 7 + Salt)));
  SetLength(Result, Limbs);
  for I := 0 to Limbs - 1 do
    Result[I] := Cardinal(ResidentNext(State) and $FFFFFFFF);
  { Старший лимб не должен быть нулём, иначе разрядность окажется меньше
    заказанной и задача незаметно измельчает. }
  if Result[Limbs - 1] = 0 then
    Result[Limbs - 1] := $80000001;
  Trim(Result);
end;

procedure FeedNumber(Carrier: TResidentCarrier; const A: TLimbs);
var
  I: Integer;
begin
  Carrier.Feed(UInt64(Cardinal(Length(A))));
  for I := 0 to High(A) do
    Carrier.Feed(UInt64(A[I]));
end;

{ ------------------------------------------------------------- стадии ----- }

{ Договор деления: частное, остаток и делимое обязаны сойтись в одном равенстве,
  а остаток — лежать в берегах. }
procedure StageDivisionContract(Carrier: TResidentCarrier);
var
  A, B, Q, R, Back: TLimbs;
  Size: Integer;
begin
  { Размер задачи меняется от оборота: то короткий делитель, то длинный. }
  Size := 2 + (Carrier.Lap mod 7);
  A := MakeNumber(Carrier, 1, Size + 3);
  B := MakeNumber(Carrier, 2, Size);

  DivMod(A, B, Q, R);
  FeedNumber(Carrier, Q);
  FeedNumber(Carrier, R);

  { (a div b) * b + (a mod b) = a }
  Back := Add(Mul(Q, B), R);
  Carrier.Claim(Compare(Back, A) = 0, 'division contract: q*b+r <> a');
  { 0 <= r < b }
  Carrier.Claim(Compare(R, B) < 0, 'remainder not smaller than divisor');
  Carrier.Feed(UInt64(Cardinal(BitLength(A))));
  Carrier.Feed(UInt64(Cardinal(BitLength(B))));
  Carrier.Feed(UInt64(Cardinal(BitLength(Q))));
end;

{ Умножение и деление — взаимно обратные: произведение, поделённое на
  сомножитель, обязано дать второй сомножитель и нулевой остаток. }
procedure StageRoundTrip(Carrier: TResidentCarrier);
var
  A, B, P, Q, R: TLimbs;
begin
  A := MakeNumber(Carrier, 3, 2 + (Carrier.Lap mod 5));
  B := MakeNumber(Carrier, 4, 2 + (Carrier.Serial mod 4));

  P := Mul(A, B);
  FeedNumber(Carrier, P);

  DivMod(P, B, Q, R);
  Carrier.Claim(Compare(Q, A) = 0, 'product divided by factor lost the other factor');
  Carrier.Feed(UInt64(Ord(IsZero(R))));

  DivMod(P, A, Q, R);
  Carrier.Claim(Compare(Q, B) = 0, 'product divided by factor lost the other factor');
  Carrier.Feed(UInt64(Ord(IsZero(R))));

  { Умножение переставимо. }
  Carrier.Claim(Compare(Mul(A, B), Mul(B, A)) = 0, 'multiplication not commutative');
  { Сложение и вычитание тоже. }
  Carrier.Claim(Compare(Sub(Add(A, B), B), A) = 0, 'add then subtract lost the value');
end;

{ Сдвиги: умножение на степень двойки обязано совпасть со сдвигом, а сдвиг
  туда-обратно — вернуть исходное. }
procedure StageShifts(Carrier: TResidentCarrier);
var
  A, Shifted, Back, Factor: TLimbs;
  Bits: Integer;
begin
  A := MakeNumber(Carrier, 5, 2 + (Carrier.Lap mod 6));
  Bits := 1 + (Carrier.Lap mod 31);

  Shifted := ShlBits(A, Bits);
  FeedNumber(Carrier, Shifted);
  Carrier.Feed(UInt64(Cardinal(BitLength(Shifted) - BitLength(A))));
  Carrier.Feed(UInt64(Ord(BitLength(Shifted) = BitLength(A) + Bits)));

  Back := ShrBits(Shifted, Bits);
  Carrier.Claim(Compare(Back, A) = 0, 'division contract: q*b+r <> a');

  { Сдвиг на N — то же, что умножение на 2^N. }
  Factor := ShlBits(FromCardinal(1), Bits);
  Carrier.Feed(UInt64(Ord(Compare(Mul(A, Factor), Shifted) = 0)));

  { Сдвиг на целые лимбы — та же проверка другой дорогой. }
  Shifted := ShlLimbs(A, 2);
  Carrier.Feed(UInt64(Ord(BitLength(Shifted) = BitLength(A) + 64)));
  Carrier.Feed(UInt64(Ord(Compare(ShrBits(Shifted, 64), A) = 0)));
end;

{ Малая теорема Ферма: для простого p и не делящегося на него a обязано
  выполняться a^(p-1) mod p = 1. Одно равенство проверяет тысячи умножений и
  делений внутри возведения в степень. }
procedure StageFermat(Carrier: TResidentCarrier);
const
  { Простые числа, помещающиеся в лимб с запасом: заход берёт разное. }
  Primes: array[0 .. 7] of Cardinal =
    (2147483647, 999999937, 1000000007, 1000000009,
     2147483629, 999999893, 1000000021, 2147483587);
var
  P, A, Exp_, Got, Q, R: TLimbs;
  Which: Integer;
begin
  Which := (Carrier.Lap + Carrier.Serial) mod Length(Primes);
  P := FromCardinal(Primes[Which]);
  A := MakeNumber(Carrier, 6, 2);

  { Основание приводится по модулю и не должно оказаться нулём. }
  DivMod(A, P, Q, R);
  if IsZero(R) then
    R := FromCardinal(3);
  A := R;

  Exp_ := Sub(P, FromCardinal(1));
  Got := PowMod(A, Exp_, P);

  FeedNumber(Carrier, Got);
  Carrier.Claim(Compare(Got, FromCardinal(1)) = 0, 'fermat: a^(p-1) mod p <> 1');
  Carrier.Feed(UInt64(Cardinal(Which)));
  Carrier.Feed(UInt64(Primes[Which]));
end;

{ Запись числа шестнадцатеричной строкой и разбор обратно: строка едет через
  обычный строковый буфер, значит по дороге успевает попасть под управление
  памятью. }
procedure StageHexRoundTrip(Carrier: TResidentCarrier);
var
  A, Back: TLimbs;
  Text: string;
begin
  A := MakeNumber(Carrier, 7, 1 + (Carrier.Lap mod 8));
  Text := ToHex(A);
  Carrier.FeedWide(Text);
  Carrier.Feed(UInt64(Cardinal(Length(Text))));

  Back := FromHex(Text);
  Carrier.Claim(Compare(Back, A) = 0, 'division contract: q*b+r <> a');
  Carrier.Feed(UInt64(Ord(ToHex(Back) = Text)));

  { Ноль записывается и читается особым образом — проверяется отдельно. }
  Carrier.Feed(UInt64(Ord(ToHex(nil) = '0')));
  Carrier.Feed(UInt64(Ord(IsZero(FromHex('0')))));
end;

{ Расчёт, размазанный по кольцу: на каждом обороте делается один шаг, состояние
  живёт в кармане носителя и переезжает между потоками вместе с ним. Итог
  проверяется инвариантом через десятки оборотов — то есть длинное вычисление
  обязано пережить все пересадки, переезды памяти и смены владельца. }
procedure StageRunningProduct(Carrier: TResidentCarrier);
var
  Pocket: TResidentBigPocket;
  Factor, Q, R: TLimbs;
begin
  Pocket := Carrier.PocketAs<TResidentBigPocket>('bignum-running');
  if Length(Pocket.FRunning) = 0 then
  begin
    Pocket.FRunning := FromCardinal(1);
    Pocket.FSteps := 0;
  end;

  { Шаг: домножаем накопитель на очередной множитель. }
  Factor := FromCardinal(Cardinal(2 + (Pocket.FSteps mod 97)));
  Pocket.FRunning := Mul(Pocket.FRunning, Factor);
  Inc(Pocket.FSteps);

  { Инвариант на каждом шаге: деление на только что применённый множитель
    обязано вернуть предыдущее состояние без остатка. }
  DivMod(Pocket.FRunning, Factor, Q, R);
  Carrier.Feed(UInt64(Ord(IsZero(R))));
  Carrier.Feed(UInt64(Cardinal(BitLength(Pocket.FRunning))));
  Carrier.Feed(UInt64(Pocket.FSteps));

  { Накопитель растёт, пока не станет тяжёлым, потом начинает жизнь заново:
    за прогон случается и рост до сотен лимбов, и полный сброс. }
  if BitLength(Pocket.FRunning) > 4096 then
  begin
    FeedNumber(Carrier, Pocket.FRunning);
    Pocket.FRunning := FromCardinal(1);
    Pocket.FSteps := 0;
  end;
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

{ Сложение и вычитание на границах лимбов: перенос обязан пройти через всю
  цепочку единиц, а заём — через всю цепочку нулей. }
procedure StageCarryChain(Carrier: TResidentCarrier);
var
  Ones, One, Sum, Back: TLimbs;
  I, Size: Integer;
begin
  Size := 2 + (Carrier.Lap mod 9);
  SetLength(Ones, Size);
  for I := 0 to Size - 1 do
    Ones[I] := $FFFFFFFF;
  One := FromCardinal(1);

  { Перенос обязан пройти насквозь и родить новый лимб. }
  Sum := Add(Ones, One);
  Carrier.Feed(UInt64(Cardinal(Length(Sum))));
  Carrier.Feed(UInt64(Ord(Length(Sum) = Size + 1)));
  Carrier.Feed(UInt64(Sum[High(Sum)]));
  for I := 0 to Size - 1 do
    Carrier.Feed(UInt64(Sum[I]));

  { Заём обязан пройти обратно и убрать лимб. }
  Back := Sub(Sum, One);
  Carrier.Feed(UInt64(Ord(Compare(Back, Ones) = 0)));
  Carrier.Feed(UInt64(Cardinal(Length(Back))));

  { Умножение цепочки единиц само на себя — проверка переносов в столбике. }
  Sum := Mul(Ones, Ones);
  Carrier.Feed(UInt64(Cardinal(Length(Sum))));
  Carrier.Feed(UInt64(Cardinal(BitLength(Sum))));
  Carrier.Feed(UInt64(Ord(BitLength(Sum) = Size * 64)));
end;

initialization
  ResidentRegisterStage('bignum-carry-chain', @StageCarryChain);
  ResidentRegisterStage('bignum-division-contract', @StageDivisionContract);
  ResidentRegisterStage('bignum-fermat', @StageFermat);
  ResidentRegisterStage('bignum-hex-roundtrip', @StageHexRoundTrip);
  ResidentRegisterStage('bignum-round-trip', @StageRoundTrip);
  ResidentRegisterStage('bignum-running-product', @StageRunningProduct);
  ResidentRegisterStage('bignum-shifts', @StageShifts);

end.
