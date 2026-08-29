unit resident_strops;

{ Семейство `strops` — операции над строками.

  Семейство `text` спрашивает про представление: кодировку, ширину символа,
  разделяемый буфер. Здесь спрашивается про действие: поиск подстроки, вырезка,
  вставка, удаление, сравнение. Всё это библиотечные подпрограммы, и компилятор
  вправе подменять их встроенными командами, разворачивать короткие случаи и
  выбрасывать проверки, которые счёл лишними.

  Проверка везде одна: то же действие, выполненное вручную посимвольно.
  Библиотека работает с длиной, счётчиком ссылок и памятью; ручной цикл — с
  отдельными символами. Общего у них ничего, кроме ответа, и ответ обязан
  совпасть — включая вырожденные случаи, где библиотечная подпрограмма чаще
  всего и ошибается: пустая строка, позиция за концом, нулевая длина, поиск
  того, чего нет.

  Строки только из латиницы и цифр: широта символа здесь не предмет, а помеха,
  и её проверяет `text`. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, resident_core;

implementation

function MakeText(var State: UInt64; Len: Integer): string;
var
  I: Integer;
begin
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := Char(Ord('a') + Integer(ResidentNext(State) and 3));
end;

{ Поиск подстроки: библиотечный против побуквенного. }
procedure StagePosition(Carrier: TResidentCarrier);
var
  State: UInt64;
  Text, Needle: string;
  I, J, Bad, ByLib, ByHand: Integer;
  Match: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for I := 1 to 8 do
    begin
      Text := MakeText(State, 12 + Integer(ResidentNext(State) and 7));
      Needle := MakeText(State, 1 + Integer(ResidentNext(State) and 2));

      ByLib := Pos(Needle, Text);

      ByHand := 0;
      for J := 1 to Length(Text) - Length(Needle) + 1 do
        begin
          Match := True;
          for var K := 1 to Length(Needle) do
            if Text[J + K - 1] <> Needle[K] then
              begin
                Match := False;
                Break;
              end;
          if Match then
            begin
              ByHand := J;
              Break;
            end;
        end;

      if ByLib <> ByHand then
        Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(ByLib)));
    end;

  { Вырожденные случаи, на которых библиотека и ошибается. }
  if Pos('', 'abc') <> 0 then Inc(Bad);
  if Pos('abc', '') <> 0 then Inc(Bad);
  if Pos('a', 'a') <> 1 then Inc(Bad);
  if Pos('abcd', 'abc') <> 0 then Inc(Bad);
  if Pos('c', 'abc') <> 3 then Inc(Bad);
  if Pos('ab', 'aab') <> 2 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: library search disagrees with a letter-by-letter scan');
end;

{ Вырезка: библиотечная против посимвольной, включая края и выход за конец. }
procedure StageSlice(Carrier: TResidentCarrier);
var
  State: UInt64;
  Text, ByLib, ByHand: string;
  I, J, Start, Count, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 1 to 10 do
    begin
      Text := MakeText(State, 10 + Integer(ResidentNext(State) and 7));
      Start := 1 + Integer(ResidentNext(State) and 15);
      Count := Integer(ResidentNext(State) and 15);

      ByLib := Copy(Text, Start, Count);

      ByHand := '';
      for J := Start to Start + Count - 1 do
        if (J >= 1) and (J <= Length(Text)) then
          ByHand := ByHand + Text[J];

      if ByLib <> ByHand then
        Inc(Bad);

      Carrier.FeedWide(ByLib);
    end;

  if Copy('abcdef', 1, 0) <> '' then Inc(Bad);
  if Copy('abcdef', 1, 6) <> 'abcdef' then Inc(Bad);
  if Copy('abcdef', 1, 100) <> 'abcdef' then Inc(Bad);
  if Copy('abcdef', 7, 3) <> '' then Inc(Bad);
  if Copy('abcdef', 6, 1) <> 'f' then Inc(Bad);
  if Copy('', 1, 5) <> '' then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: library slice disagrees with a character-by-character one');
end;

{ Вставка и удаление: обе меняют строку на месте, и обе легко сдвигают
  границу на единицу. }
procedure StageInsertDelete(Carrier: TResidentCarrier);
var
  State: UInt64;
  Text, Piece, Live, Mirror: string;
  I, At, Count, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 8 do
    begin
      Text := MakeText(State, 8 + Integer(ResidentNext(State) and 7));
      Piece := MakeText(State, 1 + Integer(ResidentNext(State) and 3));
      At := 1 + Integer(ResidentNext(State) and 7);

      Live := Text;
      Insert(Piece, Live, At);
      Mirror := Copy(Text, 1, At - 1) + Piece + Copy(Text, At, Length(Text));
      if Live <> Mirror then
        Inc(Bad);
      if Length(Live) <> Length(Text) + Length(Piece) then
        Inc(Bad);

      Count := 1 + Integer(ResidentNext(State) and 3);
      Live := Text;
      Delete(Live, At, Count);
      Mirror := Copy(Text, 1, At - 1) + Copy(Text, At + Count, Length(Text));
      if Live <> Mirror then
        Inc(Bad);

      Carrier.FeedWide(Live);
    end;

  { Вставка в начало, в конец и за конец. }
  Live := 'abc';
  Insert('X', Live, 1);
  if Live <> 'Xabc' then Inc(Bad);
  Live := 'abc';
  Insert('X', Live, 4);
  if Live <> 'abcX' then Inc(Bad);
  Live := 'abc';
  Insert('X', Live, 100);
  if Live <> 'abcX' then Inc(Bad);
  Live := 'abc';
  Delete(Live, 1, 0);
  if Live <> 'abc' then Inc(Bad);
  Live := 'abc';
  Delete(Live, 2, 100);
  if Live <> 'a' then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: insert or delete moved the boundary');
end;

{ Сравнение строк: порядок задан кодами символов, и он обязан быть
  согласован — если A меньше B, то B больше A, и оба не равны. }
procedure StageCompare(Carrier: TResidentCarrier);
var
  State: UInt64;
  A, B: string;
  I, J, Bad, Verdict, ByHand: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  for I := 1 to 12 do
    begin
      A := MakeText(State, 4 + Integer(ResidentNext(State) and 3));
      B := MakeText(State, 4 + Integer(ResidentNext(State) and 3));

      if A < B then
        Verdict := -1
      else if A > B then
        Verdict := 1
      else
        Verdict := 0;

      { То же сравнение вручную: первый различающийся символ решает всё, а при
        общем начале решает длина. }
      ByHand := 0;
      for J := 1 to Length(A) do
        begin
          if J > Length(B) then
            begin
              ByHand := 1;
              Break;
            end;
          if A[J] <> B[J] then
            begin
              if A[J] < B[J] then
                ByHand := -1
              else
                ByHand := 1;
              Break;
            end;
        end;
      if (ByHand = 0) and (Length(B) > Length(A)) then
        ByHand := -1;

      if Verdict <> ByHand then
        Inc(Bad);

      { Согласованность: обратное сравнение обязано дать обратный ответ. }
      if (A < B) and not (B > A) then Inc(Bad);
      if (A = B) and ((A < B) or (A > B)) then Inc(Bad);
      if (A = B) <> (CompareStr(A, B) = 0) then Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(Verdict + 1)));
    end;

  if not ('' < 'a') then Inc(Bad);
  if not ('a' < 'ab') then Inc(Bad);
  if not ('ab' < 'b') then Inc(Bad);
  if '' <> '' then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: string ordering is inconsistent');
end;

{ Пустая строка: длина, обращение, склейка, вырезка. }
procedure StageEmpty(Carrier: TResidentCarrier);
var
  Empty, Live: string;
  Bad: Integer;
begin
  Bad := 0;
  Empty := '';

  if Length(Empty) <> 0 then Inc(Bad);
  if Empty <> '' then Inc(Bad);
  if Copy(Empty, 1, 5) <> '' then Inc(Bad);
  if Pos('a', Empty) <> 0 then Inc(Bad);

  Live := Empty + 'abc';
  if Live <> 'abc' then Inc(Bad);
  Live := 'abc' + Empty;
  if Live <> 'abc' then Inc(Bad);
  Live := Empty + Empty;
  if Length(Live) <> 0 then Inc(Bad);

  Live := 'abc';
  Delete(Live, 1, 3);
  if Length(Live) <> 0 then Inc(Bad);
  if Live <> '' then Inc(Bad);

  SetLength(Live, 0);
  if Length(Live) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: empty string does not behave as empty');
end;

{ Сборка строки склейкой и записью по месту: разные механики, один результат
  и одна длина. }
procedure StageBuild(Carrier: TResidentCarrier);
var
  State: UInt64;
  ByConcat, ByPlace, Source: string;
  I, Len, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Len := 16 + Integer(ResidentNext(State) and 15);
  Source := MakeText(State, Len);
  Bad := 0;

  ByConcat := '';
  for I := 1 to Len do
    ByConcat := ByConcat + Source[I];

  SetLength(ByPlace, Len);
  for I := 1 to Len do
    ByPlace[I] := Source[I];

  if ByConcat <> Source then Inc(Bad);
  if ByPlace <> Source then Inc(Bad);
  if Length(ByConcat) <> Len then Inc(Bad);

  { Обратная сборка: та же строка, собранная с конца. }
  ByConcat := '';
  for I := Len downto 1 do
    ByConcat := Source[I] + ByConcat;
  if ByConcat <> Source then Inc(Bad);

  { Удвоение и вырезка половины возвращают исходное. }
  ByConcat := Source + Source;
  if Length(ByConcat) <> Len * 2 then Inc(Bad);
  if Copy(ByConcat, 1, Len) <> Source then Inc(Bad);
  if Copy(ByConcat, Len + 1, Len) <> Source then Inc(Bad);

  Carrier.FeedWide(Source);
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'strops: two ways of building a string disagree');
end;

initialization
  ResidentRegisterStage('strops-build', @StageBuild);
  ResidentRegisterStage('strops-compare', @StageCompare);
  ResidentRegisterStage('strops-empty', @StageEmpty);
  ResidentRegisterStage('strops-insert-delete', @StageInsertDelete);
  ResidentRegisterStage('strops-position', @StagePosition);
  ResidentRegisterStage('strops-slice', @StageSlice);

end.
