unit resident_overflow;

{ Семейство `overflow` — арифметика, вышедшая за края типа.

  Контроль переполнения в боевом профиле выключен, и это не небрежность, а
  договор: без него арифметика становится модульной — результат равен
  математическому, взятому по модулю разрядности типа. Модульная арифметика
  ничем не хуже обычной, пока её правила соблюдаются точно; беда начинается,
  когда компилятор считает промежуточное значение в более широком регистре и
  забывает усечь, или наоборот — усекает раньше времени.

  Проверяется тем, что модульность задаёт однозначно: узкий результат обязан
  совпасть с тем же вычислением в широком типе, усечённым по разрядности. Для
  самого широкого типа сравнивать не с чем, поэтому там проверяются тождества,
  которые обязаны держаться при любой обёртке: прибавление и вычитание одного и
  того же возвращают исходное, умножение на единицу ничего не меняет, а
  знаковая и беззнаковая суммы совпадают побитово.

  Деления здесь нет: единственное его переполнение — наименьшее значение,
  делённое на минус единицу, и процессор отвечает на это ловушкой, а не
  числом. }

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

{ Сложение и вычитание в узких типах против того же в широком с усечением. }
procedure StageAddSubtract(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A8, B8, R8: Byte;
  A16, B16, R16: Word;
  A32, B32, R32: Cardinal;
  S8, T8: ShortInt;
  S16, T16: SmallInt;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A8 := Byte(ResidentNext(State));
      B8 := Byte(ResidentNext(State));
      R8 := A8 + B8;
      if R8 <> Byte((Integer(A8) + Integer(B8)) and $FF) then Inc(Bad);
      R8 := A8 - B8;
      if R8 <> Byte((Integer(A8) - Integer(B8)) and $FF) then Inc(Bad);

      A16 := Word(ResidentNext(State));
      B16 := Word(ResidentNext(State));
      R16 := A16 + B16;
      if R16 <> Word((Integer(A16) + Integer(B16)) and $FFFF) then Inc(Bad);
      R16 := A16 - B16;
      if R16 <> Word((Integer(A16) - Integer(B16)) and $FFFF) then Inc(Bad);

      A32 := Cardinal(ResidentNext(State));
      B32 := Cardinal(ResidentNext(State));
      R32 := A32 + B32;
      if R32 <> Cardinal((Int64(A32) + Int64(B32)) and $FFFFFFFF) then Inc(Bad);
      R32 := A32 - B32;
      if R32 <> Cardinal((Int64(A32) - Int64(B32)) and $FFFFFFFF) then Inc(Bad);

      { Знаковые узкие: усечение то же, а читается со знаком. }
      S8 := ShortInt(ResidentNext(State));
      T8 := ShortInt(ResidentNext(State));
      if ShortInt(S8 + T8) <> ShortInt(Byte((Integer(S8) + Integer(T8)) and $FF)) then Inc(Bad);

      S16 := SmallInt(ResidentNext(State));
      T16 := SmallInt(ResidentNext(State));
      if SmallInt(S16 + T16) <> SmallInt(Word((Integer(S16) + Integer(T16)) and $FFFF)) then Inc(Bad);

      Carrier.Feed(UInt64(R32));
    end;

  { Края: обёртка через нуль в обе стороны. }
  if Byte(255) + Byte(1) <> 256 then Inc(Bad);
  if Byte(Byte(255) + Byte(1)) <> 0 then Inc(Bad);
  if Byte(Byte(0) - Byte(1)) <> 255 then Inc(Bad);
  if Word(Word(65535) + Word(1)) <> 0 then Inc(Bad);
  A32 := High(Cardinal);
  B32 := 1;
  if Cardinal(A32 + B32) <> 0 then Inc(Bad);
  A32 := 0;
  if Cardinal(A32 - B32) <> High(Cardinal) then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'overflow: narrow addition disagrees with the wide one truncated');
end;

{ Умножение: та же проверка, но переполнение наступает раньше. }
procedure StageMultiply(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A8, B8: Byte;
  A16, B16: Word;
  A32, B32: Cardinal;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A8 := Byte(ResidentNext(State));
      B8 := Byte(ResidentNext(State));
      if Byte(A8 * B8) <> Byte((Integer(A8) * Integer(B8)) and $FF) then Inc(Bad);

      A16 := Word(ResidentNext(State));
      B16 := Word(ResidentNext(State));
      if Word(A16 * B16) <> Word((Integer(A16) * Integer(B16)) and $FFFF) then Inc(Bad);

      A32 := Cardinal(ResidentNext(State));
      B32 := Cardinal(ResidentNext(State));
      if Cardinal(A32 * B32) <> Cardinal((Int64(A32) * Int64(B32)) and $FFFFFFFF) then Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(A32 * B32)));
    end;

  if Byte(Byte(16) * Byte(16)) <> 0 then Inc(Bad);
  if Word(Word(256) * Word(256)) <> 0 then Inc(Bad);
  A32 := $10000;
  B32 := $10000;
  if Cardinal(A32 * B32) <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'overflow: narrow multiplication disagrees with the wide one truncated');
end;

{ Самый широкий тип: сравнивать не с чем, зато держатся тождества. }
procedure StageWidest(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B: Int64;
  U, V: UInt64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A := Int64(ResidentNext(State));
      B := Int64(ResidentNext(State));
      U := UInt64(A);
      V := UInt64(B);

      { Прибавили и отняли — вернулись. }
      if (A + B) - B <> A then Inc(Bad);
      if (A - B) + B <> A then Inc(Bad);

      { Умножение на единицу и на ноль. }
      if A * 1 <> A then Inc(Bad);
      if A * 0 <> 0 then Inc(Bad);

      { Знаковая и беззнаковая арифметика совпадают побитово. }
      if UInt64(A + B) <> U + V then Inc(Bad);
      if UInt64(A - B) <> U - V then Inc(Bad);
      if UInt64(A * B) <> U * V then Inc(Bad);

      { Удвоение — это сложение с собой и сдвиг влево. }
      if A * 2 <> A + A then Inc(Bad);
      if UInt64(A * 2) <> U shl 1 then Inc(Bad);

      Carrier.Feed(UInt64(A + B));
    end;

  { Обёртка у самого края. Слагаемые непрозрачны намеренно: та же проверка
    константами компилятором сворачивается, а Delphi её вовсе не принимает —
    переполнение в константном выражении он считает ошибкой (E2099). Что
    делает с ней наш компилятор, записано отдельно (Devil-0064); здесь
    проверяется обёртка при счёте, а не при сборке. }
  A := High(Int64);
  B := 1;
  if A + B <> Low(Int64) then Inc(Bad);
  A := Low(Int64);
  if A - B <> High(Int64) then Inc(Bad);
  U := High(UInt64);
  V := 1;
  if U + V <> 0 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'overflow: identities of modular arithmetic broken in the widest type');
end;

{ Приращение и уменьшение на единицу у самой границы. }
procedure StageIncDec(Carrier: TResidentCarrier);
var
  Bad: Integer;
  B: Byte;
  W: Word;
  C: Cardinal;
  S: ShortInt;
  M: SmallInt;
  I: Integer;
begin
  Bad := 0;

  B := 255;
  Inc(B);
  if B <> 0 then Inc(Bad);
  Dec(B);
  if B <> 255 then Inc(Bad);

  W := 65535;
  Inc(W);
  if W <> 0 then Inc(Bad);
  Dec(W);
  if W <> 65535 then Inc(Bad);

  C := $FFFFFFFF;
  Inc(C);
  if C <> 0 then Inc(Bad);
  Dec(C);
  if C <> $FFFFFFFF then Inc(Bad);

  S := 127;
  Inc(S);
  if S <> -128 then Inc(Bad);
  Dec(S);
  if S <> 127 then Inc(Bad);

  M := 32767;
  Inc(M);
  if M <> -32768 then Inc(Bad);
  Dec(M);
  if M <> 32767 then Inc(Bad);

  I := High(Integer);
  Inc(I);
  if I <> Low(Integer) then Inc(Bad);
  Dec(I);
  if I <> High(Integer) then Inc(Bad);

  { Приращение на много сразу — та же обёртка. }
  B := 250;
  Inc(B, 10);
  if B <> 4 then Inc(Bad);
  W := 65530;
  Inc(W, 10);
  if W <> 4 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(B)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'overflow: increment at the boundary did not wrap');
end;

{ Накопление в узком типе: сумма обязана обернуться ровно столько раз,
  сколько выходила за край. }
procedure StageNarrowAccumulator(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Bad: Integer;
  Narrow: Byte;
  Wide: Integer;
  Step: Byte;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;
  Steps := 40 + Integer(ResidentNext(State) and 31);
  Step := Byte(ResidentNext(State) and $3F) + 1;

  Narrow := 0;
  Wide := 0;
  for I := 1 to Steps do
    begin
      Narrow := Narrow + Step;
      Wide := Wide + Step;
      if Narrow <> Byte(Wide and $FF) then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Narrow)));
  Carrier.Feed(UInt64(Cardinal(Wide)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Narrow = Byte(Wide and $FF), 'overflow: narrow accumulator drifted from the wide one');
  Carrier.Claim(Bad = 0, 'overflow: narrow accumulator wrapped at the wrong lap');
end;

{ Смешанные ширины в одном выражении: расширение идёт до самого широкого
  операнда, и усекается только при записи в приёмник. }
procedure StageMixedWidths(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  B: Byte;
  W: Word;
  C: Cardinal;
  Wide: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Bad := 0;

  for I := 1 to 16 do
    begin
      B := Byte(ResidentNext(State));
      W := Word(ResidentNext(State));
      C := Cardinal(ResidentNext(State));

      { Промежуточное значение шире всех операндов и не усекается по дороге. }
      Wide := Int64(B) * Int64(W) * Int64(C);
      if Wide <> (Int64(B) * W) * C then Inc(Bad);

      { А присваивание в узкий приёмник усекает. }
      if Byte(Int64(B) + Int64(W)) <> Byte((Integer(B) + Integer(W)) and $FF) then Inc(Bad);
      if Word(Int64(W) + Int64(C)) <> Word((Int64(W) + Int64(C)) and $FFFF) then Inc(Bad);

      Carrier.Feed(UInt64(Wide));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'overflow: mixed-width expression truncated too early');
end;

initialization
  ResidentRegisterStage('overflow-add-subtract', @StageAddSubtract);
  ResidentRegisterStage('overflow-inc-dec', @StageIncDec);
  ResidentRegisterStage('overflow-mixed-widths', @StageMixedWidths);
  ResidentRegisterStage('overflow-multiply', @StageMultiply);
  ResidentRegisterStage('overflow-narrow-accumulator', @StageNarrowAccumulator);
  ResidentRegisterStage('overflow-widest', @StageWidest);

end.
