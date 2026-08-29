unit resident_edge;

{ Семейство `edge` — края машинной арифметики и вставленный код.

  Здесь собрано то, где компилятор чаще всего подменяет написанное более
  дешёвым: сдвиг вместо умножения, условное присваивание вместо ветки,
  развёрнутый хвост вместо цикла, вставленное тело вместо вызова. Каждая такая
  замена законна ровно до тех пор, пока она сохраняет ответ на **всех** входах,
  включая те, что лежат на границе типа.

  Разделение утверждений строгое. То, что язык гарантирует, проверяется
  `Claim` — договор `div`/`mod`, обратимость сужения, сумма арифметической
  прогрессии, число вызовов при коротком замыкании. То, что язык оставляет на
  усмотрение (порядок вычисления операндов, сдвиг шире разрядности), в `Claim`
  не попадает никогда: такие значения только вливаются в дайджест, и судьёй им
  служит сравнение сборок между собой, а не наше мнение о правильном ответе.
  Смешивать эти два вида нельзя — иначе стенд начнёт требовать от компилятора
  того, чего никто не обещал.

  Где сумма зависит от порядка вычисления операндов, проверяется не сумма, а
  её инвариант: сколько раз каждый операнд был вычислен. Это свойство от
  порядка не зависит, значит его можно утверждать. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}{$B-}

interface

uses
  SysUtils, resident_core;

implementation

var
  { Состояние, которое меняют вставляемые тела. Живёт в юните, а не в стадии:
    вставка обязана менять именно его, где бы её ни раскрыли. }
  InlineTicks: Integer;

{ Помечено `inline` намеренно: интерес именно в том, что вставленное тело
  несёт побочный эффект, а место вставки — цикл. }
procedure TickOnce; inline;
begin
  Inc(InlineTicks);
end;

function TickAndTake(Value: Integer): Integer; inline;
begin
  Inc(InlineTicks);
  Result := Value * 2;
end;

{ Сдвиг на величину, известную только в рантайме, против умножения и деления
  на ту же степень двойки. }
procedure StageShiftVariable(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Shift, Bad: Integer;
  Base, Wide: Int64;
  Small: Cardinal;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Base := Int64(ResidentNext(State) and $FFFF) + 1;
  Small := Cardinal(ResidentNext(State) and $FFFF) + 1;
  Bad := 0;

  for I := 0 to 15 do
    begin
      Shift := I;
      Wide := Base shl Shift;
      if Wide <> Base * (Int64(1) shl Shift) then
        Inc(Bad);
      if (Wide shr Shift) <> Base then
        Inc(Bad);
      if (Small shl Shift) <> Small * (Cardinal(1) shl Shift) then
        Inc(Bad);
      Carrier.Feed(UInt64(Wide));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: variable shift disagrees with multiplication by a power of two');
end;

{ Сдвиг шире разрядности типа. Язык ответа не обещает, поэтому здесь нет ни
  одного утверждения — только вливание в дайджест: пусть сборки договорятся
  между собой. }
procedure StageShiftBeyondWidth(Carrier: TResidentCarrier);
var
  State: UInt64;
  I: Integer;
  Wide: Int64;
  Narrow: Cardinal;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Wide := Int64(ResidentNext(State));
  Narrow := Cardinal(ResidentNext(State));

  for I := 60 to 70 do
    begin
      Carrier.Feed(UInt64(Wide shl (I and 63)));
      Carrier.Feed(UInt64(Narrow shl (I and 31)));
    end;
end;

{ Сужение и обратное расширение. Обратимость держится ровно до тех пор, пока
  значение помещается в узкий тип, и это проверяется маской, а не догадкой. }
procedure StageNarrowRoundTrip(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Source: Int64;
  AsInt: Integer;
  AsSmall: SmallInt;
  AsShort: ShortInt;
  AsWord: Word;
  AsByte: Byte;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Bad := 0;

  for I := 1 to 24 do
    begin
      Source := Int64(ResidentNext(State));

      AsInt := Integer(Source);
      AsSmall := SmallInt(Source);
      AsShort := ShortInt(Source);
      AsWord := Word(Source);
      AsByte := Byte(Source);

      { Сужение — это отбрасывание старших бит, а расширение знакового типа
        повторяет старший бит оставшегося. }
      if Cardinal(AsInt) <> Cardinal(Source and $FFFFFFFF) then
        Inc(Bad);
      if Word(AsSmall) <> Word(Source and $FFFF) then
        Inc(Bad);
      if Byte(AsShort) <> Byte(Source and $FF) then
        Inc(Bad);
      if AsWord <> Word(Source and $FFFF) then
        Inc(Bad);
      if AsByte <> Byte(Source and $FF) then
        Inc(Bad);

      { Знаковое узкое, расширенное обратно, обязано совпасть с собой. }
      if Int64(AsSmall) <> Int64(SmallInt(Word(AsSmall))) then
        Inc(Bad);
      if Int64(AsShort) <> Int64(ShortInt(Byte(AsShort))) then
        Inc(Bad);

      Carrier.Feed(UInt64(Cardinal(AsInt)));
      Carrier.Feed(UInt64(Word(AsSmall)));
      Carrier.Feed(UInt64(AsWord));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: narrowing is not a plain drop of the high bits');
end;

{ Сравнения у самой границы беззнакового домена: половина ошибок расширения
  видна только здесь. }
procedure StageUnsignedBoundary(Carrier: TResidentCarrier);
var
  Bad: Integer;
  Top, Near, Zero: Cardinal;
  WideTop: UInt64;
begin
  Bad := 0;
  Top := Cardinal($FFFFFFFF);
  Near := Cardinal($FFFFFFFE);
  Zero := 0;
  WideTop := UInt64($FFFFFFFFFFFFFFFF);

  if not (Top > Near) then
    Inc(Bad);
  if not (Zero < Near) then
    Inc(Bad);
  if Top + 1 <> Zero then
    Inc(Bad);
  if Zero - 1 <> Top then
    Inc(Bad);
  if not (WideTop > UInt64(Top)) then
    Inc(Bad);
  if Int64(Top) <> 4294967295 then
    Inc(Bad);
  if UInt64(Top) + 1 <> UInt64(4294967296) then
    Inc(Bad);

  Carrier.Feed(UInt64(Top));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: unsigned boundary comparison is wrong');
end;

{ Хвост цикла. Развёртка меняет число оборотов на итерацию, и ошибка почти
  всегда сидит не в теле, а в последних оборотах. }
procedure StageUnrollTail(Carrier: TResidentCarrier);
var
  State: UInt64;
  Len, I, Bad: Integer;
  Sum, Want: Int64;
  Data: array[0 .. 31] of Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  for I := 0 to High(Data) do
    Data[I] := Int64(I) + Int64(ResidentNext(State) and 15);
  Bad := 0;

  { Длины подряд: какая-то обязательно попадёт на неудобный остаток. }
  for Len := 1 to 20 do
    begin
      Sum := 0;
      for I := 0 to Len - 1 do
        Sum := Sum + Data[I];

      Want := 0;
      I := 0;
      while I < Len do
        begin
          Want := Want + Data[I];
          Inc(I);
        end;

      if Sum <> Want then
        Inc(Bad);
      Carrier.Feed(UInt64(Sum));
    end;

  { Прогрессия считается и в лоб, и по формуле. }
  Sum := 0;
  for I := 1 to 17 do
    Sum := Sum + I;
  if Sum <> 17 * 18 div 2 then
    Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: loop tail lost or duplicated a lap');
end;

{ Ветка с побочным эффектом не может стать условным присваиванием: эффект
  случается только на одной стороне. }
procedure StageBranchWithEffect(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Taken, Skipped: Integer;
  Value, Mirror: Int64;

  function Mark(Delta: Integer): Int64;
  begin
    Inc(Taken);
    Result := Delta;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Steps := 16 + Integer(ResidentNext(State) and 15);
  Taken := 0;
  Skipped := 0;
  Value := 0;

  for I := 1 to Steps do
    if (I and 3) = 0 then
      Value := Value + Mark(I)
    else
      begin
        Inc(Skipped);
        Value := Value - 1;
      end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 3) = 0 then
      Mirror := Mirror + I
    else
      Mirror := Mirror - 1;

  Carrier.Feed(UInt64(Value));
  Carrier.Feed(UInt64(Cardinal(Taken)));
  Carrier.Feed(UInt64(Cardinal(Skipped)));
  Carrier.Claim(Value = Mirror, 'edge: branch with a side effect computed the wrong total');
  Carrier.Claim(Taken + Skipped = Steps, 'edge: both sides of the branch ran on one lap');
  Carrier.Claim(Taken = Steps div 4, 'edge: side effect happened on the wrong number of laps');
end;

{ Вставляемое тело меняет состояние юнита. Читается оно тут же, в цикле. }
procedure StageInlineEffect(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Steps := 6 + Integer(ResidentNext(State) and 7);

  InlineTicks := 0;
  Live := 0;
  for I := 1 to Steps do
    begin
      Live := Live + Int64(I) * InlineTicks;
      TickOnce;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) * (I - 1);

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(InlineTicks)));
  Carrier.Claim(Live = Mirror, 'edge: state changed by an inlined body read as invariant');
  Carrier.Claim(InlineTicks = Steps, 'edge: inlined body ran the wrong number of times');
end;

{ Две вставки с побочным эффектом в одном выражении. Порядок операндов язык не
  фиксирует, поэтому сумма здесь не предъявляется; предъявляется то, что от
  порядка не зависит — сколько раз выполнилось тело. }
procedure StageInlineTwice(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Total: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Steps := 4 + Integer(ResidentNext(State) and 3);

  InlineTicks := 0;
  Total := 0;
  for I := 1 to Steps do
    Total := Total + TickAndTake(I) + TickAndTake(I + 1);

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(InlineTicks)));
  Carrier.Claim(InlineTicks = Steps * 2, 'edge: inlined body ran a different number of times');

  { Сумма от порядка не зависит: оба слагаемых считаются полностью. }
  Carrier.Claim(Total = Int64(Steps) * (Steps + 1) + Int64(Steps) * (Steps + 3),
    'edge: sum of two inlined calls is wrong');
end;

{ Аргументы с побочными эффектами. Порядок их вычисления не обещан, число
  вычислений — обещано. }
procedure StageArgumentOrder(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Left, Right: Integer;
  Total: Int64;

  function TakeLeft(Value: Integer): Int64;
  begin
    Inc(Left);
    Result := Value;
  end;

  function TakeRight(Value: Integer): Int64;
  begin
    Inc(Right);
    Result := Value * 10;
  end;

  function Join(A, B: Int64): Int64;
  begin
    Result := A + B;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Steps := 6 + Integer(ResidentNext(State) and 7);
  Left := 0;
  Right := 0;
  Total := 0;

  for I := 1 to Steps do
    Total := Total + Join(TakeLeft(I), TakeRight(I));

  Carrier.Feed(UInt64(Total));
  Carrier.Feed(UInt64(Cardinal(Left)));
  Carrier.Feed(UInt64(Cardinal(Right)));
  Carrier.Claim(Left = Steps, 'edge: left argument evaluated the wrong number of times');
  Carrier.Claim(Right = Steps, 'edge: right argument evaluated the wrong number of times');
  Carrier.Claim(Total = Int64(Steps) * (Steps + 1) div 2 * 11,
    'edge: sum over arguments with side effects is wrong');
end;

{ Договор целого деления: остаток берёт знак делимого, и разложение обязано
  сойтись на всех знаках. }
procedure StageDivModContract(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B, Q, R: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 23 + 13);
  Bad := 0;

  for I := 1 to 24 do
    begin
      A := Int64(ResidentNext(State) and $FFFF) - 32768;
      B := Int64(ResidentNext(State) and $FF) + 1;
      if (I and 1) = 1 then
        B := -B;

      Q := A div B;
      R := A mod B;

      if Q * B + R <> A then
        Inc(Bad);
      if (R <> 0) and ((R < 0) <> (A < 0)) then
        Inc(Bad);
      if Abs(R) >= Abs(B) then
        Inc(Bad);

      Carrier.Feed(UInt64(Q));
      Carrier.Feed(UInt64(R));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: div/mod contract broken');
end;

{ Умножение с обёрткой: проверка контроля переполнения здесь выключена, значит
  результат — это младшие биты произведения, и он собирается по частям. }
procedure StageWrapMultiply(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  A, B, Direct, Parts: UInt64;
  Alo, Ahi, Blo, Bhi: UInt64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 29 + 17);
  Bad := 0;

  for I := 1 to 16 do
    begin
      A := ResidentNext(State);
      B := ResidentNext(State);
      Direct := A * B;

      Alo := A and $FFFFFFFF;
      Ahi := A shr 32;
      Blo := B and $FFFFFFFF;
      Bhi := B shr 32;
      Parts := Alo * Blo + ((Alo * Bhi + Ahi * Blo) shl 32);

      if Direct <> Parts then
        Inc(Bad);
      Carrier.Feed(Direct);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: wrapping multiplication disagrees with the part-wise product');
end;

{ Вращение бит: собрано из сдвигов, поэтому обязано быть обратимым. }
procedure StageRotate(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, By, Bad: Integer;
  Value, Turned, Back: UInt64;

  function RotateLeft(V: UInt64; Count: Integer): UInt64;
  begin
    Count := Count and 63;
    if Count = 0 then
      Result := V
    else
      Result := (V shl Count) or (V shr (64 - Count));
  end;

  function RotateRight(V: UInt64; Count: Integer): UInt64;
  begin
    Count := Count and 63;
    if Count = 0 then
      Result := V
    else
      Result := (V shr Count) or (V shl (64 - Count));
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 31 + 19);
  Bad := 0;

  for I := 1 to 16 do
    begin
      Value := ResidentNext(State);
      By := Integer(ResidentNext(State) and 63);

      Turned := RotateLeft(Value, By);
      Back := RotateRight(Turned, By);
      if Back <> Value then
        Inc(Bad);

      { Вращение на полный оборот возвращает то же самое. }
      if RotateLeft(Value, 0) <> Value then
        Inc(Bad);
      if RotateLeft(RotateLeft(Value, 32), 32) <> Value then
        Inc(Bad);

      Carrier.Feed(Turned);
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: bit rotation is not reversible');
end;

{ Цепочка расширений через промежуточные типы: каждый шаг обязан быть
  отдельным, а не схлопнутым в один. }
procedure StageWideningChain(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bad: Integer;
  Source: Int64;
  ViaByte, ViaWord, Direct: Int64;
  B: Byte;
  W: Word;
  S: SmallInt;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 37 + 23);
  Bad := 0;

  for I := 1 to 24 do
    begin
      Source := Int64(ResidentNext(State));

      B := Byte(Source);
      W := Word(B);
      ViaByte := Int64(W);
      if ViaByte <> Int64(Source and $FF) then
        Inc(Bad);

      S := SmallInt(Word(Source));
      ViaWord := Int64(S);
      Direct := Int64(SmallInt(Source and $FFFF));
      if ViaWord <> Direct then
        Inc(Bad);

      { Беззнаковое узкое не имеет права привезти знак. }
      if Int64(Word(Source)) < 0 then
        Inc(Bad);
      if Int64(Byte(Source)) < 0 then
        Inc(Bad);

      Carrier.Feed(UInt64(ViaByte));
      Carrier.Feed(UInt64(ViaWord));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: widening chain collapsed into a single wrong step');
end;

{ Значения на самом краю знаковых типов. Ответы здесь не обещаны языком в
  части переполнения, поэтому утверждается только то, что заведомо верно, а
  остальное вливается в дайджест. }
procedure StageSignedExtremes(Carrier: TResidentCarrier);
var
  Bad: Integer;
  LowInt: Integer;
  LowWide: Int64;
begin
  Bad := 0;
  LowInt := Low(Integer);
  LowWide := Low(Int64);

  if LowInt <> -2147483648 then
    Inc(Bad);
  if LowWide + 1 <> -9223372036854775807 then
    Inc(Bad);
  if High(Integer) <> 2147483647 then
    Inc(Bad);
  if Int64(LowInt) - 1 <> -2147483649 then
    Inc(Bad);
  if not (LowInt < 0) then
    Inc(Bad);
  if Cardinal(LowInt) <> $80000000 then
    Inc(Bad);

  { Обёртка при выключенном контроле переполнения: значение не утверждается,
    только предъявляется сборкам. }
  Carrier.Feed(UInt64(Cardinal(Abs(LowInt))));
  Carrier.Feed(UInt64(LowWide));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'edge: signed extreme value is not what the type promises');
end;

initialization
  ResidentRegisterStage('edge-argument-order', @StageArgumentOrder);
  ResidentRegisterStage('edge-branch-with-effect', @StageBranchWithEffect);
  ResidentRegisterStage('edge-divmod-contract', @StageDivModContract);
  ResidentRegisterStage('edge-inline-effect', @StageInlineEffect);
  ResidentRegisterStage('edge-inline-twice', @StageInlineTwice);
  ResidentRegisterStage('edge-narrow-round-trip', @StageNarrowRoundTrip);
  ResidentRegisterStage('edge-rotate', @StageRotate);
  ResidentRegisterStage('edge-shift-beyond-width', @StageShiftBeyondWidth);
  ResidentRegisterStage('edge-shift-variable', @StageShiftVariable);
  ResidentRegisterStage('edge-signed-extremes', @StageSignedExtremes);
  ResidentRegisterStage('edge-unroll-tail', @StageUnrollTail);
  ResidentRegisterStage('edge-unsigned-boundary', @StageUnsignedBoundary);
  ResidentRegisterStage('edge-widening-chain', @StageWideningChain);
  ResidentRegisterStage('edge-wrap-multiply', @StageWrapMultiply);

end.
