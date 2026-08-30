unit chimera_agg;

{ Орган «поглощение»: сделка втягивается в одну из двух предыдущих.

  Источник: `MoonBot/TradeTypes.pas`, `TTrade.TryAggregate`.
  Перенесено дословно по форме: метод записи с ДВУМЯ `var`-параметрами своего
  же типа, два составных предиката по четыре условия каждый, досрочный
  `Exit(True)` из середины и один `Result := False` в конце.

  Почему это отдельная форма, а не частный случай кольца:

    * оба предыдущих слота приходят по ССЫЛКЕ и оба того же типа, что и сам
      получатель. Ничто не мешает вызывателю передать одну и ту же запись
      дважды — в живом коде так и происходит на краю кольца, когда занят один
      слот. Значит компилятор не вправе считать `Prev1` и `Prev2`
      непересекающимися;
    * предикат из четырёх условий с коротким замыканием: сторож пустого слота,
      совпадение направления через бит знака, близость цены и близость
      времени. Оптимизатор волен переставлять и сворачивать — при условии, что
      количество вычислений каждого операнда не изменит наблюдаемого итога;
    * два досрочных выхода из середины плюс один обычный возврат — три разные
      дороги наружу из одного тела;
    * `-0.0` в количестве: модуль равен нулю, а бит знака стоит. Направление
      такой сделки — свойство представления, и живой код обязан обращаться с
      ней так же, как с обычной продажей.

  Оракул независим по построению: решение принимается таблицей условий,
  посчитанных ЗАРАНЕЕ и по-другому — направление сравнением с нулём, а не
  битом знака, — и без единого досрочного выхода. Сходятся обе стороны и по
  вердикту, и по тому, в какой слот легло количество. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body;

const
  { Шаг цены рынка: ближе этого сделки считаются идущими по одной цене. }
  ChiAggPriceStep = 0.0009;

type
  { Перенесённая форма живёт методом записи — как в оригинале. }
  TChiAgg = record helper for TChiTrade
    function TryAggregate(var Prev1, Prev2: TChiTrade;
      const PriceStep: Double): Boolean;
  end;

function ChiAggRun: Int64;

implementation

function TChiAgg.TryAggregate(var Prev1, Prev2: TChiTrade;
  const PriceStep: Double): Boolean;
begin
  if (Prev1.Time > 1) and SameDirection(Prev1)
     and (Abs(Prev1.Price - Price) < PriceStep)
     and (Abs(Prev1.Time - Time) < ChiSameTime) then
  begin
    Prev1.Qty := Prev1.Qty + Qty;
    Exit(True);
  end;
  if (Prev2.Time > 1) and SameDirection(Prev2)
     and (Abs(Prev2.Price - Price) < PriceStep)
     and (Abs(Prev2.Time - Time) < ChiSameTime) then
  begin
    Prev2.Qty := Prev2.Qty + Qty;
    Exit(True);
  end;
  Result := False;
end;

{ ═══ Независимый оракул ══════════════════════════════════════════════════

  Ни методов записи, ни досрочных выходов, ни бита знака. Все четыре условия
  каждого слота считаются заранее и складываются в число, а решение
  принимается по этому числу. Куда лечь количеству — отдельный ответ, а не
  побочное действие. }

type
  TChiAggVerdict = (avMiss, avFirst, avSecond);

function Fits(const Slot, T: TChiTrade; PriceStep: Double): Boolean;
var
  Filled, Direction, Near, Fresh: Boolean;
begin
  Filled := Slot.Time > 1;
  { Направление — сравнением с нулём, а не битом знака. Ноль со знаком минус
    сравнением НЕ отличается от обычного нуля, поэтому здесь он разбирается
    явно: это единственный способ повторить решение бита знака, не заглядывая
    в биты. }
  Direction := ((Slot.Qty < 0) or ((Slot.Qty = 0) and (1 / Slot.Qty < 0)))
               = ((T.Qty < 0) or ((T.Qty = 0) and (1 / T.Qty < 0)));
  Near := Abs(Slot.Price - T.Price) < PriceStep;
  Fresh := Abs(Slot.Time - T.Time) < ChiSameTime;
  Result := Filled and Direction and Near and Fresh;
end;

function Decide(const P1, P2, T: TChiTrade;
  PriceStep: Double): TChiAggVerdict;
begin
  if Fits(P1, T, PriceStep) then
    Result := avFirst
  else if Fits(P2, T, PriceStep) then
    Result := avSecond
  else
    Result := avMiss;
end;

{ ═══ Наборы ══════════════════════════════════════════════════════════════

  Каждый случай заведён ради своей ветви: попадание в первый слот, во второй,
  промах по каждому из четырёх условий по отдельности, пустой слот, ноль со
  знаком и совпадение обоих слотов в одну переменную. }

const
  IdAgg = 'CHI-MB-TRADE-002';
  BaseTime = 45000.0;

function Trade(TimeOffsetMs, PriceDelta: Double; Qty: Single): TChiTrade;
begin
  Result.Time := BaseTime + TimeOffsetMs / (ChiSecsPerDay * 1000.0);
  Result.Price := 1.0 + PriceDelta;
  Result.Qty := Qty;
end;

function Empty: TChiTrade;
begin
  { Пустой слот: время меньше единицы — сторож оригинала. }
  Result.Time := 0;
  Result.Price := 0;
  Result.Qty := 0;
end;

procedure Case1(var P1, P2, T: TChiTrade; Kind: Integer);
begin
  P1 := Trade(0, 0, 10);
  P2 := Trade(0, 0, 20);
  case Kind of
    0: T := Trade(10, 0.0001, 5);            { попадание в первый }
    1: begin                                  { первый не подходит по цене }
         P1 := Trade(0, 0.01, 10);
         T := Trade(10, 0.0001, 5);
       end;
    2: begin                                  { первый другого направления }
         P1 := Trade(0, 0, -10);
         T := Trade(10, 0.0001, 5);
       end;
    3: begin                                  { первый слишком стар }
         P1 := Trade(-500, 0, 10);
         T := Trade(10, 0.0001, 5);
       end;
    4: begin                                  { первый пуст }
         P1 := Empty;
         T := Trade(10, 0.0001, 5);
       end;
    5: begin                                  { не подходит ни один }
         P1 := Trade(0, 0.01, 10);
         P2 := Trade(0, 0.02, 20);
         T := Trade(10, 0.0001, 5);
       end;
    6: begin                                  { оба пусты }
         P1 := Empty;
         P2 := Empty;
         T := Trade(10, 0.0001, 5);
       end;
    7: begin                                  { ноль со знаком минус }
         P1 := Trade(0, 0, -0.0);
         P2 := Trade(0, 0, 20);
         T := Trade(10, 0.0001, -5);
       end;
    8: begin                                  { ровно на границе цены }
         P1 := Trade(0, ChiAggPriceStep, 10);
         T := Trade(10, 0, 5);
       end;
    9: begin                                  { ровно на границе времени }
         P1 := Trade(-200, 0, 10);
         T := Trade(0, 0.0001, 5);
       end;
  end;
end;

function ChiAggRun: Int64;
var
  Kind, Rounds: Integer;
  P1, P2, T, O1, O2: TChiTrade;
  Got: Boolean;
  Want: TChiAggVerdict;
  Acc: UInt64;
  Aliased: TChiTrade;
  AliasHit: Boolean;
  Hits1, Hits2, Misses: Int64;
begin
  ChiCovered(IdAgg);
  Acc := ChiOffset;
  Hits1 := 0; Hits2 := 0; Misses := 0;

  for Kind := 0 to 9 do
  begin
    Case1(P1, P2, T, Kind);
    O1 := P1;
    O2 := P2;
    Want := Decide(P1, P2, T, ChiAggPriceStep);

    Got := T.TryAggregate(P1, P2, ChiAggPriceStep);

    ChiClaim(Got = (Want <> avMiss),
      'поглощение: вердикт разошёлся с оракулом, случай ' + IntToStr(Kind));

    { Куда легло количество — отдельная проверка: вердикт мог совпасть, а
      слот оказаться не тот. }
    case Want of
      avFirst:
        begin
          ChiClaim(PInteger(@P1.Qty)^ <> PInteger(@O1.Qty)^,
            'поглощение: первый слот не изменился, случай ' + IntToStr(Kind));
          ChiClaim(PInteger(@P2.Qty)^ = PInteger(@O2.Qty)^,
            'поглощение: тронут второй слот, случай ' + IntToStr(Kind));
          Inc(Hits1);
          ChiBranch(IdAgg, 'hit-first');
        end;
      avSecond:
        begin
          ChiClaim(PInteger(@P1.Qty)^ = PInteger(@O1.Qty)^,
            'поглощение: тронут первый слот, случай ' + IntToStr(Kind));
          ChiClaim(PInteger(@P2.Qty)^ <> PInteger(@O2.Qty)^,
            'поглощение: второй слот не изменился, случай ' + IntToStr(Kind));
          Inc(Hits2);
          ChiBranch(IdAgg, 'hit-second');
        end;
      avMiss:
        begin
          ChiClaim((PInteger(@P1.Qty)^ = PInteger(@O1.Qty)^)
                   and (PInteger(@P2.Qty)^ = PInteger(@O2.Qty)^),
            'поглощение: промах изменил слот, случай ' + IntToStr(Kind));
          Inc(Misses);
          ChiBranch(IdAgg, 'miss');
        end;
    end;

    Acc := ChiMix(Acc, Ord(Want));
    Acc := ChiMix(Acc, PInteger(@P1.Qty)^);
    Acc := ChiMix(Acc, PInteger(@P2.Qty)^);
  end;

  ChiClaim(Hits1 > 0, 'поглощение: первый слот ни разу не сработал');
  ChiClaim(Hits2 > 0, 'поглощение: второй слот ни разу не сработал');
  ChiClaim(Misses > 0, 'поглощение: промаха ни разу не было');

  { Оба слота — одна и та же запись. В живом коде так выходит на краю кольца.
    Компилятор не вправе считать `var`-параметры непересекающимися: попадание
    обязано случиться в первый же слот, и второй предикат вообще не считается. }
  Aliased := Trade(0, 0, 10);
  T := Trade(10, 0.0001, 5);
  AliasHit := T.TryAggregate(Aliased, Aliased, ChiAggPriceStep);
  ChiClaim(AliasHit, 'поглощение: совпавшие слоты не сработали');
  ChiClaim(Aliased.Qty = 15,
    'поглощение: совпавшие слоты сложили количество не один раз');
  ChiBranch(IdAgg, 'aliased-slots');
  Acc := ChiMix(Acc, PInteger(@Aliased.Qty)^);

  { Ноль со знаком: модуль нулевой, направление — продажа. }
  T := Trade(0, 0, -0.0);
  ChiClaim(not T.IsBuy, 'поглощение: ноль со знаком минус прочитан как покупка');
  ChiClaim(T.Quantity = 0, 'поглощение: модуль нуля не ноль');
  ChiBranch(IdAgg, 'negative-zero');

  { Повторное поглощение в один слот: количество обязано накапливаться, а не
    замещаться. }
  P1 := Trade(0, 0, 10);
  P2 := Empty;
  for Rounds := 1 to 5 do
  begin
    T := Trade(10, 0.0001, 2);
    ChiClaim(T.TryAggregate(P1, P2, ChiAggPriceStep),
      'поглощение: повторное не сработало');
  end;
  ChiClaim(P1.Qty = 20, 'поглощение: количество не накопилось');
  ChiBranch(IdAgg, 'repeat-into-first');
  Acc := ChiMix(Acc, PInteger(@P1.Qty)^);

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
