unit chimera_pack;

{ Орган «свечной пакет»: два сжатия подряд и публикация теневым буфером.

  Источник: `MoonBot/MarketsU.pas` — `StoreCandlesToZip`,
  `BuildCandlesZlibLocked`, `GetCandlesStream`, `ApplyRecvdStream`. Перенесено
  дословно по форме:

    * заголовок пишется так, чтобы читатель СТАРОЙ версии прочитал ноль и
      дальше не пошёл: сперва счётчик нулём, потом версия, потом счётчик ещё
      раз. Настоящее число рынков вписывается в конце возвратом на позицию
      `размер счётчика + размер версии`;
    * сдвиг часового пояса едет в потоке числом минут, и читатель вычитает из
      него СВОЙ сдвиг — время приезжает в местное время читателя, а не в общее;
    * тела свечей пишутся записью фиксированного размера, и размер этот у
      версий РАЗНЫЙ: у второй — плотная запись из трёх дробных одинарной
      точности и времени, у первой — обычная запись из двойных. Читатель
      выбирает размер по версии;
    * рынок, которого у читателя нет, не разбирается, а ПРОМАТЫВАЕТСЯ на
      число свечей, умноженное на размер записи ЭТОЙ версии, плюс две стенки;
    * готовый поток жмётся быстрым сжатием библиотеки в ТЕНЕВОЙ буфер, и лишь
      потом под замком переключается указатель текущего буфера и ставится
      отметка «пережать заново»;
    * читатель под тем же замком, увидев отметку, распаковывает быстрое сжатие
      и пережимает результат другим, медленным сжатием из состава языка. Два
      разных сжатия подряд — не украшение: по проводу едет второе, а в памяти
      держится первое.

  Заменено оснасткой: сеть, файлы и часы. Сдвиг пояса задаётся числом, иначе
  ответ зависел бы от машины.

  Почему это отдельная форма от буферов и провода:

    * там переиспользование памяти, здесь — ДВА буфера и переключатель между
      ними: читатель обязан не увидеть полусобранного;
    * там длина едет рядом с данными, здесь длину распакованного сообщает сам
      сжатый блок из своего заголовка;
    * размер элемента здесь решает поле версии, а не тип в объявлении.

  Оракулы:

    1. независимый сборщик и разборщик того же потока, написанный без
       библиотеки сжатия и без общих со стройкой помощников: он строит эталон
       байт в байт и разбирает то, что построил живой путь;
    2. свойства сжатия: обещанный размер назначения не меньше полученного,
       длина из заголовка сжатого блока равна исходной, распакованное равно
       исходному;
    3. отметка «пережать» предъявляется счётчиком: пережатие случается ровно
       один раз на публикацию, а не на каждое чтение;
    4. версия и размер записи — таблицей: двадцать байт против тридцати двух;
    5. поток, собранный второй версией, читается второй; поток, собранный
       первой, читается той же программой по её же выбору размера. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, SyncObjs,
  {$ifdef FPC} zstream, {$else} System.ZLib, {$endif}
  Generics.Collections,
  mormot.core.base, mormot.core.buffers, chimera_body;

{ Медленное сжатие берётся из состава языка, и зовётся оно на двух системах
  по-разному: у одной поток сжатия пишется строчными буквами, у другой имя
  начинается с указания на библиотеку. Живой код MoonBot использует вторую. }
type
  {$ifdef FPC}
  TChiZipStream   = Tcompressionstream;
  TChiUnzipStream = Tdecompressionstream;
  {$else}
  TChiZipStream   = TZCompressionStream;
  TChiUnzipStream = TZDecompressionStream;
  {$endif}

function ChiPackRun: Int64;

implementation

const
  IdPack = 'CHI-MB-PACK-001';

  ChiCandlesVersion = 2;
  MinsInDay         = 1440;

type
  { Плотная запись второй версии: три дробных одинарной точности и время. }
  TChiCandle = packed record
    MaxP, MinP: Single;
    Vol:        Single;
    Time:       TDateTime;
  end;

  { Запись первой версии: обычная, из двойных. Размер её другой, и это
    единственное, чем она интересна. }
  TChiCandleOld = record
    MaxP, MinP: Double;
    Vol:        Double;
    Time:       TDateTime;
  end;

  TChiWallItem = record
    Vol:   Single;
    Count: Integer;
  end;

  TChiWall = array [1 .. 4] of TChiWallItem;

  TChiMarketRow = class
    Name:     string;
    Candles:  array of TChiCandle;
    BuyWall:  TChiWall;
    SellWall: TChiWall;
  end;

  TChiRows = TObjectList<TChiMarketRow>;

{ ═══ Строки в потоке — как в живом пути: длина, затем байты ═══════════════ }

procedure WriteStr(AStream: TStream; const S: string);
var
  U: RawByteString;
  N: Integer;
begin
  U := RawByteString(AnsiString(S));
  N := Length(U);
  AStream.Write(N, SizeOf(N));
  if N > 0 then
    AStream.Write(Pointer(U)^, N);
end;

procedure ReadStr(AStream: TStream; out S: string);
var
  U: RawByteString;
  N: Integer;
begin
  N := 0;
  AStream.Read(N, SizeOf(N));
  SetLength(U, N);
  if N > 0 then
    AStream.Read(Pointer(U)^, N);
  S := string(AnsiString(U));
end;

{ ═══ Сборка потока ═══════════════════════════════════════════════════════ }

{ Пишет тело так же, как живой путь: пустой счётчик, версия, счётчик, сдвиг
  пояса, тела рынков, и в конце возврат на позицию счётчика с настоящим
  числом. Версия задаётся снаружи, чтобы обе ветви размера записи были
  живыми. }
procedure BuildStream(AStream: TMemoryStream; const ARows: TChiRows;
  AVer: Byte; AShiftMinutes: Double);
var
  ACount: Integer;
  Ver:    Byte;
  N:      Integer;
  C:      TChiCandle;
  COld:   TChiCandleOld;
begin
  Ver := AVer;
  ACount := 0;
  AStream.Write(ACount, SizeOf(ACount));
  AStream.Write(Ver, SizeOf(Ver));
  { Второй счётчик — примета версий старше первой. Первый остаётся нулём
    ровно затем, чтобы читатель первой версии увидел «рынков нет» и не полез
    разбирать незнакомую ему раскладку. }
  if AVer > 1 then
    AStream.Write(ACount, SizeOf(ACount));
  AStream.Write(AShiftMinutes, SizeOf(AShiftMinutes));

  for var Row in ARows do
  begin
    WriteStr(AStream, Row.Name);
    N := Length(Row.Candles);
    AStream.Write(N, SizeOf(N));
    if N > 0 then
      for var K := 0 to N - 1 do
        if AVer >= 2 then
        begin
          C := Row.Candles[K];
          AStream.Write(C, SizeOf(C));
        end
        else
        begin
          COld.MaxP := Row.Candles[K].MaxP;
          COld.MinP := Row.Candles[K].MinP;
          COld.Vol  := Row.Candles[K].Vol;
          COld.Time := Row.Candles[K].Time;
          AStream.Write(COld, SizeOf(COld));
        end;
    AStream.Write(Row.BuyWall, SizeOf(TChiWall));
    AStream.Write(Row.SellWall, SizeOf(TChiWall));
    Inc(ACount);
  end;

  if AVer > 1
    then AStream.Position := SizeOf(ACount) + SizeOf(Ver)
    else AStream.Position := 0;
  AStream.Write(ACount, SizeOf(ACount));
  AStream.Position := 0;
end;

{ ═══ Разбор потока ═══════════════════════════════════════════════════════ }

{ Разбирает то, что собрал живой путь. Рынок, которого нет в списке
  известных, проматывается: длина его тела считается из числа свечей и
  размера записи ЭТОЙ версии. Ошибка здесь не роняет разбор, а сдвигает всё
  последующее — потому промотка и проверяется отдельно. }
function ParseStream(AStream: TMemoryStream; const AKnown: TStringList;
  ARows: TChiRows; AOwnShiftMinutes: Double; out ASkipped: Integer): Boolean;
var
  ACount:    Integer;
  Ver:       Byte;
  Shift:     Double;
  MName:     string;
  N:         Integer;
  C:         TChiCandle;
  COld:      TChiCandleOld;
  Row:       TChiMarketRow;
  Idx:       Integer;
begin
  Result := False;
  ASkipped := 0;
  AStream.Position := 0;
  if AStream.Size = 0 then
    Exit;

  ACount := 0;
  Ver := 0;
  AStream.Read(ACount, SizeOf(ACount));
  AStream.Read(Ver, SizeOf(Ver));
  if Ver > 1 then
    AStream.Read(ACount, SizeOf(ACount));
  if Ver > ChiCandlesVersion then
    Exit;

  Shift := 0;
  AStream.Read(Shift, SizeOf(Shift));
  Shift := (AOwnShiftMinutes - Shift) / MinsInDay;

  for var K := 0 to ACount - 1 do
  begin
    ReadStr(AStream, MName);
    Idx := AKnown.IndexOf(MName);
    if Idx >= 0 then
    begin
      N := 0;
      AStream.Read(N, SizeOf(N));
      Row := TChiMarketRow.Create;
      Row.Name := MName;
      SetLength(Row.Candles, N);
      if N > 0 then
        if Ver >= 2 then
          for var J := 0 to N - 1 do
          begin
            AStream.Read(C, SizeOf(C));
            Row.Candles[J].MaxP := C.MaxP;
            Row.Candles[J].MinP := C.MinP;
            Row.Candles[J].Vol  := C.Vol;
            Row.Candles[J].Time := C.Time + Shift;
          end
        else
          for var J := 0 to N - 1 do
          begin
            AStream.Read(COld, SizeOf(COld));
            Row.Candles[J].MaxP := COld.MaxP;
            Row.Candles[J].MinP := COld.MinP;
            Row.Candles[J].Vol  := COld.Vol;
            Row.Candles[J].Time := COld.Time + Shift;
          end;
      AStream.Read(Row.BuyWall, SizeOf(TChiWall));
      AStream.Read(Row.SellWall, SizeOf(TChiWall));
      ARows.Add(Row);
    end
    else
    begin
      N := 0;
      AStream.Read(N, SizeOf(N));
      if Ver >= 2 then
        AStream.Seek(Int64(N) * SizeOf(TChiCandle), soFromCurrent)
      else
        AStream.Seek(Int64(N) * SizeOf(TChiCandleOld), soFromCurrent);
      AStream.Seek(SizeOf(TChiWall) * 2, soFromCurrent);
      Inc(ASkipped);
    end;
  end;
  Result := True;
end;

{ ═══ Двойной буфер с переключателем и отметкой ═══════════════════════════ }

type
  { Живой путь держит два буфера быстрого сжатия и один медленного. Пишущий
    заполняет теневой и под замком переключает указатель; читающий под тем же
    замком пережимает, если стоит отметка. }
  TChiPublisher = class
  private
    FPacked:    array [Boolean] of TMemoryStream;
    FCurrent:   Boolean;
    FZlib:      TMemoryStream;
    FDirty:     Boolean;
    FLock:      TCriticalSection;
    FRepacks:   Integer;
    FBreakNext: Boolean;   { оснастка: следующее пережатие бросит исключение }
    function BuildZlibLocked: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Publish(APlain: TMemoryStream);
    function GetStream: TMemoryStream;
    property Repacks: Integer read FRepacks;
    property BreakNext: Boolean read FBreakNext write FBreakNext;
    property Dirty: Boolean read FDirty;
  end;

constructor TChiPublisher.Create;
begin
  inherited Create;
  FPacked[False] := TMemoryStream.Create;
  FPacked[True] := TMemoryStream.Create;
  FZlib := TMemoryStream.Create;
  FLock := TCriticalSection.Create;
end;

destructor TChiPublisher.Destroy;
begin
  FreeAndNil(FPacked[False]);
  FreeAndNil(FPacked[True]);
  FreeAndNil(FZlib);
  FreeAndNil(FLock);
  inherited Destroy;
end;

{ Пишущая половина: жмёт в теневой буфер, и только удавшееся сжатие
  переключает текущий. Неудача оставляет читателю прежнее. }
procedure TChiPublisher.Publish(APlain: TMemoryStream);
var
  Dest:       TMemoryStream;
  PlainSize:  Integer;
  PackedSize: Integer;
  PackedOK:   Boolean;
begin
  Dest := FPacked[not FCurrent];
  APlain.Position := 0;
  Dest.Size := 0;
  PackedOK := False;
  try
    PlainSize := APlain.Size;
    Dest.Size := AlgoSynLZ.AlgoCompressDestLen(PlainSize);
    PackedSize := AlgoSynLZ.AlgoCompress(APlain.Memory, PlainSize, Dest.Memory);
    if PackedSize <= 0 then
      Dest.Size := 0
    else
    begin
      Dest.Size := PackedSize;
      PackedOK := True;
    end;
  except
    Dest.Size := 0;
  end;

  if not PackedOK then
    Exit;
  FLock.Acquire;
  try
    FCurrent := not FCurrent;
    FDirty := True;
  finally
    FLock.Release;
  end;
end;

{ Читающая половина. Дословная особенность живого пути: отметка снимается
  ДО того, как пережатие удалось, поэтому тихий отказ (пустой источник,
  несошедшийся размер) больше не повторится, а исключение — вернёт отметку и
  повторится. Обе дороги предъявлены оракулом. }
function TChiPublisher.BuildZlibLocked: Boolean;
var
  Src:        TMemoryStream;
  Raw:        TMemoryStream;
  Z:          TChiZipStream;
  PlainSize:  Integer;
  PackedSize: Integer;
begin
  Result := False;
  try
    if not FDirty then
    begin
      Result := FZlib.Size > 0;
      Exit;
    end;

    FZlib.Size := 0;
    FDirty := False;

    Src := FPacked[FCurrent];
    if (Src = nil) or (Src.Size = 0) then
      Exit;

    Raw := TMemoryStream.Create;
    try
      PackedSize := Src.Size;
      PlainSize := AlgoSynLZ.AlgoDecompressDestLen(Src.Memory);
      if PlainSize <= 0 then
        Exit;

      Raw.Size := PlainSize;
      if AlgoSynLZ.AlgoDecompress(Src.Memory, PackedSize, Raw.Memory) <> PlainSize then
        Exit;

      if FBreakNext then
      begin
        FBreakNext := False;
        raise EStreamError.Create('оснастка: сбой пережатия');
      end;

      Raw.Position := 0;
      Z := TChiZipStream.Create(clDefault, FZlib);
      try
        Z.CopyFrom(Raw, 0);
      finally
        Z.Free;
      end;
      FZlib.Position := 0;
      Inc(FRepacks);
      Result := FZlib.Size > 0;
    finally
      Raw.Free;
    end;
  except
    FZlib.Size := 0;
    FDirty := True;
    Result := False;
  end;
end;

function TChiPublisher.GetStream: TMemoryStream;
begin
  Result := nil;
  FLock.Acquire;
  try
    if BuildZlibLocked then
      Result := FZlib;
  finally
    FLock.Release;
  end;
end;

{ ═══ Оракул: тот же поток, собранный и разобранный вручную ═══════════════ }

type
  { Независимая модель. Она не знает ни про потоки, ни про сжатие: складывает
    байты в массив сама и читает из него сама. Общих помощников со стройкой
    нет — даже строки пишутся здесь своим кодом. }
  TChiTally = record
    Bytes: TBytes;
    Pos:   Integer;
    procedure Put(const Buf; Len: Integer);
    procedure Take(var Buf; Len: Integer);
    procedure PutInt(V: Integer);
    function TakeInt: Integer;
  end;

procedure TChiTally.Put(const Buf; Len: Integer);
begin
  if Pos + Len > Length(Bytes) then
    SetLength(Bytes, Pos + Len);
  Move(Buf, Bytes[Pos], Len);
  Inc(Pos, Len);
end;

procedure TChiTally.Take(var Buf; Len: Integer);
begin
  Move(Bytes[Pos], Buf, Len);
  Inc(Pos, Len);
end;

procedure TChiTally.PutInt(V: Integer);
begin
  Put(V, SizeOf(V));
end;

function TChiTally.TakeInt: Integer;
begin
  Result := 0;
  Take(Result, SizeOf(Result));
end;

{ Эталонная сборка. Порядок и содержимое обязаны совпасть с живым путём
  байт в байт — включая пустой счётчик впереди и перезапись в конце. }
function OracleBuild(const ARows: TChiRows; AVer: Byte;
  AShiftMinutes: Double): TBytes;
var
  T:    TChiTally;
  Ver:  Byte;
  U:    RawByteString;
  N:    Integer;
  C:    TChiCandle;
  COld: TChiCandleOld;
  Save: Integer;
begin
  T.Bytes := nil;
  T.Pos := 0;
  Ver := AVer;
  T.PutInt(0);
  T.Put(Ver, SizeOf(Ver));
  if AVer > 1 then
    T.PutInt(0);
  T.Put(AShiftMinutes, SizeOf(AShiftMinutes));

  N := 0;
  for var Row in ARows do
  begin
    U := RawByteString(AnsiString(Row.Name));
    T.PutInt(Length(U));
    if Length(U) > 0 then
      T.Put(Pointer(U)^, Length(U));
    T.PutInt(Length(Row.Candles));
    for var K := 0 to High(Row.Candles) do
      if AVer >= 2 then
      begin
        C := Row.Candles[K];
        T.Put(C, SizeOf(C));
      end
      else
      begin
        COld.MaxP := Row.Candles[K].MaxP;
        COld.MinP := Row.Candles[K].MinP;
        COld.Vol  := Row.Candles[K].Vol;
        COld.Time := Row.Candles[K].Time;
        T.Put(COld, SizeOf(COld));
      end;
    T.Put(Row.BuyWall, SizeOf(TChiWall));
    T.Put(Row.SellWall, SizeOf(TChiWall));
    Inc(N);
  end;

  Save := T.Pos;
  if AVer > 1
    then T.Pos := SizeOf(Integer) + SizeOf(Byte)
    else T.Pos := 0;
  T.PutInt(N);
  T.Pos := Save;
  Result := T.Bytes;
end;

{ ═══ Оснастка данных ═════════════════════════════════════════════════════ }

function MakeRows(ACount: Integer; ASeed: UInt64): TChiRows;
var
  Src: TChiSource;
  Row: TChiMarketRow;
  N:   Integer;
begin
  Src := ChiSource(ASeed);
  Result := TChiRows.Create(True);
  for var I := 0 to ACount - 1 do
  begin
    Row := TChiMarketRow.Create;
    Row.Name := 'MKT' + IntToStr(I) + Char(Ord('A') + Src.NextBelow(26));
    N := Src.NextBelow(9);
    SetLength(Row.Candles, N);
    for var K := 0 to N - 1 do
    begin
      Row.Candles[K].MaxP := 100 + Src.NextBelow(1000) * 0.25;
      Row.Candles[K].MinP := Row.Candles[K].MaxP - Src.NextBelow(50) * 0.125;
      Row.Candles[K].Vol  := Src.NextBelow(100000) * 0.5;
      Row.Candles[K].Time := 45000 + K * (5 / MinsInDay);
    end;
    for var W := 1 to 4 do
    begin
      Row.BuyWall[W].Vol := Src.NextBelow(5000) * 0.25;
      Row.BuyWall[W].Count := Src.NextBelow(40);
      Row.SellWall[W].Vol := Src.NextBelow(5000) * 0.25;
      Row.SellWall[W].Count := Src.NextBelow(40);
    end;
    Result.Add(Row);
  end;
end;

function SameBytes(const A: TBytes; B: Pointer; Len: Integer): Boolean;
begin
  Result := (Length(A) = Len) and ((Len = 0) or CompareMem(Pointer(A), B, Len));
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiPackRun: Int64;
var
  Acc:       UInt64;
  Rows:      TChiRows;
  Back:      TChiRows;
  Known:     TStringList;
  Plain:     TMemoryStream;
  Want:      TBytes;
  Pub:       TChiPublisher;
  Z:         TMemoryStream;
  Unz:       TChiUnzipStream;
  Restored:  TMemoryStream;
  Skipped:   Integer;
  Src:       TMemoryStream;
  Comp:      TMemoryStream;
  Got:       TMemoryStream;
  PackedLen: Integer;
begin
  Acc := 0;
  ChiCovered(IdPack);

  { Размеры записей — часть провода, а не подробность объявления. }
  ChiClaim(SizeOf(TChiCandle) = 20, 'пакет: запись второй версии не 20 байт');
  ChiClaim(SizeOf(TChiCandleOld) = 32, 'пакет: запись первой версии не 32 байта');
  ChiClaim(SizeOf(TChiWall) = 32, 'пакет: стенка не 32 байта');
  ChiBranch(IdPack, 'record-sizes');

  Rows := MakeRows(24, 20260830);
  Known := TStringList.Create;
  Plain := TMemoryStream.Create;
  try
    { Половину рынков читатель знает, половину — нет: промотка обязана
      попадать в стык следующего имени. }
    for var I := 0 to Rows.Count - 1 do
      if (I mod 2) = 0 then
        Known.Add(Rows[I].Name);

    { ── Вторая версия: сборка и сверка с эталоном байт в байт ── }
    BuildStream(Plain, Rows, 2, 180);
    Want := OracleBuild(Rows, 2, 180);
    ChiClaim(SameBytes(Want, Plain.Memory, Plain.Size),
      'пакет: собранный поток не совпал с эталоном');
    ChiBranch(IdPack, 'build-matches-oracle');
    Acc := ChiMix(Acc, Plain.Size);

    { ── Свойства быстрого сжатия ── }
    Src := TMemoryStream.Create;
    Comp := TMemoryStream.Create;
    Got := TMemoryStream.Create;
    try
      Src.CopyFrom(Plain, 0);
      Src.Position := 0;
      Comp.Size := AlgoSynLZ.AlgoCompressDestLen(Src.Size);
      ChiClaim(Comp.Size >= Src.Size div 2, 'пакет: обещанный размер подозрительно мал');
      PackedLen := AlgoSynLZ.AlgoCompress(Src.Memory, Src.Size, Comp.Memory);
      ChiClaim(PackedLen > 0, 'пакет: сжатие ничего не дало');
      ChiClaim(PackedLen <= Comp.Size, 'пакет: сжатие вышло за обещанный размер');
      ChiBranch(IdPack, 'destlen-covers');

      ChiClaim(AlgoSynLZ.AlgoDecompressDestLen(Comp.Memory) = Src.Size,
        'пакет: длина из заголовка сжатого блока не равна исходной');
      ChiBranch(IdPack, 'len-lives-in-header');

      Got.Size := Src.Size;
      ChiClaim(AlgoSynLZ.AlgoDecompress(Comp.Memory, PackedLen, Got.Memory) = Src.Size,
        'пакет: распаковка вернула другую длину');
      ChiClaim(CompareMem(Src.Memory, Got.Memory, Src.Size),
        'пакет: распакованное не равно исходному');
      ChiBranch(IdPack, 'synlz-roundtrip');
      Acc := ChiMix(Acc, PackedLen);
    finally
      FreeAndNil(Got);
      FreeAndNil(Comp);
      FreeAndNil(Src);
    end;

    { ── Публикация теневым буфером и пережатие по отметке ── }
    Pub := TChiPublisher.Create;
    Restored := TMemoryStream.Create;
    try
      ChiClaim(Pub.GetStream = nil, 'пакет: до публикации читателю нашлось что отдать');
      ChiBranch(IdPack, 'nothing-before-publish');

      Pub.Publish(Plain);
      ChiClaim(Pub.Dirty, 'пакет: публикация не поставила отметку');
      Z := Pub.GetStream;
      ChiClaim(Z <> nil, 'пакет: после публикации читателю нечего отдать');
      ChiClaim(Pub.Repacks = 1, 'пакет: первое чтение не пережало');
      ChiBranch(IdPack, 'repack-on-publish');

      { Второе чтение обязано отдать готовое, не пережимая заново. }
      Pub.GetStream;
      Pub.GetStream;
      ChiClaim(Pub.Repacks = 1, 'пакет: пережатие повторилось без публикации');
      ChiBranch(IdPack, 'repack-once');

      { Медленное сжатие — обратный путь, как у получателя по проводу. }
      Z.Position := 0;
      Unz := TChiUnzipStream.Create(Z);
      try
        Restored.CopyFrom(Unz, 0);
      finally
        Unz.Free;
      end;
      ChiClaim(Restored.Size = Plain.Size, 'пакет: медленное сжатие потеряло длину');
      ChiClaim(CompareMem(Restored.Memory, Plain.Memory, Plain.Size),
        'пакет: медленное сжатие вернуло другое содержимое');
      ChiBranch(IdPack, 'zlib-roundtrip');
      Acc := ChiMix(Acc, Restored.Size);

      { ── Разбор восстановленного: известные рынки, промотка чужих ── }
      Back := TChiRows.Create(True);
      try
        ChiClaim(ParseStream(Restored, Known, Back, 180, Skipped),
          'пакет: разбор отказался читать свой же поток');
        ChiClaim(Back.Count = Known.Count, 'пакет: разобрано не столько рынков, сколько знаем');
        ChiClaim(Skipped = Rows.Count - Known.Count, 'пакет: промотано не столько, сколько чужих');
        ChiBranch(IdPack, 'skip-unknown-market');

        for var I := 0 to Back.Count - 1 do
        begin
          var Orig := Rows[I * 2];
          ChiClaim(Back[I].Name = Orig.Name, 'пакет: имя рынка съехало после промотки');
          ChiClaim(Length(Back[I].Candles) = Length(Orig.Candles),
            'пакет: число свечей съехало');
          for var K := 0 to High(Orig.Candles) do
          begin
            ChiClaim(Back[I].Candles[K].MaxP = Orig.Candles[K].MaxP,
              'пакет: цена свечи не сошлась');
            ChiClaim(ChiNear(Back[I].Candles[K].Time, Orig.Candles[K].Time, 1E-9),
              'пакет: время свечи сдвинулось при равных поясах');
          end;
          ChiClaim(Back[I].BuyWall[3].Count = Orig.BuyWall[3].Count,
            'пакет: стенка не сошлась');
        end;
        ChiBranch(IdPack, 'parse-matches-source');
        Acc := ChiMix(Acc, Back.Count);
      finally
        FreeAndNil(Back);
      end;

      { ── Сдвиг пояса: читатель в другом поясе получает СВОЁ местное время ── }
      Back := TChiRows.Create(True);
      try
        ParseStream(Restored, Known, Back, 240, Skipped);
        ChiClaim(ChiNear(Back[0].Candles[0].Time - Rows[0].Candles[0].Time,
                         60 / MinsInDay, 1E-9),
          'пакет: разница поясов не превратилась в час');
        ChiBranch(IdPack, 'time-shift-applied');
      finally
        FreeAndNil(Back);
      end;

      { ── Тихий отказ не повторяется, исключение — повторяется ── }
      Pub.Publish(Plain);
      Pub.BreakNext := True;
      ChiClaim(Pub.GetStream = nil, 'пакет: сбой пережатия отдал поток');
      ChiClaim(Pub.Dirty, 'пакет: сбой пережатия не вернул отметку');
      ChiBranch(IdPack, 'failure-restores-dirty');

      ChiClaim(Pub.GetStream <> nil, 'пакет: после сбоя повтор не удался');
      ChiClaim(Pub.Repacks = 2, 'пакет: повтор после сбоя не пережал заново');
      ChiBranch(IdPack, 'retry-after-failure');
    finally
      FreeAndNil(Restored);
      FreeAndNil(Pub);
    end;

    { ── Первая версия: другой размер записи на том же коде ── }
    Plain.Size := 0;
    BuildStream(Plain, Rows, 1, 180);
    Want := OracleBuild(Rows, 1, 180);
    ChiClaim(SameBytes(Want, Plain.Memory, Plain.Size),
      'пакет: поток первой версии не совпал с эталоном');
    ChiBranch(IdPack, 'build-old-version');

    Back := TChiRows.Create(True);
    try
      ChiClaim(ParseStream(Plain, Known, Back, 180, Skipped),
        'пакет: разбор не принял первую версию');
      ChiClaim(Back.Count = Known.Count, 'пакет: первая версия разобрана не полностью');
      ChiClaim(Skipped = Rows.Count - Known.Count,
        'пакет: промотка первой версии считала чужой размер записи');
      ChiClaim(Back[Back.Count - 1].Name = Rows[(Known.Count - 1) * 2].Name,
        'пакет: последнее имя первой версии съехало');
      ChiBranch(IdPack, 'read-old-version');
      Acc := ChiMix(Acc, Skipped);
    finally
      FreeAndNil(Back);
    end;

    { ── Версия из будущего не читается вовсе ── }
    Plain.Position := SizeOf(Integer);
    var Future: Byte := ChiCandlesVersion + 1;
    Plain.Write(Future, SizeOf(Future));
    Back := TChiRows.Create(True);
    try
      ChiClaim(not ParseStream(Plain, Known, Back, 180, Skipped),
        'пакет: версия из будущего была прочитана');
      ChiClaim(Back.Count = 0, 'пакет: версия из будущего что-то добавила');
      ChiBranch(IdPack, 'future-version-refused');
    finally
      FreeAndNil(Back);
    end;

    { ── Пустой поток ── }
    Plain.Size := 0;
    Back := TChiRows.Create(True);
    try
      ChiClaim(not ParseStream(Plain, Known, Back, 180, Skipped),
        'пакет: пустой поток был прочитан');
      ChiBranch(IdPack, 'empty-stream');
    finally
      FreeAndNil(Back);
    end;
  finally
    FreeAndNil(Plain);
    FreeAndNil(Known);
    FreeAndNil(Rows);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
