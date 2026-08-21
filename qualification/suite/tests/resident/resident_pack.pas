unit resident_pack;

{ Сжатие и перекодировка — то есть табличные преобразования внутри повторяющихся
  проходов.

  Это семейство заведено прицельно. Ровно в такой форме — подстановка по таблице
  в цикле, вложенном в другой цикл, — нашёлся дефект, из-за которого боевой
  профиль пропускает проход. Значит форма плодотворная, и её надо разрабатывать
  вширь: разные таблицы, разные размеры, разные способы обхода.

  Оракул везде один и тот же и не требует эталона — **обратимость**: сжатое
  разжимается в исходное, закодированное раскодируется в исходное. Плюс к нему
  добавлены известные ответы там, где они есть в спецификациях: строки из
  RFC 4648 для перекодировки в печатный вид.

  Отдельная ценность: сжатие даёт **разную длину выхода** на разных данных,
  поэтому размеры буферов, границы и хвосты всё время новые. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, Generics.Collections, resident_core;

implementation

const
  Base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

type
  { Узел дерева кодирования: либо лист с символом, либо развилка. }
  THuffNode = record
    Weight: Int64;
    Symbol: Integer;
    Left, Right: Integer;
  end;

  TResidentPackPocket = class(TResidentPocket)
  private
    FStream: TBytes;
    FRounds: Int64;
  end;

var
  Base64Back: array[0 .. 255] of ShortInt;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := Length(A) = Length(B);
  if Result and (Length(A) > 0) then
    Result := CompareMem(@A[0], @B[0], Length(A));
end;

{ Данные с перекосом частот: без перекоса сжимать нечего, и проверка вырождается
  в переливание из пустого в порожнее. }
function MakeSkewed(Carrier: TResidentCarrier; Size: Integer): TBytes;
var
  State: UInt64;
  I, Pick: Integer;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 41 + Carrier.Lap)));
  SetLength(Result, Size);
  for I := 0 to Size - 1 do
  begin
    Pick := Integer(ResidentNext(State) mod 100);
    if Pick < 50 then
      Result[I] := Byte(Ord('a'))
    else if Pick < 75 then
      Result[I] := Byte(Ord('b'))
    else if Pick < 88 then
      Result[I] := Byte(Ord('c'))
    else
      Result[I] := Byte(ResidentNext(State) and $FF);
  end;
end;

{ ------------------------------------------------------------ Хаффман ----- }

{ Построение дерева по частотам, таблицы кодов по дереву, кодирование битами и
  раскодирование обходом дерева. Три прохода по данным, каждый со своей
  таблицей. }
procedure BuildHuffman(const Data: TBytes; out Nodes: System.TArray<THuffNode>;
  out Root: Integer; out Codes: System.TArray<string>);
var
  Freq: array[0 .. 255] of Int64;
  I, Count, Best1, Best2, Fresh: Integer;
  Alive: System.TArray<Boolean>;

  procedure Walk(Node: Integer; const Prefix: string);
  begin
    if Nodes[Node].Symbol >= 0 then
    begin
      if Prefix = '' then
        Codes[Nodes[Node].Symbol] := '0'
      else
        Codes[Nodes[Node].Symbol] := Prefix;
      Exit;
    end;
    Walk(Nodes[Node].Left, Prefix + '0');
    Walk(Nodes[Node].Right, Prefix + '1');
  end;

begin
  FillChar(Freq, SizeOf(Freq), 0);
  for I := 0 to High(Data) do
    Inc(Freq[Data[I]]);

  SetLength(Nodes, 0);
  for I := 0 to 255 do
    if Freq[I] > 0 then
    begin
      SetLength(Nodes, Length(Nodes) + 1);
      Nodes[High(Nodes)].Weight := Freq[I];
      Nodes[High(Nodes)].Symbol := I;
      Nodes[High(Nodes)].Left := -1;
      Nodes[High(Nodes)].Right := -1;
    end;

  Count := Length(Nodes);
  SetLength(Alive, Count);
  for I := 0 to Count - 1 do
    Alive[I] := True;

  { Пока не останется один корень: берём два самых лёгких и сливаем. Выбор
    линейным перебором — медленно, зато без сомнений в порядке. }
  while True do
  begin
    Best1 := -1;
    Best2 := -1;
    for I := 0 to High(Nodes) do
      if Alive[I] then
      begin
        if (Best1 < 0) or (Nodes[I].Weight < Nodes[Best1].Weight) then
        begin
          Best2 := Best1;
          Best1 := I;
        end
        else if (Best2 < 0) or (Nodes[I].Weight < Nodes[Best2].Weight) then
          Best2 := I;
      end;
    if Best2 < 0 then
      Break;

    SetLength(Nodes, Length(Nodes) + 1);
    SetLength(Alive, Length(Nodes));
    Fresh := High(Nodes);
    Nodes[Fresh].Weight := Nodes[Best1].Weight + Nodes[Best2].Weight;
    Nodes[Fresh].Symbol := -1;
    Nodes[Fresh].Left := Best1;
    Nodes[Fresh].Right := Best2;
    Alive[Best1] := False;
    Alive[Best2] := False;
    Alive[Fresh] := True;
  end;

  Root := -1;
  for I := 0 to High(Nodes) do
    if Alive[I] then
      Root := I;

  SetLength(Codes, 256);
  if Root >= 0 then
    Walk(Root, '');
end;

{ Кодирование в поток битов, упакованный в байты. }
function HuffEncode(const Data: TBytes; const Codes: System.TArray<string>;
  out BitCount: Integer): TBytes;
var
  I, J, Bit: Integer;
  Code: string;
begin
  BitCount := 0;
  for I := 0 to High(Data) do
    Inc(BitCount, Length(Codes[Data[I]]));

  SetLength(Result, (BitCount + 7) div 8);
  for I := 0 to High(Result) do
    Result[I] := 0;

  Bit := 0;
  for I := 0 to High(Data) do
  begin
    Code := Codes[Data[I]];
    for J := 1 to Length(Code) do
    begin
      if Code[J] = '1' then
        Result[Bit shr 3] := Result[Bit shr 3] or (1 shl (7 - (Bit and 7)));
      Inc(Bit);
    end;
  end;
end;

function HuffDecode(const Packed_: TBytes; BitCount: Integer;
  const Nodes: System.TArray<THuffNode>; Root, Count: Integer): TBytes;
var
  Bit, Node, Taken: Integer;
begin
  SetLength(Result, Count);
  Taken := 0;
  Bit := 0;
  while (Taken < Count) and (Bit <= BitCount) do
  begin
    Node := Root;
    { Один символ — спуск по дереву до листа. }
    while Nodes[Node].Symbol < 0 do
    begin
      if (Packed_[Bit shr 3] and (1 shl (7 - (Bit and 7)))) <> 0 then
        Node := Nodes[Node].Right
      else
        Node := Nodes[Node].Left;
      Inc(Bit);
    end;
    Result[Taken] := Byte(Nodes[Node].Symbol);
    Inc(Taken);
    { Дерево из одного листа: код занимает один бит, но спуска нет. }
    if Nodes[Root].Symbol >= 0 then
      Inc(Bit);
  end;
end;

{ -------------------------------------------------------------- LZ77 ------ }

{ Сжатие ссылками назад: для каждой позиции ищем самое длинное совпадение в
  окне. Поиск перебором — квадратичный, зато честный и без хеш-таблиц. }
function LzPack(const Data: TBytes): TBytes;
const
  Window = 255;
  MaxLen = 255;
var
  Pos_, Best, BestLen, Start_, K, Len: Integer;
  Out_: TBytes;
  Used: Integer;

  procedure Put(B: Byte);
  begin
    if Used >= Length(Out_) then
      SetLength(Out_, Length(Out_) * 2 + 16);
    Out_[Used] := B;
    Inc(Used);
  end;

begin
  SetLength(Out_, Length(Data) * 2 + 16);
  Used := 0;
  Pos_ := 0;
  while Pos_ < Length(Data) do
  begin
    BestLen := 0;
    Best := 0;
    Start_ := Pos_ - Window;
    if Start_ < 0 then
      Start_ := 0;
    for K := Start_ to Pos_ - 1 do
    begin
      Len := 0;
      while (Pos_ + Len < Length(Data)) and (Len < MaxLen) and
            (Data[K + Len] = Data[Pos_ + Len]) do
        Inc(Len);
      if Len > BestLen then
      begin
        BestLen := Len;
        Best := Pos_ - K;
      end;
    end;

    if BestLen >= 3 then
    begin
      Put(1);
      Put(Byte(Best));
      Put(Byte(BestLen));
      Inc(Pos_, BestLen);
    end
    else
    begin
      Put(0);
      Put(Data[Pos_]);
      Inc(Pos_);
    end;
  end;
  SetLength(Out_, Used);
  Result := Out_;
end;

function LzUnpack(const Packed_: TBytes; Expect: Integer): TBytes;
var
  I, Used, Dist, Len, K: Integer;
begin
  SetLength(Result, Expect);
  Used := 0;
  I := 0;
  while (I < Length(Packed_)) and (Used < Expect) do
  begin
    if Packed_[I] = 0 then
    begin
      Result[Used] := Packed_[I + 1];
      Inc(Used);
      Inc(I, 2);
    end
    else
    begin
      Dist := Packed_[I + 1];
      Len := Packed_[I + 2];
      for K := 0 to Len - 1 do
      begin
        Result[Used] := Result[Used - Dist];
        Inc(Used);
      end;
      Inc(I, 3);
    end;
  end;
end;

{ ------------------------------------------------------------ Base64 ------ }

function ToBase64(const Data: TBytes): string;
var
  I, Left: Integer;
  Block: Cardinal;
begin
  Result := '';
  I := 0;
  while I + 2 < Length(Data) do
  begin
    Block := (Cardinal(Data[I]) shl 16) or (Cardinal(Data[I + 1]) shl 8) or
             Cardinal(Data[I + 2]);
    Result := Result + Base64Alphabet[(Block shr 18) + 1] +
                       Base64Alphabet[((Block shr 12) and 63) + 1] +
                       Base64Alphabet[((Block shr 6) and 63) + 1] +
                       Base64Alphabet[(Block and 63) + 1];
    Inc(I, 3);
  end;
  Left := Length(Data) - I;
  if Left = 1 then
  begin
    Block := Cardinal(Data[I]) shl 16;
    Result := Result + Base64Alphabet[(Block shr 18) + 1] +
                       Base64Alphabet[((Block shr 12) and 63) + 1] + '==';
  end
  else if Left = 2 then
  begin
    Block := (Cardinal(Data[I]) shl 16) or (Cardinal(Data[I + 1]) shl 8);
    Result := Result + Base64Alphabet[(Block shr 18) + 1] +
                       Base64Alphabet[((Block shr 12) and 63) + 1] +
                       Base64Alphabet[((Block shr 6) and 63) + 1] + '=';
  end;
end;

function FromBase64(const Text: string): TBytes;
var
  I, Used, Bits, Have: Integer;
  Acc: Cardinal;
  V: ShortInt;
begin
  SetLength(Result, (Length(Text) div 4) * 3);
  Used := 0;
  Acc := 0;
  Have := 0;
  for I := 1 to Length(Text) do
  begin
    if Text[I] = '=' then
      Break;
    V := Base64Back[Byte(Word(Text[I]) and $FF)];
    if V < 0 then
      Continue;
    Acc := (Acc shl 6) or Cardinal(V);
    Inc(Have, 6);
    if Have >= 8 then
    begin
      Bits := Have - 8;
      Result[Used] := Byte((Acc shr Bits) and $FF);
      Inc(Used);
      Have := Bits;
    end;
  end;
  SetLength(Result, Used);
end;

{ ------------------------------------------------------------- стадии ----- }

{ Хаффман: три прохода с тремя разными таблицами — частоты, коды, дерево. }
procedure StageHuffman(Carrier: TResidentCarrier);
var
  Data, Packed_, Back: TBytes;
  Nodes: System.TArray<THuffNode>;
  Codes: System.TArray<string>;
  Root, BitCount, Size, I, Distinct: Integer;
begin
  Size := 512 + (Carrier.Lap mod 9) * 256;
  Data := MakeSkewed(Carrier, Size);

  BuildHuffman(Data, Nodes, Root, Codes);
  Carrier.Claim(Root >= 0, 'huffman: no tree was built');

  { У каждого встреченного символа обязан быть код, у прочих — нет. }
  Distinct := 0;
  for I := 0 to 255 do
    if Codes[I] <> '' then
      Inc(Distinct);
  Carrier.Claim(Distinct > 1, 'huffman: fewer than two distinct symbols');
  Carrier.Feed(UInt64(Cardinal(Distinct)));

  Packed_ := HuffEncode(Data, Codes, BitCount);
  Carrier.Feed(UInt64(Cardinal(BitCount)));
  Carrier.Feed(UInt64(Cardinal(Length(Packed_))));

  { Перекошенные данные обязаны ужаться: иначе кодирование бессмысленно. }
  Carrier.Claim(Length(Packed_) < Length(Data), 'huffman: skewed data did not shrink');

  Back := HuffDecode(Packed_, BitCount, Nodes, Root, Length(Data));
  Carrier.Claim(SameBytes(Back, Data), 'huffman: decode did not restore the data');

  { Ни один код не может быть началом другого — иначе раскодировать нельзя. }
  var Ok := True;
  for I := 0 to 255 do
    if Codes[I] <> '' then
      for var J := 0 to 255 do
        if (J <> I) and (Codes[J] <> '') and
           (System.Copy(Codes[J], 1, Length(Codes[I])) = Codes[I]) then
          Ok := False;
  Carrier.Claim(Ok, 'huffman: one code is a prefix of another');
end;

{ Сжатие ссылками назад: обратимость на данных с повторами и без. }
procedure StageLz(Carrier: TResidentCarrier);
var
  Data, Packed_, Back: TBytes;
  Size, I: Integer;
begin
  Size := 256 + (Carrier.Lap mod 7) * 128;
  Data := MakeSkewed(Carrier, Size);

  Packed_ := LzPack(Data);
  Back := LzUnpack(Packed_, Length(Data));
  Carrier.Claim(SameBytes(Back, Data), 'lz: unpack did not restore the data');
  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  Carrier.Feed(UInt64(Cardinal(Length(Packed_))));

  { Данные из одного повторяющегося байта обязаны ужаться в разы. }
  SetLength(Data, Size);
  for I := 0 to Size - 1 do
    Data[I] := Byte(Ord('z'));
  Packed_ := LzPack(Data);
  Back := LzUnpack(Packed_, Length(Data));
  Carrier.Claim(SameBytes(Back, Data), 'lz: run of one byte did not survive');
  Carrier.Claim(Length(Packed_) * 4 < Length(Data), 'lz: a long run barely shrank');
  Carrier.Feed(UInt64(Cardinal(Length(Packed_))));

  { Данные без единого повтора не обязаны ужиматься, но обязаны уцелеть. }
  SetLength(Data, 256);
  for I := 0 to 255 do
    Data[I] := Byte(I);
  Packed_ := LzPack(Data);
  Back := LzUnpack(Packed_, Length(Data));
  Carrier.Claim(SameBytes(Back, Data), 'lz: incompressible data was damaged');
end;

{ Перекодировка в печатный вид: известные ответы из RFC 4648 и обратимость на
  всех трёх длинах остатка. }
procedure StageBase64(Carrier: TResidentCarrier);
var
  Data, Back: TBytes;
  Text: string;
  Size, I: Integer;

  function TextToBytes(const S: string): TBytes;
  var
    K: Integer;
  begin
    SetLength(Result, Length(S));
    for K := 1 to Length(S) do
      Result[K - 1] := Byte(Word(S[K]) and $FF);
  end;

begin
  { Известные ответы из спецификации. }
  Carrier.Claim(ToBase64(TextToBytes('f')) = 'Zg==', 'base64: vector f');
  Carrier.Claim(ToBase64(TextToBytes('fo')) = 'Zm8=', 'base64: vector fo');
  Carrier.Claim(ToBase64(TextToBytes('foo')) = 'Zm9v', 'base64: vector foo');
  Carrier.Claim(ToBase64(TextToBytes('foob')) = 'Zm9vYg==', 'base64: vector foob');
  Carrier.Claim(ToBase64(TextToBytes('fooba')) = 'Zm9vYmE=', 'base64: vector fooba');
  Carrier.Claim(ToBase64(TextToBytes('foobar')) = 'Zm9vYmFy', 'base64: vector foobar');

  { Обратимость на всех трёх длинах остатка. }
  for I := 0 to 2 do
  begin
    Size := 300 + (Carrier.Lap mod 20) * 3 + I;
    Data := MakeSkewed(Carrier, Size);
    Text := ToBase64(Data);
    Back := FromBase64(Text);
    Carrier.Claim(SameBytes(Back, Data), 'base64: round trip lost the data');
    Carrier.Feed(UInt64(Cardinal(Length(Text))));
    { Длина записи известна точно: четыре знака на каждые три байта. }
    Carrier.Claim(Length(Text) = ((Size + 2) div 3) * 4, 'base64: wrong length');
  end;
end;

{ Три преобразования подряд: сжали, закодировали, раскодировали, разжали.
  Каждое со своей таблицей и своим проходом — а вернуться обязано исходное. }
procedure StageChain(Carrier: TResidentCarrier);
var
  Data, Packed_, Back, Restored: TBytes;
  Text: string;
  Nodes: System.TArray<THuffNode>;
  Codes: System.TArray<string>;
  Root, BitCount, Size: Integer;
begin
  Size := 400 + (Carrier.Lap mod 11) * 200;
  Data := MakeSkewed(Carrier, Size);

  { Сжатие ссылками. }
  Packed_ := LzPack(Data);
  { Кодирование по дереву поверх сжатого. }
  BuildHuffman(Packed_, Nodes, Root, Codes);
  var Bits := HuffEncode(Packed_, Codes, BitCount);
  { Печатный вид поверх битов. }
  Text := ToBase64(Bits);

  Carrier.Feed(UInt64(Cardinal(Length(Data))));
  Carrier.Feed(UInt64(Cardinal(Length(Packed_))));
  Carrier.Feed(UInt64(Cardinal(Length(Bits))));
  Carrier.Feed(UInt64(Cardinal(Length(Text))));

  { И весь путь обратно. }
  Back := FromBase64(Text);
  Carrier.Claim(SameBytes(Back, Bits), 'chain: base64 step lost the data');
  Restored := HuffDecode(Back, BitCount, Nodes, Root, Length(Packed_));
  Carrier.Claim(SameBytes(Restored, Packed_), 'chain: huffman step lost the data');
  Restored := LzUnpack(Restored, Length(Data));
  Carrier.Claim(SameBytes(Restored, Data), 'chain: the whole path lost the data');
end;

{ Поток, растущий между оборотами: сжимается целиком каждый оборот, и
  обратимость обязана держаться на любой длине. }
procedure StageRunningPack(Carrier: TResidentCarrier);
var
  Pocket: TResidentPackPocket;
  Piece, Packed_, Back: TBytes;
  I, Was: Integer;
begin
  Pocket := Carrier.PocketAs<TResidentPackPocket>('pack-running');
  Piece := MakeSkewed(Carrier, 96);
  Was := Length(Pocket.FStream);
  SetLength(Pocket.FStream, Was + Length(Piece));
  for I := 0 to High(Piece) do
    Pocket.FStream[Was + I] := Piece[I];

  Packed_ := LzPack(Pocket.FStream);
  Back := LzUnpack(Packed_, Length(Pocket.FStream));
  Carrier.Claim(SameBytes(Back, Pocket.FStream),
                'pack: growing stream lost data');
  Carrier.Feed(UInt64(Cardinal(Length(Pocket.FStream))));
  Carrier.Feed(UInt64(Cardinal(Length(Packed_))));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  if Length(Pocket.FStream) > 3000 then
    SetLength(Pocket.FStream, 0);
end;

initialization
  for var I := 0 to 255 do
    Base64Back[I] := -1;
  for var I := 1 to Length(Base64Alphabet) do
    Base64Back[Byte(Word(Base64Alphabet[I]) and $FF)] := ShortInt(I - 1);
  ResidentRegisterStage('pack-base64', @StageBase64);
  ResidentRegisterStage('pack-chain', @StageChain);
  ResidentRegisterStage('pack-huffman', @StageHuffman);
  ResidentRegisterStage('pack-lz', @StageLz);
  ResidentRegisterStage('pack-running', @StageRunningPack);

end.
