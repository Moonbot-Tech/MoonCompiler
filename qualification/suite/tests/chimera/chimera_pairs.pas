unit chimera_pairs;

{ Орган «пары»: построение торговых пар вокруг рынков клиента.

  Источник: `Arbitrage/ArbServer\ArbServer.pas` —
  `RebuildPairsIndex` и `BuildComboPairs`. Перенесено дословно по форме:

    * указатель по токену строится через ВРЕМЕННЫЙ словарь списков, который в
      `finally` разбирается поимённо: сначала освобождается каждое значение,
      потом сам словарь. Готовый указатель получает массивы, а не списки;
    * снимок списка рынков берётся ОДИН раз, и дальше всё опирается только на
      него: движок, который ещё грузится, пропускается целиком;
    * фильтр совпадения `((свой or чужой) = 0) or (свой = чужой)` — правило,
      в котором «ноль против N» означает РАЗРЫВ, а не совпадение;
    * множитель цены `(a*b)/(c*d)` считается в том же порядке, что в живом
      коде: переставлять сомножители нельзя, это вещественная арифметика;
    * два вложенных цикла с `Continue` по нескольким условиям, растущий буфер
      соседей и финальный `Move` записей в массив нужной длины;
    * ветка семейства бирж, где вместо одного движка берутся все родственные.

  Заменено оснасткой: сами движки и рынки (здесь они детерминированные
  записи), запись в журнал.

  Оракулы:

    1. **наивный перебор** — те же пары считаются в лоб, по всем сочетаниям,
       без указателя по токену, без снимков и без растущего буфера;
    2. **правило фильтра предъявляется таблицей** всех сочетаний нуля и двух
       разных ненулевых значений, а не примерами;
    3. **множитель цены** сверяется с отдельно посчитанным в том же порядке
       действий — расхождение означает, что порядок переставили. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Generics.Collections, chimera_body;

type
  { Рынок: то немногое из живого, что участвует в построении пар. }
  TChiMarketRef = class
    Exchange:   Integer;
    Currency:   AnsiString;
    Display:    AnsiString;
    Active:     Boolean;
    GroupId:    Integer;
    K1000:      Single;
    PriceScale: Single;
    LastPrice:  Double;
  end;

  TChiPeer = record
    Market:   TChiMarketRef;
    PriceMul: Single;
  end;

  TChiPair = record
    Mine:  TChiMarketRef;
    Peers: array of TChiPeer;
  end;

function ChiPairsRun: Int64;

implementation

type
  TChiMarketList = TObjectList<TChiMarketRef>;
  TChiEngine = class
    Platform: Integer;
    Family:   Integer;
    Loading:  Boolean;   { движок ещё грузится — его рынки не трогают }
    Markets:  TChiMarketList;
    constructor Create;
    destructor Destroy; override;
  end;
  TChiEngines = TObjectList<TChiEngine>;

constructor TChiEngine.Create;
begin
  inherited Create;
  Markets := TChiMarketList.Create(True);
end;

destructor TChiEngine.Destroy;
begin
  FreeAndNil(Markets);
  inherited Destroy;
end;

{ ═══ Указатель по токену ═════════════════════════════════════════════════

  Временный словарь списков, разбираемый в `finally` поимённо. }

function BuildIndex(const Engines: TChiEngines;
  out Total: Integer): TDictionary<AnsiString, TArray<TChiMarketRef>>;
var
  Tmp: TDictionary<AnsiString, TChiMarketList>;
  Lst: TChiMarketList;
  Pair: TPair<AnsiString, TChiMarketList>;
begin
  Result := TDictionary<AnsiString, TArray<TChiMarketRef>>.Create;
  Total := 0;
  Tmp := TDictionary<AnsiString, TChiMarketList>.Create;
  try
    for var Eng in Engines do
    begin
      if Eng.Loading then Continue;
      Inc(Total, Eng.Markets.Count);
      for var M in Eng.Markets do
      begin
        if M.Currency = '' then Continue;
        if not Tmp.TryGetValue(M.Currency, Lst) then
        begin
          { Список заводится владеющим НЕ по содержимому: рынки принадлежат
            движку, а не указателю. }
          Lst := TChiMarketList.Create(False);
          Tmp.Add(M.Currency, Lst);
        end;
        Lst.Add(M);
      end;
    end;
    for Pair in Tmp do
      Result.AddOrSetValue(Pair.Key, Pair.Value.ToArray);
  finally
    for Pair in Tmp do Pair.Value.Free;
    FreeAndNil(Tmp);
  end;
end;

{ ═══ Правило совпадения ══════════════════════════════════════════════════

  Ноль означает «никогда не расходились», ненулевое — «отнесён к своему
  тождеству». Ноль против ненулевого — РАЗРЫВ: отделённые не сходятся с
  непроверенными, иначе разделение было бы бессмысленным. }

function GroupsMatch(Mine, Peer: Integer): Boolean; inline;
begin
  Result := ((Mine or Peer) = 0) or (Mine = Peer);
end;

{ ═══ Построение пар — большое тело ═══════════════════════════════════════ }

function BuildPairs(const Engines: TChiEngines; Platform, Family: Integer;
  const Index: TDictionary<AnsiString, TArray<TChiMarketRef>>;
  const Wanted: TArray<Boolean>; out Considered, Skipped: Integer): TArray<TChiPair>;
var
  Engs: TArray<TChiEngine>;
  Snaps: TArray<TChiMarketList>;
  Peers: array of TChiPeer;
  AllPeers: TArray<TChiMarketRef>;
  Cnt, TotalMkts, PairIdx, Ei: Integer;
  MyK1000: Single;
begin
  Result := nil;
  Considered := 0;
  Skipped := 0;

  { Семейство бирж: вместо одного движка берутся все родственные, иначе часть
    рынков клиента не попадёт в пары вовсе. }
  if Family <> 0 then
  begin
    SetLength(Engs, Engines.Count);
    Cnt := 0;
    for var E in Engines do
      if E.Family = Family then
      begin
        Engs[Cnt] := E;
        Inc(Cnt);
      end;
    SetLength(Engs, Cnt);
    if Cnt = 0 then Exit;
  end
  else
  begin
    Cnt := 0;
    for var E in Engines do
      if E.Platform = Platform then
      begin
        SetLength(Engs, 1);
        Engs[0] := E;
        Cnt := 1;
        Break;
      end;
    if Cnt = 0 then Exit;
  end;

  { Снимок списков берётся ОДИН раз. Движок, который ещё грузится,
    пропускается целиком: его список мутируется под нами. }
  SetLength(Snaps, Length(Engs));
  TotalMkts := 0;
  for Ei := 0 to High(Engs) do
  begin
    if Engs[Ei].Loading then
    begin
      Snaps[Ei] := nil;
      Continue;
    end;
    Snaps[Ei] := Engs[Ei].Markets;
    Inc(TotalMkts, Snaps[Ei].Count);
  end;
  SetLength(Result, TotalMkts);
  PairIdx := 0;

  for Ei := 0 to High(Engs) do
  begin
    if Snaps[Ei] = nil then Continue;
    for var Mine in Snaps[Ei] do
    begin
      Inc(Considered);
      if not Mine.Active then
      begin
        Inc(Skipped);
        Continue;
      end;
      if not Index.TryGetValue(Mine.Currency, AllPeers) then
      begin
        Inc(Skipped);
        Continue;
      end;

      SetLength(Peers, Length(AllPeers));
      Cnt := 0;
      MyK1000 := Mine.K1000;
      for var Peer in AllPeers do
        if (Peer <> Mine) and Wanted[Peer.Exchange] and Peer.Active
           and GroupsMatch(Mine.GroupId, Peer.GroupId) then
        begin
          Peers[Cnt].Market := Peer;
          { Порядок сомножителей и деления — часть смысла, а не стиля. }
          Peers[Cnt].PriceMul := (MyK1000 * Peer.PriceScale)
                                 / (Peer.K1000 * Mine.PriceScale);
          Inc(Cnt);
        end;
      if Cnt = 0 then
      begin
        Inc(Skipped);
        Continue;
      end;

      Result[PairIdx].Mine := Mine;
      SetLength(Result[PairIdx].Peers, Cnt);
      Move(Peers[0], Result[PairIdx].Peers[0], Cnt * SizeOf(TChiPeer));
      Inc(PairIdx);
    end;
  end;
  SetLength(Result, PairIdx);
end;

{ ═══ Наивный оракул ══════════════════════════════════════════════════════

  Ни указателя по токену, ни снимков, ни растущего буфера: все сочетания
  перебираются в лоб. Множитель считается тем же выражением, потому что
  порядок вещественных действий — часть задачи, а не реализации. }

function NaivePairs(const Engines: TChiEngines; Platform, Family: Integer;
  const Wanted: TArray<Boolean>): TArray<TChiPair>;
var
  Mine, Peer: TChiMarketRef;
  Cnt: Integer;
begin
  Result := nil;
  for var EngA in Engines do
  begin
    if EngA.Loading then Continue;
    if Family <> 0 then
    begin
      if EngA.Family <> Family then Continue;
    end
    else if EngA.Platform <> Platform then Continue;

    for var IA := 0 to EngA.Markets.Count - 1 do
    begin
      Mine := EngA.Markets[IA];
      if not Mine.Active then Continue;
      if Mine.Currency = '' then Continue;
      Cnt := 0;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Mine := Mine;
      Result[High(Result)].Peers := nil;
      for var EngB in Engines do
      begin
        if EngB.Loading then Continue;
        for var IB := 0 to EngB.Markets.Count - 1 do
        begin
          Peer := EngB.Markets[IB];
          if Peer.Currency <> Mine.Currency then Continue;
          if Peer.Currency = '' then Continue;
          if Peer = Mine then Continue;
          if not Wanted[Peer.Exchange] then Continue;
          if not Peer.Active then Continue;
          if not GroupsMatch(Mine.GroupId, Peer.GroupId) then Continue;
          SetLength(Result[High(Result)].Peers, Cnt + 1);
          Result[High(Result)].Peers[Cnt].Market := Peer;
          Result[High(Result)].Peers[Cnt].PriceMul :=
            (Mine.K1000 * Peer.PriceScale) / (Peer.K1000 * Mine.PriceScale);
          Inc(Cnt);
        end;
      end;
      if Cnt = 0 then SetLength(Result, Length(Result) - 1);
    end;
  end;
end;

function SamePairs(const A, B: TArray<TChiPair>): Boolean;
var
  I, J: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
  begin
    if A[I].Mine <> B[I].Mine then Exit(False);
    if Length(A[I].Peers) <> Length(B[I].Peers) then Exit(False);
    for J := 0 to High(A[I].Peers) do
    begin
      if A[I].Peers[J].Market <> B[I].Peers[J].Market then Exit(False);
      if PCardinal(@A[I].Peers[J].PriceMul)^
         <> PCardinal(@B[I].Peers[J].PriceMul)^ then Exit(False);
    end;
  end;
end;

{ ═══ Мир ═════════════════════════════════════════════════════════════════ }

const
  IdPair  = 'CHI-ARB-PAIR-001';
  IdMatch = 'CHI-ARB-PAIR-002';
  Tokens: array [0 .. 5] of AnsiString = ('BTC', 'ETH', 'PEPE', 'SOL', 'CAT', '');

function MakeWorld(Seed: UInt64; Engines: Integer): TChiEngines;
var
  Src: TChiSource;
  E: TChiEngine;
  M: TChiMarketRef;
  I, J, Count: Integer;
begin
  Result := TChiEngines.Create(True);
  Src := ChiSource(Seed);
  for I := 0 to Engines - 1 do
  begin
    E := TChiEngine.Create;
    E.Platform := I;
    { Два движка одного семейства — ветка родственных бирж. }
    if I < 2 then E.Family := 7 else E.Family := 0;
    { Один движок нарочно ещё грузится: его рынки не имеют права попасть. }
    E.Loading := I = (Engines - 1);
    Count := 3 + Src.NextBelow(6);
    for J := 0 to Count - 1 do
    begin
      M := TChiMarketRef.Create;
      M.Exchange := I;
      M.Currency := Tokens[Src.NextBelow(Length(Tokens))];
      M.Display := M.Currency;
      M.Active := Src.NextBelow(5) > 0;
      { Ноль встречается чаще: в жизни расхождений почти не бывает. }
      if Src.NextBelow(3) = 0 then M.GroupId := 1 + Src.NextBelow(3)
                              else M.GroupId := 0;
      if Src.NextBelow(4) = 0 then M.K1000 := 1000 else M.K1000 := 1;
      if Src.NextBelow(6) = 0 then M.PriceScale := 10 else M.PriceScale := 1;
      M.LastPrice := 0.5 + Src.NextUnit * 100;
      E.Markets.Add(M);
    end;
    Result.Add(E);
  end;
end;

function ChiPairsRun: Int64;
var
  World: TChiEngines;
  Index: TDictionary<AnsiString, TArray<TChiMarketRef>>;
  Wanted: TArray<Boolean>;
  Pairs, Naive: TArray<TChiPair>;
  Total, Considered, Skipped, I, J, Round: Integer;
  Acc: UInt64;
  Mine, Peer: Integer;
  WithPeers, Scaled, Denominated: Integer;
  Expect: Single;
begin
  ChiCovered(IdPair);
  ChiCovered(IdMatch);
  Acc := ChiOffset;

  { ── Правило совпадения предъявляется таблицей, а не примерами ── }
  for Mine := 0 to 3 do
    for Peer := 0 to 3 do
    begin
      ChiClaim(GroupsMatch(Mine, Peer)
               = ((Mine = 0) and (Peer = 0)) or ((Mine <> 0) and (Mine = Peer)),
        'пары: правило совпадения нарушено на ' + IntToStr(Mine) + '/'
        + IntToStr(Peer));
      Acc := ChiMix(Acc, Ord(GroupsMatch(Mine, Peer)));
    end;
  ChiClaim(GroupsMatch(0, 0), 'пары: два непроверенных обязаны сходиться');
  ChiClaim(not GroupsMatch(0, 5), 'пары: ноль против ненулевого обязан рвать');
  ChiClaim(not GroupsMatch(5, 0), 'пары: ненулевое против нуля обязано рвать');
  ChiClaim(GroupsMatch(5, 5), 'пары: одно тождество обязано сходиться');
  ChiClaim(not GroupsMatch(5, 6), 'пары: разные тождества обязаны рваться');
  ChiBranch(IdMatch, 'table');

  WithPeers := 0;
  Scaled := 0;
  Denominated := 0;

  for Round := 0 to 3 do
  begin
    World := MakeWorld(2000 + UInt64(Round), 4 + Round);
    try
      SetLength(Wanted, World.Count);
      for I := 0 to High(Wanted) do Wanted[I] := (I mod 4) <> 3;

      Index := BuildIndex(World, Total);
      try
        ChiClaim(Total > 0, 'пары: указатель не увидел ни одного рынка');

        { Обычная ветка: один движок клиента. }
        Pairs := BuildPairs(World, 2, 0, Index, Wanted, Considered, Skipped);
        Naive := NaivePairs(World, 2, 0, Wanted);
        ChiClaim(SamePairs(Pairs, Naive),
          'пары: одиночный движок разошёлся с наивным перебором');
        if Length(Pairs) > 0 then ChiBranch(IdPair, 'single-engine');
        if Skipped > 0 then ChiBranch(IdPair, 'skipped');
        Acc := ChiMix(Acc, Length(Pairs));
        Acc := ChiMix(Acc, Considered);

        { Ветка семейства: рынки нескольких родственных движков в одном наборе. }
        Pairs := BuildPairs(World, 0, 7, Index, Wanted, Considered, Skipped);
        Naive := NaivePairs(World, 0, 7, Wanted);
        ChiClaim(SamePairs(Pairs, Naive),
          'пары: семейство движков разошлось с наивным перебором');
        if Length(Pairs) > 0 then ChiBranch(IdPair, 'engine-family');
        Acc := ChiMix(Acc, Length(Pairs));

        for I := 0 to High(Pairs) do
        begin
          if Length(Pairs[I].Peers) > 0 then Inc(WithPeers);
          for J := 0 to High(Pairs[I].Peers) do
          begin
            { Множитель обязан совпасть с посчитанным тем же выражением.
              Адрес берётся у переменной, а не у выражения: приведение типа
              выражения адреса не имеет. }
            Expect := (Pairs[I].Mine.K1000
                       * Pairs[I].Peers[J].Market.PriceScale)
                      / (Pairs[I].Peers[J].Market.K1000
                         * Pairs[I].Mine.PriceScale);
            ChiClaim(PCardinal(@Pairs[I].Peers[J].PriceMul)^
                     = PCardinal(@Expect)^,
              'пары: множитель цены пересчитан иначе');
            if Pairs[I].Peers[J].Market.PriceScale <> 1 then Inc(Scaled);
            if Pairs[I].Peers[J].Market.K1000 <> 1 then Inc(Denominated);
            Acc := ChiMix(Acc, PCardinal(@Pairs[I].Peers[J].PriceMul)^);
          end;
        end;

        { Движок, который ещё грузится, не имеет права дать ни одной пары. }
        Pairs := BuildPairs(World, World.Count - 1, 0, Index, Wanted,
                            Considered, Skipped);
        ChiClaim(Length(Pairs) = 0,
          'пары: незагруженный движок дал пары');
        ChiBranch(IdPair, 'loading-skipped');

        { Никого не хотим — ни одной пары. }
        for I := 0 to High(Wanted) do Wanted[I] := False;
        Pairs := BuildPairs(World, 2, 0, Index, Wanted, Considered, Skipped);
        ChiClaim(Length(Pairs) = 0, 'пары: при пустом наборе бирж есть пары');
        ChiBranch(IdPair, 'nobody-wanted');
        for I := 0 to High(Wanted) do Wanted[I] := (I mod 4) <> 3;
      finally
        FreeAndNil(Index);
      end;
    finally
      FreeAndNil(World);
    end;
  end;

  ChiClaim(WithPeers > 0, 'пары: ни одна пара не получила соседей');
  ChiClaim(Scaled > 0, 'пары: нестандартная шкала цены не встретилась');
  ChiClaim(Denominated > 0, 'пары: тысячный номинал не встретился');
  ChiBranch(IdPair, 'price-scale');
  ChiBranch(IdPair, 'denomination');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
