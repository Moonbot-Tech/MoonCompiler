unit chimera_text;

{ Орган «текст»: ручная выкладка отчёта писателем и усадка буфера-строки.

  Два предмета, оба про managed-строку под ручным управлением.

  ── CHI-ARB-TEXT-001 ──────────────────────────────────────────────────────
  Источник: `Arbitrage/ArbServer\ArbServer.pas` ::
  `DumpFilterAnalysis` (та же форма — в `Common/GroupManager.pas` и
  `Common/AIClient.pas`). Перенесено дословно по форме:

    * писатель создаётся НАД БУФЕРОМ В КАДРЕ вызывающей функции: восемь
      килобайт живут на стеке, и всё, что сверх, уходит в поток. Граница
      проходит внутри отчёта, а не по его краю;
    * скобки и запятые ставятся руками, а «первый ли это» помнят три
      отдельных флага на трёх уровнях вложенности;
    * вложенная процедура пишет в писателя ВНЕШНЕЙ функции — то есть в
      переменную чужого кадра;
    * значения кладутся разными способами по типу: беззнаковое, дробное
      одинарной точности, готовая строка, отдельный символ, пара символов
      одним вызовом, и кусок текста БЕЗ экранирования;
    * решение «отправили бы» собирается из восьми условий, часть которых
      сама считается из разностей времён и цен.

  ── CHI-MB-REUSE-001 ──────────────────────────────────────────────────────
  Источник: `MoonBot/websocket\WebSocket.Thread.pas` ::
  `TWSThread.EmitText` и `Arbitrage/Engines\BinanceEngine.pas`
  (разбор сделки). Обе формы пишут прямо в тело строки и подделывают её
  длину, минуя выделение памяти:

    * ёмкость помнится ОТДЕЛЬНЫМ полем, потому что подделка длины усаживает
      Length, и по Length ёмкость уже не узнать;
    * перед записью проверяется счётчик ссылок: если строку кто-то удержал,
      буфер отпускается целиком, иначе запись испортила бы чужие данные;
    * вторая форма (биржевого разбора) ёмкость отдельно НЕ помнит и меряет по
      Length. Она корректна, но теряет переиспользование после каждой усадки —
      обе формы стоят рядом именно ради этой разницы.

  Заменено оснасткой: сеть и сокет. Данные детерминированы.

  Оракулы:

    1. отчёт строится вторым, независимым способом — обычной склейкой строк,
       и решение считается вторым набором выражений. Совпадение проверяется
       посимвольно, а дробные числа — по значению: печать числа у писателя
       своя, и сверять её текстом было бы сверкой библиотеки с самой собой;
    2. переполнение стекового буфера предъявляется размером: отчёт заведомо
       длиннее буфера, и при этом совпадает с эталоном целиком;
    3. у буфера-строки сверяется содержимое, длина и счётчик перевыделений:
       форма с отдельной ёмкостью после разогрева не выделяет памяти вовсе,
       форма по длине — выделяет на каждом росте;
    4. удержанная наружу строка обязана пережить следующую запись. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  mormot.core.base, mormot.core.text, chimera_body;

function ChiTextRun: Int64;

implementation

const
  IdText  = 'CHI-ARB-TEXT-001';
  IdReuse = 'CHI-MB-REUSE-001';

  TradeStaleMS      = 15 * 60 * 1000;
  PendingWindowMS   = 5 * 60 * 1000;

type
  { Рынок в том объёме, в каком его читает выкладка отчёта. }
  TChiPeer = class
    Exchange:      Integer;
    Currency:      RawUtf8;
    GroupId:       Integer;
    LastPrice:     Single;
    LastTradeTick: Int64;
    LastWsTick:    Int64;
    Active:        Boolean;
    IsTradFI:      Boolean;
    Pending:       Boolean;
    PendingSince:  Int64;
    PriceScale:    Single;
    K1000Inv:      Single;
  end;

  TChiPeers = TObjectList<TChiPeer>;

{ ═══ Живая форма: выкладка отчёта писателем ══════════════════════════════ }

{ Дословный перенос: писатель над буфером в кадре, флаги «первый» на трёх
  уровнях, вложенная процедура пишет в писателя внешней функции. }
function BuildReport(const AClients: TObjectList<TChiPeers>;
  ANow: Int64): RawUtf8;
var
  W:     TTextWriter;
  Stack: TTextWriterStackBuffer;

  procedure WriteBool(B: Boolean);
  begin
    if B then W.AddString(RawUtf8('true')) else W.AddString(RawUtf8('false'));
  end;

begin
  W := TTextWriter.CreateOwnedStream(Stack);
  try
    W.AddDirect('{');
    W.AddString(RawUtf8('"by_client":{'));
    var FirstClient := True;
    for var Group in AClients do
    begin
      if Group.Count = 0 then Continue;
      if not FirstClient then W.AddDirect(',');
      FirstClient := False;
      W.AddDirect('"');
      W.AddU(Group[0].Exchange);
      W.AddString(RawUtf8('":{"ccy":{'));
      var FirstCcy := True;
      for var My in Group do
      begin
        if not My.Active then Continue;
        var HasAny := False;
        for var Peer in Group do
          if Peer <> My then begin HasAny := True; Break; end;
        if not HasAny then Continue;

        if not FirstCcy then W.AddDirect(',');
        FirstCcy := False;
        W.AddDirect('"');
        W.AddNoJsonEscapeUtf8(My.Currency);
        W.AddString(RawUtf8('":{"my_gid":'));
        W.AddU(Cardinal(My.GroupId));
        W.AddString(RawUtf8(',"my_price":'));
        W.AddSingle(My.LastPrice);
        W.AddString(RawUtf8(',"peers":{'));
        var FirstPeer := True;
        for var Peer in Group do
        begin
          if Peer = My then Continue;
          var NoTrade := Peer.LastTradeTick = 0;
          var NoPrice := Peer.LastPrice <= 0;
          var NotActive := not Peer.Active;
          var Stale: Boolean;
          if Peer.IsTradFI
            then Stale := (Peer.LastTradeTick = 0) or
                          (abs(ANow - Peer.LastTradeTick) > 3 * 60 * 60 * 1000)
            else Stale := (Peer.LastWsTick = 0) or
                          (abs(ANow - Peer.LastWsTick) > TradeStaleMS);
          var FilterCut := not (((Peer.GroupId or My.GroupId) = 0) or
                                (Peer.GroupId = My.GroupId));
          var TradfiMismatch := (My.GroupId = 0) and (Peer.GroupId = 0) and
                                (My.IsTradFI <> Peer.IsTradFI);
          var PendingPeer := Peer.Pending;
          var PendingMy := My.Pending;
          var SpreadCut := False;
          if PendingPeer or PendingMy or TradfiMismatch then
          begin
            var MyN := My.LastPrice * My.K1000Inv * My.PriceScale;
            var PmN := Peer.LastPrice * Peer.K1000Inv * Peer.PriceScale;
            if (MyN > 0) and (PmN > 0) then
            begin
              var MinN: Single;
              if MyN < PmN then MinN := MyN else MinN := PmN;
              SpreadCut := Abs(MyN - PmN) > 0.30 * MinN;
            end;
          end;
          var WouldSend := (not NotActive) and (not NoPrice) and
                          (not NoTrade) and (not Stale) and
                          (not FilterCut) and (not SpreadCut) and
                          (not (PendingPeer and (abs(ANow - Peer.PendingSince) >= PendingWindowMS))) and
                          (not (PendingMy and (abs(ANow - My.PendingSince) >= PendingWindowMS)));
          if not FirstPeer then W.AddDirect(',');
          FirstPeer := False;
          W.AddDirect('"');
          W.AddU(Cardinal(Peer.Exchange));
          W.AddString(RawUtf8('":{"gid":'));
          W.AddU(Cardinal(Peer.GroupId));
          W.AddString(RawUtf8(',"price":'));
          W.AddSingle(Peer.LastPrice);
          W.AddString(RawUtf8(',"age_ms":'));
          if Peer.LastTradeTick > 0
            then W.AddU(Cardinal(abs(ANow - Peer.LastTradeTick)))
            else W.AddDirect('0');
          W.AddString(RawUtf8(',"active":'));           WriteBool(Peer.Active);
          W.AddString(RawUtf8(',"stale":'));            WriteBool(Stale);
          W.AddString(RawUtf8(',"no_trade":'));         WriteBool(NoTrade);
          W.AddString(RawUtf8(',"no_price":'));         WriteBool(NoPrice);
          W.AddString(RawUtf8(',"filter_cut":'));       WriteBool(FilterCut);
          W.AddString(RawUtf8(',"tradfi_mismatch":'));  WriteBool(TradfiMismatch);
          W.AddString(RawUtf8(',"spread_cut":'));       WriteBool(SpreadCut);
          W.AddString(RawUtf8(',"my_tradfi":'));        WriteBool(My.IsTradFI);
          W.AddString(RawUtf8(',"peer_tradfi":'));      WriteBool(Peer.IsTradFI);
          W.AddString(RawUtf8(',"pending_peer":'));     WriteBool(PendingPeer);
          W.AddString(RawUtf8(',"pending_my":'));       WriteBool(PendingMy);
          W.AddString(RawUtf8(',"would_send":'));       WriteBool(WouldSend);
          W.AddDirect('}');
        end;
        W.AddDirect('}', '}');
      end;
      W.AddDirect('}', '}');
    end;
    W.AddDirect('}', '}');
    Result := W.Text;
  finally
    FreeAndNil(W);
  end;
end;

{ ═══ Оракул отчёта: та же выкладка обычной склейкой ══════════════════════ }

{ Числа печатаются своим кодом: сверять печать писателя его же печатью
  бессмысленно, поэтому эталон печатает как умеет, а сверка чисел идёт по
  значению (см. SameUpToNumbers). }
function OracleReport(const AClients: TObjectList<TChiPeers>;
  ANow: Int64): RawUtf8;
var
  S: string;

  function B(V: Boolean): string;
  begin
    if V then Result := 'true' else Result := 'false';
  end;

  function F(V: Single): string;
  begin
    Result := FloatToStr(V, TFormatSettings.Invariant);
  end;

begin
  S := '{"by_client":{';
  var FirstClient := True;
  for var Group in AClients do
  begin
    if Group.Count = 0 then Continue;
    if not FirstClient then S := S + ',';
    FirstClient := False;
    S := S + '"' + IntToStr(Group[0].Exchange) + '":{"ccy":{';
    var FirstCcy := True;
    for var My in Group do
    begin
      if not My.Active then Continue;
      var HasAny := False;
      for var Peer in Group do
        if Peer <> My then begin HasAny := True; Break; end;
      if not HasAny then Continue;
      if not FirstCcy then S := S + ',';
      FirstCcy := False;
      S := S + '"' + string(My.Currency) + '":{"my_gid":' + IntToStr(My.GroupId) +
           ',"my_price":' + F(My.LastPrice) + ',"peers":{';
      var FirstPeer := True;
      for var Peer in Group do
      begin
        if Peer = My then Continue;
        var NoTrade := Peer.LastTradeTick = 0;
        var NoPrice := not (Peer.LastPrice > 0);
        var Stale: Boolean;
        if Peer.IsTradFI
          then Stale := (Peer.LastTradeTick = 0) or
                        (abs(ANow - Peer.LastTradeTick) > 10800000)
          else Stale := (Peer.LastWsTick = 0) or
                        (abs(ANow - Peer.LastWsTick) > TradeStaleMS);
        var BothZero := (Peer.GroupId = 0) and (My.GroupId = 0);
        var FilterCut := not (BothZero or (Peer.GroupId = My.GroupId));
        var TradfiMismatch := BothZero and (My.IsTradFI <> Peer.IsTradFI);
        var SpreadCut := False;
        if Peer.Pending or My.Pending or TradfiMismatch then
        begin
          var MyN := My.LastPrice * My.K1000Inv * My.PriceScale;
          var PmN := Peer.LastPrice * Peer.K1000Inv * Peer.PriceScale;
          if (MyN > 0) and (PmN > 0) then
          begin
            var MinN: Single;
            if MyN < PmN then MinN := MyN else MinN := PmN;
            SpreadCut := Abs(MyN - PmN) > 0.30 * MinN;
          end;
        end;
        var PeerLate := Peer.Pending and (abs(ANow - Peer.PendingSince) >= PendingWindowMS);
        var MyLate := My.Pending and (abs(ANow - My.PendingSince) >= PendingWindowMS);
        var WouldSend := Peer.Active and (not NoPrice) and (not NoTrade) and
                         (not Stale) and (not FilterCut) and (not SpreadCut) and
                         (not PeerLate) and (not MyLate);
        if not FirstPeer then S := S + ',';
        FirstPeer := False;
        S := S + '"' + IntToStr(Peer.Exchange) + '":{"gid":' + IntToStr(Peer.GroupId) +
             ',"price":' + F(Peer.LastPrice) + ',"age_ms":';
        if Peer.LastTradeTick > 0
          then S := S + IntToStr(Cardinal(abs(ANow - Peer.LastTradeTick)))
          else S := S + '0';
        S := S + ',"active":' + B(Peer.Active) +
             ',"stale":' + B(Stale) +
             ',"no_trade":' + B(NoTrade) +
             ',"no_price":' + B(NoPrice) +
             ',"filter_cut":' + B(FilterCut) +
             ',"tradfi_mismatch":' + B(TradfiMismatch) +
             ',"spread_cut":' + B(SpreadCut) +
             ',"my_tradfi":' + B(My.IsTradFI) +
             ',"peer_tradfi":' + B(Peer.IsTradFI) +
             ',"pending_peer":' + B(Peer.Pending) +
             ',"pending_my":' + B(My.Pending) +
             ',"would_send":' + B(WouldSend) + '}';
      end;
      S := S + '}}';
    end;
    S := S + '}}';
  end;
  S := S + '}}';
  Result := RawUtf8(AnsiString(S));
end;

{ ═══ Сверка двух текстов ═════════════════════════════════════════════════ }

{ Проходит обе строки одновременно. Обычные символы обязаны совпасть; куски,
  похожие на число, вырезаются с обеих сторон и сравниваются по значению. Так
  разница печати дробных не мешает поймать разницу структуры. }
function SameUpToNumbers(const A, B: RawUtf8; out AWhere: Integer;
  out ANumbers: Integer): Boolean;

  function IsNumStart(const S: RawUtf8; P: Integer): Boolean;
  begin
    Result := (P <= Length(S)) and (S[P] in ['0' .. '9', '-']) and
              (P > 1) and (S[P - 1] in [':', ',']);
  end;

  function TakeNum(const S: RawUtf8; var P: Integer): Double;
  var
    Start: Integer;
    Txt:   string;
  begin
    Start := P;
    while (P <= Length(S)) and (S[P] in ['0' .. '9', '-', '+', '.', 'e', 'E']) do
      Inc(P);
    Txt := string(Copy(S, Start, P - Start));
    Result := StrToFloatDef(Txt, NaN, TFormatSettings.Invariant);
  end;

var
  I, J:   Integer;
  Na, Nb: Double;
begin
  AWhere := 0;
  ANumbers := 0;
  I := 1;
  J := 1;
  while (I <= Length(A)) and (J <= Length(B)) do
  begin
    if IsNumStart(A, I) and IsNumStart(B, J) then
    begin
      Na := TakeNum(A, I);
      Nb := TakeNum(B, J);
      Inc(ANumbers);
      if not ChiNear(Na, Nb, 1E-5 * (1 + Abs(Nb))) then
      begin
        AWhere := I;
        Exit(False);
      end;
    end
    else
    begin
      if A[I] <> B[J] then
      begin
        AWhere := I;
        Exit(False);
      end;
      Inc(I);
      Inc(J);
    end;
  end;
  AWhere := I;
  Result := (I > Length(A)) and (J > Length(B));
end;

{ ═══ Живая форма: буфер-строка с подделанной длиной ══════════════════════ }

type
  { Форма приёмника сообщений: ёмкость отдельным полем, счётчик ссылок
    решает, можно ли писать в тело. }
  TChiTextSink = class
  private
    FBuf:      RawUtf8;
    FCap:      Integer;
    FAllocs:   Integer;
    FReleases: Integer;
  public
    procedure Emit(Data: PByte; Len: Integer; out AOut: RawUtf8);
    property Allocs: Integer read FAllocs;
    property Releases: Integer read FReleases;
  end;

  { Форма биржевого разбора: ёмкость меряется по длине, потому усадка
    отменяет переиспользование. }
  TChiScratch = class
  private
    FBuf:    RawUtf8;
    FAllocs: Integer;
  public
    procedure Take(Data: PByte; Len: Integer; out AOut: RawUtf8);
    property Allocs: Integer read FAllocs;
  end;

procedure TChiTextSink.Emit(Data: PByte; Len: Integer; out AOut: RawUtf8);
begin
  if (Pointer(FBuf) <> nil) and (GetRefCount(FBuf) > 1) then
  begin
    FBuf := '';
    FCap := 0;
    Inc(FReleases);
  end;
  if Len > FCap then
  begin
    FastSetString(FBuf, Len);
    FCap := Len;
    Inc(FAllocs);
  end;
  MoveFast(Data^, Pointer(FBuf)^, Len);
  FakeLength(FBuf, Len);
  AOut := FBuf;
end;

procedure TChiScratch.Take(Data: PByte; Len: Integer; out AOut: RawUtf8);
begin
  if Len > Length(FBuf) then
  begin
    FastSetString(FBuf, Len);
    Inc(FAllocs);
  end;
  FakeLength(FBuf, Len);
  MoveFast(Data^, Pointer(FBuf)^, Len);
  AOut := FBuf;
end;

{ ═══ Оснастка данных ═════════════════════════════════════════════════════ }

function MakeClients(AGroups, APeers: Integer; ASeed: UInt64;
  ANow: Int64): TObjectList<TChiPeers>;
var
  Src:  TChiSource;
  Grp:  TChiPeers;
  Peer: TChiPeer;
begin
  Src := ChiSource(ASeed);
  Result := TObjectList<TChiPeers>.Create(True);
  for var G := 0 to AGroups - 1 do
  begin
    Grp := TChiPeers.Create(True);
    for var P := 0 to APeers - 1 do
    begin
      Peer := TChiPeer.Create;
      Peer.Exchange := G * 16 + P;
      Peer.Currency := RawUtf8(AnsiString('CCY' + IntToStr(G) + '_' + IntToStr(P)));
      { Группы 0 и совпадающие — обе ветви правила отбора. }
      case Src.NextBelow(3) of
        0: Peer.GroupId := 0;
        1: Peer.GroupId := 7;
      else Peer.GroupId := Src.NextBelow(5);
      end;
      { Ноль и отрицательная цена — обе ветви «цены нет». }
      case Src.NextBelow(8) of
        0: Peer.LastPrice := 0;
        1: Peer.LastPrice := -1;
      else Peer.LastPrice := 0.5 + Src.NextBelow(200000) * 0.001;
      end;
      if Src.NextBelow(7) = 0
        then Peer.LastTradeTick := 0
        else Peer.LastTradeTick := ANow - Src.NextBelow(4 * 60 * 60 * 1000);
      if Src.NextBelow(9) = 0
        then Peer.LastWsTick := 0
        else Peer.LastWsTick := ANow - Src.NextBelow(30 * 60 * 1000);
      Peer.Active := Src.NextBelow(10) > 0;
      Peer.IsTradFI := Src.NextBelow(4) = 0;
      Peer.Pending := Src.NextBelow(3) = 0;
      Peer.PendingSince := ANow - Src.NextBelow(10 * 60 * 1000);
      Peer.PriceScale := 1 + Src.NextBelow(4);
      Peer.K1000Inv := 1 / (1 + Src.NextBelow(3));
      Grp.Add(Peer);
    end;
    Result.Add(Grp);
  end;
  { Пустая бригада: ветвь «пропустить целиком» обязана быть живой. }
  Result.Add(TChiPeers.Create(True));
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiTextRun: Int64;
var
  Acc:      UInt64;
  Clients:  TObjectList<TChiPeers>;
  Live:     RawUtf8;
  Want:     RawUtf8;
  Where:    Integer;
  Numbers:  Integer;
  Sink:     TChiTextSink;
  Scratch:  TChiScratch;
  Held:     RawUtf8;
  Got:      RawUtf8;
  Data:     TBytes;
  Now64:    Int64;
begin
  Acc := 0;
  Now64 := Int64(1756500000000);

  { ── Выкладка отчёта ── }
  ChiCovered(IdText);
  Clients := MakeClients(6, 9, 20260830, Now64);
  try
    Live := BuildReport(Clients, Now64);
    Want := OracleReport(Clients, Now64);

    ChiClaim(Length(Live) > SizeOf(TTextWriterStackBuffer),
      'текст: отчёт короче буфера в кадре — переполнение не проверено');
    ChiBranch(IdText, 'overflows-stack-buffer');

    ChiClaim(SameUpToNumbers(Live, Want, Where, Numbers),
      'текст: отчёт разошёлся с эталоном на позиции ' + IntToStr(Where));
    ChiClaim(Numbers > 100, 'текст: чисел в отчёте меньше, чем ожидалось');
    ChiBranch(IdText, 'matches-oracle');
    Acc := ChiMix(Acc, Length(Live));
    Acc := ChiMix(Acc, Numbers);

    { Обе половины решения обязаны встретиться в отчёте, иначе восемь условий
      проверены наполовину. }
    ChiClaim(Pos(RawUtf8('"would_send":true'), Live) > 0,
      'текст: ни одного отправляемого соседа — правило проверено вхолостую');
    ChiClaim(Pos(RawUtf8('"would_send":false'), Live) > 0,
      'текст: ни одного отсечённого соседа');
    ChiBranch(IdText, 'both-decisions');
    ChiClaim(Pos(RawUtf8('"spread_cut":true'), Live) > 0,
      'текст: разброс цен ни разу не отсёк — ветвь мертва');
    ChiBranch(IdText, 'spread-cut-fires');
    ChiClaim(Pos(RawUtf8('"stale":true'), Live) > 0, 'текст: ни одного протухшего');
    ChiClaim(Pos(RawUtf8('"tradfi_mismatch":true'), Live) > 0,
      'текст: несовпадение рода рынка ни разу не случилось');
    ChiBranch(IdText, 'stale-and-mismatch');
    ChiClaim(Pos(RawUtf8('"age_ms":0'), Live) > 0,
      'текст: сосед без сделок ни разу не попался');
    ChiBranch(IdText, 'zero-age');

    { Пустая бригада не должна оставить после себя ни скобок, ни запятой. }
    ChiClaim(Pos(RawUtf8(',}'), Live) = 0, 'текст: лишняя запятая перед закрытием');
    ChiClaim(Pos(RawUtf8('{,'), Live) = 0, 'текст: лишняя запятая после открытия');
    ChiBranch(IdText, 'empty-group-skipped');

    { Печать дробного одинарной точности обязана читаться обратно тем же
      значением — иначе отчёт врёт о цене. }
    var Probe1: Single := 0.1;
    Probe1 := Probe1 * 3;   { значение, которое в одинарной точности неточно }
    var Probe := TObjectList<TChiPeers>.Create(True);
    try
      var G := TChiPeers.Create(True);
      for var K := 0 to 1 do
      begin
        var P := TChiPeer.Create;
        P.Exchange := K;
        P.Currency := RawUtf8('X');
        P.Active := True;
        P.LastPrice := Probe1;
        P.LastTradeTick := Now64 - 1000;
        P.LastWsTick := Now64 - 1000;
        P.PriceScale := 1;
        P.K1000Inv := 1;
        G.Add(P);
      end;
      Probe.Add(G);
      var One := BuildReport(Probe, Now64);
      var At := Pos(RawUtf8('"price":'), One);
      ChiClaim(At > 0, 'текст: цена не найдена в отчёте');
      var Tail := Copy(One, At + 8, 24);
      var Cut := Pos(RawUtf8(','), Tail);
      var Back := StrToFloatDef(string(Copy(Tail, 1, Cut - 1)), NaN,
        TFormatSettings.Invariant);
      ChiClaim(Single(Back) = Probe1,
        'текст: напечатанная цена не читается обратно тем же числом');
      ChiBranch(IdText, 'single-roundtrip');
      Acc := ChiMix(Acc, Length(One));
    finally
      FreeAndNil(Probe);
    end;
  finally
    FreeAndNil(Clients);
  end;

  { ── Буфер-строка с подделанной длиной ── }
  ChiCovered(IdReuse);
  Sink := TChiTextSink.Create;
  Scratch := TChiScratch.Create;
  try
    SetLength(Data, 4096);
    for var I := 0 to High(Data) do
      Data[I] := Byte(33 + (I mod 90));

    { Разогрев: первая запись выделяет память. }
    Sink.Emit(@Data[0], 1000, Got);
    ChiClaim(Sink.Allocs = 1, 'усадка: первая запись не выделила буфер');
    ChiClaim(Length(Got) = 1000, 'усадка: длина после первой записи неверна');
    ChiClaim(CompareMem(Pointer(Got), @Data[0], 1000),
      'усадка: содержимое после первой записи неверно');
    ChiBranch(IdReuse, 'first-allocates');

    { Убывающие длины: ёмкость помнится отдельно, значит выделений больше нет,
      а длина каждый раз ровно та, что просили. }
    for var Len := 999 downto 900 do
    begin
      Sink.Emit(@Data[0], Len, Got);
      ChiClaim(Length(Got) = Len, 'усадка: длина не совпала при усадке до ' + IntToStr(Len));
      ChiClaim(CompareMem(Pointer(Got), @Data[0], Len),
        'усадка: содержимое испортилось при усадке');
    end;
    ChiClaim(Sink.Allocs = 1, 'усадка: усадка вызвала перевыделение');
    ChiBranch(IdReuse, 'shrink-keeps-capacity');

    { Рост в пределах прежней ёмкости — тоже без выделения. }
    Sink.Emit(@Data[0], 1000, Got);
    ChiClaim(Sink.Allocs = 1, 'усадка: возврат к прежней длине выделил заново');
    ChiClaim(Length(Got) = 1000, 'усадка: возврат к прежней длине дал не ту длину');
    ChiBranch(IdReuse, 'regrow-within-capacity');

    { Хвост прошлой записи не имеет права торчать: после длинной пишем
      короткую и сверяем ровно короткую. }
    Sink.Emit(@Data[0], 4096, Got);
    ChiClaim(Sink.Allocs = 2, 'усадка: рост выше ёмкости не выделил');
    Sink.Emit(@Data[100], 10, Got);
    ChiClaim(Length(Got) = 10, 'усадка: короткая запись после длинной дала не ту длину');
    ChiClaim(CompareMem(Pointer(Got), @Data[100], 10),
      'усадка: короткая запись после длинной взяла чужие байты');
    ChiBranch(IdReuse, 'short-after-long');

    { Удержание наружу: пока строку держат, писать в её тело нельзя. Форма
      обязана отпустить буфер и выдать НОВУЮ память, не тронув удержанную.
      Прошлую выдачу перед этим отпускаем сами: она тоже держит буфер, и без
      этого непонятно, чьё именно удержание сработало. }
    Got := '';
    var ReleasedBefore := Sink.Releases;
    Sink.Emit(@Data[0], 64, Held);
    var Snapshot: RawUtf8;
    FastSetString(Snapshot, Pointer(Held), Length(Held));
    ChiClaim(Sink.Releases = ReleasedBefore, 'усадка: отпустил буфер раньше времени');
    Sink.Emit(@Data[500], 64, Got);
    ChiClaim(Sink.Releases = ReleasedBefore + 1, 'усадка: не отпустил удержанный буфер');
    ChiClaim(CompareMem(Pointer(Held), Pointer(Snapshot), Length(Snapshot)),
      'усадка: запись испортила удержанную наружу строку');
    ChiClaim(Pointer(Held) <> Pointer(Got), 'усадка: удержанная и новая — одна память');
    ChiBranch(IdReuse, 'held-survives');
    Acc := ChiMix(Acc, Sink.Allocs);
    Acc := ChiMix(Acc, Sink.Releases);

    { Вторая форма: ёмкость по длине. Усадка стирает память о ёмкости, и
      каждый возврат к прежней длине выделяет заново — вот цена разницы. }
    Scratch.Take(@Data[0], 40, Got);
    ChiClaim(Scratch.Allocs = 1, 'вырезка: первая запись не выделила');
    for var K := 0 to 9 do
    begin
      Scratch.Take(@Data[0], 8, Got);
      ChiClaim(Length(Got) = 8, 'вырезка: короткая длина неверна');
      Scratch.Take(@Data[0], 40, Got);
      ChiClaim(Length(Got) = 40, 'вырезка: длинная длина неверна');
      ChiClaim(CompareMem(Pointer(Got), @Data[0], 40), 'вырезка: содержимое неверно');
    end;
    ChiClaim(Scratch.Allocs = 11, 'вырезка: число перевыделений не то, что обещает форма');
    ChiBranch(IdReuse, 'length-based-realloc');
    Acc := ChiMix(Acc, Scratch.Allocs);

    { Пустая запись: живой путь до неё не доходит намеренно — подделка длины
      нулём пишет в отсутствующий буфер. Проверяем, что защита выше по потоку
      именно поэтому и нужна: у пустого буфера тела нет. }
    var Empty: RawUtf8 := '';
    ChiClaim(Pointer(Empty) = nil, 'усадка: пустая строка имеет тело');
    ChiBranch(IdReuse, 'empty-has-no-body');
  finally
    FreeAndNil(Scratch);
    FreeAndNil(Sink);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
