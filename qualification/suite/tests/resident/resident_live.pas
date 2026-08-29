unit resident_live;

{ Семейство `live` — живучесть значений и давление на регистры.

  Регистров у машины конечное число, а живых значений в выражении может быть
  сколько угодно. Когда их больше, чем регистров, часть уезжает на стек и
  возвращается обратно, и вот на этой развозке ошибаются: значение сохранили не
  туда, вернули не то, не сохранили вовсе, потому что решили, что дальше оно не
  понадобится. Ошибка тем вероятнее, чем длиннее промежуток между записью и
  чтением и чем больше поперёк него всего происходит.

  Отсюда устройство стадий: значение заводится, потом между ним и его чтением
  ставится препятствие — вызов, ветвление, цикл, обработчик исключения,
  вложенная процедура, — и только после этого оно предъявляется. Препятствия
  подобраны по типу того, что заставляет компилятор освобождать регистры:
  чужой вызов не обязан сохранять всё, раскрутка стека проходит мимо обычного
  эпилога, вложенная процедура добирается до кадра родителя.

  Ответ всегда считается дважды: один раз россыпью отдельных переменных, второй
  — тем же счётом по массиву, где никакого давления нет, потому что всё лежит в
  памяти по индексу. Обе формы описывают одну арифметику. }

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
  ELiveSignal = class(Exception);

var
  { Вызов в чужой юнит компилятору непрозрачен, значит перед ним придётся
    развезти живые значения по местам. }
  LiveNoise: Int64;

procedure Disturb(Value: Int64);
begin
  LiveNoise := LiveNoise xor (Value * 3 + 1);
end;

{ Двадцать четыре живых значения сразу, и каждое нужно в конце. }
procedure StageManyValues(Carrier: TResidentCarrier);
var
  State, Save: UInt64;
  A0, A1, A2, A3, A4, A5, A6, A7: Int64;
  B0, B1, B2, B3, B4, B5, B6, B7: Int64;
  C0, C1, C2, C3, C4, C5, C6, C7: Int64;
  Spread, Packed_: Int64;
  Cells: array[0 .. 23] of Int64;
  I: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Save := State;

  A0 := Int64(ResidentNext(State) and $FFFF); A1 := Int64(ResidentNext(State) and $FFFF);
  A2 := Int64(ResidentNext(State) and $FFFF); A3 := Int64(ResidentNext(State) and $FFFF);
  A4 := Int64(ResidentNext(State) and $FFFF); A5 := Int64(ResidentNext(State) and $FFFF);
  A6 := Int64(ResidentNext(State) and $FFFF); A7 := Int64(ResidentNext(State) and $FFFF);
  B0 := Int64(ResidentNext(State) and $FFFF); B1 := Int64(ResidentNext(State) and $FFFF);
  B2 := Int64(ResidentNext(State) and $FFFF); B3 := Int64(ResidentNext(State) and $FFFF);
  B4 := Int64(ResidentNext(State) and $FFFF); B5 := Int64(ResidentNext(State) and $FFFF);
  B6 := Int64(ResidentNext(State) and $FFFF); B7 := Int64(ResidentNext(State) and $FFFF);
  C0 := Int64(ResidentNext(State) and $FFFF); C1 := Int64(ResidentNext(State) and $FFFF);
  C2 := Int64(ResidentNext(State) and $FFFF); C3 := Int64(ResidentNext(State) and $FFFF);
  C4 := Int64(ResidentNext(State) and $FFFF); C5 := Int64(ResidentNext(State) and $FFFF);
  C6 := Int64(ResidentNext(State) and $FFFF); C7 := Int64(ResidentNext(State) and $FFFF);

  { Между заведением и чтением — чужой вызов: все двадцать четыре обязаны
    пережить его. }
  Disturb(A0 + C7);

  Spread := (A0 * 1 + A1 * 2 + A2 * 3 + A3 * 4 + A4 * 5 + A5 * 6 + A6 * 7 + A7 * 8) xor
            (B0 * 9 + B1 * 10 + B2 * 11 + B3 * 12 + B4 * 13 + B5 * 14 + B6 * 15 + B7 * 16) xor
            (C0 * 17 + C1 * 18 + C2 * 19 + C3 * 20 + C4 * 21 + C5 * 22 + C6 * 23 + C7 * 24);

  { То же самое, но всё лежит в памяти по индексу — давить нечему. }
  State := Save;
  for I := 0 to High(Cells) do
    Cells[I] := Int64(ResidentNext(State) and $FFFF);
  Packed_ := 0;
  for I := 0 to 7 do
    Packed_ := Packed_ + Cells[I] * (I + 1);
  var Middle: Int64 := 0;
  for I := 8 to 15 do
    Middle := Middle + Cells[I] * (I + 1);
  var Last: Int64 := 0;
  for I := 16 to 23 do
    Last := Last + Cells[I] * (I + 1);
  Packed_ := Packed_ xor Middle xor Last;

  Carrier.Feed(UInt64(Spread));
  Carrier.Feed(UInt64(Packed_));
  Carrier.Claim(Spread = Packed_, 'live: values spread over registers lost against the same sum in memory');
end;

{ Значение живёт через чужой вызов, который волен портить регистры. }
procedure StageAcrossCall(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Kept, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Kept := Int64(ResidentNext(State) and $FFFF);

  Sum := 0;
  for I := 1 to Steps do
    begin
      Disturb(Int64(I));
      Sum := Sum + Kept * I;
      Disturb(Sum);
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Kept * I;

  Carrier.Feed(UInt64(Sum));
  Carrier.Feed(UInt64(Kept));
  Carrier.Claim(Sum = Mirror, 'live: value did not survive a foreign call');
end;

{ Значение живёт через ветвление, у которого разные пути. }
procedure StageAcrossBranch(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Held, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 12 + Integer(ResidentNext(State) and 7);
  Held := Int64(ResidentNext(State) and $FFF) + 1;

  Sum := 0;
  for I := 1 to Steps do
    begin
      if (I mod 3) = 0 then
        begin
          Disturb(I);
          Sum := Sum + Held;
        end
      else if (I mod 3) = 1 then
        Sum := Sum + Held * 2
      else
        begin
          Disturb(-I);
          Sum := Sum - Held;
        end;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    case I mod 3 of
      0: Mirror := Mirror + Held;
      1: Mirror := Mirror + Held * 2;
    else
      Mirror := Mirror - Held;
    end;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'live: value did not survive a branch');
end;

{ Значение живёт через раскрутку стека. Обработчик стоит там, где обычный
  эпилог не выполняется, поэтому сохранённое обязано лежать в памяти. }
procedure StageAcrossUnwind(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Before, After, Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 6 + Integer(ResidentNext(State) and 7);
  Sum := 0;

  for I := 1 to Steps do
    begin
      Before := Int64(I) * 37 + 11;
      After := 0;
      try
        Disturb(Before);
        if (I and 1) = 1 then
          raise ELiveSignal.Create('resident: live');
        After := Before * 2;
      except
        on ELiveSignal do
          After := Before * 3;
      end;
      Sum := Sum + After;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 1) = 1 then
      Mirror := Mirror + (Int64(I) * 37 + 11) * 3
    else
      Mirror := Mirror + (Int64(I) * 37 + 11) * 2;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'live: value did not survive stack unwinding');
end;

{ Много значений живут через цикл, а нужны после него. }
procedure StageAcrossLoop(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  P0, P1, P2, P3, P4, P5: Int64;
  Churn, Total, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Steps := 10 + Integer(ResidentNext(State) and 7);
  P0 := Int64(ResidentNext(State) and $FF);
  P1 := Int64(ResidentNext(State) and $FF);
  P2 := Int64(ResidentNext(State) and $FF);
  P3 := Int64(ResidentNext(State) and $FF);
  P4 := Int64(ResidentNext(State) and $FF);
  P5 := Int64(ResidentNext(State) and $FF);

  Churn := 0;
  for I := 1 to Steps do
    begin
      Churn := Churn + Int64(I) * (I + 1);
      Disturb(Churn);
    end;

  Total := P0 * 1 + P1 * 2 + P2 * 3 + P3 * 4 + P4 * 5 + P5 * 6 + Churn;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) * (I + 1);
  Mirror := Mirror + P0 * 1 + P1 * 2 + P2 * 3 + P3 * 4 + P4 * 5 + P5 * 6;

  Carrier.Feed(UInt64(Total));
  Carrier.Claim(Total = Mirror, 'live: values did not survive a busy loop');
end;

{ Вложенная процедура читает и пишет кадр родителя, пока родитель считает. }
procedure StageParentFrameLive(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Alpha, Beta, Gamma, Sum, Mirror: Int64;

  procedure Shuffle;
  var
    Spare: Int64;
  begin
    Spare := Alpha;
    Alpha := Beta + 1;
    Beta := Gamma + 2;
    Gamma := Spare + 3;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Steps := 9 + Integer(ResidentNext(State) and 7);
  Alpha := 1;
  Beta := 2;
  Gamma := 3;

  Sum := 0;
  for I := 1 to Steps do
    begin
      Sum := Sum + Alpha * 100 + Beta * 10 + Gamma;
      Shuffle;
    end;

  { Зеркало повторяет перестановку без вложенной процедуры. }
  Alpha := 1;
  Beta := 2;
  Gamma := 3;
  Mirror := 0;
  for I := 1 to Steps do
    begin
      Mirror := Mirror + Alpha * 100 + Beta * 10 + Gamma;
      var Spare: Int64 := Alpha;
      Alpha := Beta + 1;
      Beta := Gamma + 2;
      Gamma := Spare + 3;
    end;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'live: nested routine disturbed the parent frame');
end;

{ Значения нужны в порядке, обратном тому, в котором заведены: развозка по
  стеку обязана вернуть каждое на своё место. }
procedure StageReverseUse(Carrier: TResidentCarrier);
var
  State, Save: UInt64;
  V: array[0 .. 15] of Int64;
  I: Integer;
  Forward_, Backward: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Save := State;
  for I := 0 to High(V) do
    V[I] := Int64(ResidentNext(State) and $FFFF);

  { Заводим россыпью, читаем в обратном порядке, между делом мешая. }
  var W0: Int64 := V[0];  var W1: Int64 := V[1];
  var W2: Int64 := V[2];  var W3: Int64 := V[3];
  var W4: Int64 := V[4];  var W5: Int64 := V[5];
  var W6: Int64 := V[6];  var W7: Int64 := V[7];
  Disturb(W0);
  var W8: Int64 := V[8];  var W9: Int64 := V[9];
  var WA: Int64 := V[10]; var WB: Int64 := V[11];
  var WC: Int64 := V[12]; var WD: Int64 := V[13];
  var WE: Int64 := V[14]; var WF: Int64 := V[15];
  Disturb(WF);

  Backward := WF * 1 + WE * 2 + WD * 3 + WC * 4 + WB * 5 + WA * 6 + W9 * 7 + W8 * 8 +
              W7 * 9 + W6 * 10 + W5 * 11 + W4 * 12 + W3 * 13 + W2 * 14 + W1 * 15 + W0 * 16;

  State := Save;
  Forward_ := 0;
  for I := 0 to High(V) do
    Forward_ := Forward_ + V[High(V) - I] * (I + 1);

  Carrier.Feed(UInt64(Backward));
  Carrier.Claim(Backward = Forward_, 'live: values came back from the stack in the wrong order');
end;

{ Длинная цепочка обменов между многими переменными: каждое значение обязано
  доехать до своего конца. }
procedure StageSwapChain(Carrier: TResidentCarrier);
var
  State: UInt64;
  A, B, C, D, E, F: Int64;
  Start: array[0 .. 5] of Int64;
  I, Round_: Integer;
  Sum, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  for I := 0 to High(Start) do
    Start[I] := Int64(ResidentNext(State) and $FFFF);

  A := Start[0]; B := Start[1]; C := Start[2];
  D := Start[3]; E := Start[4]; F := Start[5];

  { Шесть переменных по кругу: за шесть поворотов каждая вернётся на место. }
  for Round_ := 1 to 6 do
    begin
      var Spare: Int64 := A;
      A := B; B := C; C := D; D := E; E := F; F := Spare;
      Disturb(A);
    end;

  Sum := A * 1 + B * 2 + C * 3 + D * 4 + E * 5 + F * 6;
  Mirror := 0;
  for I := 0 to High(Start) do
    Mirror := Mirror + Start[I] * (I + 1);

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(A = Start[0], 'live: full rotation did not return the first value');
  Carrier.Claim(Sum = Mirror, 'live: rotation lost or duplicated a value');
end;

{ Значение, записанное и не читаемое по прямому пути, читается через
  указатель. Признать такую запись мёртвой нельзя. }
procedure StageHiddenRead(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Slot, Sum, Mirror: Int64;
  Hook: ^Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 23 + 13);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Hook := @Slot;
  Sum := 0;

  for I := 1 to Steps do
    begin
      Slot := Int64(I) * 5;
      Disturb(I);
      Sum := Sum + Hook^;
      Slot := 0;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) * 5;

  Carrier.Feed(UInt64(Sum));
  Carrier.Claim(Sum = Mirror, 'live: store read only through a pointer was dropped');
end;

initialization
  ResidentRegisterStage('live-across-branch', @StageAcrossBranch);
  ResidentRegisterStage('live-across-call', @StageAcrossCall);
  ResidentRegisterStage('live-across-loop', @StageAcrossLoop);
  ResidentRegisterStage('live-across-unwind', @StageAcrossUnwind);
  ResidentRegisterStage('live-hidden-read', @StageHiddenRead);
  ResidentRegisterStage('live-many-values', @StageManyValues);
  ResidentRegisterStage('live-parent-frame', @StageParentFrameLive);
  ResidentRegisterStage('live-reverse-use', @StageReverseUse);
  ResidentRegisterStage('live-swap-chain', @StageSwapChain);

end.
