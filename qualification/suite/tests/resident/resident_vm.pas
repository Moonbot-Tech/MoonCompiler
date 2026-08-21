unit resident_vm;

{ Виртуальная машина — программа внутри программы.

  Зачем она здесь, три причины.

  Первая: это **снова таблица переходов внутри цикла** — форма, на которой уже
  нашёлся дефект оптимизатора. Только теперь таблица не байтовая, а таблица
  действий: код операции выбирает ветвь, ветвь меняет состояние, состояние
  влияет на следующий код операции. Зависимость плотнее некуда.

  Вторая: **оракул точный и бесплатный**. Выражение вычисляется дважды — обходом
  дерева напрямую и исполнением скомпилированного из него кода. Целые числа,
  значит равенство точное, без всяких допусков.

  Третья: **стек и переходы**. У машины есть стек, ветвления и вызовы, поэтому
  проверяется не арифметика, а то, что состояние живёт правильно: стек сходится
  в ноль, переходы попадают куда указано, вызов возвращается туда, откуда ушёл.

  Выражения строятся из сида, поэтому каждый заход исполняет ДРУГУЮ программу, а
  не одну и ту же много раз. }

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
  { Коды операций. }
  OpPush = 0;
  OpAdd = 1;
  OpSub = 2;
  OpMul = 3;
  OpNeg = 4;
  OpDup = 5;
  OpSwap = 6;
  OpDrop = 7;
  OpLoad = 8;
  OpStore = 9;
  OpJump = 10;
  OpJumpZero = 11;
  OpCall = 12;
  OpReturn = 13;
  OpHalt = 14;

  SlotCount = 8;

type
  TInstr = record
    Code: Integer;
    Arg: Int64;
  end;

  TProgram = System.TArray<TInstr>;

  { Узел выражения: либо число, либо переменная, либо действие над двумя. }
  TNode = record
    Kind: Integer;        { 0 число, 1 переменная, 2 действие }
    Value: Int64;
    Op: Integer;
    Left, Right: Integer; { номера в общем хранилище узлов }
  end;

  TTree = System.TArray<TNode>;

  TResidentVmPocket = class(TResidentPocket)
  private
    FSlots: array[0 .. SlotCount - 1] of Int64;
    FRounds: Int64;
  end;

{ ------------------------------------------------------------- машина ----- }

{ Исполнение. Возвращает вершину стека; глубина стека и число шагов отдаются
  наружу, потому что по ним проверяется, что машина не наплодила мусора. }
function Execute(const Code: TProgram; var Slots: array of Int64;
  out Depth, Steps: Integer; out Overflow_: Boolean): Int64;
const
  StackLimit = 256;
  StepLimit = 100000;
var
  Stack: array[0 .. StackLimit - 1] of Int64;
  Calls: array[0 .. 63] of Integer;
  Top, CallTop, Pc: Integer;
  A, B: Int64;
begin
  Top := 0;
  CallTop := 0;
  Pc := 0;
  Steps := 0;
  Overflow_ := False;
  Result := 0;

  while (Pc >= 0) and (Pc <= High(Code)) and (Steps < StepLimit) do
  begin
    Inc(Steps);
    case Code[Pc].Code of
      OpPush:
        begin
          if Top >= StackLimit then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top] := Code[Pc].Arg;
          Inc(Top);
        end;
      OpAdd:
        begin
          if Top < 2 then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top - 2] := Stack[Top - 2] + Stack[Top - 1];
          Dec(Top);
        end;
      OpSub:
        begin
          if Top < 2 then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top - 2] := Stack[Top - 2] - Stack[Top - 1];
          Dec(Top);
        end;
      OpMul:
        begin
          if Top < 2 then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top - 2] := Stack[Top - 2] * Stack[Top - 1];
          Dec(Top);
        end;
      OpNeg:
        begin
          if Top < 1 then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top - 1] := -Stack[Top - 1];
        end;
      OpDup:
        begin
          if (Top < 1) or (Top >= StackLimit) then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top] := Stack[Top - 1];
          Inc(Top);
        end;
      OpSwap:
        begin
          if Top < 2 then
          begin
            Overflow_ := True;
            Break;
          end;
          A := Stack[Top - 1];
          Stack[Top - 1] := Stack[Top - 2];
          Stack[Top - 2] := A;
        end;
      OpDrop:
        begin
          if Top < 1 then
          begin
            Overflow_ := True;
            Break;
          end;
          Dec(Top);
        end;
      OpLoad:
        begin
          if Top >= StackLimit then
          begin
            Overflow_ := True;
            Break;
          end;
          Stack[Top] := Slots[Code[Pc].Arg];
          Inc(Top);
        end;
      OpStore:
        begin
          if Top < 1 then
          begin
            Overflow_ := True;
            Break;
          end;
          Slots[Code[Pc].Arg] := Stack[Top - 1];
          Dec(Top);
        end;
      OpJump:
        begin
          Pc := Integer(Code[Pc].Arg);
          Continue;
        end;
      OpJumpZero:
        begin
          if Top < 1 then
          begin
            Overflow_ := True;
            Break;
          end;
          B := Stack[Top - 1];
          Dec(Top);
          if B = 0 then
          begin
            Pc := Integer(Code[Pc].Arg);
            Continue;
          end;
        end;
      OpCall:
        begin
          if CallTop > High(Calls) then
          begin
            Overflow_ := True;
            Break;
          end;
          Calls[CallTop] := Pc + 1;
          Inc(CallTop);
          Pc := Integer(Code[Pc].Arg);
          Continue;
        end;
      OpReturn:
        begin
          if CallTop < 1 then
          begin
            Overflow_ := True;
            Break;
          end;
          Dec(CallTop);
          Pc := Calls[CallTop];
          Continue;
        end;
      OpHalt:
        Break;
    end;
    Inc(Pc);
  end;

  Depth := Top;
  if Top > 0 then
    Result := Stack[Top - 1];
  { Незакрытые вызовы — тоже беспорядок. }
  if CallTop <> 0 then
    Overflow_ := True;
end;

{ ------------------------------------------------------- дерево и перевод - }

{ Построение случайного выражения. Глубина ограничена, значения небольшие —
  иначе произведение уедет за разрядность и сравнивать станет нечего. }
function BuildTree(var State: UInt64; var Tree: TTree; Depth: Integer): Integer;
var
  Pick: Integer;
begin
  SetLength(Tree, Length(Tree) + 1);
  Result := High(Tree);

  if Depth <= 0 then
    Pick := Integer(ResidentNext(State) mod 2)
  else
    Pick := 2 + Integer(ResidentNext(State) mod 3);

  if Pick = 0 then
  begin
    Tree[Result].Kind := 0;
    Tree[Result].Value := Int64(ResidentNext(State) mod 19) - 9;
  end
  else if Pick = 1 then
  begin
    Tree[Result].Kind := 1;
    Tree[Result].Value := Int64(ResidentNext(State) mod SlotCount);
  end
  else
  begin
    Tree[Result].Kind := 2;
    case Pick of
      2: Tree[Result].Op := OpAdd;
      3: Tree[Result].Op := OpSub;
    else
      Tree[Result].Op := OpMul;
    end;
    { Порядок важен: рекурсия расширяет массив, поэтому номера берутся после. }
    var L := BuildTree(State, Tree, Depth - 1);
    var R := BuildTree(State, Tree, Depth - 1);
    Tree[Result].Left := L;
    Tree[Result].Right := R;
  end;
end;

{ Прямое вычисление обходом дерева — эталон для сравнения. }
function EvalTree(const Tree: TTree; Node: Integer;
  const Slots: array of Int64): Int64;
var
  L, R: Int64;
begin
  case Tree[Node].Kind of
    0: Result := Tree[Node].Value;
    1: Result := Slots[Tree[Node].Value];
  else
    L := EvalTree(Tree, Tree[Node].Left, Slots);
    R := EvalTree(Tree, Tree[Node].Right, Slots);
    case Tree[Node].Op of
      OpAdd: Result := L + R;
      OpSub: Result := L - R;
    else
      Result := L * R;
    end;
  end;
end;

{ Перевод дерева в код: сначала оба довода, потом действие над ними. }
procedure Compile(const Tree: TTree; Node: Integer; var Code: TProgram);

  procedure Emit(ACode: Integer; AArg: Int64);
  begin
    SetLength(Code, Length(Code) + 1);
    Code[High(Code)].Code := ACode;
    Code[High(Code)].Arg := AArg;
  end;

begin
  case Tree[Node].Kind of
    0: Emit(OpPush, Tree[Node].Value);
    1: Emit(OpLoad, Tree[Node].Value);
  else
    Compile(Tree, Tree[Node].Left, Code);
    Compile(Tree, Tree[Node].Right, Code);
    Emit(Tree[Node].Op, 0);
  end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Исполнение против прямого вычисления: две дороги к одному числу. }
procedure StageCompileRun(Carrier: TResidentCarrier);
var
  Tree: TTree;
  Code: TProgram;
  Slots: array[0 .. SlotCount - 1] of Int64;
  State: UInt64;
  Root, Depth, Steps, I, K: Integer;
  Direct, Ran: Int64;
  Overflow_: Boolean;
begin
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 101 + Carrier.Lap)));
  for I := 0 to SlotCount - 1 do
    Slots[I] := Int64(ResidentNext(State) mod 21) - 10;

  for K := 1 to 6 do
  begin
    SetLength(Tree, 0);
    SetLength(Code, 0);
    Root := BuildTree(State, Tree, 3 + (K mod 3));
    Compile(Tree, Root, Code);
    Carrier.Claim(Length(Code) > 0, 'vm: compiled to nothing');

    Direct := EvalTree(Tree, Root, Slots);
    Ran := Execute(Code, Slots, Depth, Steps, Overflow_);

    Carrier.Claim(not Overflow_, 'vm: machine ran into a bad state');
    Carrier.Claim(Ran = Direct, 'vm: execution disagrees with direct evaluation');
    { Стек обязан сойтись ровно к одному значению — результату. }
    Carrier.Claim(Depth = 1, 'vm: stack did not settle to a single value');
    Carrier.Feed(UInt64(Direct));
    Carrier.Feed(UInt64(Cardinal(Length(Code))));
    Carrier.Feed(UInt64(Cardinal(Steps)));
  end;
end;

{ Стековые действия: у каждого своё обещание, и все они проверяемы. }
procedure StageStackOps(Carrier: TResidentCarrier);
var
  Code: TProgram;
  Slots: array[0 .. SlotCount - 1] of Int64;
  Depth, Steps, I: Integer;
  Value: Int64;
  Overflow_: Boolean;

  procedure Emit(ACode: Integer; AArg: Int64);
  begin
    SetLength(Code, Length(Code) + 1);
    Code[High(Code)].Code := ACode;
    Code[High(Code)].Arg := AArg;
  end;

begin
  for I := 0 to SlotCount - 1 do
    Slots[I] := I;

  { Удвоение и сложение: число плюс само себя. }
  SetLength(Code, 0);
  Emit(OpPush, 21);
  Emit(OpDup, 0);
  Emit(OpAdd, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 42, 'vm: dup then add is wrong');
  Carrier.Claim(Depth = 1, 'vm: dup left the stack unbalanced');

  { Обмен: вычитание после обмена меняет знак. }
  SetLength(Code, 0);
  Emit(OpPush, 10);
  Emit(OpPush, 3);
  Emit(OpSwap, 0);
  Emit(OpSub, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = -7, 'vm: swap then subtract is wrong');

  { Сброс: верхнее уходит, под ним остаётся прежнее. }
  SetLength(Code, 0);
  Emit(OpPush, 5);
  Emit(OpPush, 99);
  Emit(OpDrop, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 5, 'vm: drop removed the wrong value');
  Carrier.Claim(Depth = 1, 'vm: drop left the stack unbalanced');

  { Смена знака дважды возвращает исходное. }
  SetLength(Code, 0);
  Emit(OpPush, 17);
  Emit(OpNeg, 0);
  Emit(OpNeg, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 17, 'vm: negating twice changed the value');

  { Ячейки: записанное читается обратно. }
  SetLength(Code, 0);
  Emit(OpPush, 1234);
  Emit(OpStore, 3);
  Emit(OpLoad, 3);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 1234, 'vm: store then load lost the value');
  Carrier.Claim(Slots[3] = 1234, 'vm: store did not reach the slot');
  Carrier.Feed(UInt64(Value));
end;

{ Переходы и вызовы: управление обязано попадать ровно туда, куда указано, и
  возвращаться туда, откуда ушло. }
procedure StageControl(Carrier: TResidentCarrier);
var
  Code: TProgram;
  Slots: array[0 .. SlotCount - 1] of Int64;
  Depth, Steps, I: Integer;
  Value: Int64;
  Overflow_: Boolean;

  procedure Emit(ACode: Integer; AArg: Int64);
  begin
    SetLength(Code, Length(Code) + 1);
    Code[High(Code)].Code := ACode;
    Code[High(Code)].Arg := AArg;
  end;

begin
  for I := 0 to SlotCount - 1 do
    Slots[I] := 0;

  { Безусловный переход обязан перепрыгнуть через середину. }
  SetLength(Code, 0);
  Emit(OpPush, 7);
  Emit(OpJump, 4);
  Emit(OpPush, 999);   { сюда попадать нельзя }
  Emit(OpAdd, 0);
  Emit(OpHalt, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 7, 'vm: unconditional jump did not skip the code');
  Carrier.Claim(not Overflow_, 'vm: jump left the machine in a bad state');

  { Переход по нулю: срабатывает на нуле и не срабатывает на прочем. }
  SetLength(Code, 0);
  Emit(OpPush, 0);
  Emit(OpJumpZero, 4);
  Emit(OpPush, 111);
  Emit(OpHalt, 0);
  Emit(OpPush, 222);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 222, 'vm: zero jump did not fire on zero');

  SetLength(Code, 0);
  Emit(OpPush, 5);
  Emit(OpJumpZero, 4);
  Emit(OpPush, 111);
  Emit(OpHalt, 0);
  Emit(OpPush, 222);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 111, 'vm: zero jump fired on a non-zero value');

  { Вызов и возврат: подпрограмма удваивает вершину, управление возвращается. }
  SetLength(Code, 0);
  Emit(OpPush, 6);
  Emit(OpCall, 4);
  Emit(OpPush, 1);
  Emit(OpHalt, 0);
  Emit(OpDup, 0);      { подпрограмма с адреса 4 }
  Emit(OpAdd, 0);
  Emit(OpReturn, 0);
  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Carrier.Claim(Value = 1, 'vm: call did not return to the right place');
  Carrier.Claim(Depth = 2, 'vm: call left the stack unbalanced');
  Carrier.Claim(not Overflow_, 'vm: call left an open frame');
  Carrier.Feed(UInt64(Cardinal(Steps)));
end;

{ Цикл на переходах: счётчик крутится заданное число раз, и сумма обязана
  совпасть с известной формулой. }
procedure StageLoop(Carrier: TResidentCarrier);
var
  Code: TProgram;
  Slots: array[0 .. SlotCount - 1] of Int64;
  Depth, Steps, I, N: Integer;
  Value, Want: Int64;
  Overflow_: Boolean;

  procedure Emit(ACode: Integer; AArg: Int64);
  begin
    SetLength(Code, Length(Code) + 1);
    Code[High(Code)].Code := ACode;
    Code[High(Code)].Arg := AArg;
  end;

begin
  N := 10 + (Carrier.Lap mod 40);
  for I := 0 to SlotCount - 1 do
    Slots[I] := 0;
  Slots[0] := N;    { счётчик }
  Slots[1] := 0;    { накопитель }

  { Пока счётчик не ноль: прибавить его к накопителю, уменьшить на единицу. }
  SetLength(Code, 0);
  Emit(OpLoad, 0);          { 0: счётчик на стек }
  Emit(OpJumpZero, 9);      { 1: ноль — выходим }
  Emit(OpLoad, 1);          { 2 }
  Emit(OpLoad, 0);          { 3 }
  Emit(OpAdd, 0);           { 4 }
  Emit(OpStore, 1);         { 5: накопитель += счётчик }
  Emit(OpLoad, 0);          { 6 }
  Emit(OpPush, 1);          { 7 }
  Emit(OpSub, 0);           { 8 -> дальше падает на 9? нет: store ниже }
  Emit(OpStore, 0);         { 9 }
  Emit(OpJump, 0);          { 10: снова }

  { Выход по нулю ведёт на 9 — а там ещё Store. Адрес выхода правится на конец. }
  Code[1].Arg := Length(Code);
  Emit(OpLoad, 1);
  Emit(OpHalt, 0);

  Value := Execute(Code, Slots, Depth, Steps, Overflow_);
  Want := Int64(N) * (N + 1) div 2;

  Carrier.Claim(not Overflow_, 'vm: loop ran into a bad state');
  Carrier.Claim(Value = Want, 'vm: loop sum does not match the formula');
  Carrier.Claim(Slots[0] = 0, 'vm: loop counter did not reach zero');
  Carrier.Claim(Steps < 100000, 'vm: loop did not terminate');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Value));
  Carrier.Feed(UInt64(Cardinal(Steps)));
end;

{ Ячейки, живущие между оборотами: программа читает оставленное прошлым
  оборотом и дописывает своё. }
procedure StageRunningVm(Carrier: TResidentCarrier);
var
  Pocket: TResidentVmPocket;
  Code: TProgram;
  Depth, Steps, I: Integer;
  Value, Before: Int64;
  Overflow_: Boolean;

  procedure Emit(ACode: Integer; AArg: Int64);
  begin
    SetLength(Code, Length(Code) + 1);
    Code[High(Code)].Code := ACode;
    Code[High(Code)].Arg := AArg;
  end;

begin
  Pocket := Carrier.PocketAs<TResidentVmPocket>('vm-running');
  Before := Pocket.FSlots[0];

  { Накопитель увеличивается на номер оборота. }
  SetLength(Code, 0);
  Emit(OpLoad, 0);
  Emit(OpPush, Int64(Carrier.Lap) + 1);
  Emit(OpAdd, 0);
  Emit(OpDup, 0);
  Emit(OpStore, 0);
  Emit(OpHalt, 0);

  Value := Execute(Code, Pocket.FSlots, Depth, Steps, Overflow_);
  Carrier.Claim(not Overflow_, 'vm: running program ran into a bad state');
  Carrier.Claim(Value = Before + Int64(Carrier.Lap) + 1,
                'vm: running accumulator did not advance correctly');
  Carrier.Claim(Pocket.FSlots[0] = Value, 'vm: slot did not keep the value');
  Carrier.Feed(UInt64(Value));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  if Pocket.FSlots[0] > 100000 then
    for I := 0 to SlotCount - 1 do
      Pocket.FSlots[I] := 0;
end;

initialization
  ResidentRegisterStage('vm-compile-run', @StageCompileRun);
  ResidentRegisterStage('vm-control', @StageControl);
  ResidentRegisterStage('vm-loop', @StageLoop);
  ResidentRegisterStage('vm-running', @StageRunningVm);
  ResidentRegisterStage('vm-stack-ops', @StageStackOps);

end.
