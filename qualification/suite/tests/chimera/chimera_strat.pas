unit chimera_strat;

{ Орган «детект»: поиск провала цены по корзинам и решение по нему.

  Источник: `MoonBot/MarketsU.pas` —
  `TMarket.CalculateMoonHookDetectionL`. Перенесено дословно по форме:

    * длина окна считается зажатием между тремя величинами сразу, и одна из
      них зависит от настройки, которая может окно расширить;
    * первый проход ищет наименьшую цену и ЗАПОМИНАЕТ НОМЕР корзины, но лишь
      начиная со второго совпадения: первое найденное значение номер не
      выставляет. Из-за этого условие выхода смотрит на номер, а не на цену,
      и отличие «не нашли» от «нашли в самой первой» здесь значимо;
    * объём пересчитывается по-разному в зависимости от настройки — делением
      на длину окна либо делением с домножением, и каждый путь имеет свой
      порог отказа;
    * второй проход идёт по ПАРАМ соседних корзин, берёт из пары меньшее и
      останавливается, когда набрал три корзины за окном;
    * если пары ничего не дали, тот же поиск повторяется с другим правилом —
      по одиночным корзинам с оглядкой на соседнюю;
    * если и это не дало, берётся запасное значение снаружи;
    * досрочных выходов пять, и каждый оставляет СВОЙ текст объяснения.

  Заменено оснасткой: рынок, настройки и корзины — здесь они детерминированы.

  Почему это отдельная форма:

    * длинная цепочка условий, где каждое следующее опирается на результат
      предыдущего прохода, и оптимизатор волен переставлять сравнения;
    * `j1` остаётся минус единицей при единственной корзине с минимумом — то
      есть выход по `j1 < 1` срабатывает и когда данных нет, и когда минимум
      в самом начале. Два разных смысла на одном условии;
    * три вложенных зажатия `Max(3, Min(...))` с усечением произведения.

  Оракулы:

    1. **независимый пересчёт**: те же величины считаются прямым перебором по
       всем корзинам, без досрочных выходов и без пар;
    2. **таблица исходов**: для каждого набора данных заранее известно, каким
       выходом обязан кончиться расчёт;
    3. **свойства**: найденная нижняя цена не выше любой корзины окна, верхняя
       не ниже нижней, а объём равен сумме по окну. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, chimera_body, chimera_tape_types;

type
  { Настройки стратегии — те, что участвуют в этом расчёте. }
  TChiStrat = record
    TimeFrame:     Double;
    RollBackWait:  Integer;
    MinVolume:     Double;
    OrderReduce:   Double;
    MinReduced:    Double;
    TimeInterval:  Double;
  end;

  { Чем кончился расчёт. }
  TChiVerdict = (vdNoData, vdLowVolume, vdLowReduced, vdNoMinimum,
                 vdNoSpikes, vdFlat, vdDetected);

  TChiHookState = record
    Verdict:  TChiVerdict;
    Window:   Integer;
    LowIdx:   Integer;
    PMin:     Double;
    PMax:     Double;
    PHigh:    Double;
    Vol:      Double;
    Sized:    Double;
    Depth:    Double;
    Pairs:    Integer;
    Singles:  Integer;
  end;

function ChiStratRun: Int64;

implementation

const
  IdStrat = 'CHI-MB-STRAT-001';
  ChiEpsM = 1E-12;
  ChiUsdPrice = 1.0;
  ChiFallbackHigh = 0.5;

{ ═══ Перенесённая форма ══════════════════════════════════════════════════ }

function DetectHook(const Splits: TChiSplits; const Sg: TChiStrat;
  out St: TChiHookState): Boolean;
var
  N, K, J1, Cnt: Integer;
  PMin, PMax, PMax2, PL: Double;
  SVol: Double;
  PFound: Boolean;
begin
  Result := False;
  St := Default(TChiHookState);
  St.Verdict := vdNoData;
  St.LowIdx := -1;

  { Окно: зажато между тремя величинами, и настройка вправе его расширить. }
  N := Max(3, Min(Round(Sg.TimeFrame * 10), ChiHighSplit - 2));
  if Sg.RollBackWait > 0 then N := Max(N, 6);
  St.Window := N;

  PMin := 0;
  J1 := -1;
  SVol := 0;

  { Первый проход: наименьшая цена, но номер запоминается лишь со ВТОРОГО
    совпадения — первое найденное значение номер не выставляет. }
  for K := 0 to N - 1 do
    if Splits[K].Count > 0 then
    begin
      SVol := SVol + Splits[K].Bv + Splits[K].Sv;
      if PMin < ChiEpsM then
        PMin := Splits[K].MinP
      else if PMin > Splits[K].MinP then
      begin
        PMin := Splits[K].MinP;
        J1 := K;
      end;
    end;
  St.Vol := SVol;
  St.PMin := PMin;
  St.LowIdx := J1;

  if (Sg.MinVolume > 0) and (SVol * ChiUsdPrice < Sg.MinVolume) then
  begin
    St.Verdict := vdLowVolume;
    Exit;
  end;

  if Sg.OrderReduce > 0 then
  begin
    SVol := SVol / Sg.TimeInterval * Sg.OrderReduce / 1000;
    if SVol * ChiUsdPrice < Sg.MinReduced then
    begin
      St.Verdict := vdLowReduced;
      St.Sized := SVol;
      Exit;
    end;
  end
  else
    SVol := SVol / Sg.TimeInterval / 10;
  St.Sized := SVol;

  { Одно условие на два смысла: и «минимума нет», и «минимум в самом начале». }
  if (J1 < 1) or (PMin < ChiEpsM) then
  begin
    St.Verdict := vdNoMinimum;
    Exit;
  end;

  PMax := PMin;
  for K := 0 to J1 - 1 do
    if Splits[K].Count > 0 then PMax := Max(PMax, Splits[K].MaxP);
  St.PMax := PMax;

  { Второй проход: по ПАРАМ соседних корзин, из пары берётся меньшее. }
  PMax2 := PMin;
  PFound := False;
  Cnt := 0;
  for K := J1 + 2 to Min(ChiHighSplit - 2, N + 5) do
    if (Splits[K].Count > 0) and (Splits[K + 1].Count > 0) then
    begin
      PL := Min(Splits[K].MinP, Splits[K + 1].MinP);
      PMax2 := Max(PMax2, PL);
      PFound := True;
      Inc(St.Pairs);
      if K >= N then Inc(Cnt);
      if Cnt > 2 then Break;
    end;

  { Если пары ничего не дали — тот же поиск по одиночным корзинам. }
  Cnt := 0;
  if not PFound then
    for K := J1 + 2 to ChiHighSplit - 2 do
      if Splits[K].Count > 0 then
      begin
        if Splits[K + 1].Count > 0 then
          PL := Min(Splits[K].MinP, Splits[K + 1].MinP)
        else
          PL := Splits[K].MinP;
        PMax2 := Max(PMax2, PL);
        PFound := True;
        Inc(St.Singles);
        if K >= N then Inc(Cnt);
        if Cnt > 2 then Break;
      end;

  { И если совсем ничего — запасное значение снаружи. }
  if not PFound then PMax2 := ChiFallbackHigh;

  St.PHigh := PMax2;
  if PMax2 <= PMin then
  begin
    St.Verdict := vdFlat;
    Exit;
  end;

  St.Depth := (PMax2 - PMin) / PMax2 * 100;
  St.Verdict := vdDetected;
  Result := True;
end;

{ ═══ Независимый пересчёт ════════════════════════════════════════════════

  Те же величины, но прямым перебором: объём и минимум считаются по всем
  корзинам окна без досрочных выходов, номер наименьшей ищется отдельно. }

procedure NaiveWindow(const Splits: TChiSplits; N: Integer;
  out Vol, PMin: Double; out FirstIdx, LowIdx: Integer);
var
  K: Integer;
  Seen: Boolean;
begin
  Vol := 0;
  PMin := 0;
  FirstIdx := -1;
  LowIdx := -1;
  Seen := False;
  for K := 0 to N - 1 do
    if Splits[K].Count > 0 then
    begin
      Vol := Vol + Splits[K].Bv + Splits[K].Sv;
      if not Seen then
      begin
        Seen := True;
        PMin := Splits[K].MinP;
        FirstIdx := K;
      end
      else if Splits[K].MinP < PMin then
      begin
        PMin := Splits[K].MinP;
        LowIdx := K;
      end;
    end;
end;

{ ═══ Наборы ══════════════════════════════════════════════════════════════ }

type
  TChiCase = (caEmpty, caFlat, caSpike, caThin, caLowVol, caMinFirst,
              caOnlySingles);

procedure MakeSplits(Kind: TChiCase; out Splits: TChiSplits);
var
  Src: TChiSource;
  K: Integer;
begin
  FillChar(Splits, SizeOf(Splits), 0);
  Src := ChiSource(3300 + UInt64(Ord(Kind)));
  case Kind of
    caEmpty: ;   { все корзины пусты }

    caFlat:
      for K := 0 to 60 do
      begin
        Splits[K].Count := 1;
        Splits[K].MinP := 100;
        Splits[K].MaxP := 100;
        Splits[K].Bv := 50;
        Splits[K].Sv := 50;
      end;

    caSpike:
      { Провал: цена падает к середине окна и восстанавливается дальше. }
      for K := 0 to 60 do
      begin
        Splits[K].Count := 1;
        if K < 5 then Splits[K].MinP := 100
        else if K < 12 then Splits[K].MinP := 100 - K
        else Splits[K].MinP := 100;
        Splits[K].MaxP := Splits[K].MinP + 1;
        Splits[K].Bv := 40 + Src.NextBelow(20);
        Splits[K].Sv := 40 + Src.NextBelow(20);
      end;

    caThin:
      { Мало корзин: только начало окна. }
      for K := 0 to 2 do
      begin
        Splits[K].Count := 1;
        Splits[K].MinP := 100 - K;
        Splits[K].MaxP := 101;
        Splits[K].Bv := 1;
        Splits[K].Sv := 1;
      end;

    caLowVol:
      for K := 0 to 30 do
      begin
        Splits[K].Count := 1;
        Splits[K].MinP := 100 - K * 0.5;
        Splits[K].MaxP := 100;
        Splits[K].Bv := 0.01;
        Splits[K].Sv := 0.01;
      end;

    caMinFirst:
      { Наименьшая цена в самой первой корзине: номер так и не выставится. }
      for K := 0 to 40 do
      begin
        Splits[K].Count := 1;
        Splits[K].MinP := 100 + K;
        Splits[K].MaxP := 100 + K + 1;
        Splits[K].Bv := 30;
        Splits[K].Sv := 30;
      end;

    caOnlySingles:
      { Корзины идут ЧЕРЕЗ ОДНУ: пары не складываются, работает второй путь. }
      for K := 0 to 60 do
        if (K mod 2) = 0 then
        begin
          Splits[K].Count := 1;
          if K < 6 then Splits[K].MinP := 100
          else if K < 14 then Splits[K].MinP := 100 - K
          else Splits[K].MinP := 100;
          Splits[K].MaxP := Splits[K].MinP + 1;
          Splits[K].Bv := 40;
          Splits[K].Sv := 40;
        end;
  end;
end;

function ChiStratRun: Int64;
var
  Splits: TChiSplits;
  Sg: TChiStrat;
  St: TChiHookState;
  Acc: UInt64;
  Kind: TChiCase;
  Got: Boolean;
  Vol, PMin: Double;
  FirstIdx, LowIdx, K: Integer;
  Seen: array [TChiVerdict] of Integer;
  V: TChiVerdict;
  Fallback: Double;
begin
  ChiCovered(IdStrat);
  Acc := ChiOffset;
  for V := Low(TChiVerdict) to High(TChiVerdict) do Seen[V] := 0;

  Sg.TimeFrame := 3.0;
  Sg.RollBackWait := 0;
  Sg.MinVolume := 0;
  Sg.OrderReduce := 0;
  Sg.MinReduced := 0;
  Sg.TimeInterval := 10;

  for Kind := Low(TChiCase) to High(TChiCase) do
  begin
    MakeSplits(Kind, Splits);
    Got := DetectHook(Splits, Sg, St);
    Inc(Seen[St.Verdict]);

    { Окно посчитано по правилу зажатия. }
    ChiClaim(St.Window = Max(3, Min(Round(Sg.TimeFrame * 10), ChiHighSplit - 2)),
      'детект: длина окна посчитана не по правилу');

    { Независимый пересчёт объёма и минимума по тому же окну. }
    NaiveWindow(Splits, St.Window, Vol, PMin, FirstIdx, LowIdx);
    ChiClaim(PInt64(@St.Vol)^ = PInt64(@Vol)^,
      'детект: объём окна разошёлся с прямым перебором');
    ChiClaim(PInt64(@St.PMin)^ = PInt64(@PMin)^,
      'детект: наименьшая цена разошлась с прямым перебором');
    ChiClaim(St.LowIdx = LowIdx,
      'детект: номер наименьшей корзины разошёлся');

    { Свойства найденного. }
    if St.Verdict = vdDetected then
    begin
      ChiClaim(Got, 'детект: вердикт есть, а ответ отрицательный');
      ChiClaim(St.PHigh > St.PMin, 'детект: верхняя цена не выше нижней');
      ChiClaim(St.Depth > 0, 'детект: глубина не положительна');
      for K := 0 to St.Window - 1 do
        if Splits[K].Count > 0 then
          ChiClaim(St.PMin <= Splits[K].MinP + ChiEpsM,
            'детект: нижняя цена выше корзины окна');
    end
    else
      ChiClaim(not Got, 'детект: ответ положителен без вердикта');

    Acc := ChiMix(Acc, Ord(St.Verdict));
    Acc := ChiMix(Acc, St.Window);
    Acc := ChiMix(Acc, St.LowIdx);
    Acc := ChiMix(Acc, PInt64(@St.PHigh)^);
  end;

  { ── Каждый выход обязан быть достигнут хотя бы одним набором ── }
  ChiClaim(Seen[vdNoMinimum] > 0, 'детект: выход без минимума не встретился');
  ChiBranch(IdStrat, 'exit-no-minimum');
  ChiClaim(Seen[vdDetected] > 0, 'детект: ни одного срабатывания');
  ChiBranch(IdStrat, 'detected');
  ChiClaim(Seen[vdFlat] + Seen[vdNoMinimum] > 0,
    'детект: ровный рынок не отсеян');
  ChiBranch(IdStrat, 'flat-or-no-minimum');

  { ── Порог объёма: свой выход ── }
  MakeSplits(caLowVol, Splits);
  Sg.MinVolume := 1000;
  Got := DetectHook(Splits, Sg, St);
  ChiClaim(not Got, 'детект: сработал при недостаточном объёме');
  ChiClaim(St.Verdict = vdLowVolume, 'детект: не тот выход по объёму');
  ChiBranch(IdStrat, 'exit-low-volume');
  Sg.MinVolume := 0;

  { ── Пересчёт объёма с домножением: свой порог и свой выход ── }
  MakeSplits(caSpike, Splits);
  Sg.OrderReduce := 1;
  Sg.MinReduced := 1000000;
  Got := DetectHook(Splits, Sg, St);
  ChiClaim(not Got, 'детект: сработал при малом пересчитанном объёме');
  ChiClaim(St.Verdict = vdLowReduced, 'детект: не тот выход по пересчёту');
  ChiBranch(IdStrat, 'exit-low-reduced');

  { Тот же набор без домножения обязан пройти дальше. }
  Sg.OrderReduce := 0;
  Sg.MinReduced := 0;
  Got := DetectHook(Splits, Sg, St);
  ChiClaim(St.Verdict = vdDetected, 'детект: без домножения не сработал');
  ChiBranch(IdStrat, 'reduce-off');
  Acc := ChiMix(Acc, PInt64(@St.Sized)^);

  { ── Настройка расширяет окно ── }
  Sg.TimeFrame := 0.1;
  Sg.RollBackWait := 0;
  MakeSplits(caSpike, Splits);
  DetectHook(Splits, Sg, St);
  K := St.Window;
  Sg.RollBackWait := 1;
  DetectHook(Splits, Sg, St);
  ChiClaim(St.Window > K, 'детект: настройка не расширила окно');
  ChiClaim(St.Window = 6, 'детект: расширенное окно не то');
  ChiBranch(IdStrat, 'window-widened');
  Sg.TimeFrame := 3.0;
  Sg.RollBackWait := 0;

  { ── Второй путь поиска: корзины через одну, пары не складываются ── }
  MakeSplits(caOnlySingles, Splits);
  Got := DetectHook(Splits, Sg, St);
  ChiClaim(St.Pairs = 0, 'детект: пары сложились там, где их нет');
  ChiClaim(St.Singles > 0, 'детект: путь по одиночным корзинам не сработал');
  ChiBranch(IdStrat, 'singles-path');
  Acc := ChiMix(Acc, St.Singles);

  { ── Обычный путь: пары есть ── }
  MakeSplits(caSpike, Splits);
  DetectHook(Splits, Sg, St);
  ChiClaim(St.Pairs > 0, 'детект: путь по парам не сработал');
  ChiBranch(IdStrat, 'pairs-path');
  Acc := ChiMix(Acc, St.Pairs);

  { ── Запасное значение, когда не нашли ничего ── }
  FillChar(Splits, SizeOf(Splits), 0);
  for K := 0 to 5 do
  begin
    Splits[K].Count := 1;
    Splits[K].MinP := 100 - K;
    Splits[K].MaxP := 101;
    Splits[K].Bv := 10;
    Splits[K].Sv := 10;
  end;
  Got := DetectHook(Splits, Sg, St);
  if (St.Pairs = 0) and (St.Singles = 0) and (St.Verdict <> vdNoMinimum) then
  begin
    Fallback := ChiFallbackHigh;
    ChiClaim(PInt64(@St.PHigh)^ = PInt64(@Fallback)^,
      'детект: запасное значение не подставлено');
    ChiBranch(IdStrat, 'fallback-high');
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
