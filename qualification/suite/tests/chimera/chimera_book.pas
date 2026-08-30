unit chimera_book;

{ Орган «стакан»: пересборка стакана и достройка его дальних уровней.

  Источники: `MoonBot/MarketsU.pas` — `TMarket.HandleGlass`
  (свёртка стен) и `BitGetEngine.pas` — `HandleBookChain` (полный снимок и
  достройка уровней из второго источника). Перенесено дословно по форме:

    * полный снимок кладётся `SetLength` плюс `Move` по обеим сторонам сразу,
      и рабочая копия получается тем же `Move` из служебной — две копии одного
      массива записей;
    * свёртка стен: вложенные циклы `for k := 1 to 4` и `for j := k to 4`,
      где ОДИН уровень стакана попадает сразу в несколько корзин. Порог
      корзины считается делением на процент, а не умножением;
    * достройка дальних уровней: индекс последнего наращивается по ходу,
      длина массива увеличивается с запасом, а объём добавляемого уровня
      уменьшается на уже учтённый — тот считается ОБРАТНЫМ проходом с
      досрочным выходом;
    * обходы идут через `With Glass[i] do`.

  Заменено оснасткой: источник уровней и блокировка.

  Почему это отдельная форма от ленты:

    * здесь массив записей не кольцо, а отсортированный по цене список, и
      работа идёт сдвигами внутри него, а не по кругу;
    * одно значение попадает в несколько накопителей сразу, и порядок обхода
      корзин задаёт, какие именно;
    * наращивание длины с запасом означает, что за фактическим концом лежат
      старые записи — и они не имеют права попасть в ответ.

  Оракулы:

    1. стены пересчитываются прямым перебором: для каждой корзины — свой
       проход по всему стакану, без вложенности и без накопления;
    2. достройка проверяется свойствами результата: порядок цен сохранён,
       исходные уровни не тронуты, добавленные лежат за последним исходным, и
       суммарный объём не превысил поданного;
    3. полный снимок — побитовое совпадение обеих копий с источником. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, chimera_body;

type
  TChiLevel = record
    Rate:     Double;
    Quantity: Double;
  end;
  TChiGlass = array of TChiLevel;

  TChiWall = record
    Vol:   Double;
    Count: Integer;
  end;
  TChiWalls = array [1 .. 4] of TChiWall;

function ChiBookRun: Int64;

implementation

const
  IdBook  = 'CHI-MB-BOOK-001';
  IdDiff  = 'CHI-MB-BOOK-003';
  IdChunk = 'CHI-MB-BOOK-004';
  IdWalls = 'CHI-MB-BOOK-002';
  ChiEpsM = 1E-12;
  { Шаг уровня стены в процентах — как настройка рынка в живом коде. }
  ChiWallStep = 0.5;

{ ═══ Полный снимок ═══════════════════════════════════════════════════════ }

procedure ApplySnapshot(const Bids, Asks: TChiGlass;
  var BuyX, SellX, Buy, Sell: TChiGlass);
begin
  SetLength(BuyX, Length(Bids));
  if Length(BuyX) > 0 then
    Move(Bids[0], BuyX[0], Length(BuyX) * SizeOf(TChiLevel));

  SetLength(SellX, Length(Asks));
  if Length(SellX) > 0 then
    Move(Asks[0], SellX[0], Length(SellX) * SizeOf(TChiLevel));

  { Рабочая копия делается из служебной тем же переносом. }
  SetLength(Buy, Length(BuyX));
  SetLength(Sell, Length(SellX));
  if Length(SellX) > 0 then
    Move(SellX[0], Sell[0], Length(SellX) * SizeOf(TChiLevel));
  if Length(BuyX) > 0 then
    Move(BuyX[0], Buy[0], Length(BuyX) * SizeOf(TChiLevel));
end;

{ ═══ Свёртка стен ════════════════════════════════════════════════════════

  Один уровень попадает сразу в несколько корзин: внешний цикл ищет самую
  дальнюю корзину, куда уровень ещё проходит, внутренний разносит его по всем
  корзинам от неё и дальше. }

procedure FoldWalls(const Buy: TChiGlass; MidPrice: Double; var Walls: TChiWalls);
var
  I, K, J: Integer;
begin
  FillChar(Walls[1], SizeOf(Walls[1]) * Length(Walls), 0);
  for I := Low(Buy) to High(Buy) do
    with Buy[I] do
      for K := 1 to 4 do
        if Rate > MidPrice / (1 + K * ChiWallStep / 100) then
          for J := K to 4 do
          begin
            Walls[J].Vol := Walls[J].Vol + Rate * Quantity;
            Inc(Walls[J].Count);
          end;
end;

{ Независимый пересчёт: по корзине на проход, без вложенности. }
procedure FoldWallsNaive(const Buy: TChiGlass; MidPrice: Double;
  var Walls: TChiWalls);
var
  I, J, K: Integer;
begin
  for J := 1 to 4 do
  begin
    Walls[J].Vol := 0;
    Walls[J].Count := 0;
  end;
  for J := 1 to 4 do
    for I := Low(Buy) to High(Buy) do
      for K := 1 to J do
        if Buy[I].Rate > MidPrice / (1 + K * ChiWallStep / 100) then
        begin
          Walls[J].Vol := Walls[J].Vol + Buy[I].Rate * Buy[I].Quantity;
          Inc(Walls[J].Count);
        end;
end;

{ ═══ Достройка дальних уровней ═══════════════════════════════════════════

  Уровни второго источника лежат реже. Первый из них поглощает всё, что уже
  учтено ближними уровнями основного стакана, поэтому его объём уменьшается на
  сумму, собранную ОБРАТНЫМ проходом с досрочным выходом. }

procedure ExtendBuy(var Buy: TChiGlass; const Extra: TChiGlass;
  PriceStep: Double; out Added: Integer; out Trimmed: Boolean);
var
  L, K, J: Integer;
  FirstLevel: Boolean;
  RestSize: Double;
begin
  Added := 0;
  Trimmed := False;
  L := High(Buy);
  if L <= 0 then Exit;

  FirstLevel := True;
  RestSize := 0;
  for K := Low(Extra) to High(Extra) do
    if (Extra[K].Rate > 0) and (Extra[K].Rate < Buy[L].Rate) then
    begin
      if FirstLevel then
      begin
        for J := L downto 0 do
        begin
          if Buy[J].Rate >= Extra[K].Rate + PriceStep - ChiEpsM then Break;
          RestSize := RestSize + Buy[J].Quantity;
        end;
        FirstLevel := False;

        if Extra[K].Quantity - RestSize > 0 then
        begin
          Inc(L);
          { Длина наращивается с запасом: за фактическим концом остаются
            старые записи. }
          if High(Buy) < L then SetLength(Buy, L + 10);
          Buy[L] := Extra[K];
          Buy[L].Quantity := Buy[L].Quantity - RestSize;
          Inc(Added);
          Trimmed := True;
        end;
      end
      else
      begin
        Inc(L);
        if High(Buy) < L then SetLength(Buy, L + 10);
        Buy[L] := Extra[K];
        Inc(Added);
      end;
    end;

  { Хвост запаса отрезается — иначе в ответ уйдут старые записи. }
  if L > 0 then SetLength(Buy, L + 1);
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

function MakeBook(Count: Integer; Top, Step: Double; Down: Boolean;
  Seed: UInt64; Scale: Double = 1): TChiGlass;
var
  Src: TChiSource;
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(Seed);
  for I := 0 to Count - 1 do
  begin
    if Down then
      Result[I].Rate := Top - I * Step
    else
      Result[I].Rate := Top + I * Step;
    Result[I].Quantity := (1 + Src.NextBelow(100)) * Scale;
  end;
end;

function TotalVolume(const G: TChiGlass): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(G) do Result := Result + G[I].Quantity;
end;


{ ═══ CHI-MB-BOOK-003: слияние дельты стакана ═════════════════════════════ }

{ Источник: `MoonBot/EngineBase.pas` ::
  `TMarketEngine.ApplyOrderBookDiffKeepZero` — третья форма работы со стаканом,
  отличная и от полного снимка, и от достройки дальних уровней. Перенесено
  дословно:

    * два отсортированных списка сливаются одним проходом, и направление
      сравнения зависит от стороны: покупки идут по убыванию цены, продажи по
      возрастанию;
    * уровень дельты с нулевым объёмом в новый список НЕ попадает — так
      выглядит удаление уровня;
    * старый уровень с той же ценой пропускается независимо от того, попал
      новый в список или нет: цена совпала — прежней записи больше нет;
    * потом голова списка обрезается по цене из ВТОРОГО списка дельты (цены
      противоположной стороны сообщают, докуда стакан уже неверен), и обрезка
      делается сдвигом внутри того же массива;
    * длина массива выправляется в самом конце, и до этого за фактическим
      концом лежат старые записи. }

procedure ApplyBookDiff(var ABook, NewBook: TChiGlass; ADiff, Shrink: TChiGlass;
  AIsBids: Boolean);
const
  _eps  = 1E-12;
  _epsM = 1E-9;
var
  K, J, N:   Integer;
  Count:     Integer;
  CutPrice:  Double;
begin
  Count := Length(ADiff);
  if Count = 0 then Exit;
  SetLength(NewBook, Length(ABook) + Count);

  K := 0;
  N := 0;

  for J := 0 to Count - 1 do
  begin
    if AIsBids then
      while (K <= High(ABook)) and (ABook[K].Rate > ADiff[J].Rate + _epsM) do
      begin
        NewBook[N] := ABook[K];
        Inc(K);
        Inc(N);
      end
    else
      while (K <= High(ABook)) and (ABook[K].Rate < ADiff[J].Rate - _epsM) do
      begin
        NewBook[N] := ABook[K];
        Inc(K);
        Inc(N);
      end;

    if ADiff[J].Quantity > _eps then
    begin
      NewBook[N] := ADiff[J];
      Inc(N);
    end;

    if (K <= High(ABook)) and (Abs(ABook[K].Rate - ADiff[J].Rate) < _epsM) then
      Inc(K);
  end;

  while K <= High(ABook) do
  begin
    NewBook[N] := ABook[K];
    Inc(K);
    Inc(N);
  end;

  CutPrice := -1;
  for K := 0 to High(Shrink) do
    if Shrink[K].Rate > _epsM then
    begin
      CutPrice := Shrink[K].Rate;
      Break;
    end;

  K := 0;
  if CutPrice > 0 then
    if AIsBids
      then while (K < N) and (NewBook[K].Rate >= CutPrice) do Inc(K)
      else while (K < N) and (NewBook[K].Rate <= CutPrice) do Inc(K);

  if K > 0 then
  begin
    N := N - K;
    Move(NewBook[K], NewBook[0], N * SizeOf(TChiLevel));
  end;

  SetLength(NewBook, N);
  SetLength(ABook, N);
  if N > 0 then
    Move(NewBook[0], ABook[0], N * SizeOf(TChiLevel));
end;

{ Оракул: тот же ответ, полученный совершенно иначе — сводом цен в список пар
  с заменой по цене, потом упорядочиванием и отсевом. Ни слияния, ни сдвигов. }
function OracleDiff(const ABook, ADiff, Shrink: TChiGlass; AIsBids: Boolean): TChiGlass;
var
  Rates: array of Double;
  Vols:  array of Double;
  Cnt:   Integer;

  procedure PutLevel(ARate, AVol: Double);
  begin
    for var I := 0 to Cnt - 1 do
      if Abs(Rates[I] - ARate) < 1E-9 then
      begin
        Vols[I] := AVol;
        Exit;
      end;
    if Cnt = Length(Rates) then
    begin
      SetLength(Rates, Cnt + 16);
      SetLength(Vols, Cnt + 16);
    end;
    Rates[Cnt] := ARate;
    Vols[Cnt] := AVol;
    Inc(Cnt);
  end;

var
  CutPrice: Double;
  Keep:     Integer;
begin
  Cnt := 0;
  SetLength(Rates, 16);
  SetLength(Vols, 16);
  for var I := 0 to High(ABook) do PutLevel(ABook[I].Rate, ABook[I].Quantity);
  for var I := 0 to High(ADiff) do PutLevel(ADiff[I].Rate, ADiff[I].Quantity);

  { упорядочивание пузырьком: медленно, зато очевидно }
  for var I := 0 to Cnt - 2 do
    for var J := 0 to Cnt - 2 - I do
    begin
      var Swap: Boolean;
      if AIsBids then Swap := Rates[J] < Rates[J + 1] else Swap := Rates[J] > Rates[J + 1];
      if Swap then
      begin
        var R := Rates[J]; Rates[J] := Rates[J + 1]; Rates[J + 1] := R;
        var V := Vols[J];  Vols[J] := Vols[J + 1];   Vols[J + 1] := V;
      end;
    end;

  CutPrice := -1;
  for var I := 0 to High(Shrink) do
    if Shrink[I].Rate > 1E-9 then
    begin
      CutPrice := Shrink[I].Rate;
      Break;
    end;

  SetLength(Result, Cnt);
  Keep := 0;
  for var I := 0 to Cnt - 1 do
  begin
    if Vols[I] <= 1E-12 then Continue;
    if CutPrice > 0 then
      if AIsBids then
      begin
        if Rates[I] >= CutPrice then Continue;
      end
      else
        if Rates[I] <= CutPrice then Continue;
    Result[Keep].Rate := Rates[I];
    Result[Keep].Quantity := Vols[I];
    Inc(Keep);
  end;
  SetLength(Result, Keep);
end;

function SameGlass(const A, B: TChiGlass): Boolean;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for var I := 0 to High(A) do
    if (Abs(A[I].Rate - B[I].Rate) > 1E-9) or (Abs(A[I].Quantity - B[I].Quantity) > 1E-9) then
      Exit(False);
end;

function MakeSide(ABase: Double; ACount: Integer; AIsBids: Boolean): TChiGlass;
begin
  SetLength(Result, ACount);
  for var I := 0 to ACount - 1 do
  begin
    if AIsBids
      then Result[I].Rate := ABase - I * 0.5
      else Result[I].Rate := ABase + I * 0.5;
    Result[I].Quantity := 1 + I;
  end;
end;

procedure RunDiff(var Acc: UInt64);
var
  Book, New1, Diff, Shrink, Want: TChiGlass;
begin
  ChiCovered(IdDiff);

  for var Side := 0 to 1 do
  begin
    var IsBids := Side = 0;
    var Base: Double;
    if IsBids then Base := 100 else Base := 200;

    { ── Замена, вставка и удаление в одной дельте ── }
    Book := MakeSide(Base, 8, IsBids);
    SetLength(Diff, 3);
    if IsBids then
    begin
      Diff[0].Rate := Base - 0.5; Diff[0].Quantity := 42;      { замена }
      Diff[1].Rate := Base - 1.25; Diff[1].Quantity := 7;      { вставка между }
      Diff[2].Rate := Base - 2.0; Diff[2].Quantity := 0;       { удаление }
    end
    else
    begin
      Diff[0].Rate := Base + 0.5; Diff[0].Quantity := 42;
      Diff[1].Rate := Base + 1.25; Diff[1].Quantity := 7;
      Diff[2].Rate := Base + 2.0; Diff[2].Quantity := 0;
    end;
    SetLength(Shrink, 0);

    Want := OracleDiff(Book, Diff, Shrink, IsBids);
    ApplyBookDiff(Book, New1, Diff, Shrink, IsBids);
    ChiClaim(SameGlass(Book, Want), 'дельта: слияние разошлось с независимым ответом');
    ChiClaim(Length(Book) = 8 + 1 - 1, 'дельта: длина после замены, вставки и удаления не та');
    ChiClaim(SameGlass(Book, New1), 'дельта: рабочий список не совпал с собранным');
    Acc := ChiMix(Acc, Length(Book));
  end;
  ChiBranch(IdDiff, 'replace-insert-delete');

  { ── Обрезка головы по цене противоположной стороны ── }
  Book := MakeSide(100, 10, True);
  SetLength(Diff, 1);
  Diff[0].Rate := 99.75;
  Diff[0].Quantity := 5;
  SetLength(Shrink, 2);
  Shrink[0].Rate := 0;          { нулевая цена пропускается: берётся первая ненулевая }
  Shrink[0].Quantity := 0;
  Shrink[1].Rate := 99.0;
  Shrink[1].Quantity := 3;
  Want := OracleDiff(Book, Diff, Shrink, True);
  ApplyBookDiff(Book, New1, Diff, Shrink, True);
  ChiClaim(SameGlass(Book, Want), 'обрезка: ответ разошёлся с независимым');
  ChiClaim((Length(Book) > 0) and (Book[0].Rate < 99.0),
    'обрезка: голова списка не отрезана');
  ChiBranch(IdDiff, 'head-trimmed');
  Acc := ChiMix(Acc, Length(Book));

  { ── Обрезка, съедающая список целиком ── }
  Book := MakeSide(100, 4, True);
  SetLength(Shrink, 1);
  Shrink[0].Rate := 1;
  Shrink[0].Quantity := 1;
  SetLength(Diff, 1);
  Diff[0].Rate := 98.0;
  Diff[0].Quantity := 2;
  ApplyBookDiff(Book, New1, Diff, Shrink, True);
  ChiClaim(Length(Book) = 0, 'обрезка: список не опустел, хотя отрезано всё');
  ChiBranch(IdDiff, 'trim-everything');

  { ── Пустая дельта не трогает стакан вовсе ── }
  Book := MakeSide(100, 5, True);
  var Before := Copy(Book);
  SetLength(Diff, 0);
  SetLength(Shrink, 1);
  Shrink[0].Rate := 99;
  Shrink[0].Quantity := 1;
  ApplyBookDiff(Book, New1, Diff, Shrink, True);
  ChiClaim(SameGlass(Book, Before), 'дельта: пустая дельта изменила стакан');
  ChiBranch(IdDiff, 'empty-diff-untouched');

  { ── Дельта целиком новая: цены ниже всех прежних ── }
  Book := MakeSide(100, 3, True);
  SetLength(Diff, 2);
  Diff[0].Rate := 90;
  Diff[0].Quantity := 1;
  Diff[1].Rate := 89;
  Diff[1].Quantity := 2;
  SetLength(Shrink, 0);
  Want := OracleDiff(Book, Diff, Shrink, True);
  ApplyBookDiff(Book, New1, Diff, Shrink, True);
  ChiClaim(SameGlass(Book, Want), 'дельта: хвостовые уровни разошлись с независимым ответом');
  ChiClaim(Length(Book) = 5, 'дельта: хвостовые уровни не добавились');
  ChiBranch(IdDiff, 'diff-below-all');

  { ── Дельта нулями удаляет всё, что было ── }
  Book := MakeSide(100, 4, True);
  SetLength(Diff, 4);
  for var I := 0 to 3 do
  begin
    Diff[I].Rate := 100 - I * 0.5;
    Diff[I].Quantity := 0;
  end;
  SetLength(Shrink, 0);
  Want := OracleDiff(Book, Diff, Shrink, True);
  ApplyBookDiff(Book, New1, Diff, Shrink, True);
  ChiClaim(Length(Book) = 0, 'дельта: нулевая дельта не опустошила стакан');
  ChiClaim(SameGlass(Book, Want), 'дельта: опустошение разошлось с независимым ответом');
  ChiBranch(IdDiff, 'delete-all');

  { ── Порядок цен обязан сохраниться на обеих сторонах ── }
  for var Side := 0 to 1 do
  begin
    var IsBids := Side = 0;
    var Base: Double;
    if IsBids then Base := 100 else Base := 200;
    Book := MakeSide(Base, 12, IsBids);
    SetLength(Diff, 4);
    for var I := 0 to 3 do
    begin
      if IsBids
        then Diff[I].Rate := Base - 0.25 - I * 1.5
        else Diff[I].Rate := Base + 0.25 + I * 1.5;
      Diff[I].Quantity := 10 + I;
    end;
    SetLength(Shrink, 0);
    ApplyBookDiff(Book, New1, Diff, Shrink, IsBids);
    for var I := 1 to High(Book) do
      if IsBids
        then ChiClaim(Book[I].Rate < Book[I - 1].Rate, 'дельта: покупки перестали убывать')
        else ChiClaim(Book[I].Rate > Book[I - 1].Rate, 'дельта: продажи перестали возрастать');
    ChiClaim(Length(Book) = 16, 'дельта: вставки не все доехали');
  end;
  ChiBranch(IdDiff, 'order-preserved');
  Acc := ChiMix(Acc, Length(Book));
end;


{ ═══ CHI-MB-BOOK-004: нарезка дельты по пакетам и кеш по номеру ══════════ }

{ Источник: `MoonBot/MoonProto\MoonProtoOrderBook.pas` —
  `CompareSeq`, `PackDiffIntoChunks`, `TOrderBookCache`. Перенесено дословно:

    * номера пакетов — шестнадцатибитные и ЗАВОРАЧИВАЮТСЯ. Сравнение сделано
      знаковым приведением разности, и потому «после 65535 идёт 0» работает
      само, без особого случая;
    * дельта режется на пакеты ЧЕРЕДОВАНИЕМ сторон: пока есть слоты, берётся
      по уровню от покупок и продаж по очереди. Число пакетов оценивается
      делением с округлением вверх ЗАРАНЕЕ, а массивы усекаются по факту;
    * кеш пришедших не по порядку пакетов держит их упорядоченными: место
      вставки ищется половинным делением по тому же завёрнутому сравнению;
    * кеш считается просроченным, если он непуст дольше порога, и запрос
      полного снимка троттлится. Обе проверки времени — через модуль
      разности, чтобы скачок часов назад не заклинил их навсегда. }

type
  TChiSeqPacket = record
    Seq:  Word;
    Tag:  Integer;
  end;

function CompareSeq(Seq1, Seq2: Word): Integer;
begin
  Result := SmallInt(Seq1 - Seq2);
end;

procedure PackDiffIntoChunks(const ABuy, ASell: TChiGlass; AMaxPerPacket: Integer;
  out ABuyChunks, ASellChunks: TArray<TChiGlass>);
var
  BuyIdx, SellIdx, PacketIdx:          Integer;
  RemainingSlots, BuyCount, SellCount: Integer;
  NumPackets:                          Integer;
begin
  NumPackets := ((Length(ABuy) + Length(ASell)) + AMaxPerPacket - 1) div AMaxPerPacket;
  if NumPackets = 0 then
  begin
    SetLength(ABuyChunks, 0);
    SetLength(ASellChunks, 0);
    Exit;
  end;

  SetLength(ABuyChunks, NumPackets);
  SetLength(ASellChunks, NumPackets);

  BuyIdx := 0;
  SellIdx := 0;
  PacketIdx := 0;

  while (BuyIdx < Length(ABuy)) or (SellIdx < Length(ASell)) do
  begin
    RemainingSlots := AMaxPerPacket;
    BuyCount := 0;
    SellCount := 0;

    while (RemainingSlots > 0) and
          ((BuyIdx + BuyCount < Length(ABuy)) or (SellIdx + SellCount < Length(ASell))) do
    begin
      if BuyIdx + BuyCount < Length(ABuy) then
      begin
        Inc(BuyCount);
        Dec(RemainingSlots);
        if RemainingSlots = 0 then Break;
      end;

      if SellIdx + SellCount < Length(ASell) then
      begin
        Inc(SellCount);
        Dec(RemainingSlots);
      end;
    end;

    SetLength(ABuyChunks[PacketIdx], BuyCount);
    if BuyCount > 0 then
      Move(ABuy[BuyIdx], ABuyChunks[PacketIdx][0], BuyCount * SizeOf(TChiLevel));
    Inc(BuyIdx, BuyCount);

    SetLength(ASellChunks[PacketIdx], SellCount);
    if SellCount > 0 then
      Move(ASell[SellIdx], ASellChunks[PacketIdx][0], SellCount * SizeOf(TChiLevel));
    Inc(SellIdx, SellCount);

    Inc(PacketIdx);
  end;

  SetLength(ABuyChunks, PacketIdx);
  SetLength(ASellChunks, PacketIdx);
end;

type
  { Кеш пакетов, пришедших не по порядку: держится упорядоченным по номеру. }
  TChiSeqCache = class
  private
    FPackets: array of TChiSeqPacket;
    FCount:   Integer;
    FSince:   Int64;
    FLastReq: Int64;
    FCorrupt: Boolean;
    function FindInsertPos(Seq: Word): Integer;
  public
    procedure Add(Seq: Word; Tag: Integer; ANow: Int64);
    procedure DropOldest;
    function IsExpired(ANow: Int64; ATimeout: Int64): Boolean;
    function TryRequestFull(ANow: Int64; AThrottle: Int64): Boolean;
    function SeqAt(I: Integer): Word;
    property Count: Integer read FCount;
    property Corrupt: Boolean read FCorrupt write FCorrupt;
  end;

function TChiSeqCache.FindInsertPos(Seq: Word): Integer;
var
  L, R, M, Cmp: Integer;
begin
  L := 0;
  R := FCount - 1;

  while L <= R do
  begin
    M := (L + R) div 2;
    Cmp := CompareSeq(FPackets[M].Seq, Seq);

    if Cmp < 0 then
      L := M + 1
    else if Cmp > 0 then
      R := M - 1
    else
      Exit(M);
  end;

  Result := L;
end;

procedure TChiSeqCache.Add(Seq: Word; Tag: Integer; ANow: Int64);
var
  At: Integer;
begin
  if FCount = 0 then FSince := ANow;
  if FCount = Length(FPackets) then SetLength(FPackets, FCount + 16);
  At := FindInsertPos(Seq);
  if At < FCount then
    Move(FPackets[At], FPackets[At + 1], (FCount - At) * SizeOf(TChiSeqPacket));
  FPackets[At].Seq := Seq;
  FPackets[At].Tag := Tag;
  Inc(FCount);
end;

procedure TChiSeqCache.DropOldest;
begin
  if FCount > 0 then
  begin
    Dec(FCount);
    if FCount > 0 then
      Move(FPackets[1], FPackets[0], FCount * SizeOf(TChiSeqPacket))
    else
      FSince := 0;
  end;
end;

function TChiSeqCache.IsExpired(ANow: Int64; ATimeout: Int64): Boolean;
begin
  Result := (FSince > 0) and (Abs(ANow - FSince) > ATimeout);
end;

function TChiSeqCache.TryRequestFull(ANow: Int64; AThrottle: Int64): Boolean;
begin
  Result := False;
  if not FCorrupt then Exit;
  if Abs(ANow - FLastReq) <= AThrottle then Exit;
  FLastReq := ANow;
  Result := True;
end;

function TChiSeqCache.SeqAt(I: Integer): Word;
begin
  Result := FPackets[I].Seq;
end;

const
  { Номера приходят вперемешку, а вокруг предела — с заворотом. }
  CacheOrder: array [0 .. 5] of Word = (5, 1, 4, 2, 6, 3);
  WrapOrder:  array [0 .. 3] of Word = (65534, 0, 65535, 1);

procedure RunChunks(var Acc: UInt64);
var
  Buy, Sell:             TChiGlass;
  BuyCh, SellCh:         TArray<TChiGlass>;
  Cache:                 TChiSeqCache;
  Now64:                 Int64;
begin
  ChiCovered(IdChunk);

  { ── Сравнение номеров переживает заворот ── }
  ChiClaim(CompareSeq(5, 3) > 0, 'номера: больший номер не признан большим');
  ChiClaim(CompareSeq(3, 5) < 0, 'номера: меньший номер не признан меньшим');
  ChiClaim(CompareSeq(7, 7) = 0, 'номера: равные номера не равны');
  ChiClaim(CompareSeq(0, 65535) > 0, 'номера: заворот не понят — ноль младше предела');
  ChiClaim(CompareSeq(65535, 0) < 0, 'номера: заворот не понят в другую сторону');
  ChiClaim(CompareSeq(1, 65534) > 0, 'номера: заворот через несколько шагов не понят');
  ChiBranch(IdChunk, 'seq-wraps');

  { ── Нарезка: чередование сторон, полнота и порядок ── }
  Buy := MakeSide(100, 7, True);
  Sell := MakeSide(200, 3, False);
  PackDiffIntoChunks(Buy, Sell, 4, BuyCh, SellCh);
  ChiClaim(Length(BuyCh) = Length(SellCh), 'нарезка: сторон получилось разное число пакетов');
  ChiClaim(Length(BuyCh) = 3, 'нарезка: число пакетов не то, что даёт округление вверх');

  var TotalBuy := 0;
  var TotalSell := 0;
  for var I := 0 to High(BuyCh) do
  begin
    ChiClaim(Length(BuyCh[I]) + Length(SellCh[I]) <= 4,
      'нарезка: в пакет попало больше уровней, чем позволено');
    for var K := 0 to High(BuyCh[I]) do
      ChiClaim(BuyCh[I][K].Rate = Buy[TotalBuy + K].Rate, 'нарезка: покупки перепутаны');
    for var K := 0 to High(SellCh[I]) do
      ChiClaim(SellCh[I][K].Rate = Sell[TotalSell + K].Rate, 'нарезка: продажи перепутаны');
    Inc(TotalBuy, Length(BuyCh[I]));
    Inc(TotalSell, Length(SellCh[I]));
  end;
  ChiClaim(TotalBuy = Length(Buy), 'нарезка: покупки доехали не все');
  ChiClaim(TotalSell = Length(Sell), 'нарезка: продажи доехали не все');
  ChiBranch(IdChunk, 'chunks-complete');
  Acc := ChiMix(Acc, Length(BuyCh));

  { Ровное деление и деление с остатком — обе дороги оценки числа пакетов. }
  PackDiffIntoChunks(MakeSide(100, 4, True), MakeSide(200, 4, False), 4, BuyCh, SellCh);
  ChiClaim(Length(BuyCh) = 2, 'нарезка: ровное деление дало не два пакета');
  PackDiffIntoChunks(MakeSide(100, 1, True), MakeSide(200, 0, False), 4, BuyCh, SellCh);
  ChiClaim(Length(BuyCh) = 1, 'нарезка: один уровень не уложился в один пакет');
  ChiClaim(Length(SellCh[0]) = 0, 'нарезка: пустая сторона дала уровни');
  ChiBranch(IdChunk, 'chunks-edge-counts');

  { Пустая дельта не даёт ни одного пакета. }
  SetLength(Buy, 0);
  SetLength(Sell, 0);
  PackDiffIntoChunks(Buy, Sell, 4, BuyCh, SellCh);
  ChiClaim(Length(BuyCh) = 0, 'нарезка: из пустой дельты вышли пакеты');
  ChiBranch(IdChunk, 'chunks-empty');

  { Одна сторона длиннее другой: остаток едет один. }
  PackDiffIntoChunks(MakeSide(100, 9, True), MakeSide(200, 1, False), 4, BuyCh, SellCh);
  var LastIdx := High(BuyCh);
  ChiClaim(Length(SellCh[LastIdx]) = 0, 'нарезка: короткая сторона не кончилась раньше');
  ChiClaim(Length(BuyCh[LastIdx]) > 0, 'нарезка: длинная сторона не доехала до последнего пакета');
  ChiBranch(IdChunk, 'chunks-uneven-sides');

  { ── Кеш пакетов: вставка половинным делением, порядок и заворот ── }
  Now64 := Int64(1756500000000);
  Cache := TChiSeqCache.Create;
  try
    for var I := 0 to High(CacheOrder) do
      Cache.Add(CacheOrder[I], I, Now64);
    ChiClaim(Cache.Count = 6, 'кеш: пакетов накопилось не столько');
    for var I := 1 to Cache.Count - 1 do
      ChiClaim(CompareSeq(Cache.SeqAt(I), Cache.SeqAt(I - 1)) > 0,
        'кеш: порядок номеров нарушен');
    ChiBranch(IdChunk, 'cache-ordered');

    Cache.DropOldest;
    ChiClaim(Cache.Count = 5, 'кеш: удаление старшего не уменьшило число');
    ChiClaim(Cache.SeqAt(0) = 2, 'кеш: удалён не самый старый');
    ChiBranch(IdChunk, 'cache-drop-oldest');

    { Просрочка и троттлинг: обе проверки на модуле разности, значит скачок
      часов НАЗАД не заклинивает их навсегда. }
    ChiClaim(not Cache.IsExpired(Now64 + 100, 800), 'кеш: свежий признан просроченным');
    ChiClaim(Cache.IsExpired(Now64 + 900, 800), 'кеш: залежавшийся не признан просроченным');
    ChiClaim(Cache.IsExpired(Now64 - 900, 800),
      'кеш: часы, ушедшие назад, отменили просрочку');
    ChiBranch(IdChunk, 'cache-expiry-abs');

    ChiClaim(not Cache.TryRequestFull(Now64, 5000), 'кеш: запрос ушёл при целом стакане');
    Cache.Corrupt := True;
    ChiClaim(Cache.TryRequestFull(Now64 + 6000, 5000), 'кеш: первый запрос не ушёл');
    ChiClaim(not Cache.TryRequestFull(Now64 + 6100, 5000), 'кеш: троттлинг не сработал');
    ChiClaim(Cache.TryRequestFull(Now64 + 12000, 5000), 'кеш: повтор после паузы не ушёл');
    ChiBranch(IdChunk, 'cache-throttle');
    Acc := ChiMix(Acc, Cache.Count);
  finally
    FreeAndNil(Cache);
  end;

  { Заворот номеров в кеше: пакеты вокруг предела обязаны лечь подряд. }
  Cache := TChiSeqCache.Create;
  try
    for var I := 0 to High(WrapOrder) do
      Cache.Add(WrapOrder[I], I, Now64);
    ChiClaim(Cache.SeqAt(0) = 65534, 'кеш: заворот сбил начало');
    ChiClaim(Cache.SeqAt(1) = 65535, 'кеш: заворот сбил предел');
    ChiClaim(Cache.SeqAt(2) = 0, 'кеш: после предела встал не ноль');
    ChiClaim(Cache.SeqAt(3) = 1, 'кеш: заворот сбил хвост');
    ChiBranch(IdChunk, 'cache-wrap-order');
  finally
    FreeAndNil(Cache);
  end;
end;

function ChiBookRun: Int64;
var
  Bids, Asks, BuyX, SellX, Buy, Sell, Extra, Before: TChiGlass;
  Walls, Naive: TChiWalls;
  Acc: UInt64;
  I, J, Added, Round: Integer;
  Mid, VolBefore, VolExtra: Double;
  Trimmed, Ok: Boolean;
begin
  ChiCovered(IdBook);
  ChiCovered(IdWalls);
  Acc := ChiOffset;

  for Round := 0 to 3 do
  begin
    { Покупки идут вниз от середины, продажи вверх — как в живом стакане. }
    Bids := MakeBook(60 + Round * 20, 100.0, 0.05, True, 900 + UInt64(Round));
    Asks := MakeBook(60 + Round * 20, 100.1, 0.05, False, 950 + UInt64(Round));

    { ── Полный снимок ── }
    ApplySnapshot(Bids, Asks, BuyX, SellX, Buy, Sell);
    ChiClaim(SameGlass(Buy, Bids), 'стакан: покупки скопированы неверно');
    ChiClaim(SameGlass(Sell, Asks), 'стакан: продажи скопированы неверно');
    ChiClaim(SameGlass(BuyX, Buy), 'стакан: служебная копия разошлась');
    ChiBranch(IdWalls, 'snapshot');

    { ── Свёртка стен против прямого пересчёта ── }
    Mid := (Buy[0].Rate + Sell[0].Rate) / 2;
    FoldWalls(Buy, Mid, Walls);
    FoldWallsNaive(Buy, Mid, Naive);
    for J := 1 to 4 do
    begin
      ChiClaim(Walls[J].Count = Naive[J].Count,
        'стены: счёт корзины ' + IntToStr(J) + ' разошёлся');
      ChiClaim(PInt64(@Walls[J].Vol)^ = PInt64(@Naive[J].Vol)^,
        'стены: объём корзины ' + IntToStr(J) + ' разошёлся');
      Acc := ChiMix(Acc, Walls[J].Count);
      Acc := ChiMix(Acc, PInt64(@Walls[J].Vol)^);
    end;
    ChiClaim(Walls[4].Count >= Walls[1].Count,
      'стены: дальняя корзина не шире ближней');
    ChiClaim(Walls[1].Count > 0, 'стены: ближняя корзина пуста');
    ChiBranch(IdWalls, 'fold');
    ChiBranch(IdWalls, 'nested-buckets');

    { ── Достройка дальних уровней ── }
    Before := Copy(Buy);
    VolBefore := TotalVolume(Buy);
    { Второй источник даёт уровни РЕЖЕ и ниже последнего в основном стакане.
      Объёмы там крупнее: один редкий уровень покрывает несколько частых, и
      именно поэтому первый из них уменьшается на уже учтённое. С мелкими
      объёмами эта ветвь не исполнялась бы вовсе. }
    Extra := MakeBook(10, Buy[High(Buy)].Rate - 0.2, 0.5, True,
                      970 + UInt64(Round), 50);
    VolExtra := TotalVolume(Extra);

    ExtendBuy(Buy, Extra, 0.5, Added, Trimmed);
    ChiClaim(Added > 0, 'стакан: не добавлено ни одного дальнего уровня');
    ChiBranch(IdBook, 'extend');
    if Trimmed then ChiBranch(IdBook, 'first-level-trimmed');

    { Исходные уровни не тронуты. }
    Ok := True;
    for I := 0 to High(Before) do
      if (PInt64(@Buy[I].Rate)^ <> PInt64(@Before[I].Rate)^)
         or (PInt64(@Buy[I].Quantity)^ <> PInt64(@Before[I].Quantity)^) then
        Ok := False;
    ChiClaim(Ok, 'стакан: достройка тронула исходные уровни');
    ChiBranch(IdBook, 'originals-intact');

    { Порядок цен сохранён: покупки строго вниз. }
    Ok := True;
    for I := 1 to High(Buy) do
      if Buy[I].Rate >= Buy[I - 1].Rate then Ok := False;
    ChiClaim(Ok, 'стакан: порядок цен нарушен');
    ChiBranch(IdBook, 'order-kept');

    { Длина отрезана по факту: за концом не осталось запаса. }
    ChiClaim(Length(Buy) = Length(Before) + Added,
      'стакан: длина не отрезана по фактическому концу');
    ChiBranch(IdBook, 'trimmed-length');

    { Объём не мог вырасти больше, чем подано вторым источником. }
    ChiClaim(TotalVolume(Buy) <= VolBefore + VolExtra + 1E-9,
      'стакан: объём вырос больше поданного');
    ChiClaim(TotalVolume(Buy) > VolBefore, 'стакан: объём не изменился');
    ChiBranch(IdBook, 'volume-bounded');
    Acc := ChiMix(Acc, Length(Buy));
    Acc := ChiMix(Acc, Added);
  end;

  { ── Края ── }
  Bids := nil;
  Asks := nil;
  ApplySnapshot(Bids, Asks, BuyX, SellX, Buy, Sell);
  ChiClaim(Length(Buy) = 0, 'стакан: пустой снимок дал уровни');
  ChiBranch(IdWalls, 'empty-snapshot');

  Buy := MakeBook(1, 100, 0.05, True, 1);
  Extra := MakeBook(5, 99, 0.5, True, 2);
  ExtendBuy(Buy, Extra, 0.5, Added, Trimmed);
  ChiClaim(Added = 0, 'стакан: достройка сработала на стакане из одного уровня');
  ChiBranch(IdBook, 'too-short');

  RunDiff(Acc);

  RunChunks(Acc);

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
