unit chimera_buf;

{ Орган «буферы»: переиспользуемый поток и линейный кеш пакетов.

  Источник: `MoonBot/MoonProto\MoonProtoTradesStream.pas` —
  `TReusableMemStream` и `TPacketCache`. Перенесено дословно по форме:

    * переопределённое перевыделение памяти, которое НИКОГДА не отдаёт её
      обратно: уменьшение и очистка возвращают прежнюю ёмкость и прежний
      адрес, рост идёт с запасом вдвое, и только явное ужатие делает
      настоящее уменьшение — под флагом, который сам же метод и читает;
    * отметка наибольшей запрошенной ёмкости, по которой потом решается,
      есть ли что ужимать;
    * линейный кеш пакетов: данные пишутся подряд, при переполнении цикл
      начинается сначала с нулевого смещения, а старые записи вытесняются
      не разом, а по мере того, как их область перезаписывается;
    * массив указателей растёт сотнями и дозаполняется нулями через `FillChar`
      ровно на добавленный кусок.

  Почему это отдельная форма:

    * метод перевыделения вызывается РТЛ-ом изнутри, и его побочный эффект —
      правка переданной по ссылке новой ёмкости. Значение, которое он вернёт
      наружу, и значение, которое он положит в параметр, — разные ответы, и
      оба важны;
    * «не отдавать память» означает, что после большого пакета маленький
      пишется в ту же область, и хвост прошлого обязан не попасть в новый;
    * вытеснение по перекрытию областей — арифметика смещений, где ошибка
      даёт не падение, а тихую выдачу чужих данных под своим номером.

  Оракулы:

    1. независимая модель кеша на обычном словаре: она хранит копии и не знает
       ни про смещения, ни про вытеснение. Любой пакет, который живой кеш
       отдал, обязан совпасть с моделью байт в байт; любой, который он не
       отдал, модель вправе иметь — но НЕ наоборот;
    2. ёмкость и адрес памяти сверяются напрямую: после уменьшения адрес
       обязан не измениться, а ёмкость — не упасть;
    3. счётчики роста и ужатия предъявляются, чтобы обе ветви были живыми. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Math, Generics.Collections, chimera_body;

type
  { Переиспользуемый поток: память вниз не отдаётся. }
  TChiReusableStream = class(TMemoryStream)
  private
    FHighWater: NativeInt;
    FTrimming: Boolean;
    FGrows: Int64;
    FKeeps: Int64;
  protected
    function Realloc(var NewCapacity: NativeInt): Pointer; override;
  public
    procedure Trim;
    property Grows: Int64 read FGrows;
    property Keeps: Int64 read FKeeps;
    property HighWater: NativeInt read FHighWater;
  end;

  TChiCachedRec = record
    Valid:     Boolean;
    Offset:    Integer;
    Len:       Integer;
    PacketNum: Word;
  end;

  { Линейный кеш пакетов с вытеснением по перекрытию. }
  TChiPacketCache = class
  private
    FData:        Pointer;
    FBufferSize:  Integer;
    FWritePos:    Integer;
    FTotalSize:   Integer;
    FCurrentIndex: Integer;
    FIndices:     array of TChiCachedRec;
    FMaxIndices:  Integer;
    FLastTrashed: Integer;
    FWraps:       Int64;
    FTrashed:     Int64;
    FGrewIndices: Int64;
  public
    constructor Create(ABufferSize: Integer);
    destructor Destroy; override;
    procedure AddPacket(PacketNum: Word; const Data: TBytes; Len: Integer);
    function FindPacket(PacketNum: Word; out Data: TBytes): Boolean;
    property Wraps: Int64 read FWraps;
    property Trashed: Int64 read FTrashed;
    property GrewIndices: Int64 read FGrewIndices;
  end;

function ChiBufRun: Int64;

implementation

{ ═══ Переиспользуемый поток ══════════════════════════════════════════════ }

function TChiReusableStream.Realloc(var NewCapacity: NativeInt): Pointer;
begin
  if NewCapacity > FHighWater then FHighWater := NewCapacity;
  if FTrimming or (NewCapacity > Capacity) then
  begin
    if not FTrimming then
      { Рост с запасом вдвое — чтобы перевыделение было редким. }
      NewCapacity := Max(NewCapacity, Capacity * 2);
    Inc(FGrows);
    Result := inherited Realloc(NewCapacity);
  end
  else
  begin
    { Уменьшение и очистка: память НЕ отдаём, адрес не меняем. }
    NewCapacity := Capacity;
    Inc(FKeeps);
    Result := Memory;
  end;
end;

procedure TChiReusableStream.Trim;
begin
  if Capacity > Max(FHighWater, Size) then
  begin
    FTrimming := True;
    try
      SetCapacity(Max(FHighWater, Size));
    finally
      FTrimming := False;
    end;
  end;
  FHighWater := Size;
end;

{ ═══ Кеш пакетов ═════════════════════════════════════════════════════════ }

constructor TChiPacketCache.Create(ABufferSize: Integer);
begin
  inherited Create;
  FBufferSize := ABufferSize;
  GetMem(FData, FBufferSize);
  FMaxIndices := 16;
  SetLength(FIndices, FMaxIndices);
  FLastTrashed := 1;
end;

destructor TChiPacketCache.Destroy;
begin
  FreeMem(FData);
  inherited Destroy;
end;

procedure TChiPacketCache.AddPacket(PacketNum: Word; const Data: TBytes;
  Len: Integer);
begin
  if Len <= 0 then Exit;
  if Len > FBufferSize then Exit;

  { Не влезает в текущий цикл — цикл начинается сначала. }
  if FTotalSize + Len > FBufferSize then
  begin
    FWritePos := 0;
    FCurrentIndex := 0;
    FTotalSize := 0;
    FLastTrashed := 1;
    Inc(FWraps);
  end;

  if FCurrentIndex >= FMaxIndices then
  begin
    SetLength(FIndices, FMaxIndices + 100);
    FillChar(FIndices[FMaxIndices], 100 * SizeOf(TChiCachedRec), 0);
    FMaxIndices := FMaxIndices + 100;
    Inc(FGrewIndices);
  end;

  Move(Data[0], Pointer(NativeInt(FData) + FWritePos)^, Len);

  FIndices[FCurrentIndex].Valid := True;
  FIndices[FCurrentIndex].Offset := FWritePos;
  FIndices[FCurrentIndex].Len := Len;
  FIndices[FCurrentIndex].PacketNum := PacketNum;

  Inc(FCurrentIndex);
  Inc(FWritePos, Len);
  Inc(FTotalSize, Len);

  { Вытеснение: записи, чья область попала под перезапись, объявляются
    негодными — по одной, по мере продвижения. }
  FLastTrashed := Max(FLastTrashed, FCurrentIndex);
  while (FLastTrashed < FMaxIndices) and (FIndices[FLastTrashed].Offset > 0)
        and (FIndices[FLastTrashed].Offset < FWritePos) do
  begin
    if FIndices[FLastTrashed].Valid then Inc(FTrashed);
    FIndices[FLastTrashed].Valid := False;
    Inc(FLastTrashed);
  end;
end;

function TChiPacketCache.FindPacket(PacketNum: Word; out Data: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  Data := nil;
  for I := FCurrentIndex - 1 downto 0 do
    if FIndices[I].Valid and (FIndices[I].PacketNum = PacketNum) then
    begin
      SetLength(Data, FIndices[I].Len);
      Move(Pointer(NativeInt(FData) + FIndices[I].Offset)^, Data[0],
           FIndices[I].Len);
      Exit(True);
    end;
end;

{ ═══ Независимая модель кеша ═════════════════════════════════════════════

  Обычный словарь копий. Ни смещений, ни вытеснения, ни циклов: он помнит всё,
  что клали. Живой кеш вправе ЗАБЫТЬ пакет, но не вправе отдать под его
  номером что-то другое. }

type
  TChiModel = TDictionary<Word, TBytes>;

const
  IdBuf   = 'CHI-MB-BUF-001';
  IdCache = 'CHI-MB-BUF-002';

function SameBytes(const A, B: TBytes; Len: Integer): Boolean;
var
  I: Integer;
begin
  Result := (Length(A) = Len) and (Length(B) >= Len);
  if not Result then Exit;
  for I := 0 to Len - 1 do
    if A[I] <> B[I] then Exit(False);
end;

function ChiBufRun: Int64;
var
  Stream: TChiReusableStream;
  Cache: TChiPacketCache;
  Model: TChiModel;
  Src: TChiSource;
  Acc: UInt64;
  Data, Got, Want: TBytes;
  I, J, Len, Found, Lost: Integer;
  BigCap, AfterCap: NativeInt;
  BigMem, AfterMem: Pointer;
  Num: Word;
begin
  ChiCovered(IdBuf);
  ChiCovered(IdCache);
  Acc := ChiOffset;
  Src := ChiSource(606060);

  { ── Переиспользуемый поток ── }
  Stream := TChiReusableStream.Create;
  try
    SetLength(Data, 64 * 1024);
    for I := 0 to High(Data) do Data[I] := Byte(I);
    Stream.Write(Data[0], Length(Data));
    BigCap := Stream.Capacity;
    BigMem := Stream.Memory;
    ChiClaim(BigCap >= 64 * 1024, 'буфер: ёмкость меньше записанного');
    ChiClaim(Stream.Grows > 0, 'буфер: рост ни разу не случился');
    ChiBranch(IdBuf, 'grow');

    { Очистка не имеет права отдать память. }
    Stream.Clear;
    ChiClaim(Stream.Capacity = BigCap, 'буфер: очистка отдала память');
    ChiClaim(Stream.Memory = BigMem, 'буфер: очистка сменила адрес');
    ChiClaim(Stream.Size = 0, 'буфер: очистка не обнулила длину');
    ChiBranch(IdBuf, 'clear-keeps');

    { Меньший пакет пишется в ту же память. }
    Stream.Write(Data[0], 128);
    ChiClaim(Stream.Capacity = BigCap, 'буфер: меньший пакет ужал ёмкость');
    ChiClaim(Stream.Memory = BigMem, 'буфер: меньший пакет сменил адрес');
    ChiClaim(Stream.Size = 128, 'буфер: длина после меньшего пакета не та');
    ChiClaim(Stream.Keeps > 0, 'буфер: ветвь сохранения памяти не сработала');
    ChiBranch(IdBuf, 'smaller-keeps');

    { Прочитанное обязано быть тем, что записали сейчас, а не хвостом
      прошлого пакета. }
    Stream.Position := 0;
    SetLength(Got, 128);
    Stream.Read(Got[0], 128);
    ChiClaim(SameBytes(Got, Data, 128), 'буфер: прочитан хвост прошлого пакета');
    ChiBranch(IdBuf, 'no-stale');

    { Явное ужатие — единственный способ вернуть память. Но ужимается не
      «всё лишнее», а лишь то, что раздуто СВЕРХ наибольшей потребности
      периода: первое ужатие только закрывает период, сбрасывая отметку
      наибольшего на текущую длину. Отдаёт память следующее — уже зная, что
      период прошёл скромно. }
    Stream.Trim;
    ChiClaim(Stream.HighWater = Stream.Size,
      'буфер: первое ужатие не закрыло период');
    ChiBranch(IdBuf, 'trim-closes-period');

    Stream.Trim;
    AfterCap := Stream.Capacity;
    AfterMem := Stream.Memory;
    ChiClaim(AfterCap < BigCap, 'буфер: ужатие ничего не отдало');
    ChiClaim(AfterCap >= Stream.Size, 'буфер: ужатие обрезало данные');
    ChiBranch(IdBuf, 'trim');
    Acc := ChiMix(Acc, AfterCap);

    { После ужатия отметка наибольшего сбрасывается на текущую длину, значит
      следующий большой пакет снова вырастет. }
    Stream.Write(Data[0], 32 * 1024);
    ChiClaim(Stream.Capacity > AfterCap, 'буфер: после ужатия не вырос');
    ChiBranch(IdBuf, 'regrow-after-trim');
    Acc := ChiMix(Acc, Stream.Grows);
    Acc := ChiMix(Acc, Stream.Keeps);
  finally
    FreeAndNil(Stream);
  end;

  { ── Кеш пакетов ── }
  Cache := TChiPacketCache.Create(8192);
  Model := TChiModel.Create;
  try
    Found := 0;
    Lost := 0;
    for I := 0 to 499 do
    begin
      { Длины небольшие: за цикл в буфер влезает несколько десятков пакетов,
        значит и заворот случается часто, и массив указателей успевает
        дорасти до своего предела. }
      Len := 1 + Src.NextBelow(256);
      SetLength(Data, Len);
      for J := 0 to Len - 1 do Data[J] := Byte((I * 31 + J) and $FF);
      Num := Word(I);
      Cache.AddPacket(Num, Data, Len);
      Model.AddOrSetValue(Num, Copy(Data, 0, Len));
    end;
    ChiClaim(Cache.Wraps > 0, 'кеш: заворот ни разу не случился');
    ChiClaim(Cache.Trashed > 0, 'кеш: вытеснение ни разу не сработало');
    ChiClaim(Cache.GrewIndices > 0, 'кеш: массив указателей не рос');
    ChiBranch(IdCache, 'wrap');
    ChiBranch(IdCache, 'evict');
    ChiBranch(IdCache, 'grow-indices');

    { Всё, что кеш отдал, обязано совпасть с моделью. Забыть он вправе. }
    for I := 0 to 499 do
    begin
      Num := Word(I);
      if Cache.FindPacket(Num, Got) then
      begin
        Inc(Found);
        ChiClaim(Model.TryGetValue(Num, Want), 'кеш: отдал неизвестный номер');
        ChiClaim(SameBytes(Got, Want, Length(Want)),
          'кеш: отдал чужие данные под номером ' + IntToStr(I));
      end
      else
        Inc(Lost);
    end;
    ChiClaim(Found > 0, 'кеш: не отдал ни одного пакета');
    ChiClaim(Lost > 0, 'кеш: ничего не вытеснил — ёмкость слишком велика');
    ChiBranch(IdCache, 'hit');
    ChiBranch(IdCache, 'miss');
    Acc := ChiMix(Acc, Found);

    { Пакет больше буфера обязан быть отвергнут молча, не испортив кеш. }
    SetLength(Data, 9000);
    Cache.AddPacket(60000, Data, 9000);
    ChiClaim(not Cache.FindPacket(60000, Got), 'кеш: слишком большой принят');
    ChiBranch(IdCache, 'too-big');

    { Пустой пакет тоже отвергается. }
    Cache.AddPacket(60001, Data, 0);
    ChiClaim(not Cache.FindPacket(60001, Got), 'кеш: пустой принят');
    ChiBranch(IdCache, 'empty');
  finally
    FreeAndNil(Model);
    FreeAndNil(Cache);
  end;

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
