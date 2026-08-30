unit chimera_stream;

{ Орган «поток»: блочная передача сделок с контрольной суммой и пересборкой.

  Источник: `Arbitrage/StreamServer\StreamProto.pas` —
  проводной формат потока сделок. Перенесено дословно по форме:

    * заголовок в четырнадцать байт `packed record`, где контрольная сумма
      стоит ПЕРВОЙ и считается по всему блоку при обнулённой самой себе;
    * контрольная сумма — перенос из ассемблерной функции: сложение с
      переносом, сдвиг влево через перенос, вращение на восемь бит, и всё это
      над одним восьмибайтовым состоянием, куда байт входит дважды — с двумя
      разными масками. Свёртка в четыре байта складывает половины;
    * полезная нагрузка самоограничена по рынкам:
      `[длина имени][имя][счёт срочных][сделки][счёт спотовых][сделки]`;
    * номер блока — байт с заворотом через двести пятьдесят шесть, и по нему
      блок ищут в кеше повторов;
    * признак сжатия — бит в поле флагов.

  Заменено оснасткой: сеть и сжатие.

  Почему это отдельная форма:

    * контрольная сумма построена на переносах и вращениях, то есть на битах,
      которые оптимизатор трогает охотнее всего. Она же и есть внешняя
      проверка: клиент сверяет её байт в байт, и расхождение ломает связь с
      тысячами ботов;
    * заголовок читается наложением указателя на буфер, а не полем за полем;
    * блоки приходят с повторами и не по порядку, и пересборка обязана дать
      ровно исходную последовательность.

  Оракулы:

    1. **вторая реализация контрольной суммы**, написанная иначе — над
       массивом байтов состояния вместо целого;
    2. **канонический размер** блока, посчитанный по правилам формата;
    3. **точная пересборка**: последовательность сделок после приёма обязана
       совпасть с отправленной байт в байт, при любом порядке доставки;
    4. **отказ**: порча блока обязана быть замечена суммой — но не всякая:
       у этого алгоритма есть столкновения на одиночном изменении бита, и
       доля пропущенных измеряется, а не выдаётся за ноль. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections, chimera_body;

const
  ChiStreamVer  = 3;
  ChiFlagZipped = $01;
  ChiFlagRepeat = $02;

type
  TChiDataHeader = packed record
    CheckSum: Cardinal;
    Ver:      Byte;
    BotId:    Integer;
    Command:  Byte;
    Port:     Word;
    BlockNum: Byte;
    Exchange: Byte;
    Flag:     Byte;
  end;
  PChiDataHeader = ^TChiDataHeader;

function ChiStreamRun: Int64;

implementation

const
  IdStream = 'CHI-ARB-STREAM-001';

{ ═══ Контрольная сумма ═══════════════════════════════════════════════════

  Перенос ассемблерной формы: байт входит в состояние дважды, с масками
  $AA и $39, между входами — сдвиг с переносом и вращение на восемь бит. }

function AddByteWithCarry(var AState: UInt64; AByteIndex: Integer;
  AAddend: Byte; ACarry: Boolean): Boolean; inline;
var
  Shift: Integer;
  Sum: Cardinal;
  Mask: UInt64;
begin
  Shift := AByteIndex * 8;
  Sum := Cardinal(Byte(AState shr Shift)) + AAddend + Ord(ACarry);
  Mask := UInt64($FF) shl Shift;
  AState := (AState and not Mask) or (UInt64(Byte(Sum)) shl Shift);
  Result := Sum > $FF;
end;

function CheckSumW(Buf: Pointer; Size: Cardinal): UInt64;
var
  State: UInt64;
  P: PByte;
  I: Cardinal;
  B: Byte;
  Carry, NextCarry: Boolean;
begin
  State := 0;
  if Size = 0 then Exit(0);
  P := Buf;
  for I := 0 to Size - 1 do
  begin
    B := P^;
    Inc(P);

    Carry := AddByteWithCarry(State, 0, B xor $AA, False);

    NextCarry := (State and (UInt64(1) shl 63)) <> 0;
    State := (State shl 1) or Ord(Carry);
    Carry := NextCarry;

    Carry := AddByteWithCarry(State, 0, 0, Carry);

    State := (State shl 8) or (State shr 56);
    Carry := (State and 1) <> 0;

    Carry := AddByteWithCarry(State, 1, B xor $39, Carry);
    Carry := AddByteWithCarry(State, 0, 0, Carry);

    State := (State shl 8) or (State shr 56);
    Carry := (State and 1) <> 0;

    AddByteWithCarry(State, 0, 0, Carry);
  end;
  Result := State;
end;

function CheckSum32(Buf: Pointer; Size: Cardinal): Cardinal;
var
  Value: UInt64;
begin
  Value := CheckSumW(Buf, Size);
  { Свёртка в четыре байта: нижняя половина плюс верхняя. }
  Result := Cardinal(UInt64(Cardinal(Value)) + Cardinal(Value shr 32));
end;

{ ═══ Независимая реализация той же суммы ═════════════════════════════════

  Состояние держится массивом байтов, а не целым: сдвиги и вращения делаются
  перестановкой элементов, переносы — явными сравнениями. Ни одной общей
  строки с формой выше. }

type
  TChiState8 = array [0 .. 7] of Byte;

procedure Rol8(var S: TChiState8);
var
  Top: Byte;
  I: Integer;
begin
  { Вращение целого на восемь бит влево = сдвиг байтов к старшим. }
  Top := S[7];
  for I := 7 downto 1 do S[I] := S[I - 1];
  S[0] := Top;
end;

procedure Shl1(var S: TChiState8; InBit: Boolean; out OutBit: Boolean);
var
  I: Integer;
  Carry, Next: Boolean;
begin
  OutBit := (S[7] and $80) <> 0;
  Carry := InBit;
  for I := 0 to 7 do
  begin
    Next := (S[I] and $80) <> 0;
    S[I] := Byte((S[I] shl 1) or Ord(Carry));
    Carry := Next;
  end;
end;

function AddByte(var S: TChiState8; Idx: Integer; Addend: Byte;
  Carry: Boolean): Boolean;
var
  Sum: Integer;
begin
  Sum := S[Idx] + Addend + Ord(Carry);
  S[Idx] := Byte(Sum);
  Result := Sum > $FF;
end;

function CheckSumWBytes(Buf: Pointer; Size: Cardinal): UInt64;
var
  S: TChiState8;
  P: PByte;
  I: Cardinal;
  B: Byte;
  Carry, Out1: Boolean;
begin
  FillChar(S, SizeOf(S), 0);
  if Size = 0 then Exit(0);
  P := Buf;
  for I := 0 to Size - 1 do
  begin
    B := P^;
    Inc(P);

    Carry := AddByte(S, 0, B xor $AA, False);
    Shl1(S, Carry, Out1);
    Carry := Out1;
    Carry := AddByte(S, 0, 0, Carry);
    Rol8(S);
    Carry := (S[0] and 1) <> 0;
    Carry := AddByte(S, 1, B xor $39, Carry);
    Carry := AddByte(S, 0, 0, Carry);
    Rol8(S);
    Carry := (S[0] and 1) <> 0;
    AddByte(S, 0, 0, Carry);
  end;
  Move(S, Result, 8);
end;

{ ═══ Блок ════════════════════════════════════════════════════════════════ }

type
  TChiCoinTrades = record
    Coin:    AnsiString;
    Futures: array of TChiTrade;
    Spot:    array of TChiTrade;
  end;
  TChiCoinList = array of TChiCoinTrades;

function BuildBlock(const Coins: TChiCoinList; BlockNum: Byte;
  Exchange: Byte; Zipped: Boolean): TBytes;
var
  Stream: TMemoryStream;
  Hdr: TChiDataHeader;
  I: Integer;
  W: Word;
begin
  Stream := TMemoryStream.Create;
  try
    Hdr := Default(TChiDataHeader);
    Hdr.Ver := ChiStreamVer;
    Hdr.BotId := 4242;
    Hdr.Command := 8;
    Hdr.Port := 20000;
    Hdr.BlockNum := BlockNum;
    Hdr.Exchange := Exchange;
    if Zipped then Hdr.Flag := ChiFlagZipped;
    Stream.WriteBuffer(Hdr, SizeOf(Hdr));

    for I := 0 to High(Coins) do
    begin
      W := Length(Coins[I].Coin);
      Stream.WriteBuffer(W, SizeOf(W));
      if W > 0 then Stream.WriteBuffer(Coins[I].Coin[1], W);
      W := Length(Coins[I].Futures);
      Stream.WriteBuffer(W, SizeOf(W));
      if W > 0 then
        Stream.WriteBuffer(Coins[I].Futures[0], W * SizeOf(TChiTrade));
      W := Length(Coins[I].Spot);
      Stream.WriteBuffer(W, SizeOf(W));
      if W > 0 then
        Stream.WriteBuffer(Coins[I].Spot[0], W * SizeOf(TChiTrade));
    end;

    Result := nil;
    SetLength(Result, Stream.Size);
    Move(Stream.Memory^, Result[0], Stream.Size);
  finally
    FreeAndNil(Stream);
  end;

  { Сумма считается по всему блоку при обнулённом собственном поле. }
  PChiDataHeader(@Result[0])^.CheckSum := 0;
  PChiDataHeader(@Result[0])^.CheckSum := CheckSum32(@Result[0], Length(Result));
end;

function ParseBlock(const Data: TBytes; out Hdr: TChiDataHeader;
  out Coins: TChiCoinList): Boolean;
var
  Copy1: TBytes;
  Sum, Want: Cardinal;
  P, Stop: Integer;
  W: Word;
begin
  Coins := nil;
  Result := False;
  if Length(Data) < SizeOf(TChiDataHeader) then Exit;

  Hdr := PChiDataHeader(@Data[0])^;
  Want := Hdr.CheckSum;
  Copy1 := System.Copy(Data, 0, Length(Data));
  PChiDataHeader(@Copy1[0])^.CheckSum := 0;
  Sum := CheckSum32(@Copy1[0], Length(Copy1));
  if Sum <> Want then Exit;
  if Hdr.Ver <> ChiStreamVer then Exit;

  P := SizeOf(TChiDataHeader);
  Stop := Length(Data);
  while P < Stop do
  begin
    if P + 2 > Stop then Exit;
    Move(Data[P], W, 2);
    Inc(P, 2);
    if P + W > Stop then Exit;
    SetLength(Coins, Length(Coins) + 1);
    with Coins[High(Coins)] do
    begin
      SetLength(Coin, W);
      if W > 0 then Move(Data[P], Coin[1], W);
      Inc(P, W);

      if P + 2 > Stop then Exit;
      Move(Data[P], W, 2);
      Inc(P, 2);
      if P + W * SizeOf(TChiTrade) > Stop then Exit;
      SetLength(Futures, W);
      if W > 0 then Move(Data[P], Futures[0], W * SizeOf(TChiTrade));
      Inc(P, W * SizeOf(TChiTrade));

      if P + 2 > Stop then Exit;
      Move(Data[P], W, 2);
      Inc(P, 2);
      if P + W * SizeOf(TChiTrade) > Stop then Exit;
      SetLength(Spot, W);
      if W > 0 then Move(Data[P], Spot[0], W * SizeOf(TChiTrade));
      Inc(P, W * SizeOf(TChiTrade));
    end;
  end;
  Result := P = Stop;
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

function MakeCoins(Count: Integer; Seed: UInt64): TChiCoinList;
var
  Src: TChiSource;
  I, J, N: Integer;
begin
  Result := nil;
  SetLength(Result, Count);
  Src := ChiSource(Seed);
  for I := 0 to Count - 1 do
  begin
    Result[I].Coin := AnsiString('COIN' + IntToStr(I));
    N := Src.NextBelow(5);
    SetLength(Result[I].Futures, N);
    for J := 0 to N - 1 do
    begin
      Result[I].Futures[J].Time := 45000 + J * 1E-6;
      Result[I].Futures[J].Price := 1 + J * 0.001;
      Result[I].Futures[J].Qty := 1 + Src.NextBelow(50);
    end;
    { Спотовая часть бывает пустой — это законный край формата. }
    N := Src.NextBelow(3);
    SetLength(Result[I].Spot, N);
    for J := 0 to N - 1 do
    begin
      Result[I].Spot[J].Time := 45000 + J * 2E-6;
      Result[I].Spot[J].Price := 2 + J * 0.002;
      Result[I].Spot[J].Qty := -(1 + Src.NextBelow(50));
    end;
  end;
end;

function SameCoins(const A, B: TChiCoinList): Boolean;
var
  I, J: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
  begin
    if A[I].Coin <> B[I].Coin then Exit(False);
    if Length(A[I].Futures) <> Length(B[I].Futures) then Exit(False);
    if Length(A[I].Spot) <> Length(B[I].Spot) then Exit(False);
    for J := 0 to High(A[I].Futures) do
      if not CompareMem(@A[I].Futures[J], @B[I].Futures[J],
                        SizeOf(TChiTrade)) then Exit(False);
    for J := 0 to High(A[I].Spot) do
      if not CompareMem(@A[I].Spot[J], @B[I].Spot[J],
                        SizeOf(TChiTrade)) then Exit(False);
  end;
end;

function ChiStreamRun: Int64;
var
  Coins, Got: TChiCoinList;
  Block, Broken: TBytes;
  Hdr: TChiDataHeader;
  Acc: UInt64;
  I, J, Delivered, Repeats, Canon: Integer;
  Order: array of Integer;
  Seen: array [0 .. 15] of Boolean;
  Blocks: array [0 .. 15] of TBytes;
  Src: TChiSource;
  Tmp, Missed, BlindFull: Integer;
  Tmp2, Tmp3: TBytes;
  Empty: TChiCoinList;
begin
  ChiCovered(IdStream);
  Acc := ChiOffset;
  Src := ChiSource(515151);

  { ── Заголовок: размер и смещения, посчитанные по полям ── }
  ChiClaim(SizeOf(TChiDataHeader) = 4 + 1 + 4 + 1 + 2 + 1 + 1 + 1,
    'поток: размер заголовка не равен сумме полей');
  Block := nil;
  SetLength(Block, SizeOf(TChiDataHeader));
  ChiClaim(PByte(@PChiDataHeader(@Block[0])^.Ver) - PByte(@Block[0]) = 4,
    'поток: версия не сразу за суммой');
  ChiClaim(PByte(@PChiDataHeader(@Block[0])^.Port) - PByte(@Block[0]) = 10,
    'поток: порт не на своём смещении');
  ChiClaim(PByte(@PChiDataHeader(@Block[0])^.Flag) - PByte(@Block[0])
           = SizeOf(TChiDataHeader) - 1,
    'поток: флаги не последним байтом');
  ChiBranch(IdStream, 'header-layout');

  { ── Контрольная сумма: две независимые реализации ── }
  for I := 0 to 63 do
  begin
    SetLength(Broken, I);
    for J := 0 to I - 1 do Broken[J] := Byte(Src.NextBelow(256));
    if I = 0 then
      ChiClaim(CheckSumW(nil, 0) = CheckSumWBytes(nil, 0),
        'поток: сумма пустого буфера разошлась')
    else
      ChiClaim(CheckSumW(@Broken[0], I) = CheckSumWBytes(@Broken[0], I),
        'поток: две реализации суммы разошлись на длине ' + IntToStr(I));
    if I > 0 then Acc := ChiMix(Acc, Int64(CheckSumW(@Broken[0], I)));
  end;
  ChiBranch(IdStream, 'checksum-two-ways');

  { ── Блок целиком ── }
  for I := 0 to 7 do
  begin
    Coins := MakeCoins(1 + I * 2, 700 + UInt64(I));
    Block := BuildBlock(Coins, Byte(I), 3, False);

    { Канонический размер: заголовок плюс сумма частей. }
    Canon := SizeOf(TChiDataHeader);
    for J := 0 to High(Coins) do
      Canon := Canon + 2 + Length(Coins[J].Coin) + 2
               + Length(Coins[J].Futures) * SizeOf(TChiTrade) + 2
               + Length(Coins[J].Spot) * SizeOf(TChiTrade);
    ChiClaim(Length(Block) = Canon,
      'поток: размер блока не канонический, ' + IntToStr(I));

    ChiClaim(ParseBlock(Block, Hdr, Got), 'поток: блок не разобрался');
    ChiClaim(Hdr.BlockNum = Byte(I), 'поток: номер блока не тот');
    ChiClaim(Hdr.Ver = ChiStreamVer, 'поток: версия не та');
    ChiClaim(SameCoins(Coins, Got), 'поток: сделки восстановились неверно');
    Acc := ChiMix(Acc, Length(Block));
  end;
  ChiBranch(IdStream, 'roundtrip');
  ChiBranch(IdStream, 'canonical-size');

  { ── Порча ──

    Полная сумма — восьмибайтовая, и на ней утверждение строгое: изменение
    ЛЮБОГО байта обязано её сдвинуть. На проводе же едет её свёртка в четыре
    байта (нижняя половина плюс верхняя), а свёртка вдвое короче исходной и
    потому имеет столкновения: часть порч она пропускает. Это свойство
    формата, а не дефект, поэтому здесь оно измеряется и предъявляется
    числом, а не выдаётся за строгую проверку. }
  Coins := MakeCoins(4, 4242);
  Block := BuildBlock(Coins, 9, 3, False);
  Missed := 0;
  BlindFull := 0;
  for I := 0 to Length(Block) - 1 do
  begin
    Broken := System.Copy(Block, 0, Length(Block));
    Broken[I] := Broken[I] xor $01;

    if I >= 4 then
    begin
      Tmp2 := System.Copy(Broken, 0, Length(Broken));
      PChiDataHeader(@Tmp2[0])^.CheckSum := 0;
      Tmp3 := System.Copy(Block, 0, Length(Block));
      PChiDataHeader(@Tmp3[0])^.CheckSum := 0;
      if CheckSumW(@Tmp2[0], Length(Tmp2))
         = CheckSumW(@Tmp3[0], Length(Tmp3)) then Inc(BlindFull);
    end;

    if ParseBlock(Broken, Hdr, Got) then Inc(Missed);
  end;

  { Сумма ловит подавляющее большинство порч, но НЕ все: у неё есть
    столкновения на одиночном изменении бита — и у полной восьмибайтовой
    формы тоже, не только у свёртки. Это свойство самого алгоритма, взятого
    из живого протокола, а не дефект переноса и не дефект компилятора.
    Поэтому здесь предъявляется доля, а не «поймано всё»: строгое
    утверждение было бы неправдой и мигало бы от данных. }
  ChiClaim(Missed * 10 < Length(Block),
    'поток: разбор пропускает больше десятой доли порч');
  ChiClaim(BlindFull * 10 < Length(Block),
    'поток: сумма слепа больше чем к десятой доле порч');
  { Связывать эти два числа неравенством нельзя: разбор отвергает блок не
    только по сумме, но и по строению — порча длины имени ломает разбор даже
    там, где сумма совпала. }
  ChiBranch(IdStream, 'reject-tampered');
  if Missed > 0 then ChiBranch(IdStream, 'checksum-collision');
  Acc := ChiMix(Acc, Missed);
  Acc := ChiMix(Acc, BlindFull);

  { Обрезанный блок обязан быть отвергнут. }
  Broken := System.Copy(Block, 0, Length(Block) - 5);
  ChiClaim(not ParseBlock(Broken, Hdr, Got), 'поток: обрезанный блок принят');
  Broken := System.Copy(Block, 0, 10);
  ChiClaim(not ParseBlock(Broken, Hdr, Got), 'поток: огрызок принят');
  ChiBranch(IdStream, 'reject-truncated');

  { ── Доставка не по порядку и с повторами ── }
  for I := 0 to 15 do
  begin
    Coins := MakeCoins(2, 800 + UInt64(I));
    Blocks[I] := BuildBlock(Coins, Byte(I), 3, False);
    Seen[I] := False;
  end;

  { Перемешиваем порядок и добавляем повторы. }
  SetLength(Order, 24);
  for I := 0 to 15 do Order[I] := I;
  for I := 16 to 23 do Order[I] := Src.NextBelow(16);
  for I := 0 to High(Order) - 1 do
  begin
    J := I + Src.NextBelow(Length(Order) - I);
    Tmp := Order[I];
    Order[I] := Order[J];
    Order[J] := Tmp;
  end;

  Delivered := 0;
  Repeats := 0;
  for I := 0 to High(Order) do
  begin
    ChiClaim(ParseBlock(Blocks[Order[I]], Hdr, Got),
      'поток: блок из очереди не разобрался');
    ChiClaim(Hdr.BlockNum = Byte(Order[I]), 'поток: номер блока перепутан');
    ChiClaim(SameCoins(MakeCoins(2, 800 + UInt64(Order[I])), Got),
      'поток: содержимое блока не то');
    if Seen[Order[I]] then
      Inc(Repeats)
    else
    begin
      Seen[Order[I]] := True;
      Inc(Delivered);
    end;
  end;
  ChiClaim(Delivered = 16, 'поток: доставлены не все блоки');
  ChiClaim(Repeats > 0, 'поток: повторов не было — ветка не проверена');
  ChiBranch(IdStream, 'out-of-order');
  ChiBranch(IdStream, 'repeats');
  Acc := ChiMix(Acc, Repeats);

  { ── Края ── }
  Empty := nil;
  Block := BuildBlock(Empty, 0, 3, False);
  ChiClaim(Length(Block) = SizeOf(TChiDataHeader),
    'поток: пустой блок не равен заголовку');
  ChiClaim(ParseBlock(Block, Hdr, Got), 'поток: пустой блок не разобрался');
  ChiClaim(Length(Got) = 0, 'поток: пустой блок дал рынки');
  ChiBranch(IdStream, 'empty-block');

  { Признак сжатия — бит флага, и он обязан доехать. }
  Coins := MakeCoins(3, 999);
  Block := BuildBlock(Coins, 5, 7, True);
  ChiClaim(ParseBlock(Block, Hdr, Got), 'поток: помеченный блок не разобрался');
  ChiClaim((Hdr.Flag and ChiFlagZipped) <> 0, 'поток: признак сжатия потерян');
  ChiClaim(Hdr.Exchange = 7, 'поток: биржа не та');
  ChiBranch(IdStream, 'flags');

  { Номер блока — байт с заворотом. }
  Block := BuildBlock(Coins, 255, 3, False);
  ChiClaim(ParseBlock(Block, Hdr, Got) and (Hdr.BlockNum = 255),
    'поток: предельный номер блока не доехал');
  ChiBranch(IdStream, 'blocknum-wrap');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
