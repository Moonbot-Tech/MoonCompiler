unit resident_convert;

{ Семейство `convert` — преобразования между типами.

  Преобразование выглядит одним словом, а стоит за ним правило, которое легко
  подменить более простым: округление к ближайшему — не то же, что отбрасывание
  дробной части; отбрасывание — не то же, что округление вниз, и отличаются они
  ровно на отрицательных; половина округляется не «вверх», а к чётному.
  Подмена не видна на удобных числах и вылезает на серединах и на минусах.

  Все вещественные значения здесь представимы в двоичной дроби точно: целые,
  половины и четверти. Поэтому сравнения строгие и законные — никакой
  накопленной погрешности в стадии нет, а любое расхождение означает подмену
  правила, а не потерю точности.

  Текстовые преобразования проверяются возвратом: строка, полученная из числа,
  обязана дать то же число обратно. Разбор формата чисел зависит от настроек
  разделителей, поэтому вещественные через текст здесь не гоняются — это не
  свойство компилятора. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, resident_core;

implementation

{ Целое, проехавшее через вещественное, обязано вернуться собой — пока оно
  помещается в мантиссу без потери. }
procedure StageIntegerFloatRoundTrip(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Source, Back: Int64;
  Bridge: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for I := 1 to 24 do
    begin
      { Домен ограничен сорока восемью битами: двойная точность держит
        пятьдесят три, значит потери разряда здесь заведомо нет. }
      Source := Int64(ResidentNext(State) and $FFFFFFFFFFFF) - Int64($800000000000);
      Bridge := Source;
      Back := Trunc(Bridge);
      if Back <> Source then
        Inc(Bad);
      if Round(Bridge) <> Source then
        Inc(Bad);
      Carrier.Feed(UInt64(Back));
    end;

  { Степени двойки и соседи — там, где мантисса меняет разряд. }
  for I := 0 to 47 do
    begin
      Source := Int64(1) shl I;
      Bridge := Source;
      if Trunc(Bridge) <> Source then
        Inc(Bad);
      Bridge := Source - 1;
      if Trunc(Bridge) <> Source - 1 then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: integer did not survive a trip through floating point');
end;

{ Четыре разных правила на одних и тех же числах. Отличаются они на минусах и
  на серединах — там и проверяются. }
procedure StageRoundingRules(Carrier: TResidentCarrier);
var
  Bad: Integer;
begin
  Bad := 0;

  { Отбрасывание дробной части идёт к нулю с обеих сторон. }
  if Trunc(2.75) <> 2 then Inc(Bad);
  if Trunc(-2.75) <> -2 then Inc(Bad);
  if Trunc(2.25) <> 2 then Inc(Bad);
  if Trunc(-2.25) <> -2 then Inc(Bad);

  { Вниз и вверх — по числовой оси, а не по модулю. }
  if Floor(2.75) <> 2 then Inc(Bad);
  if Floor(-2.75) <> -3 then Inc(Bad);
  if Ceil(2.25) <> 3 then Inc(Bad);
  if Ceil(-2.25) <> -2 then Inc(Bad);

  { На целых все четыре правила обязаны совпасть. }
  if (Trunc(4.0) <> 4) or (Floor(4.0) <> 4) or (Ceil(4.0) <> 4) or (Round(4.0) <> 4) then
    Inc(Bad);
  if (Trunc(-4.0) <> -4) or (Floor(-4.0) <> -4) or (Ceil(-4.0) <> -4) or (Round(-4.0) <> -4) then
    Inc(Bad);

  { Ровная половина округляется к чётному — в обе стороны от нуля. }
  if Round(0.5) <> 0 then Inc(Bad);
  if Round(1.5) <> 2 then Inc(Bad);
  if Round(2.5) <> 2 then Inc(Bad);
  if Round(3.5) <> 4 then Inc(Bad);
  if Round(-0.5) <> 0 then Inc(Bad);
  if Round(-1.5) <> -2 then Inc(Bad);
  if Round(-2.5) <> -2 then Inc(Bad);
  if Round(-3.5) <> -4 then Inc(Bad);

  { А четверти — к ближайшему, без всяких «к чётному». }
  if Round(2.25) <> 2 then Inc(Bad);
  if Round(2.75) <> 3 then Inc(Bad);
  if Round(-2.25) <> -2 then Inc(Bad);
  if Round(-2.75) <> -3 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Feed(UInt64(Cardinal(Round(2.5) * 100 + Trunc(-2.75) * 10 + Floor(-2.75))));
  Carrier.Claim(Bad = 0, 'convert: rounding rule was replaced by a simpler one');
end;

{ Деление вещественных на степень двойки точно, поэтому четверти и половины
  можно складывать и сравнивать строго. }
procedure StageExactFractions(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Whole: Int64;
  Quarter, Sum: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Whole := Int64(ResidentNext(State) and $FFFF);
      Quarter := Whole + 0.25;

      if Quarter * 4 <> Whole * 4 + 1 then
        Inc(Bad);
      if Quarter - Whole <> 0.25 then
        Inc(Bad);
      if Trunc(Quarter) <> Whole then
        Inc(Bad);
      if Round(Quarter) <> Whole then
        Inc(Bad);
      if Ceil(Quarter) <> Whole + 1 then
        Inc(Bad);

      Carrier.Feed(UInt64(Whole));
    end;

  { Четыре четверти дают ровно единицу: в двоичной дроби это точно. }
  Sum := 0;
  for I := 1 to 4 do
    Sum := Sum + 0.25;
  if Sum <> 1.0 then
    Inc(Bad);

  { А восемь восьмых — ровно единицу. }
  Sum := 0;
  for I := 1 to 8 do
    Sum := Sum + 0.125;
  if Sum <> 1.0 then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: exactly representable fractions stopped being exact');
end;

{ Число в строку и обратно. Проверяются края типов — там, где знак и
  разрядность решают. }
procedure StageIntegerText(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Source, Back: Int64;
  Text: string;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Source := Int64(ResidentNext(State));
      Text := IntToStr(Source);
      Back := StrToInt64(Text);
      if Back <> Source then
        Inc(Bad);
      Carrier.FeedWide(Text);
    end;

  if StrToInt64(IntToStr(Low(Int64))) <> Low(Int64) then Inc(Bad);
  if StrToInt64(IntToStr(High(Int64))) <> High(Int64) then Inc(Bad);
  if StrToInt(IntToStr(Low(Integer))) <> Low(Integer) then Inc(Bad);
  if StrToInt(IntToStr(High(Integer))) <> High(Integer) then Inc(Bad);
  if IntToStr(0) <> '0' then Inc(Bad);
  if IntToStr(-1) <> '-1' then Inc(Bad);

  { Беззнаковое, не влезающее в знаковое, обязано печататься полностью. }
  if UIntToStr(Cardinal($FFFFFFFF)) <> '4294967295' then Inc(Bad);
  if IntToStr(Int64(Cardinal($FFFFFFFF))) <> '4294967295' then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: number did not survive the trip through text');
end;

{ Шестнадцатеричная запись: ширина, регистр и разбор обратно. }
procedure StageHexText(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Source, Back: Int64;
  Text: string;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Source := Int64(ResidentNext(State) and $FFFFFFFF);
      Text := IntToHex(Source, 8);
      if Length(Text) <> 8 then
        Inc(Bad);
      Back := StrToInt64('$' + Text);
      if Back <> Source then
        Inc(Bad);
      Carrier.FeedWide(Text);
    end;

  if IntToHex(Int64(0), 4) <> '0000' then Inc(Bad);
  if IntToHex(Int64(255), 2) <> 'FF' then Inc(Bad);
  if IntToHex(Int64(255), 4) <> '00FF' then Inc(Bad);
  if StrToInt64('$FF') <> 255 then Inc(Bad);
  if StrToInt64('$7FFFFFFFFFFFFFFF') <> High(Int64) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: hexadecimal text lost width or value');
end;

{ Символ и его код. Домен широкий, поэтому проверяются края и то, что
  преобразование обратимо. }
procedure StageCharCode(Carrier: TResidentCarrier);
var
  I, Bad: Integer;
  Ch: Char;
begin
  Bad := 0;

  for I := 0 to 255 do
    begin
      Ch := Char(I);
      if Ord(Ch) <> I then
        Inc(Bad);
    end;

  { Единица кодирования шире байта, и старший разряд обязан сохраняться. }
  if Ord(Char($0410)) <> $0410 then Inc(Bad);
  if Ord(Char($FFFF)) <> $FFFF then Inc(Bad);
  if Ord(#0) <> 0 then Inc(Bad);
  if Char(65) <> 'A' then Inc(Bad);
  if Ord('A') <> 65 then Inc(Bad);
  if Ord('z') - Ord('a') <> 25 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Ord(Char($0410)))));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: character and its code disagree');
end;

{ Логическое значение и его порядковый номер. }
procedure StageBooleanOrdinal(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Flag: Boolean;
  Value: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  if Ord(False) <> 0 then Inc(Bad);
  if Ord(True) <> 1 then Inc(Bad);
  if not (False < True) then Inc(Bad);

  for I := 1 to 16 do
    begin
      Value := Integer(ResidentNext(State) and $FF);
      Flag := Value > 128;

      if Ord(Flag) <> Ord(Value > 128) then
        Inc(Bad);
      if Flag <> (Value > 128) then
        Inc(Bad);
      if (Ord(Flag) <> 0) <> Flag then
        Inc(Bad);
      if Ord(not Flag) <> 1 - Ord(Flag) then
        Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(Ord(Flag))));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: boolean and its ordinal disagree');
end;

{ Вещественное в целое там, где дробная часть есть всегда: правило видно
  только на знаке. }
procedure StageTruncationSign(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Whole: Int64;
  Value: Double;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Whole := Int64(ResidentNext(State) and $FFFF) + 1;

      Value := Whole + 0.5;
      if Trunc(Value) <> Whole then Inc(Bad);
      if Floor(Value) <> Whole then Inc(Bad);
      if Ceil(Value) <> Whole + 1 then Inc(Bad);

      Value := -(Whole + 0.5);
      if Trunc(Value) <> -Whole then Inc(Bad);
      if Floor(Value) <> -Whole - 1 then Inc(Bad);
      if Ceil(Value) <> -Whole then Inc(Bad);

      { Отбрасывание и округление вниз расходятся ровно на отрицательных
        дробных — и ни на чём другом. }
      if Trunc(Value) = Floor(Value) then Inc(Bad);

      Carrier.Feed(UInt64(Whole));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'convert: truncation and flooring were mixed up on negatives');
end;

initialization
  ResidentRegisterStage('convert-boolean-ordinal', @StageBooleanOrdinal);
  ResidentRegisterStage('convert-char-code', @StageCharCode);
  ResidentRegisterStage('convert-exact-fractions', @StageExactFractions);
  ResidentRegisterStage('convert-hex-text', @StageHexText);
  ResidentRegisterStage('convert-integer-float', @StageIntegerFloatRoundTrip);
  ResidentRegisterStage('convert-integer-text', @StageIntegerText);
  ResidentRegisterStage('convert-rounding-rules', @StageRoundingRules);
  ResidentRegisterStage('convert-truncation-sign', @StageTruncationSign);

end.
