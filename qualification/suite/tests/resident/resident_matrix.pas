unit resident_matrix;

{ Семейство `matrix` — вложенные циклы и индексная арифметика.

  Двумерный обход — любимая мишень оптимизатора: он переставляет циклы местами,
  разбивает их на блоки, заменяет умножение индекса на прибавление шага,
  разворачивает внутренний. Каждое из превращений опирается на утверждение
  «порядок обхода не влияет на ответ» — и оно верно ровно до тех пор, пока
  адрес элемента считается правильно. Ошибка в индексной арифметике не портит
  все элементы сразу: она сдвигает часть, и итог остаётся правдоподобным.

  Поэтому здесь проверяется не сумма (её легко получить и по сдвинутым
  адресам), а тождества, которые сдвиг рушит: транспонирование дважды — это
  исходная матрица; сумма по строкам равна сумме по столбцам; умножение матриц
  в трёх порядках циклов даёт одно и то же; блочный обход — то же, что
  сплошной; линейный индекс — то же, что пара.

  Размеры намеренно не квадратные и не степени двойки: у квадрата ошибка
  перестановки индексов не видна вовсе, а на степени двойки не видна ошибка
  разбиения на блоки. }

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

const
  Rows = 6;
  Cols = 7;
  Mid = 5;

type
  TMatrix = array[0 .. Rows - 1, 0 .. Cols - 1] of Int64;
  TTransposed = array[0 .. Cols - 1, 0 .. Rows - 1] of Int64;
  TLeft = array[0 .. Rows - 1, 0 .. Mid - 1] of Int64;
  TRight = array[0 .. Mid - 1, 0 .. Cols - 1] of Int64;
  TProduct = array[0 .. Rows - 1, 0 .. Cols - 1] of Int64;

procedure FillMatrix(var M: TMatrix; var State: UInt64);
var
  R, C: Integer;
begin
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      M[R, C] := Int64(ResidentNext(State) and $FFF) - 2048;
end;

{ Транспонирование дважды возвращает исходную матрицу. Перепутанные индексы
  этого тождества не переживают. }
procedure StageTranspose(Carrier: TResidentCarrier);
var
  State: UInt64;
  Source, Back: TMatrix;
  Flipped: TTransposed;
  R, C, Bad: Integer;
  Trace: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  FillMatrix(Source, State);
  Bad := 0;

  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      Flipped[C, R] := Source[R, C];

  for C := 0 to Cols - 1 do
    for R := 0 to Rows - 1 do
      Back[R, C] := Flipped[C, R];

  Trace := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      begin
        if Back[R, C] <> Source[R, C] then
          Inc(Bad);
        Trace := Trace + Source[R, C] * (R * Cols + C + 1);
      end;

  Carrier.Feed(UInt64(Trace));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'matrix: transposing twice did not restore the matrix');
end;

{ Сумма по строкам равна сумме по столбцам равна сумме по линейному индексу.
  Любой сдвиг адреса рушит хотя бы одно из равенств. }
procedure StageRowColumnSums(Carrier: TResidentCarrier);
var
  State: UInt64;
  M: TMatrix;
  R, C, I: Integer;
  ByRows, ByCols, ByLinear: Int64;
  RowSum, ColSum: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  FillMatrix(M, State);

  ByRows := 0;
  for R := 0 to Rows - 1 do
    begin
      RowSum := 0;
      for C := 0 to Cols - 1 do
        RowSum := RowSum + M[R, C];
      ByRows := ByRows + RowSum;
    end;

  ByCols := 0;
  for C := 0 to Cols - 1 do
    begin
      ColSum := 0;
      for R := 0 to Rows - 1 do
        ColSum := ColSum + M[R, C];
      ByCols := ByCols + ColSum;
    end;

  ByLinear := 0;
  for I := 0 to Rows * Cols - 1 do
    ByLinear := ByLinear + M[I div Cols, I mod Cols];

  Carrier.Feed(UInt64(ByRows));
  Carrier.Claim(ByRows = ByCols, 'matrix: row walk and column walk disagree');
  Carrier.Claim(ByRows = ByLinear, 'matrix: linear index disagrees with the index pair');
end;

{ Умножение матриц тремя порядками циклов. Порядок влияет на то, как ложатся
  обращения к памяти, но не на ответ. }
procedure StageMultiplyOrders(Carrier: TResidentCarrier);
var
  State: UInt64;
  A: TLeft;
  B: TRight;
  Pijk, Pikj, Pjik: TProduct;
  I, J, K, Bad: Integer;
  Total: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  for I := 0 to Rows - 1 do
    for K := 0 to Mid - 1 do
      A[I, K] := Int64(ResidentNext(State) and $FF) - 128;
  for K := 0 to Mid - 1 do
    for J := 0 to Cols - 1 do
      B[K, J] := Int64(ResidentNext(State) and $FF) - 128;
  Bad := 0;

  for I := 0 to Rows - 1 do
    for J := 0 to Cols - 1 do
      begin
        Pijk[I, J] := 0;
        Pikj[I, J] := 0;
        Pjik[I, J] := 0;
      end;

  for I := 0 to Rows - 1 do
    for J := 0 to Cols - 1 do
      for K := 0 to Mid - 1 do
        Pijk[I, J] := Pijk[I, J] + A[I, K] * B[K, J];

  for I := 0 to Rows - 1 do
    for K := 0 to Mid - 1 do
      for J := 0 to Cols - 1 do
        Pikj[I, J] := Pikj[I, J] + A[I, K] * B[K, J];

  for J := 0 to Cols - 1 do
    for I := 0 to Rows - 1 do
      for K := 0 to Mid - 1 do
        Pjik[I, J] := Pjik[I, J] + A[I, K] * B[K, J];

  Total := 0;
  for I := 0 to Rows - 1 do
    for J := 0 to Cols - 1 do
      begin
        if (Pijk[I, J] <> Pikj[I, J]) or (Pijk[I, J] <> Pjik[I, J]) then
          Inc(Bad);
        Total := Total + Pijk[I, J];
      end;

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'matrix: three loop orders gave three different products');
end;

{ Блочный обход против сплошного. Размеры не делятся на размер блока нацело —
  хвост обязан обойтись правильно. }
procedure StageBlocked(Carrier: TResidentCarrier);
var
  State: UInt64;
  M: TMatrix;
  R, C, BR, BC, Bad: Integer;
  Plain, Blocked: Int64;
  Seen: array[0 .. Rows - 1, 0 .. Cols - 1] of Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  FillMatrix(M, State);
  Bad := 0;

  Plain := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      begin
        Plain := Plain + M[R, C] * (R + 1) - M[R, C] * C;
        Seen[R, C] := 0;
      end;

  Blocked := 0;
  BR := 0;
  while BR < Rows do
    begin
      BC := 0;
      while BC < Cols do
        begin
          for R := BR to BR + 3 do
            if R < Rows then
              for C := BC to BC + 3 do
                if C < Cols then
                  begin
                    Blocked := Blocked + M[R, C] * (R + 1) - M[R, C] * C;
                    Inc(Seen[R, C]);
                  end;
          Inc(BC, 4);
        end;
      Inc(BR, 4);
    end;

  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      if Seen[R, C] <> 1 then
        Inc(Bad);

  Carrier.Feed(UInt64(Plain));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Plain = Blocked, 'matrix: blocked walk disagrees with the plain one');
  Carrier.Claim(Bad = 0, 'matrix: blocked walk visited a cell twice or missed it');
end;

{ Диагонали: главная считается по совпадению индексов, побочная — по их
  сумме. Обе обязаны совпасть с прямым перебором. }
procedure StageDiagonals(Carrier: TResidentCarrier);
var
  State: UInt64;
  M: TMatrix;
  R, C, I, Bad: Integer;
  Main, Anti, MainDirect, AntiDirect: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  FillMatrix(M, State);
  Bad := 0;

  Main := 0;
  Anti := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      begin
        if R = C then
          Main := Main + M[R, C];
        if R + C = Rows - 1 then
          Anti := Anti + M[R, C];
      end;

  MainDirect := 0;
  for I := 0 to Rows - 1 do
    if I < Cols then
      MainDirect := MainDirect + M[I, I];

  AntiDirect := 0;
  for I := 0 to Rows - 1 do
    if (Rows - 1 - I) < Cols then
      AntiDirect := AntiDirect + M[I, Rows - 1 - I];

  if Main <> MainDirect then Inc(Bad);
  if Anti <> AntiDirect then Inc(Bad);

  Carrier.Feed(UInt64(Main));
  Carrier.Feed(UInt64(Anti));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'matrix: diagonal by condition disagrees with diagonal by index');
end;

{ Обход с шагом: строка читается через шаг, столбец — через шаг длиной в
  строку. Замена умножения на прибавление шага — обычная оптимизация, и
  проверяется, что она не сбилась. }
procedure StageStrides(Carrier: TResidentCarrier);
var
  State: UInt64;
  Flat: array[0 .. Rows * Cols - 1] of Int64;
  I, R, C, Bad: Integer;
  ByStride, ByIndex: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  for I := 0 to High(Flat) do
    Flat[I] := Int64(ResidentNext(State) and $FFF);
  Bad := 0;

  { По строкам: шаг единица, начало — номер строки на длину строки. }
  ByStride := 0;
  for R := 0 to Rows - 1 do
    begin
      var Offset: Integer := R * Cols;
      for C := 0 to Cols - 1 do
        begin
          ByStride := ByStride + Flat[Offset] * (C + 1);
          Inc(Offset);
        end;
    end;

  ByIndex := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      ByIndex := ByIndex + Flat[R * Cols + C] * (C + 1);

  if ByStride <> ByIndex then Inc(Bad);

  { По столбцам: шаг — длина строки. }
  ByStride := 0;
  for C := 0 to Cols - 1 do
    begin
      var Offset: Integer := C;
      for R := 0 to Rows - 1 do
        begin
          ByStride := ByStride + Flat[Offset] * (R + 1);
          Inc(Offset, Cols);
        end;
    end;

  ByIndex := 0;
  for C := 0 to Cols - 1 do
    for R := 0 to Rows - 1 do
      ByIndex := ByIndex + Flat[R * Cols + C] * (R + 1);

  if ByStride <> ByIndex then Inc(Bad);

  Carrier.Feed(UInt64(ByIndex));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'matrix: stepping by stride disagrees with computing the index');
end;

{ Обход в обратную сторону: развёртка и смена направления не имеют права
  сдвинуть границы. }
procedure StageReversedWalk(Carrier: TResidentCarrier);
var
  State: UInt64;
  M: TMatrix;
  R, C, Bad: Integer;
  Forward_, Backward: Int64;
  Visits: array[0 .. Rows - 1, 0 .. Cols - 1] of Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  FillMatrix(M, State);
  Bad := 0;

  Forward_ := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      begin
        Forward_ := Forward_ + M[R, C] * (R * Cols + C + 1);
        Visits[R, C] := 0;
      end;

  Backward := 0;
  for R := Rows - 1 downto 0 do
    for C := Cols - 1 downto 0 do
      begin
        Backward := Backward + M[R, C] * (R * Cols + C + 1);
        Inc(Visits[R, C]);
      end;

  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      if Visits[R, C] <> 1 then
        Inc(Bad);

  Carrier.Feed(UInt64(Forward_));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Forward_ = Backward, 'matrix: reversed walk gave a different sum');
  Carrier.Claim(Bad = 0, 'matrix: reversed walk missed a cell or visited it twice');
end;

initialization
  ResidentRegisterStage('matrix-blocked', @StageBlocked);
  ResidentRegisterStage('matrix-diagonals', @StageDiagonals);
  ResidentRegisterStage('matrix-multiply-orders', @StageMultiplyOrders);
  ResidentRegisterStage('matrix-reversed-walk', @StageReversedWalk);
  ResidentRegisterStage('matrix-row-column-sums', @StageRowColumnSums);
  ResidentRegisterStage('matrix-strides', @StageStrides);
  ResidentRegisterStage('matrix-transpose', @StageTranspose);

end.
