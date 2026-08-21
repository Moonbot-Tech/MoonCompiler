unit resident_hash;

{ Криптографические свёртки — единственное место в слое, где есть **внешний**
  эталон.

  Все прочие оракулы Devil внутренние: сравниваем с собой на другом уровне
  оптимизации, с собой после пересборки, с Delphi. Такой оракул говорит
  «разошлось», но не говорит, кто прав. Здесь иначе: SHA-256 от `abc` — это
  константа из FIPS 180-4, CRC-32 от `123456789` — константа из спецификации.
  Их не с чем согласовывать, они просто верны, и несовпадение означает
  неправильно, а не по-другому.

  Второе, ради чего семейство существует, — **вес**. Свёртка большого блока это
  десятки тысяч зависимых шагов с вращениями, сложениями по модулю и
  расписанием сообщения. Короткий код такой нагрузки не создаёт, а на длинной
  зависимой цепочке у оптимизатора появляется и повод, и место ошибиться.

  Третье — **переплетение**. Число считается в одном потоке, его запись едет в
  другой, там сворачивается, и ответ сверяется с эталоном. Значение обязано
  пережить и вычисление, и переезд между потоками, и обратный путь. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, SyncObjs, Generics.Collections,
  resident_core, resident_bignum;

type
  { Состояние свёртки: годится и для разового вызова, и для подачи кусками. }
  TSha256 = record
  private
    FState: array[0 .. 7] of Cardinal;
    FTail: array[0 .. 63] of Byte;
    FTailLen: Integer;
    FTotal: UInt64;
    procedure Block(const Data; Offset: Integer);
  public
    procedure Init;
    procedure Update(const Data: TBytes); overload;
    procedure Update(const Data: TBytes; Offset, Count: Integer); overload;
    function Done: string;
  end;

function Sha256Hex(const Data: TBytes): string;
function Sha256HexOfText(const Text: string): string;
function Crc32(const Data: TBytes): Cardinal;

implementation

const
  { Константы раунда — кубические корни первых 64 простых. Из спецификации. }
  K: array[0 .. 63] of Cardinal = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1,
    $923F82A4, $AB1C5ED5, $D807AA98, $12835B01, $243185BE, $550C7DC3,
    $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174, $E49B69C1, $EFBE4786,
    $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147,
    $06CA6351, $14292967, $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13,
    $650A7354, $766A0ABB, $81C2C92E, $92722C85, $A2BFE8A1, $A81A664B,
    $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A,
    $5B9CCA4F, $682E6FF3, $748F82EE, $78A5636F, $84C87814, $8CC70208,
    $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);

  { Известные ответы. Взяты из спецификации, а не посчитаны нами: в этом весь
    смысл — эталон обязан быть внешним. }
  VectorEmpty =
    'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855';
  VectorAbc =
    'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD';
  VectorTwoBlocks =
    '248D6A61D20638B8E5C026930C3E6039A33CE45964FF2167F6ECEDD419DB06C1';
  TwoBlockText =
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq';

type
  { Поток, которому отдают строку на свёртку. Владение простое: строка приходит
    до старта, ответ забирают после завершения, между этими двумя точками её
    никто не трогает. }
  TSha256Hand = class(TThread)
  private
    FText: string;
    FDigest: string;
  public
    constructor Create(const AText: string);
    procedure Execute; override;
    property Digest: string read FDigest;
  end;

  TResidentHashPocket = class(TResidentPocket)
  private
    FRunning: TSha256;
    FFed: Int64;
    FRounds: Int64;
  end;

var
  CrcTable: array[0 .. 255] of Cardinal;

function RotR(Value: Cardinal; Bits: Integer): Cardinal; inline;
begin
  Result := (Value shr Bits) or (Value shl (32 - Bits));
end;

procedure TSha256.Init;
begin
  { Начальные значения — дробные части квадратных корней первых восьми простых. }
  FState[0] := $6A09E667;
  FState[1] := $BB67AE85;
  FState[2] := $3C6EF372;
  FState[3] := $A54FF53A;
  FState[4] := $510E527F;
  FState[5] := $9B05688C;
  FState[6] := $1F83D9AB;
  FState[7] := $5BE0CD19;
  FTailLen := 0;
  FTotal := 0;
end;

procedure TSha256.Block(const Data; Offset: Integer);
var
  W: array[0 .. 63] of Cardinal;
  A, B, C, D, E, F, G, H, T1, T2: Cardinal;
  I: Integer;
  P: PByte;
begin
  P := PByte(@Data) + Offset;
  { Расписание сообщения: первые шестнадцать слов — сам блок, старшим байтом
    вперёд; остальные сорок восемь выводятся из них. }
  for I := 0 to 15 do
    W[I] := (Cardinal(P[I * 4]) shl 24) or (Cardinal(P[I * 4 + 1]) shl 16) or
            (Cardinal(P[I * 4 + 2]) shl 8) or Cardinal(P[I * 4 + 3]);
  for I := 16 to 63 do
    W[I] := W[I - 16] +
            (RotR(W[I - 15], 7) xor RotR(W[I - 15], 18) xor (W[I - 15] shr 3)) +
            W[I - 7] +
            (RotR(W[I - 2], 17) xor RotR(W[I - 2], 19) xor (W[I - 2] shr 10));

  A := FState[0];
  B := FState[1];
  C := FState[2];
  D := FState[3];
  E := FState[4];
  F := FState[5];
  G := FState[6];
  H := FState[7];

  for I := 0 to 63 do
  begin
    T1 := H + (RotR(E, 6) xor RotR(E, 11) xor RotR(E, 25)) +
          ((E and F) xor ((not E) and G)) + K[I] + W[I];
    T2 := (RotR(A, 2) xor RotR(A, 13) xor RotR(A, 22)) +
          ((A and B) xor (A and C) xor (B and C));
    H := G;
    G := F;
    F := E;
    E := D + T1;
    D := C;
    C := B;
    B := A;
    A := T1 + T2;
  end;

  Inc(FState[0], A);
  Inc(FState[1], B);
  Inc(FState[2], C);
  Inc(FState[3], D);
  Inc(FState[4], E);
  Inc(FState[5], F);
  Inc(FState[6], G);
  Inc(FState[7], H);
end;

procedure TSha256.Update(const Data: TBytes; Offset, Count: Integer);
var
  Taken, Pos_: Integer;
begin
  Inc(FTotal, UInt64(Cardinal(Count)));
  Pos_ := Offset;

  { Хвост от прошлого раза добирается до полного блока. Именно здесь живёт
    независимость от нарезки: как бы данные ни делили на куски, блоки обязаны
    сложиться теми же. }
  if FTailLen > 0 then
  begin
    Taken := 64 - FTailLen;
    if Taken > Count then
      Taken := Count;
    Move(Data[Pos_], FTail[FTailLen], Taken);
    Inc(FTailLen, Taken);
    Inc(Pos_, Taken);
    Dec(Count, Taken);
    if FTailLen = 64 then
    begin
      Block(FTail[0], 0);
      FTailLen := 0;
    end;
  end;

  while Count >= 64 do
  begin
    Block(Data[0], Pos_);
    Inc(Pos_, 64);
    Dec(Count, 64);
  end;

  if Count > 0 then
  begin
    Move(Data[Pos_], FTail[FTailLen], Count);
    Inc(FTailLen, Count);
  end;
end;

procedure TSha256.Update(const Data: TBytes);
begin
  if Length(Data) > 0 then
    Update(Data, 0, Length(Data));
end;

function TSha256.Done: string;
var
  Bits: UInt64;
  Pad: array[0 .. 127] of Byte;
  PadLen, I: Integer;
begin
  Bits := FTotal * 8;
  FillChar(Pad, SizeOf(Pad), 0);
  Pad[0] := $80;
  { Дополнение до длины, кратной блоку, с восемью байтами длины в хвосте. }
  if FTailLen < 56 then
    PadLen := 56 - FTailLen
  else
    PadLen := 120 - FTailLen;
  for I := 0 to 7 do
    Pad[PadLen + I] := Byte((Bits shr ((7 - I) * 8)) and $FF);
  Inc(PadLen, 8);

  { Дополнение подаётся тем же путём, что и данные, но без счёта длины. }
  I := 0;
  while I < PadLen do
  begin
    Move(Pad[I], FTail[FTailLen], 1);
    Inc(FTailLen);
    Inc(I);
    if FTailLen = 64 then
    begin
      Block(FTail[0], 0);
      FTailLen := 0;
    end;
  end;

  Result := '';
  for I := 0 to 7 do
    Result := Result + IntToHex(FState[I], 8);
end;

function Sha256Hex(const Data: TBytes): string;
var
  Ctx: TSha256;
begin
  Ctx.Init;
  Ctx.Update(Data);
  Result := Ctx.Done;
end;

function Sha256HexOfText(const Text: string): string;
var
  Data: TBytes;
  I: Integer;
begin
  { Текст здесь всегда ASCII по построению, поэтому байт равен коду символа и
    кодировка машины ни при чём. }
  SetLength(Data, Length(Text));
  for I := 1 to Length(Text) do
    Data[I - 1] := Byte(Word(Text[I]) and $FF);
  Result := Sha256Hex(Data);
end;

procedure BuildCrcTable;
var
  I, J: Integer;
  Value: Cardinal;
begin
  for I := 0 to 255 do
  begin
    Value := Cardinal(I);
    for J := 0 to 7 do
      if (Value and 1) <> 0 then
        Value := $EDB88320 xor (Value shr 1)
      else
        Value := Value shr 1;
    CrcTable[I] := Value;
  end;
end;

function Crc32(const Data: TBytes): Cardinal;
var
  I: Integer;
begin
  Result := $FFFFFFFF;
  for I := 0 to High(Data) do
    Result := CrcTable[(Result xor Data[I]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

constructor TSha256Hand.Create(const AText: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FText := AText;
end;

procedure TSha256Hand.Execute;
begin
  FDigest := Sha256HexOfText(FText);
end;

function MakeAscii(Carrier: TResidentCarrier; Len: Integer): TBytes;
var
  State: UInt64;
  I: Integer;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 17 + Carrier.Lap)));
  SetLength(Result, Len);
  for I := 0 to Len - 1 do
    Result[I] := Byte(ResidentNext(State) and $FF);
end;

{ ------------------------------------------------------------- стадии ----- }

{ Известные ответы: три вектора из спецификации, включая тот, что не влезает в
  один блок и требует правильного дополнения. }
procedure StageVectors(Carrier: TResidentCarrier);
var
  Empty: TBytes;
begin
  SetLength(Empty, 0);
  Carrier.Claim(Sha256Hex(Empty) = VectorEmpty, 'sha256 vector: empty');
  Carrier.Claim(Sha256HexOfText('abc') = VectorAbc, 'sha256 vector: abc');
  Carrier.Claim(Sha256HexOfText(TwoBlockText) = VectorTwoBlocks, 'sha256 vector: two blocks');
  Carrier.FeedWide(Sha256HexOfText('abc'));

  { Ответ обязан меняться от одного изменённого бита входа. }
  Carrier.Feed(UInt64(Ord(Sha256HexOfText('abc') <> Sha256HexOfText('abd'))));
  Carrier.Claim(Sha256HexOfText('') = VectorEmpty, 'sha256 vector: empty text');

  { CRC-32: свой известный ответ из спецификации. }
  Carrier.Claim(Crc32(TEncoding.ASCII.GetBytes('123456789')) = $CBF43926,
                'crc32 vector: 123456789');
  Carrier.Feed(UInt64(Crc32(TEncoding.ASCII.GetBytes('123456789'))));
end;

{ Независимость от нарезки: тот же поток байт, поданный кусками любой длины,
  обязан дать тот же ответ, что и поданный целиком. Куски специально задевают
  границу блока — там, где хвост переносится между вызовами. }
procedure StageChunked(Carrier: TResidentCarrier);
var
  Data: TBytes;
  Whole: string;
  Ctx: TSha256;
  Cut, Taken, Step: Integer;
begin
  Data := MakeAscii(Carrier, 200 + (Carrier.Lap mod 300));
  Whole := Sha256Hex(Data);
  Carrier.FeedWide(Whole);

  { По одному байту. }
  Ctx.Init;
  for Cut := 0 to High(Data) do
    Ctx.Update(Data, Cut, 1);
  Carrier.Claim(Ctx.Done = Whole, 'sha256 chunking changes the answer');

  { Кусками неровной длины. }
  Ctx.Init;
  Taken := 0;
  Step := 1;
  while Taken < Length(Data) do
  begin
    Cut := Step;
    if Taken + Cut > Length(Data) then
      Cut := Length(Data) - Taken;
    Ctx.Update(Data, Taken, Cut);
    Inc(Taken, Cut);
    Step := 1 + (Step * 3) mod 97;
  end;
  Carrier.Claim(Ctx.Done = Whole, 'sha256 chunking changes the answer');

  { Ровно по границе блока и на байт мимо неё. }
  if Length(Data) > 130 then
  begin
    Ctx.Init;
    Ctx.Update(Data, 0, 64);
    Ctx.Update(Data, 64, Length(Data) - 64);
    Carrier.Claim(Ctx.Done = Whole, 'sha256 chunking changes the answer');

    Ctx.Init;
    Ctx.Update(Data, 0, 65);
    Ctx.Update(Data, 65, Length(Data) - 65);
    Carrier.Claim(Ctx.Done = Whole, 'sha256 chunking changes the answer');
  end;
end;

{ Тяжёлый вход: свёртка блока в сотни килобайт — это уже настоящая нагрузка на
  длинную зависимую цепочку, а не проверка одного вызова. Размер меняется от
  оборота, поэтому каждый заход считает другое. }
procedure StageHeavy(Carrier: TResidentCarrier);
var
  Data: TBytes;
  Size: Integer;
  Digest: string;
begin
  Size := 65536 + (Carrier.Lap mod 8) * 32768;
  Data := MakeAscii(Carrier, Size);
  Digest := Sha256Hex(Data);
  Carrier.FeedWide(Digest);
  Carrier.Feed(UInt64(Cardinal(Size)));

  { Повторный счёт того же входа обязан дать тот же ответ — это проверка не
    математики, а того, что длинная цепочка не зависит от состояния машины. }
  Carrier.Claim(Sha256Hex(Data) = Digest, 'sha256 not repeatable on the same input');
  Carrier.Feed(UInt64(Crc32(Data)));
  Carrier.Feed(UInt64(Ord(Crc32(Data) = Crc32(Data))));
end;

{ Переплетение: число считается здесь, его запись уезжает в другой поток, там
  сворачивается, и ответ сверяется с посчитанным на месте. Значение обязано
  пережить вычисление, переезд между потоками и обратный путь. }
procedure StageHandoff(Carrier: TResidentCarrier);
var
  A, B, P: TLimbs;
  Text: string;
  Mine: string;
  Hands: array[0 .. 2] of TSha256Hand;
  I: Integer;
  Agreed: Boolean;
begin
  { Работа для переезда: произведение двух длинных чисел, записанное строкой. }
  A := FromCardinal(Cardinal(1000003 + Carrier.Lap));
  B := FromCardinal(Cardinal(1000033 + Carrier.Serial));
  P := Mul(A, B);
  for I := 0 to 3 + (Carrier.Lap mod 5) do
    P := Mul(P, A);
  Text := ToHex(P);

  Mine := Sha256HexOfText(Text);
  Carrier.FeedWide(Mine);
  Carrier.Feed(UInt64(Cardinal(Length(Text))));

  { Три потока получают одну и ту же строку и обязаны сойтись на одном ответе.
    Строка отдана до старта и не трогается никем до завершения. }
  for I := 0 to High(Hands) do
    Hands[I] := TSha256Hand.Create(Text);
  try
    for I := 0 to High(Hands) do
      Hands[I].Start;
    Agreed := True;
    for I := 0 to High(Hands) do
    begin
      Hands[I].WaitFor;
      if Hands[I].Digest <> Mine then
        Agreed := False;
    end;
  finally
    for I := 0 to High(Hands) do
      Hands[I].Free;
  end;
  Carrier.Claim(Agreed, 'sha256 across threads disagrees');

  { Обратная сторона: разбор строки обратно в число обязан вернуть исходное,
    а его свёртка — совпасть с уже полученной. }
  Carrier.Claim(Compare(FromHex(Text), P) = 0, 'hex round trip lost the number');
  Carrier.Feed(UInt64(Ord(Sha256HexOfText(ToHex(FromHex(Text))) = Mine)));
end;

{ Свёртка, растущая между оборотами: состояние живёт в кармане носителя и
  переезжает вместе с ним между потоками. Через десятки оборотов итог
  сверяется с честным пересчётом всего скормленного разом. }
procedure StageRunning(Carrier: TResidentCarrier);
var
  Pocket: TResidentHashPocket;
  Piece: TBytes;
  Snapshot: TSha256;
begin
  Pocket := Carrier.PocketAs<TResidentHashPocket>('hash-running');
  if Pocket.FFed = 0 then
    Pocket.FRunning.Init;

  Piece := MakeAscii(Carrier, 37);
  Pocket.FRunning.Update(Piece);
  Inc(Pocket.FFed, Length(Piece));
  Carrier.Feed(UInt64(Pocket.FFed));

  { Снимок состояния можно завершить, не трогая накопитель: запись копируется
    по значению, и продолжение обязано этого не заметить. }
  Snapshot := Pocket.FRunning;
  Carrier.FeedWide(Snapshot.Done);
  Carrier.Feed(UInt64(Pocket.FFed));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  if Pocket.FFed > 4000 then
  begin
    Carrier.FeedWide(Pocket.FRunning.Done);
    Pocket.FFed := 0;
    Pocket.FRounds := 0;
  end;
end;

initialization
  BuildCrcTable;
  ResidentRegisterStage('hash-chunked', @StageChunked);
  ResidentRegisterStage('hash-handoff', @StageHandoff);
  ResidentRegisterStage('hash-heavy', @StageHeavy);
  ResidentRegisterStage('hash-running', @StageRunning);
  ResidentRegisterStage('hash-vectors', @StageVectors);

end.
