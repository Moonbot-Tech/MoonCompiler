unit chimera_state;

{ Орган «канон состояния»: плотная запись, секции по маске и число переменной
  длины.

  Источник: `MoonBot/MoonProto\MoonProtoOrderState.pas` — канон
  состояния ордера в протоколе бота. Перенесено дословно по форме:

    * состояние — ОДНА плотная запись строго заданного размера, собранная из
      вложенных плотных записей; её байты детерминированы, потому что по ним
      считается пруф и делается сравнение;
    * поверх записи лежит таблица границ: тринадцать секций заданы массивами
      смещений и размеров. Секция едет по проводу ТОЛЬКО целиком;
    * какие секции менялись — считается сравнением памяти по границам, ответ
      возвращается битовой маской;
    * какие секции непустые — считается побайтовым обходом с досрочным
      выходом на первом ненулевом;
    * длины и счётчики едут числом ПЕРЕМЕННОЙ ДЛИНЫ: по семь бит на байт,
      старший бит — признак продолжения. Запись собирает байты в кадре и
      отдаёт разом, чтение идёт прямо по памяти буфера, минуя поток, и
      обрывается на десятом байте;
    * пруф — контрольная сумма от трёх кусков подряд: счётчика правок,
      паспорта в проводной форме и всего канона;
    * паспорт несёт длину имени и ровно столько байт имени, сколько сказано;
      нулевой хвост буфера в пруф НЕ входит;
    * времена на проводе — целые в мировом времени, а всё, что раньше начала
      отсчёта, считается не фактом, а пустотой.

  Заменено оснасткой: настройки стопов взяты непрозрачными байтами того же
  размера — канон и сам обращается с ними как с байтами (сравнение памяти), а
  их разбор живёт в другом месте.

  Оракулы:

    1. число переменной длины пишется и читается ВТОРЫМ способом — делением и
       умножением вместо сдвигов, и на общепринятых границах;
    2. таблица границ проверяется на согласованность: смещение каждой секции
       обязано равняться сумме размеров предыдущих, а сумма всех — размеру
       канона. Это проверка самой таблицы, а не пользы от неё;
    3. частичная передача сверяется двусторонне: внутри маски копия обязана
       совпасть с источником, ВНЕ маски — остаться нетронутой;
    4. пруф считается независимо, склейкой тех же трёх кусков вручную, и
       обязан меняться от правки в ЛЮБОЙ секции. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, DateUtils, Math,
  mormot.core.base, mormot.core.datetime, chimera_body;

function ChiStateRun: Int64;

implementation

const
  IdState = 'CHI-MB-STATE-001';

  ChiSectionCount = 13;
  ChiStateSize    = 342;
  ChiNameMax      = 64;
  ChiDescSize     = 66;
  ChiHashSeed     = Cardinal($4F726432);

  MinsInDay       = 1440;
  UnixDelta       = 25569.0;   { начало отсчёта в счёте дней }

type
  TChiExecSection = packed record
    QuantityRemaining: Double;
    ActualQ:           Double;
    TotalBTC:          Double;
    MeanPrice:         Double;
    PartialDone:       Byte;
  end;

  TChiPlacementSection = packed record
    IntID:        Int64;
    ActualPrice:  Double;
    OpenTime:     Int64;
    Quantity:     Double;
    QuantityBase: Double;
    CloseTime:    Int64;
    CreateTime:   Int64;
    StopFlag:     Byte;
    OrderType:    Byte;
    SubType:      Byte;
    Leverage:     Byte;
    IsOpened:     Byte;
    IsClosed:     Byte;
    Canceled:     Byte;
  end;

  TChiSlowSection = packed record
    SpentBTC:      Double;
    TmpBTC:        Double;
    PanicSellDown: Single;
  end;

  { Настройки стопов канон трактует как непрозрачные байты — здесь так же. }
  TChiStops = packed array [0 .. 45] of Byte;

  TChiOrderState = packed record
    Status:            Byte;
    EffectiveStratID:  UInt64;
    SellReason:        Byte;
    Flags:             Byte;
    TargetBuyPrice:    Double;
    TargetBuySize:     Double;
    BuyReplacing:      Byte;
    TargetSell:        Double;
    SellReplacing:     Byte;
    BuyExec:           TChiExecSection;
    BuyPlacement:      TChiPlacementSection;
    BuySlow:           TChiSlowSection;
    SellExec:          TChiExecSection;
    SellPlacement:     TChiPlacementSection;
    SellSlow:          TChiSlowSection;
    Stops:             TChiStops;
    VStopOn:           Byte;
    VStopFixed:        Byte;
    VStopLevel:        Double;
    VStopVol:          Double;
    PredefinedSellPrice: Double;
    UseMarketStop:     Byte;
  end;

  TChiOrderDesc = packed record
    NameLen: Byte;
    Name:    array [0 .. ChiNameMax - 1] of Byte;
    Flags:   Byte;
  end;

{$IF SizeOf(TChiOrderState) <> ChiStateSize}
  {$MESSAGE ERROR 'раскладка канона сломана: не 342 байта'}
{$ENDIF}
{$IF SizeOf(TChiOrderDesc) <> ChiDescSize}
  {$MESSAGE ERROR 'раскладка паспорта сломана: не 66 байт'}
{$ENDIF}

const
  ChiSectionOffset: array [0 .. ChiSectionCount - 1] of Word =
    (0, 9, 11, 28, 37, 70, 133, 153, 186, 249, 269, 315, 333);
  ChiSectionSize: array [0 .. ChiSectionCount - 1] of Byte =
    (9, 2, 17, 9, 33, 63, 20, 33, 63, 20, 46, 18, 9);

{ ═══ Живые формы ═════════════════════════════════════════════════════════ }

procedure InitState(out S: TChiOrderState);
begin
  FillChar(S, SizeOf(S), 0);
end;

function StatesEqual(const A, B: TChiOrderState): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(TChiOrderState));
end;

function DiffSectionMask(const A, B: TChiOrderState): Word;
begin
  Result := 0;
  for var K := 0 to ChiSectionCount - 1 do
    if not CompareMem(PByte(@A) + ChiSectionOffset[K], PByte(@B) + ChiSectionOffset[K],
                      ChiSectionSize[K]) then
      Result := Result or (1 shl K);
end;

function NonZeroSectionMask(const S: TChiOrderState): Word;
var
  P:       PByte;
  AllZero: Boolean;
begin
  Result := 0;
  for var K := 0 to ChiSectionCount - 1 do
  begin
    P := PByte(@S) + ChiSectionOffset[K];
    AllZero := True;
    for var I := 0 to ChiSectionSize[K] - 1 do
      if P[I] <> 0 then
      begin
        AllZero := False;
        Break;
      end;
    if not AllZero then Result := Result or (1 shl K);
  end;
end;

function ULEBSize(V: UInt64): Integer;
begin
  Result := 1;
  while V >= $80 do
  begin
    V := V shr 7;
    Inc(Result);
  end;
end;

procedure WriteULEB(Stream: TMemoryStream; V: UInt64);
var
  Buf: array [0 .. 9] of Byte;
  N:   Integer;
begin
  N := 0;
  repeat
    Buf[N] := Byte(V and $7F);
    V := V shr 7;
    if V <> 0 then Buf[N] := Buf[N] or $80;
    Inc(N);
  until V = 0;
  Stream.Write(Buf[0], N);
end;

{ Чтение идёт прямо по памяти буфера: на горячем пути виртуальный вызов на
  каждый байт не нужен. Ложь = байты кончились либо число длиннее десяти. }
function ReadULEB(ms: TMemoryStream; out V: UInt64): Boolean;
var
  P, PEnd:  PByte;
  B:        Byte;
  Shift, N: Integer;
begin
  Result := False;
  V := 0;
  P := PByte(ms.Memory) + ms.Position;
  PEnd := PByte(ms.Memory) + ms.Size;
  Shift := 0;
  N := 0;
  repeat
    if (P >= PEnd) or (N >= 10) then Exit;
    B := P^;
    Inc(P);
    Inc(N);
    V := V or (UInt64(B and $7F) shl Shift);
    Inc(Shift, 7);
  until (B and $80) = 0;
  ms.Position := ms.Position + N;
  Result := True;
end;

procedure WriteSections(Stream: TMemoryStream; const S: TChiOrderState; AMask: Word);
begin
  for var K := 0 to ChiSectionCount - 1 do
    if (AMask and (1 shl K)) <> 0 then
      Stream.Write((PByte(@S) + ChiSectionOffset[K])^, ChiSectionSize[K]);
end;

function ReadSections(ms: TMemoryStream; AMask: Word; var S: TChiOrderState): Boolean;
begin
  Result := False;
  for var K := 0 to ChiSectionCount - 1 do
    if (AMask and (1 shl K)) <> 0 then
      if ms.Read((PByte(@S) + ChiSectionOffset[K])^, ChiSectionSize[K]) <> ChiSectionSize[K] then
        Exit;
  Result := True;
end;

procedure InitDesc(out D: TChiOrderDesc);
begin
  FillChar(D, SizeOf(D), 0);
end;

function BuildDesc(const AName: RawByteString; AFlags: Byte; out D: TChiOrderDesc): Boolean;
begin
  InitDesc(D);
  Result := Length(AName) <= ChiNameMax;
  if not Result then Exit;
  D.NameLen := Length(AName);
  if D.NameLen > 0 then
    Move(Pointer(AName)^, D.Name[0], D.NameLen);
  D.Flags := AFlags;
end;

procedure WriteDesc(Stream: TMemoryStream; const D: TChiOrderDesc);
begin
  Stream.Write(D.NameLen, 1);
  if D.NameLen > 0 then
    Stream.Write(D.Name[0], D.NameLen);
  Stream.Write(D.Flags, 1);
end;

function ReadDesc(ms: TMemoryStream; out D: TChiOrderDesc): Boolean;
begin
  InitDesc(D);
  Result := False;
  if ms.Read(D.NameLen, 1) <> 1 then Exit;
  if D.NameLen > ChiNameMax then Exit;
  if D.NameLen > 0 then
    if ms.Read(D.Name[0], D.NameLen) <> D.NameLen then Exit;
  if ms.Read(D.Flags, 1) <> 1 then Exit;
  Result := True;
end;

{ Пруф: счётчик правок, паспорт в ПРОВОДНОЙ форме (без нулевого хвоста) и
  весь канон — три куска подряд. }
function CalcStateHash(AStateRev: UInt64; const ADesc: TChiOrderDesc;
  const AState: TChiOrderState): Cardinal;
var
  H: Cardinal;
begin
  H := crc32c(ChiHashSeed, PAnsiChar(@AStateRev), SizeOf(AStateRev));
  H := crc32c(H, PAnsiChar(@ADesc.NameLen), 1);
  if ADesc.NameLen > 0 then
    H := crc32c(H, PAnsiChar(@ADesc.Name[0]), ADesc.NameLen);
  H := crc32c(H, PAnsiChar(@ADesc.Flags), 1);
  Result := crc32c(H, PAnsiChar(@AState), SizeOf(AState));
end;

function TimeToWire(dt: TDateTime; ATZShift: TDateTime): Int64;
begin
  if dt < UnixDelta
    then Result := 0
    else Result := DateTimeToUnixMSTime(dt - ATZShift);
end;

function WireToLocalTime(ms: Int64; ATZShift: TDateTime): TDateTime;
begin
  if ms <= 0
    then Result := 0
    else Result := UnixMSTimeToDateTime(ms) + ATZShift;
end;

{ ═══ Оракулы ═════════════════════════════════════════════════════════════ }

{ Число переменной длины вторым способом: деление и остаток вместо сдвигов. }
function OracleWriteULEB(V: UInt64): TBytes;
var
  N: Integer;
begin
  SetLength(Result, 10);
  N := 0;
  repeat
    Result[N] := V mod 128;
    V := V div 128;
    if V <> 0 then Result[N] := Result[N] + 128;
    Inc(N);
  until V = 0;
  SetLength(Result, N);
end;

function OracleReadULEB(const A: TBytes; var Pos: Integer; out V: UInt64): Boolean;
var
  Mul: UInt64;
  N:   Integer;
begin
  V := 0;
  Mul := 1;
  N := 0;
  repeat
    if (Pos >= Length(A)) or (N >= 10) then Exit(False);
    V := V + UInt64(A[Pos] and $7F) * Mul;
    if Mul <= (UInt64(1) shl 56) then Mul := Mul * 128;
    Inc(N);
    Inc(Pos);
  until (A[Pos - 1] and $80) = 0;
  Result := True;
end;

{ ═══ Оснастка ════════════════════════════════════════════════════════════ }

procedure FillState(var S: TChiOrderState; ASeed: UInt64);
var
  Src: TChiSource;
  P:   PByte;
begin
  Src := ChiSource(ASeed);
  P := PByte(@S);
  for var I := 0 to SizeOf(TChiOrderState) - 1 do
    P[I] := Byte(Src.NextBelow(256));
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiStateRun: Int64;
var
  Acc:    UInt64;
  A, B:   TChiOrderState;
  Copy1:  TChiOrderState;
  D, D2:  TChiOrderDesc;
  ms:     TMemoryStream;
  V:      UInt64;
  Mask:   Word;
  Src:    TChiSource;
begin
  Acc := 0;
  ChiCovered(IdState);

  { ── Таблица границ обязана быть согласована с раскладкой ── }
  ChiClaim(SizeOf(TChiOrderState) = ChiStateSize, 'канон: размер записи не тот');
  ChiClaim(SizeOf(TChiOrderDesc) = ChiDescSize, 'канон: размер паспорта не тот');
  var Sum := 0;
  for var K := 0 to ChiSectionCount - 1 do
  begin
    ChiClaim(ChiSectionOffset[K] = Sum,
      'канон: смещение секции ' + IntToStr(K) + ' не равно сумме предыдущих');
    Inc(Sum, ChiSectionSize[K]);
  end;
  ChiClaim(Sum = ChiStateSize, 'канон: сумма размеров секций не равна размеру записи');
  ChiBranch(IdState, 'offsets-are-cumulative');

  { ── Число переменной длины: границы и второй способ ── }
  ms := TMemoryStream.Create;
  try
    var Probes: TArray<UInt64> := [0, 1, 63, 127, 128, 129, 255, 16383, 16384,
      $FFFFFFFF, UInt64($7FFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF)];
    for var Probe in Probes do
    begin
      ms.Size := 0;
      ms.Position := 0;
      WriteULEB(ms, Probe);
      var Want := OracleWriteULEB(Probe);
      ChiClaim(ms.Size = Length(Want),
        'число: длина записи разошлась со вторым способом на ' + IntToStr(Probe));
      ChiClaim(CompareMem(ms.Memory, Pointer(Want), Length(Want)),
        'число: байты записи разошлись со вторым способом');
      ChiClaim(ULEBSize(Probe) = Length(Want), 'число: обещанная длина не та');

      ms.Position := 0;
      ChiClaim(ReadULEB(ms, V), 'число: чтение отказалось');
      ChiClaim(V = Probe, 'число: прочитано не то, что записано');
      ChiClaim(ms.Position = ms.Size, 'число: чтение съело не столько байт');

      var Pos := 0;
      var V2: UInt64;
      ChiClaim(OracleReadULEB(Want, Pos, V2), 'число: второй способ не прочитал');
      ChiClaim(V2 = Probe, 'число: второй способ прочитал не то');
      Acc := ChiMix(Acc, Int64(V));
    end;
    ChiBranch(IdState, 'uleb-boundaries');

    { Двухбайтовая граница обязана реально случиться, иначе проверено вхолостую. }
    ChiClaim(ULEBSize(127) = 1, 'число: сто двадцать семь заняло не один байт');
    ChiClaim(ULEBSize(128) = 2, 'число: сто двадцать восемь заняло не два байта');
    ChiClaim(ULEBSize(UInt64($FFFFFFFFFFFFFFFF)) = 10, 'число: предел занял не десять байт');
    ChiBranch(IdState, 'uleb-sizes');

    { Обрыв буфера: последний байт с признаком продолжения и ничего дальше. }
    ms.Size := 0;
    ms.Position := 0;
    var Cont: Byte := $80 or 5;
    ms.Write(Cont, 1);
    ms.Position := 0;
    ChiClaim(not ReadULEB(ms, V), 'число: оборванное принято');
    ChiBranch(IdState, 'uleb-truncated');

    { Слишком длинное: одиннадцать байт с признаком продолжения. }
    ms.Size := 0;
    ms.Position := 0;
    for var I := 1 to 11 do
      ms.Write(Cont, 1);
    ms.Position := 0;
    ChiClaim(not ReadULEB(ms, V), 'число: слишком длинное принято');
    ChiBranch(IdState, 'uleb-too-long');
  finally
    FreeAndNil(ms);
  end;

  { ── Маски секций ── }
  InitState(A);
  ChiClaim(NonZeroSectionMask(A) = 0, 'маска: пустое состояние не пустое');
  ChiBranch(IdState, 'empty-mask');

  FillState(A, 20260830);
  B := A;
  ChiClaim(StatesEqual(A, B), 'маска: копия не равна источнику');
  ChiClaim(DiffSectionMask(A, B) = 0, 'маска: копия отличается от источника');
  ChiBranch(IdState, 'copy-has-no-diff');

  { Правка в каждой секции по очереди обязана поднимать РОВНО её бит. }
  for var K := 0 to ChiSectionCount - 1 do
  begin
    B := A;
    var P := PByte(@B) + ChiSectionOffset[K];
    P[ChiSectionSize[K] - 1] := P[ChiSectionSize[K] - 1] xor $FF;
    Mask := DiffSectionMask(A, B);
    ChiClaim(Mask = Word(1 shl K),
      'маска: правка в секции ' + IntToStr(K) + ' дала не тот бит');
  end;
  ChiBranch(IdState, 'diff-per-section');

  { Ненулевая маска: собираем состояние, где часть секций осталась пустой. }
  InitState(B);
  Move((PByte(@A) + ChiSectionOffset[4])^, (PByte(@B) + ChiSectionOffset[4])^, ChiSectionSize[4]);
  Move((PByte(@A) + ChiSectionOffset[10])^, (PByte(@B) + ChiSectionOffset[10])^, ChiSectionSize[10]);
  ChiClaim(NonZeroSectionMask(B) = Word((1 shl 4) or (1 shl 10)),
    'маска: непустыми оказались не те секции');
  ChiBranch(IdState, 'nonzero-mask');
  Acc := ChiMix(Acc, NonZeroSectionMask(B));

  { ── Частичная передача: внутри маски совпало, вне — не тронуто ── }
  ms := TMemoryStream.Create;
  try
    Mask := Word((1 shl 2) or (1 shl 5) or (1 shl 12));
    WriteSections(ms, A, Mask);
    var Expect := 0;
    for var K := 0 to ChiSectionCount - 1 do
      if (Mask and (1 shl K)) <> 0 then
        Inc(Expect, ChiSectionSize[K]);
    ChiClaim(ms.Size = Expect, 'секции: записано не столько байт, сколько в маске');

    FillState(B, 777);
    Copy1 := B;
    ms.Position := 0;
    ChiClaim(ReadSections(ms, Mask, B), 'секции: чтение отказалось');
    for var K := 0 to ChiSectionCount - 1 do
      if (Mask and (1 shl K)) <> 0 then
        ChiClaim(CompareMem(PByte(@A) + ChiSectionOffset[K],
                            PByte(@B) + ChiSectionOffset[K], ChiSectionSize[K]),
          'секции: секция ' + IntToStr(K) + ' из маски не приехала')
      else
        ChiClaim(CompareMem(PByte(@Copy1) + ChiSectionOffset[K],
                            PByte(@B) + ChiSectionOffset[K], ChiSectionSize[K]),
          'секции: секция ' + IntToStr(K) + ' вне маски была тронута');
    ChiClaim(DiffSectionMask(A, B) = (not Mask) and $1FFF,
      'секции: после передачи расхождение не дополняет маску');
    ChiBranch(IdState, 'partial-roundtrip');
    Acc := ChiMix(Acc, ms.Size);

    { Полная маска возвращает состояние целиком. }
    ms.Size := 0;
    ms.Position := 0;
    WriteSections(ms, A, $1FFF);
    ChiClaim(ms.Size = ChiStateSize, 'секции: полная маска записала не весь канон');
    InitState(B);
    ms.Position := 0;
    ChiClaim(ReadSections(ms, $1FFF, B), 'секции: полное чтение отказалось');
    ChiClaim(StatesEqual(A, B), 'секции: полный обход не вернул исходное');
    ChiBranch(IdState, 'full-roundtrip');

    { Оборванный поток: последней секции не хватает байт. }
    ms.Size := ms.Size - 3;
    ms.Position := 0;
    InitState(B);
    ChiClaim(not ReadSections(ms, $1FFF, B), 'секции: оборванный поток принят');
    ChiBranch(IdState, 'read-runs-out');
  finally
    FreeAndNil(ms);
  end;

  { ── Паспорт: имя, длина, предел ── }
  ms := TMemoryStream.Create;
  try
    ChiClaim(BuildDesc(RawByteString('BTCUSDT'), 3, D), 'паспорт: имя не принято');
    ChiClaim(D.NameLen = 7, 'паспорт: длина имени не та');
    WriteDesc(ms, D);
    ChiClaim(ms.Size = 1 + 7 + 1, 'паспорт: проводная форма длиннее имени с хвостом');
    ms.Position := 0;
    ChiClaim(ReadDesc(ms, D2), 'паспорт: чтение отказалось');
    ChiClaim(CompareMem(@D, @D2, SizeOf(D)), 'паспорт: круговой обход исказил');
    ChiBranch(IdState, 'desc-roundtrip');

    var Long: RawByteString;
    SetLength(Long, ChiNameMax);
    FillChar(Pointer(Long)^, ChiNameMax, Ord('X'));
    ChiClaim(BuildDesc(Long, 0, D), 'паспорт: имя предельной длины отвергнуто');
    ChiClaim(BuildDesc(Long + RawByteString('Y'), 0, D) = False,
      'паспорт: имя длиннее предела принято');
    ChiBranch(IdState, 'desc-name-limit');

    { Пустое имя — законный паспорт, и его проводная форма ровно два байта. }
    ms.Size := 0;
    ms.Position := 0;
    ChiClaim(BuildDesc(RawByteString(''), 1, D), 'паспорт: пустое имя отвергнуто');
    WriteDesc(ms, D);
    ChiClaim(ms.Size = 2, 'паспорт: пустое имя заняло не два байта');
    ms.Position := 0;
    ChiClaim(ReadDesc(ms, D2) and (D2.NameLen = 0) and (D2.Flags = 1),
      'паспорт: пустое имя прочитано неверно');
    ChiBranch(IdState, 'desc-empty-name');
  finally
    FreeAndNil(ms);
  end;

  { ── Пруф ── }
  { Сама сумма — общий код с проверяемым путём, поэтому сперва внешняя истина:
    общепринятый пример. Без него сверка кусочного расчёта со сплошным
    доказывала бы лишь их согласие между собой. }
  ChiClaim(crc32c(0, PAnsiChar('123456789'), 9) = $E3069283,
    'пруф: общепринятый пример суммы не сошёлся');
  ChiBranch(IdState, 'crc-vector');

  BuildDesc(RawByteString('ETHUSDT'), 2, D);
  var H := CalcStateHash(42, D, A);

  { Независимо: те же три куска, склеенные вручную. }
  var Blob: TBytes;
  SetLength(Blob, SizeOf(UInt64) + 1 + D.NameLen + 1 + SizeOf(TChiOrderState));
  var Rev: UInt64 := 42;
  Move(Rev, Blob[0], SizeOf(Rev));
  Blob[8] := D.NameLen;
  Move(D.Name[0], Blob[9], D.NameLen);
  Blob[9 + D.NameLen] := D.Flags;
  Move(A, Blob[10 + D.NameLen], SizeOf(TChiOrderState));
  ChiClaim(H = crc32c(ChiHashSeed, PAnsiChar(Pointer(Blob)), Length(Blob)),
    'пруф: посчитанный кусками не равен посчитанному целиком');
  ChiBranch(IdState, 'hash-matches-blob');

  { Нулевой хвост имени в пруф не входит: другое имя той же длины — другой
    пруф, а тот же паспорт с мусором в хвосте — тот же. }
  D2 := D;
  FillChar(D2.Name[D2.NameLen], ChiNameMax - D2.NameLen, $AB);
  ChiClaim(CalcStateHash(42, D2, A) = H, 'пруф: хвост имени попал в пруф');
  ChiBranch(IdState, 'hash-ignores-name-tail');

  { Правка в любой секции обязана менять пруф. }
  Src := ChiSource(31337);
  for var K := 0 to ChiSectionCount - 1 do
  begin
    B := A;
    var P := PByte(@B) + ChiSectionOffset[K];
    var At := Src.NextBelow(ChiSectionSize[K]);
    P[At] := P[At] xor $5A;
    ChiClaim(CalcStateHash(42, D, B) <> H,
      'пруф: правка в секции ' + IntToStr(K) + ' не изменила пруф');
  end;
  ChiClaim(CalcStateHash(43, D, A) <> H, 'пруф: другой счётчик правок дал тот же пруф');
  ChiBranch(IdState, 'hash-covers-everything');
  Acc := ChiMix(Acc, H);

  { ── Времена: провод в мировом, местное — только при разборе ── }
  var Shift: TDateTime := 180 / MinsInDay;
  var Local: TDateTime := 45900.5;
  var Wire := TimeToWire(Local, Shift);
  ChiClaim(Wire > 0, 'время: местное время не превратилось в целое');
  ChiClaim(ChiNear(WireToLocalTime(Wire, Shift), Local, 1E-8),
    'время: круговой обход сместил местное время');
  ChiBranch(IdState, 'time-roundtrip');

  ChiClaim(TimeToWire(0, Shift) = 0, 'время: незаполненное поле поехало числом');
  ChiClaim(TimeToWire(UnixDelta - 1, Shift) = 0, 'время: дата до начала отсчёта поехала числом');
  ChiClaim(WireToLocalTime(0, Shift) = 0, 'время: ноль с провода стал датой');
  ChiClaim(WireToLocalTime(-5, Shift) = 0, 'время: отрицательное с провода стало датой');
  ChiBranch(IdState, 'time-empty-is-empty');

  { Читатель в другом поясе получает СВОЁ местное время: разница ровно в
    разнице поясов, а на проводе число одно и то же. }
  var Other: TDateTime := 300 / MinsInDay;
  ChiClaim(ChiNear(WireToLocalTime(Wire, Other) - WireToLocalTime(Wire, Shift),
                   120 / MinsInDay, 1E-9),
    'время: разница поясов не превратилась в два часа');
  ChiClaim(TimeToWire(Local, Other) <> Wire,
    'время: одно и то же местное время в разных поясах дало одно число на проводе');
  ChiBranch(IdState, 'time-tz-shift');
  Acc := ChiMix(Acc, Wire);

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
