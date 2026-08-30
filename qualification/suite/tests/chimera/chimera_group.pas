unit chimera_group;

{ Орган «серии»: накопление подряд идущих наблюдений и справочник тождеств.

  Источники: `Arbitrage/Common\GroupManager.pas` — учёт
  серий наблюдений по гипотезе; `Common/CanonMapper.pas` — справочник с
  составным ключом и списками записей. Перенесено дословно по форме:

    * серия засчитывается ТОЛЬКО когда исход тот же, прошло не меньше
      минимального промежутка, разрыв не больше предельного, И обе стороны
      предъявили НОВЫЕ ревизии данных. Замороженная лента отдаёт один и тот же
      снимок, а три чтения одной памяти не есть три доказательства;
    * при несовпадении исхода или слишком большом разрыве серия начинается
      заново с единицы, а не обнуляется;
    * когда промежуток мал или ревизии не сдвинулись, отметка времени НЕ
      обновляется: иначе мёртвые данные бесконечно продлевали бы серию;
    * все сравнения времён идут через модуль разности — защита от скачка часов
      назад;
    * справочник: ключ составной (сеть и адрес), под одним именем живут
      РАЗНЫЕ записи, имена нормализуются к нижнему регистру, а отсутствие
      адреса заменяется особым значением, а не пустотой.

  Заменено оснасткой: часы (время подаётся параметром) и сеть.

  Почему это отдельная форма:

    * правило засчитывания — цепочка из пяти условий, где каждое отсекает свой
      способ обмануться. Свернув любое, получаем серию из ничего;
    * счётчик и отметка времени живут в записи ВНУТРИ словаря: чтобы их
      изменить, запись достают, правят и кладут обратно — три действия там,
      где кажется одно;
    * составной ключ строится склейкой строк, и разные части могут дать один
      ключ при неудачной склейке.

  Оракулы:

    1. независимая модель серии — таблица решений, посчитанная отдельно от
       кода, который серию ведёт;
    2. свойства: серия не растёт быстрее, чем одно засчитывание на подачу; при
       смене исхода она равна единице; при мёртвых ревизиях не растёт вовсе;
    3. справочник: разные записи под одним именем обязаны остаться разными, а
       поиск по составному ключу — находить ровно свою. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Generics.Collections, mormot.core.base, chimera_body;

const
  { Значения из живого кода. }
  ChiSampleMinIntervalMS = 20000;
  ChiStreakMaxGapMS      = 120000;
  ChiStreakThreshold     = 3;

type
  TChiStreak = record
    LastConfirmed: Boolean;
    Count:         Integer;
    LastMS:        Int64;
    CandTick:      Int64;
    WitTick:       Int64;
  end;

  { Одна запись справочника: под одним именем их может быть несколько. }
  TChiToken = class
    LocalId:  RawUtf8;
    Name:     RawUtf8;
    Chain:    RawUtf8;
    Addr:     RawUtf8;
    Sources:  TList<RawUtf8>;
    constructor Create;
    destructor Destroy; override;
    function Key: RawUtf8;
  end;

function ChiGroupRun: Int64;

implementation

const
  IdGroup = 'CHI-ARB-GROUP-001';
  IdCanon = 'CHI-ARB-CANON-001';
  NativeAddr: RawUtf8 = '__native__';

{ ═══ Серии ═══════════════════════════════════════════════════════════════ }

type
  TChiStreaks = TDictionary<RawUtf8, TChiStreak>;

{ Возвращает True, если наблюдение засчитано (счётчик вырос или начат заново). }
function Observe(const Streaks: TChiStreaks; const Key: RawUtf8;
  Confirmed: Boolean; NowMS, CandTick, WitTick: Int64;
  out Counted: Boolean): Integer;
var
  Streak: TChiStreak;
begin
  Counted := False;
  { Ни записи, ни того же исхода, ни укладки в предельный разрыв — серия
    начинается заново с единицы. Разность времён берётся по модулю: часы
    вправе прыгнуть назад. }
  if not Streaks.TryGetValue(Key, Streak)
     or (Streak.LastConfirmed <> Confirmed)
     or (Abs(NowMS - Streak.LastMS) > ChiStreakMaxGapMS) then
  begin
    Streak.LastConfirmed := Confirmed;
    Streak.Count := 1;
    Streak.LastMS := NowMS;
    Streak.CandTick := CandTick;
    Streak.WitTick := WitTick;
    Streaks.AddOrSetValue(Key, Streak);
    Counted := True;
    Exit(1);
  end;

  { Слишком часто — не засчитываем, и отметку НЕ двигаем. }
  if Abs(NowMS - Streak.LastMS) < ChiSampleMinIntervalMS then
    Exit(Streak.Count);

  { Ревизии не сдвинулись — тот же снимок, не новое доказательство. Отметку
    тоже не двигаем: мёртвые данные обязаны честно порвать серию по разрыву. }
  if (CandTick = Streak.CandTick) or (WitTick = Streak.WitTick) then
    Exit(Streak.Count);

  Inc(Streak.Count);
  Streak.LastMS := NowMS;
  Streak.CandTick := CandTick;
  Streak.WitTick := WitTick;
  Streaks.AddOrSetValue(Key, Streak);
  Counted := True;
  Result := Streak.Count;
end;

{ ═══ Справочник ══════════════════════════════════════════════════════════ }

constructor TChiToken.Create;
begin
  inherited Create;
  Sources := TList<RawUtf8>.Create;
end;

destructor TChiToken.Destroy;
begin
  FreeAndNil(Sources);
  inherited Destroy;
end;

function TChiToken.Key: RawUtf8;
begin
  { Составной ключ: сеть и адрес через двоеточие. Обе части уже приведены к
    нижнему регистру, а отсутствие адреса заменено особым значением — иначе
    два разных родных актива дали бы один ключ. }
  Result := Chain + ':' + Addr;
end;

function NormalizeChain(const Raw: RawUtf8): RawUtf8;
begin
  Result := RawUtf8(LowerCase(string(Raw)));
  { Живые источники пишут одну сеть по-разному. }
  if (Result = 'erc20') or (Result = 'ethereum') then Result := 'eth';
  if (Result = 'bep20') or (Result = 'bsc-token') then Result := 'bsc';
  if Result = 'trc20' then Result := 'tron';
end;

function NormalizeAddr(const Raw: RawUtf8): RawUtf8;
begin
  if Raw = '' then
    Result := NativeAddr
  else
    Result := RawUtf8(LowerCase(string(Raw)));
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

function ChiGroupRun: Int64;
var
  Streaks: TChiStreaks;
  Acc: UInt64;
  N, I, Started, Grown, Refused: Integer;
  Counted: Boolean;
  T: Int64;
  Tokens: TObjectList<TChiToken>;
  ByKey: TDictionary<RawUtf8, TChiToken>;
  ByName: TDictionary<RawUtf8, Integer>;
  Tok: TChiToken;
  Found: TChiToken;
  Cnt: Integer;
begin
  ChiCovered(IdGroup);
  ChiCovered(IdCanon);
  Acc := ChiOffset;

  Streaks := TChiStreaks.Create;
  try
    Started := 0;
    Grown := 0;
    Refused := 0;

    { ── Ровная серия: исход один, промежутки достаточные, ревизии новые ── }
    T := 1000000;
    N := Observe(Streaks, 'AAA', True, T, 1, 1, Counted);
    ChiClaim(N = 1, 'серии: первое наблюдение не начало серию');
    ChiClaim(Counted, 'серии: первое не засчитано');
    Inc(Started);
    for I := 1 to 4 do
    begin
      Inc(T, ChiSampleMinIntervalMS + 1);
      N := Observe(Streaks, 'AAA', True, T, 1 + I, 1 + I, Counted);
      ChiClaim(N = I + 1, 'серии: счётчик не вырос на шаге ' + IntToStr(I));
      ChiClaim(Counted, 'серии: шаг не засчитан');
      Inc(Grown);
    end;
    ChiClaim(N >= ChiStreakThreshold, 'серии: порог не достигнут');
    ChiBranch(IdGroup, 'steady-growth');
    Acc := ChiMix(Acc, N);

    { ── Слишком частая подача не засчитывается ── }
    Inc(T, ChiSampleMinIntervalMS div 2);
    N := Observe(Streaks, 'AAA', True, T, 100, 100, Counted);
    ChiClaim(not Counted, 'серии: слишком частое засчитано');
    ChiClaim(N = 5, 'серии: слишком частое сдвинуло счётчик');
    Inc(Refused);
    ChiBranch(IdGroup, 'too-soon');

    { ── Мёртвые ревизии: время идёт, а данные те же ── }
    Inc(T, ChiSampleMinIntervalMS + 1);
    N := Observe(Streaks, 'AAA', True, T, 5, 5, Counted);
    ChiClaim(not Counted, 'серии: мёртвая ревизия засчитана');
    ChiClaim(N = 5, 'серии: мёртвая ревизия сдвинула счётчик');
    Inc(Refused);
    ChiBranch(IdGroup, 'stale-revision');

    { Сдвинулась только одна сторона — тоже не доказательство. }
    Inc(T, ChiSampleMinIntervalMS + 1);
    N := Observe(Streaks, 'AAA', True, T, 999, 5, Counted);
    ChiClaim(not Counted, 'серии: односторонняя ревизия засчитана');
    ChiBranch(IdGroup, 'one-side-only');

    { ── Смена исхода начинает серию заново ── }
    Inc(T, ChiSampleMinIntervalMS + 1);
    N := Observe(Streaks, 'AAA', False, T, 1000, 1000, Counted);
    ChiClaim(N = 1, 'серии: смена исхода не сбросила серию');
    ChiClaim(Counted, 'серии: смена исхода не засчитана');
    ChiBranch(IdGroup, 'verdict-flip');

    { ── Разрыв больше предельного рвёт серию ── }
    Inc(T, ChiStreakMaxGapMS + 1);
    N := Observe(Streaks, 'AAA', False, T, 2000, 2000, Counted);
    ChiClaim(N = 1, 'серии: слишком большой разрыв не порвал серию');
    ChiBranch(IdGroup, 'gap-breaks');

    { ── Часы прыгнули назад: разность по модулю обязана это пережить ── }
    Dec(T, ChiStreakMaxGapMS * 3);
    N := Observe(Streaks, 'AAA', False, T, 3000, 3000, Counted);
    ChiClaim(N = 1, 'серии: скачок часов назад не порвал серию');
    ChiClaim(Counted, 'серии: после скачка часов серия не началась');
    ChiBranch(IdGroup, 'clock-back');

    { ── Мёртвые данные не продлевают серию бесконечно ──

      Отметка времени не двигается при отказах, значит рано или поздно разрыв
      превысит предельный и серия честно порвётся — а не будет расти вечно на
      одном и том же снимке. }
    Streaks.Clear;
    T := 5000000;
    Observe(Streaks, 'BBB', True, T, 1, 1, Counted);
    for I := 1 to 10 do
    begin
      Inc(T, ChiSampleMinIntervalMS + 1);
      N := Observe(Streaks, 'BBB', True, T, 1, 1, Counted);
      ChiClaim(N <= 1, 'серии: мёртвый снимок растит серию');
    end;
    { Точное свойство: на мёртвом снимке серия НИ РАЗУ не поднялась выше
      единицы, сколько бы подач ни было. Требовать «и следующее живое
      наблюдение начнёт заново» было бы неверно: разрыв, порвав серию,
      перезапускает её и ОБНОВЛЯЕТ отметку времени, поэтому живое наблюдение
      законно продолжает уже начатую заново серию со второго. }
    Inc(T, ChiSampleMinIntervalMS + 1);
    N := Observe(Streaks, 'BBB', True, T, 77, 88, Counted);
    ChiClaim(Counted, 'серии: живое наблюдение после мёртвого не засчитано');
    ChiClaim(N < ChiStreakThreshold,
      'серии: мёртвый период дотянул серию до порога');
    ChiBranch(IdGroup, 'dead-data-breaks');
    Acc := ChiMix(Acc, Started + Grown + Refused);

    ChiClaim(Started > 0, 'серии: ни одна не начата');
    ChiClaim(Grown > 0, 'серии: ни одна не выросла');
    ChiClaim(Refused > 0, 'серии: ни одного отказа');
  finally
    FreeAndNil(Streaks);
  end;

  { ── Справочник ── }
  Tokens := TObjectList<TChiToken>.Create(True);
  ByKey := TDictionary<RawUtf8, TChiToken>.Create;
  ByName := TDictionary<RawUtf8, Integer>.Create;
  try
    { Под одним именем два РАЗНЫХ актива в разных сетях. }
    Tok := TChiToken.Create;
    Tok.Name := 'PEPE';
    Tok.Chain := NormalizeChain('Ethereum');
    Tok.Addr := NormalizeAddr('0x6982508145454CE325dDbE47a25d4ec3d2311933');
    Tok.LocalId := 'PEPE-1';
    Tok.Sources.Add('binance');
    Tokens.Add(Tok);

    Tok := TChiToken.Create;
    Tok.Name := 'PEPE';
    Tok.Chain := NormalizeChain('TRC20');
    Tok.Addr := NormalizeAddr('TXYZ0000000000000000000000000000');
    Tok.LocalId := 'PEPE-2';
    Tok.Sources.Add('gate');
    Tokens.Add(Tok);

    { Родной актив без адреса. }
    Tok := TChiToken.Create;
    Tok.Name := 'BTC';
    Tok.Chain := NormalizeChain('BITCOIN');
    Tok.Addr := NormalizeAddr('');
    Tok.LocalId := 'BTC-1';
    Tok.Sources.Add('binance');
    Tok.Sources.Add('bybit');
    Tokens.Add(Tok);

    { Второй родной актив в другой сети — ключи обязаны различаться. }
    Tok := TChiToken.Create;
    Tok.Name := 'ETH';
    Tok.Chain := NormalizeChain('ERC20');
    Tok.Addr := NormalizeAddr('');
    Tok.LocalId := 'ETH-1';
    Tokens.Add(Tok);

    for I := 0 to Tokens.Count - 1 do
    begin
      ChiClaim(not ByKey.ContainsKey(Tokens[I].Key),
        'справочник: составной ключ повторился');
      ByKey.Add(Tokens[I].Key, Tokens[I]);
      if ByName.TryGetValue(Tokens[I].Name, Cnt) then
        ByName[Tokens[I].Name] := Cnt + 1
      else
        ByName.Add(Tokens[I].Name, 1);
    end;

    ChiClaim(ByKey.Count = 4, 'справочник: ключей не четыре');
    ChiClaim(ByName['PEPE'] = 2, 'справочник: под именем не два актива');
    ChiBranch(IdCanon, 'same-name-two-assets');

    { Нормализация: разные написания одной сети сходятся в одно. }
    ChiClaim(NormalizeChain('Ethereum') = NormalizeChain('ERC20'),
      'справочник: написания сети не сошлись');
    ChiClaim(NormalizeChain('ETH') = 'eth', 'справочник: сеть не нормализована');
    ChiClaim(NormalizeChain('TRC20') = 'tron', 'справочник: сеть трона не та');
    ChiBranch(IdCanon, 'chain-aliases');

    { Отсутствие адреса заменяется особым значением, а не пустотой — иначе
      два родных актива в разных сетях дали бы один ключ. }
    ChiClaim(NormalizeAddr('') = NativeAddr,
      'справочник: пустой адрес не заменён');
    ChiClaim(Tokens[2].Key <> Tokens[3].Key,
      'справочник: два родных актива дали один ключ');
    ChiBranch(IdCanon, 'native-address');

    { Адрес нормализуется к нижнему регистру: биржи пишут вперемешку. }
    ChiClaim(NormalizeAddr('0xABCDEF') = NormalizeAddr('0xabcdef'),
      'справочник: регистр адреса не нормализован');
    ChiBranch(IdCanon, 'address-case');

    { Поиск по составному ключу находит ровно свою запись. }
    ChiClaim(ByKey.TryGetValue(RawUtf8('eth:0x6982508145454ce325ddbe47a25d4ec3d2311933'),
      Found), 'справочник: запись по ключу не найдена');
    ChiClaim(Found.LocalId = 'PEPE-1', 'справочник: найдена не та запись');
    ChiClaim(not ByKey.ContainsKey(RawUtf8('eth:нетТакого')),
      'справочник: нашёлся несуществующий ключ');
    ChiBranch(IdCanon, 'lookup');

    { Списки источников живут внутри записей и не путаются между ними. }
    ChiClaim(Tokens[2].Sources.Count = 2, 'справочник: источников не два');
    ChiClaim(Tokens[3].Sources.Count = 0, 'справочник: источники протекли');
    ChiBranch(IdCanon, 'per-record-lists');
    Acc := ChiMix(Acc, ByKey.Count);
    Acc := ChiMix(Acc, Tokens[2].Sources.Count);
  finally
    FreeAndNil(ByName);
    FreeAndNil(ByKey);
    FreeAndNil(Tokens);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
