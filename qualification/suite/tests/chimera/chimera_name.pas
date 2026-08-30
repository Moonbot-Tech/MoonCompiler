unit chimera_name;

{ Орган «различающие имена»: как одноимённые рынки разъезжаются на проводе.

  Источник: `Arbitrage/ArbServer\ArbServer.pas` —
  вложенная `TaggedName` и цикл разрешения коллизий внутри `BuildComboPairs`.
  Перенесено дословно по форме: подсчёт CRC32C от имени, поиск МИНИМАЛЬНОЙ
  длины префикса хэша, которая отличает запись от всех одноимённых соседей, и
  сборка проводного имени записью СЫРЫХ БАЙТОВ хэша прямо в тело управляемой
  строки.

  Почему это отдельная форма:

    * `Move` кладёт байты целого числа внутрь строки, которой перед этим
      назначили длину. Строка после этого содержит произвольные байты, включая
      нулевые, и обязана оставаться строкой — длина известна, а не считается
      по нулю;
    * длина префикса ищется наращиванием в `repeat ... until False` с ДВУМЯ
      выходами: коллизия разрешилась либо упёрлись в потолок в четыре байта.
      Второй выход означает «имя не разъехалось» и даёт пустой результат —
      такой рынок на провод не идёт;
    * `CompareMem` сравнивает первые N байтов двух чисел. Это байтовый взгляд
      на целое, то есть снова два имени на одну память;
    * вложенный цикл по всем соседям внутри цикла наращивания — O(N²) по
      группе, и именно это делает наивный оракул законным: он считает то же
      самое, но в лоб.

  Оракулы:

    1. **свойство результата**, а не совпадение с образцом: если для записи
       выбрана длина L, то префикс длины L обязан быть уникальным в группе, а
       любая меньшая длина — не уникальной. Это проверяется прямым перебором и
       не зависит от того, как именно алгоритм искал;
    2. **наивный перебор** — вторая реализация поиска той же длины, побайтным
       сравнением без `CompareMem`;
    3. **разбор собранного имени**: имя обязано делиться на исходное имя,
       разделитель и ровно L байтов хэша;
    4. **стандартный вектор CRC32C** — внешняя истина для самого хэша. }

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
  { Потолок длины тега — размер самого хэша. Значение из живого кода. }
  ChiNameTagMax = SizeOf(Cardinal);

function ChiNameRun: Int64;

implementation

{ ═══ CRC32C ══════════════════════════════════════════════════════════════

  В Арбитраже хэш берётся из библиотеки. Здесь он посчитан своей таблицей,
  потому что предмет проверки — форма разрешения коллизий, а хэш обязан лишь
  быть настоящим CRC32C: это подтверждается стандартным вектором. }

var
  Crc32cTable: array [0 .. 255] of Cardinal;

procedure InitCrc32c;
var
  I, J: Integer;
  V: Cardinal;
begin
  for I := 0 to 255 do
  begin
    V := Cardinal(I);
    for J := 0 to 7 do
      if (V and 1) <> 0 then
        V := (V shr 1) xor $82F63B78
      else
        V := V shr 1;
    Crc32cTable[I] := V;
  end;
end;

function Crc32c(Seed: Cardinal; Data: PByte; Len: Integer): Cardinal;
begin
  Result := not Seed;
  while Len > 0 do
  begin
    Result := (Result shr 8) xor Crc32cTable[(Result xor Data^) and $FF];
    Inc(Data);
    Dec(Len);
  end;
  Result := not Result;
end;

function NameCrc(const AName: AnsiString): Cardinal;
begin
  if Length(AName) = 0 then
    Result := Crc32c(0, nil, 0)
  else
    Result := Crc32c(0, PByte(@AName[1]), Length(AName));
end;

{ ═══ Перенесённая форма ══════════════════════════════════════════════════ }

function TaggedName(const ADisplayName: AnsiString; AHash: Cardinal;
  ATagLen: Integer): AnsiString;
var
  NameLen: Integer;
begin
  NameLen := Length(ADisplayName);
  SetLength(Result, NameLen + 1 + ATagLen);
  if NameLen > 0 then Move(ADisplayName[1], Result[1], NameLen);
  Result[NameLen + 1] := '#';
  { Сырые байты числа ложатся внутрь управляемой строки. }
  Move(AHash, Result[NameLen + 2], ATagLen);
end;

{ Поиск минимальной различающей длины — как в живом цикле. }
function PickTagLen(const Hashes: array of Cardinal; Index: Integer;
  out Collision: Boolean): Integer;
var
  K: Integer;
begin
  Result := 1;
  repeat
    Collision := False;
    for K := 0 to High(Hashes) do
      if (K <> Index) and CompareMem(@Hashes[Index], @Hashes[K], Result) then
      begin
        Collision := True;
        Break;
      end;
    if not Collision or (Result = ChiNameTagMax) then Break;
    Inc(Result);
  until False;
end;

{ ═══ Наивный оракул ══════════════════════════════════════════════════════

  Тот же поиск, но побайтным сравнением и без досрочных выходов внутри
  сравнения: сначала считается, сколько соседей совпадает по каждой длине,
  потом выбирается первая длина без совпадений. }

function BytesEqual(A, B: Cardinal; Len: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to Len - 1 do
    if ((A shr (I * 8)) and $FF) <> ((B shr (I * 8)) and $FF) then
      Result := False;
end;

function NaiveTagLen(const Hashes: array of Cardinal; Index: Integer;
  out Collision: Boolean): Integer;
var
  Len, K, Same: Integer;
begin
  for Len := 1 to ChiNameTagMax do
  begin
    Same := 0;
    for K := 0 to High(Hashes) do
      if (K <> Index) and BytesEqual(Hashes[Index], Hashes[K], Len) then
        Inc(Same);
    if Same = 0 then
    begin
      Collision := False;
      Exit(Len);
    end;
  end;
  Collision := True;
  Result := ChiNameTagMax;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

const
  IdName = 'CHI-ARB-NAME-001';

function MakeGroup(Count: Integer; Seed: UInt64;
  ForceCollision: Boolean): TArray<AnsiString>;
var
  Src: TChiSource;
  I, J, Len: Integer;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(Seed);
  for I := 0 to Count - 1 do
  begin
    Len := 3 + Src.NextBelow(9);
    SetLength(Result[I], Len);
    for J := 1 to Len do
      Result[I][J] := AnsiChar(Ord('A') + Src.NextBelow(26));
  end;
  { Полное совпадение символов даёт полное совпадение хэшей — тот случай, ради
    которого в живом коде и стоит потолок длины тега. }
  if ForceCollision and (Count >= 2) then Result[1] := Result[0];
end;

function ChiNameRun: Int64;
var
  Names: TArray<AnsiString>;
  Hashes: array of Cardinal;
  I, K, Len, NaiveLen, Unresolved, Tagged: Integer;
  Collision, NaiveCollision, Unique: Boolean;
  Wire: AnsiString;
  Acc: UInt64;
  Round: Integer;
  Back: Cardinal;
begin
  ChiCovered(IdName);
  Acc := ChiOffset;

  { ── Внешняя истина для хэша ── }
  ChiClaim(NameCrc('123456789') = $E3069283,
    'имена: CRC32C не совпал со стандартным вектором');
  ChiBranch(IdName, 'crc-vector');
  ChiClaim(NameCrc('') = 0, 'имена: CRC32C пустого не ноль');
  ChiBranch(IdName, 'crc-empty');

  Unresolved := 0;
  Tagged := 0;

  for Round := 0 to 3 do
  begin
    Names := MakeGroup(6 + Round * 5, 1000 + UInt64(Round), Round >= 2);
    SetLength(Hashes, Length(Names));
    for I := 0 to High(Names) do
      Hashes[I] := NameCrc(Names[I]);

    for I := 0 to High(Hashes) do
    begin
      Len := PickTagLen(Hashes, I, Collision);
      NaiveLen := NaiveTagLen(Hashes, I, NaiveCollision);

      ChiClaim(Collision = NaiveCollision,
        'имена: вердикт коллизии разошёлся с наивным перебором');
      if not Collision then
        ChiClaim(Len = NaiveLen,
          'имена: длина тега разошлась с наивным перебором');

      if Collision then
      begin
        { Имя не разъехалось: на провод такой рынок не идёт. }
        Inc(Unresolved);
        ChiBranch(IdName, 'unresolved');
        Continue;
      end;

      { Свойство результата: выбранная длина уникальна, а предыдущая — нет.
        Проверяется прямым перебором, независимо от того, как искали. }
      Unique := True;
      for K := 0 to High(Hashes) do
        if (K <> I) and BytesEqual(Hashes[I], Hashes[K], Len) then Unique := False;
      ChiClaim(Unique, 'имена: выбранная длина не различает');
      if Len > 1 then
      begin
        Unique := True;
        for K := 0 to High(Hashes) do
          if (K <> I) and BytesEqual(Hashes[I], Hashes[K], Len - 1) then
            Unique := False;
        ChiClaim(not Unique, 'имена: длина не минимальна');
        ChiBranch(IdName, 'grown-tag');
      end
      else
        ChiBranch(IdName, 'single-byte-tag');

      { Сборка проводного имени и его разбор обратно. }
      Wire := TaggedName(Names[I], Hashes[I], Len);
      Inc(Tagged);
      ChiClaim(Length(Wire) = Length(Names[I]) + 1 + Len,
        'имена: длина проводного имени не сошлась');
      ChiClaim(Copy(Wire, 1, Length(Names[I])) = Names[I],
        'имена: исходное имя испорчено');
      ChiClaim(Wire[Length(Names[I]) + 1] = '#',
        'имена: разделитель не на месте');
      Back := 0;
      Move(Wire[Length(Names[I]) + 2], Back, Len);
      ChiClaim(BytesEqual(Back, Hashes[I], Len),
        'имена: байты хэша в строке не те');
      ChiBranch(IdName, 'wire-roundtrip');

      Acc := ChiMix(Acc, Len);
      Acc := ChiMix(Acc, Length(Wire));
      Acc := ChiMix(Acc, Int64(Hashes[I]));
    end;
  end;

  ChiClaim(Tagged > 0, 'имена: ни одно имя не получило тега');
  ChiClaim(Unresolved > 0,
    'имена: коллизия ни разу не осталась неразрешённой — потолок не проверен');

  { Строка с нулевыми байтами внутри обязана сохранить длину: она байтовая, а
    не оканчивающаяся нулём. }
  Wire := TaggedName('AB', 0, 4);
  ChiClaim(Length(Wire) = 7, 'имена: нулевые байты обрезали строку');
  ChiClaim(Wire[4] = #0, 'имена: нулевой байт не записан');
  ChiBranch(IdName, 'zero-bytes');
  Acc := ChiMix(Acc, Length(Wire));

  { Пустое имя: в живом коде такие рынки отбрасываются раньше, но сама сборка
    обязана работать и на нём. }
  Wire := TaggedName('', $01020304, 2);
  ChiClaim(Length(Wire) = 3, 'имена: пустое имя дало не ту длину');
  ChiClaim(Wire[1] = '#', 'имена: разделитель пустого имени не на месте');
  ChiBranch(IdName, 'empty-name');
  Acc := ChiMix(Acc, Length(Wire));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

initialization
  InitCrc32c;

end.
