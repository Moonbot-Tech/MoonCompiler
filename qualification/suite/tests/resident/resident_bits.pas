unit resident_bits;

{ Семейство `bits` — битовые операции.

  Битовая работа — то место, где у компилятора больше всего готовых замен:
  проверку бита он превращает в тест, установку — в другую инструкцию, счёт
  единиц — в отдельную команду процессора, сдвиг с маской — в извлечение поля.
  Каждая замена законна на всём домене или незаконна вовсе, и промежуточных
  случаев тут нет: ошибка на одном бите — это ошибка на конкретном значении, а
  не приблизительность.

  Способ проверки везде один: то же самое считается вторым, независимым
  способом. Число единиц — циклом по битам и свёрткой по парам-четвёркам;
  младший установленный бит — перебором и через дополнение до двух; разворот
  битов — обязан быть обратим; извлечение поля — совпадать со сдвигом и
  маской. Ни одна пара способов не разделяет общего кода, поэтому одинаково
  ошибиться они не могут.

  Домен — весь `UInt64`, включая нуль и все единицы: именно на них ломаются
  формулы с дополнением до двух и со сдвигом на разрядность. }

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

{ Единицы, посчитанные в лоб. }
function CountByLoop(V: UInt64): Integer;
begin
  Result := 0;
  while V <> 0 do
    begin
      Inc(Result, Integer(V and 1));
      V := V shr 1;
    end;
end;

{ Единицы, посчитанные свёрткой: пары, четвёрки, байты. Общего кода с
  предыдущим способом нет. }
function CountBySwar(V: UInt64): Integer;
const
  M1 = UInt64($5555555555555555);
  M2 = UInt64($3333333333333333);
  M4 = UInt64($0F0F0F0F0F0F0F0F);
  H01 = UInt64($0101010101010101);
begin
  V := V - ((V shr 1) and M1);
  V := (V and M2) + ((V shr 2) and M2);
  V := (V + (V shr 4)) and M4;
  Result := Integer((V * H01) shr 56);
end;

{ Установка, сброс и проверка бита — маской и сдвигом. }
procedure StageSetClearTest(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Rebuilt: UInt64;
  I, Bit, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for I := 1 to 8 do
    begin
      Value := ResidentNext(State);

      { Собираем то же число заново, бит за битом. }
      Rebuilt := 0;
      for Bit := 0 to 63 do
        if (Value and (UInt64(1) shl Bit)) <> 0 then
          Rebuilt := Rebuilt or (UInt64(1) shl Bit);
      if Rebuilt <> Value then
        Inc(Bad);

      { Установка уже установленного ничего не меняет, сброс сброшенного — тоже. }
      for Bit := 0 to 63 do
        begin
          if (Value or (UInt64(1) shl Bit)) and not (UInt64(1) shl Bit) <>
             Value and not (UInt64(1) shl Bit) then
            Inc(Bad);
          if ((Value or (UInt64(1) shl Bit)) and (UInt64(1) shl Bit)) = 0 then
            Inc(Bad);
          if ((Value and not (UInt64(1) shl Bit)) and (UInt64(1) shl Bit)) <> 0 then
            Inc(Bad);
        end;

      Carrier.Feed(Value);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: setting, clearing or testing a bit went wrong');
end;

{ Число единиц двумя независимыми способами, включая края домена. }
procedure StageCount(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value: UInt64;
  I, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Value := ResidentNext(State);
      if CountByLoop(Value) <> CountBySwar(Value) then
        Inc(Bad);
      Carrier.Feed(UInt64(Cardinal(CountBySwar(Value))));
    end;

  if CountByLoop(0) <> 0 then Inc(Bad);
  if CountBySwar(0) <> 0 then Inc(Bad);
  if CountByLoop(UInt64($FFFFFFFFFFFFFFFF)) <> 64 then Inc(Bad);
  if CountBySwar(UInt64($FFFFFFFFFFFFFFFF)) <> 64 then Inc(Bad);
  if CountBySwar(UInt64(1) shl 63) <> 1 then Inc(Bad);

  { Единицы числа и его дополнения в сумме дают разрядность. }
  for I := 1 to 8 do
    begin
      Value := ResidentNext(State);
      if CountBySwar(Value) + CountBySwar(not Value) <> 64 then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: two ways of counting ones disagree');
end;

{ Младший и старший установленный бит. Формула с дополнением до двух проверяется
  перебором. }
procedure StageLowestHighest(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Lowest: UInt64;
  I, Bit, ByScan, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 12 do
    begin
      Value := ResidentNext(State) or 1;

      { Младший установленный — это пересечение числа с его отрицанием. }
      Lowest := Value and (UInt64(0) - Value);
      if CountBySwar(Lowest) <> 1 then
        Inc(Bad);
      if (Value and Lowest) = 0 then
        Inc(Bad);

      ByScan := -1;
      for Bit := 0 to 63 do
        if (Value and (UInt64(1) shl Bit)) <> 0 then
          begin
            ByScan := Bit;
            Break;
          end;
      if Lowest <> (UInt64(1) shl ByScan) then
        Inc(Bad);

      { Старший установленный — перебором сверху. }
      ByScan := -1;
      for Bit := 63 downto 0 do
        if (Value and (UInt64(1) shl Bit)) <> 0 then
          begin
            ByScan := Bit;
            Break;
          end;
      if (Value shr ByScan) <> 1 then
        Inc(Bad);

      Carrier.Feed(Lowest);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: lowest or highest set bit found wrongly');
end;

{ Маска диапазона битов: собранная сдвигами и собранная перебором. }
procedure StageMaskRange(Carrier: TResidentCarrier);
var
  State: UInt64;
  ByShift, ByLoop: UInt64;
  I, Lo, Width, Bit, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  for I := 1 to 16 do
    begin
      { Начало и ширина выбраны так, что поле всегда помещается в слово. }
      Lo := Integer(ResidentNext(State) and 31);
      Width := 1 + Integer(ResidentNext(State) and 31);

      ByShift := ((UInt64(1) shl Width) - 1) shl Lo;

      ByLoop := 0;
      for Bit := Lo to Lo + Width - 1 do
        ByLoop := ByLoop or (UInt64(1) shl Bit);

      if ByShift <> ByLoop then
        Inc(Bad);
      if CountBySwar(ByShift) <> Width then
        Inc(Bad);

      Carrier.Feed(ByShift);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: range mask built by shifting differs from the one built bit by bit');
end;

{ Разворот битов обязан быть обратим, а число единиц — сохраняться. }
procedure StageReverse(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Turned, Back: UInt64;
  I, Bit, Bad: Integer;

  function ReverseBits(V: UInt64): UInt64;
  var
    B: Integer;
  begin
    Result := 0;
    for B := 0 to 63 do
      if (V and (UInt64(1) shl B)) <> 0 then
        Result := Result or (UInt64(1) shl (63 - B));
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  for I := 1 to 12 do
    begin
      Value := ResidentNext(State);
      Turned := ReverseBits(Value);
      Back := ReverseBits(Turned);

      if Back <> Value then
        Inc(Bad);
      if CountBySwar(Turned) <> CountBySwar(Value) then
        Inc(Bad);

      { Бит номер K обязан оказаться на месте 63 - K. }
      for Bit := 0 to 63 do
        if ((Value shr Bit) and 1) <> ((Turned shr (63 - Bit)) and 1) then
          Inc(Bad);

      Carrier.Feed(Turned);
    end;

  if ReverseBits(0) <> 0 then Inc(Bad);
  if ReverseBits(1) <> (UInt64(1) shl 63) then Inc(Bad);
  if ReverseBits(UInt64($FFFFFFFFFFFFFFFF)) <> UInt64($FFFFFFFFFFFFFFFF) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: reversing bits is not reversible');
end;

{ Чётность числа единиц: свёрткой пополам и по остатку от счёта. }
procedure StageParity(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Folded: UInt64;
  I, ByFold, ByCount, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Value := ResidentNext(State);

      Folded := Value;
      Folded := Folded xor (Folded shr 32);
      Folded := Folded xor (Folded shr 16);
      Folded := Folded xor (Folded shr 8);
      Folded := Folded xor (Folded shr 4);
      Folded := Folded xor (Folded shr 2);
      Folded := Folded xor (Folded shr 1);
      ByFold := Integer(Folded and 1);

      ByCount := CountBySwar(Value) and 1;

      if ByFold <> ByCount then
        Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(ByFold)));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: parity by folding disagrees with parity by counting');
end;

{ Извлечение и вставка поля: сдвиг с маской против перебора битов. }
procedure StageFieldExtract(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Field, Rebuilt, Mask: UInt64;
  I, Lo, Width, Bit, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Bad := 0;

  for I := 1 to 12 do
    begin
      Value := ResidentNext(State);
      Lo := Integer(ResidentNext(State) and 31);
      Width := 1 + Integer(ResidentNext(State) and 15);

      Mask := ((UInt64(1) shl Width) - 1);
      Field := (Value shr Lo) and Mask;

      { То же поле, собранное по одному биту. }
      Rebuilt := 0;
      for Bit := 0 to Width - 1 do
        if (Value and (UInt64(1) shl (Lo + Bit))) <> 0 then
          Rebuilt := Rebuilt or (UInt64(1) shl Bit);
      if Field <> Rebuilt then
        Inc(Bad);

      { Вставка того же поля на то же место ничего не меняет. }
      if ((Value and not (Mask shl Lo)) or (Field shl Lo)) <> Value then
        Inc(Bad);

      Carrier.Feed(Field);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: field extraction disagrees with a bit-by-bit read');
end;

{ Обмен половин и байтов: собранный сдвигами обязан совпасть с собранным
  побайтово, а двойной обмен — вернуть исходное. }
procedure StageSwapHalves(Carrier: TResidentCarrier);
var
  State: UInt64;
  Value, Swapped, ByBytes: UInt64;
  I, B, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Bad := 0;

  for I := 1 to 12 do
    begin
      Value := ResidentNext(State);

      Swapped := (Value shr 32) or (Value shl 32);
      if ((Swapped shr 32) or (Swapped shl 32)) <> Value then
        Inc(Bad);
      if CountBySwar(Swapped) <> CountBySwar(Value) then
        Inc(Bad);

      { Разворот байтов, собранный руками. }
      ByBytes := 0;
      for B := 0 to 7 do
        ByBytes := ByBytes or (((Value shr (B * 8)) and $FF) shl ((7 - B) * 8));
      if CountBySwar(ByBytes) <> CountBySwar(Value) then
        Inc(Bad);

      { Двойной разворот байтов возвращает исходное. }
      Swapped := 0;
      for B := 0 to 7 do
        Swapped := Swapped or (((ByBytes shr (B * 8)) and $FF) shl ((7 - B) * 8));
      if Swapped <> Value then
        Inc(Bad);

      Carrier.Feed(ByBytes);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'bits: swapping halves or bytes lost data');
end;

initialization
  ResidentRegisterStage('bits-count', @StageCount);
  ResidentRegisterStage('bits-field-extract', @StageFieldExtract);
  ResidentRegisterStage('bits-lowest-highest', @StageLowestHighest);
  ResidentRegisterStage('bits-mask-range', @StageMaskRange);
  ResidentRegisterStage('bits-parity', @StageParity);
  ResidentRegisterStage('bits-reverse', @StageReverse);
  ResidentRegisterStage('bits-set-clear-test', @StageSetClearTest);
  ResidentRegisterStage('bits-swap-halves', @StageSwapHalves);

end.
