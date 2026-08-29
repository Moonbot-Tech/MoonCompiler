unit resident_param;

{ Семейство `param` — передача параметров и возврат значений.

  Договор о том, что и куда кладётся при вызове, не описан в исходнике: он
  зависит от размера типа, от его содержимого, от того, управляемый он или нет,
  от способа передачи и от того, сколько аргументов уже заняли регистры.
  Ошибка здесь не портит арифметику — она подменяет само значение, и заметна
  только на тех размерах и позициях, где правило меняется: запись в один байт
  едет иначе, чем в восемь, девятибайтовая — иначе, чем восьмибайтовая, а
  десятый аргумент — иначе, чем первый.

  Поэтому стадии перебирают именно границы: размеры записей вокруг степеней
  двойки, все четыре способа передачи, длинные списки аргументов, смесь целых
  и вещественных (для них регистры разные), вызов внутри аргумента, запись с
  управляемым полем внутри.

  Проверяется не «то же ли число», а тождество: то, что положили, обязано
  вернуться. Каждая запись несёт свои поля и метку, по которой видно, доехала
  она целиком или частями от соседа. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, resident_core;

implementation

type
  TP1 = record
    A: Byte;
  end;

  TP2 = record
    A, B: Byte;
  end;

  TP3 = record
    A, B, C: Byte;
  end;

  TP4 = record
    A: Cardinal;
  end;

  TP7 = record
    A: Cardinal;
    B, C, D: Byte;
  end;

  TP8 = record
    A: Int64;
  end;

  TP9 = record
    A: Int64;
    B: Byte;
  end;

  TP16 = record
    A, B: Int64;
  end;

  TP17 = record
    A, B: Int64;
    C: Byte;
  end;

  TP24 = record
    A, B, C: Int64;
  end;

  TP32 = record
    A, B, C, D: Int64;
  end;

  { Запись с управляемым полем: копия обязана быть настоящей копией, а не
    вторым именем той же строки. }
  TPManaged = record
    Head: Int64;
    Text: string;
    Tail: Int64;
  end;

function Sum1(V: TP1): Int64;
begin
  Result := V.A;
end;

function Sum2(V: TP2): Int64;
begin
  Result := Int64(V.A) * 2 + V.B;
end;

function Sum3(V: TP3): Int64;
begin
  Result := Int64(V.A) * 4 + Int64(V.B) * 2 + V.C;
end;

function Sum4(V: TP4): Int64;
begin
  Result := V.A;
end;

function Sum7(V: TP7): Int64;
begin
  Result := Int64(V.A) * 8 + Int64(V.B) * 4 + Int64(V.C) * 2 + V.D;
end;

function Sum8(V: TP8): Int64;
begin
  Result := V.A;
end;

function Sum9(V: TP9): Int64;
begin
  Result := V.A * 2 + V.B;
end;

function Sum16(V: TP16): Int64;
begin
  Result := V.A * 2 + V.B;
end;

function Sum17(V: TP17): Int64;
begin
  Result := V.A * 4 + V.B * 2 + V.C;
end;

function Sum24(V: TP24): Int64;
begin
  Result := V.A * 4 + V.B * 2 + V.C;
end;

function Sum32(V: TP32): Int64;
begin
  Result := V.A * 8 + V.B * 4 + V.C * 2 + V.D;
end;

function Make8(Seed: Int64): TP8;
begin
  Result.A := Seed * 7 + 1;
end;

function Make9(Seed: Int64): TP9;
begin
  Result.A := Seed * 7 + 1;
  Result.B := Byte(Seed and $FF);
end;

function Make24(Seed: Int64): TP24;
begin
  Result.A := Seed;
  Result.B := Seed * 2;
  Result.C := Seed * 3;
end;

function Make32(Seed: Int64): TP32;
begin
  Result.A := Seed;
  Result.B := Seed * 2;
  Result.C := Seed * 3;
  Result.D := Seed * 4;
end;

{ Записи всех характерных размеров едут по значению и обязаны доехать. }
procedure StageRecordSizes(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  V1: TP1; V2: TP2; V3: TP3; V4: TP4; V7: TP7; V8: TP8;
  V9: TP9; V16: TP16; V17: TP17; V24: TP24; V32: TP32;
  Base: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Base := Int64(ResidentNext(State) and $FF) + 1;
  Bad := 0;

  V1.A := Byte(Base);
  V2.A := Byte(Base); V2.B := Byte(Base + 1);
  V3.A := Byte(Base); V3.B := Byte(Base + 1); V3.C := Byte(Base + 2);
  V4.A := Cardinal(Base) * 1000;
  V7.A := Cardinal(Base) * 1000; V7.B := Byte(Base); V7.C := Byte(Base + 1); V7.D := Byte(Base + 2);
  V8.A := Base * 1000000;
  V9.A := Base * 1000000; V9.B := Byte(Base);
  V16.A := Base * 11; V16.B := Base * 13;
  V17.A := Base * 11; V17.B := Base * 13; V17.C := Byte(Base);
  V24.A := Base * 11; V24.B := Base * 13; V24.C := Base * 17;
  V32.A := Base * 11; V32.B := Base * 13; V32.C := Base * 17; V32.D := Base * 19;

  if Sum1(V1) <> Int64(V1.A) then Inc(Bad);
  if Sum2(V2) <> Int64(V2.A) * 2 + V2.B then Inc(Bad);
  if Sum3(V3) <> Int64(V3.A) * 4 + Int64(V3.B) * 2 + V3.C then Inc(Bad);
  if Sum4(V4) <> Int64(V4.A) then Inc(Bad);
  if Sum7(V7) <> Int64(V7.A) * 8 + Int64(V7.B) * 4 + Int64(V7.C) * 2 + V7.D then Inc(Bad);
  if Sum8(V8) <> V8.A then Inc(Bad);
  if Sum9(V9) <> V9.A * 2 + V9.B then Inc(Bad);
  if Sum16(V16) <> V16.A * 2 + V16.B then Inc(Bad);
  if Sum17(V17) <> V17.A * 4 + V17.B * 2 + V17.C then Inc(Bad);
  if Sum24(V24) <> V24.A * 4 + V24.B * 2 + V24.C then Inc(Bad);
  if Sum32(V32) <> V32.A * 8 + V32.B * 4 + V32.C * 2 + V32.D then Inc(Bad);

  Carrier.Feed(UInt64(Sum32(V32)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: record passed by value arrived damaged');
end;

{ Возврат записи: приёмник может быть скрытым аргументом, и на границе
  размеров правило меняется. }
procedure StageReturnRecord(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  Seed: Int64;
  R8: TP8; R9: TP9; R24: TP24; R32: TP32;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Seed := Int64(ResidentNext(State) and $FFFF) + 1;
  Bad := 0;

  R8 := Make8(Seed);
  R9 := Make9(Seed);
  R24 := Make24(Seed);
  R32 := Make32(Seed);

  if R8.A <> Seed * 7 + 1 then Inc(Bad);
  if R9.A <> Seed * 7 + 1 then Inc(Bad);
  if R9.B <> Byte(Seed and $FF) then Inc(Bad);
  if (R24.A <> Seed) or (R24.B <> Seed * 2) or (R24.C <> Seed * 3) then Inc(Bad);
  if (R32.A <> Seed) or (R32.B <> Seed * 2) or (R32.C <> Seed * 3) or (R32.D <> Seed * 4) then Inc(Bad);

  { Скрытый приёмник записи живёт только внутри внешнего аргумента. }
  if Sum32(Make32(Seed)) <> Seed * 26 then Inc(Bad);

  Carrier.Feed(UInt64(R32.D));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: returned record arrived damaged');
end;

{ Четыре способа передачи одного значения. }
procedure StageWaysOfPassing(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  Value, Copy_, Ref, Out_: Int64;

  procedure ByValue(V: Int64);
  begin
    V := V * 2;
    Copy_ := V;
  end;

  procedure ByConst(const V: Int64);
  begin
    Copy_ := Copy_ + V;
  end;

  procedure ByVar(var V: Int64);
  begin
    V := V * 3;
  end;

  procedure ByOut(out V: Int64);
  begin
    V := 777;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Value := Int64(ResidentNext(State) and $FFFF) + 1;
  Bad := 0;
  Copy_ := 0;

  { По значению: вызванный правит свою копию, оригинал не трогается. }
  ByValue(Value);
  if Copy_ <> Value * 2 then Inc(Bad);
  if Value = Value * 2 then Inc(Bad);

  ByConst(Value);
  if Copy_ <> Value * 2 + Value then Inc(Bad);

  { По ссылке: правится оригинал. }
  Ref := Value;
  ByVar(Ref);
  if Ref <> Value * 3 then Inc(Bad);

  { Выходной: до входа обнуляется, поэтому прежнее значение не переживает
    вызов — это договор, а не случайность. }
  Out_ := 12345;
  ByOut(Out_);
  if Out_ <> 777 then Inc(Bad);

  Carrier.Feed(UInt64(Copy_));
  Carrier.Feed(UInt64(Ref));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: one of the four ways of passing lost the value');
end;

{ Открытый массив: длина, границы и элементы приезжают отдельно от данных. }
procedure StageOpenArray(Carrier: TResidentCarrier);
var
  State: UInt64;
  Data: TArray<Int64>;
  Fixed: array[0 .. 5] of Int64;
  I, Bad: Integer;
  Sum, Mirror: Int64;

  function Fold(const Values: array of Int64): Int64;
  var
    J: Integer;
  begin
    Result := Int64(Length(Values)) * 1000;
    for J := Low(Values) to High(Values) do
      Result := Result + Values[J] * (J + 1);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  SetLength(Data, 9);
  for I := 0 to High(Data) do
    Data[I] := Int64(ResidentNext(State) and $FFF);
  for I := 0 to High(Fixed) do
    Fixed[I] := Int64(ResidentNext(State) and $FFF);
  Bad := 0;

  Sum := Fold(Data);
  Mirror := Int64(Length(Data)) * 1000;
  for I := 0 to High(Data) do
    Mirror := Mirror + Data[I] * (I + 1);
  if Sum <> Mirror then Inc(Bad);

  Sum := Fold(Fixed);
  Mirror := Int64(Length(Fixed)) * 1000;
  for I := 0 to High(Fixed) do
    Mirror := Mirror + Fixed[I] * (I + 1);
  if Sum <> Mirror then Inc(Bad);

  { Построенный на месте список — тоже открытый массив. }
  if Fold([1, 2, 3]) <> 3000 + 1 * 1 + 2 * 2 + 3 * 3 then Inc(Bad);
  if Fold([]) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: open array arrived with the wrong length or contents');

  Data := nil;
end;

{ Длинный список аргументов: первые едут регистрами, дальние — стеком, и
  граница между ними — самое интересное место. }
procedure StageManyArguments(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  A: array[1 .. 14] of Int64;
  I: Integer;
  Sum, Mirror: Int64;

  function Take14(P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14: Int64): Int64;
  begin
    Result := P1 * 1 + P2 * 2 + P3 * 3 + P4 * 4 + P5 * 5 + P6 * 6 + P7 * 7 +
              P8 * 8 + P9 * 9 + P10 * 10 + P11 * 11 + P12 * 12 + P13 * 13 + P14 * 14;
  end;

  function TakeMixed(P1: Byte; P2: Int64; P3: SmallInt; P4: Cardinal; P5: Int64;
    P6: Word; P7: Int64; P8: ShortInt; P9: Int64; P10: Integer): Int64;
  begin
    Result := Int64(P1) + P2 * 2 + Int64(P3) * 3 + Int64(P4) * 4 + P5 * 5 +
              Int64(P6) * 6 + P7 * 7 + Int64(P8) * 8 + P9 * 9 + Int64(P10) * 10;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  for I := 1 to 14 do
    A[I] := Int64(ResidentNext(State) and $FFF) + I;
  Bad := 0;

  Sum := Take14(A[1], A[2], A[3], A[4], A[5], A[6], A[7],
                A[8], A[9], A[10], A[11], A[12], A[13], A[14]);
  Mirror := 0;
  for I := 1 to 14 do
    Mirror := Mirror + A[I] * I;
  if Sum <> Mirror then Inc(Bad);

  { Узкие типы вперемешку с широкими: каждый обязан расшириться по своим
    правилам, а не по правилам соседа. }
  Sum := TakeMixed(200, 1000, -300, 4000, 5000, 60000, 7000, -80, 9000, -10000);
  Mirror := Int64(200) + 1000 * 2 + Int64(-300) * 3 + Int64(4000) * 4 + Int64(5000) * 5 +
            Int64(60000) * 6 + Int64(7000) * 7 + Int64(-80) * 8 + Int64(9000) * 9 +
            Int64(-10000) * 10;
  if Sum <> Mirror then Inc(Bad);

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: long argument list arrived shuffled');
end;

{ Целые и вещественные едут в разных наборах регистров, и смесь легко
  перепутать. Значения выбраны представимыми точно, поэтому сравнение
  вещественных здесь строгое и законное. }
procedure StageMixedFloat(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  Whole: Int64;
  Frac: Double;

  function Blend(I1: Int64; D1: Double; I2: Int64; D2: Double; I3: Int64;
    D3: Double; I4: Int64; D4: Double): Double;
  begin
    Result := I1 * 1.0 + D1 * 2 + I2 * 3.0 + D2 * 4 + I3 * 5.0 + D3 * 6 +
              I4 * 7.0 + D4 * 8;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Whole := Int64(ResidentNext(State) and $FF) + 1;
  Frac := 0.5;
  Bad := 0;

  if Blend(Whole, Frac, Whole * 2, Frac, Whole * 3, Frac, Whole * 4, Frac) <>
     Whole * 1.0 + Frac * 2 + Whole * 2 * 3.0 + Frac * 4 + Whole * 3 * 5.0 + Frac * 6 +
     Whole * 4 * 7.0 + Frac * 8 then
    Inc(Bad);

  { Половина представима в двоичной дроби точно, поэтому сумма целого и
    половин — тоже точное число. }
  if Blend(2, 0.5, 2, 0.5, 2, 0.5, 2, 0.5) <> 2 + 1 + 6 + 2 + 10 + 3 + 14 + 4 then
    Inc(Bad);

  Carrier.Feed(UInt64(Whole));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: mixed integer and floating arguments got swapped');
end;

{ Вызов внутри аргумента другого вызова: внутренний результат обязан дожить до
  внешнего входа. }
procedure StageNestedCalls(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  Seed: Int64;

  function Twice(V: Int64): Int64;
  begin
    Result := V * 2;
  end;

  function Three(A, B, C: Int64): Int64;
  begin
    Result := A * 100 + B * 10 + C;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Seed := Int64(ResidentNext(State) and $FF) + 1;
  Bad := 0;

  if Three(Twice(Seed), Twice(Twice(Seed)), Twice(Twice(Twice(Seed)))) <>
     Seed * 2 * 100 + Seed * 4 * 10 + Seed * 8 then
    Inc(Bad);

  if Twice(Three(Seed, Twice(Seed), Three(1, 2, 3))) <>
     (Seed * 100 + Seed * 2 * 10 + 123) * 2 then
    Inc(Bad);

  Carrier.Feed(UInt64(Seed));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: nested call result did not reach the outer call');
end;

{ Запись с управляемым полем: копия по значению обязана быть настоящей копией,
  и вызванный не имеет права испортить оригинал. }
procedure StageManagedRecord(Carrier: TResidentCarrier);
var
  State: UInt64;
  Bad: Integer;
  Source: TPManaged;
  Seen: Int64;

  function Consume(V: TPManaged): Int64;
  begin
    V.Text := V.Text + 'tail';
    V.Head := V.Head * 2;
    Result := Int64(Length(V.Text)) * 1000 + V.Head + V.Tail;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Source.Head := Int64(ResidentNext(State) and $FF) + 1;
  Source.Text := 'abcd';
  Source.Tail := Int64(ResidentNext(State) and $FF) + 1;
  Bad := 0;

  Seen := Consume(Source);
  if Seen <> Int64(8) * 1000 + Source.Head * 2 + Source.Tail then Inc(Bad);

  { Оригинал не изменился: у вызванного была своя копия. }
  if Source.Text <> 'abcd' then Inc(Bad);
  if Length(Source.Text) <> 4 then Inc(Bad);

  Carrier.Feed(UInt64(Seen));
  Carrier.FeedWide(Source.Text);
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'param: record with a managed field was shared instead of copied');

  Source.Text := '';
end;

initialization
  ResidentRegisterStage('param-managed-record', @StageManagedRecord);
  ResidentRegisterStage('param-many-arguments', @StageManyArguments);
  ResidentRegisterStage('param-mixed-float', @StageMixedFloat);
  ResidentRegisterStage('param-nested-calls', @StageNestedCalls);
  ResidentRegisterStage('param-open-array', @StageOpenArray);
  ResidentRegisterStage('param-record-sizes', @StageRecordSizes);
  ResidentRegisterStage('param-return-record', @StageReturnRecord);
  ResidentRegisterStage('param-ways-of-passing', @StageWaysOfPassing);

end.
