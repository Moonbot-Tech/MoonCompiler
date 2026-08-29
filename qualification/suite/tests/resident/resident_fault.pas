unit resident_fault;

{ Семейство `fault` — исключение как часть расчёта.

  В семействе `flow` исключение проверяется как путь: какие блоки прошли и в
  каком порядке. Здесь оно проверяется как **арифметика**: число, которым
  кончается стадия, физически проезжает через раскрутку стека. Это другой
  вопрос к компилятору. Путь можно пройти правильно и всё же потерять по
  дороге значение — например, если переменная жила в регистре, который никто
  не обязан сохранять через границу обработчика, или если присваивание перед
  `raise` признали мёртвым, потому что дальше по прямому пути его никто не
  читает.

  Каждая стадия считает одно и то же дважды: один раз через исключения, второй
  — обычным ветвлением. Разойтись они не могут: `raise` здесь не аварийный
  выход, а способ вернуть управление, и оба способа описывают один алгоритм.
  Такое сравнение сильнее счёта пройденных точек — оно ловит не только «не
  туда пошли», но и «дошли верно, а привезли не то».

  Все исключения свои и все ловятся. Ни одно не выходит за пределы стадии, и
  ни одно не зависит от состояния машины: коды и границы вычисляются из
  детерминированного потока носителя. }

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
  SysUtils, Classes, resident_core;

implementation

type
  { Исключение-переносчик: код и есть то значение, ради которого затевалась
    раскрутка. }
  EFaultValue = class(Exception)
  private
    FValue: Int64;
    FLevel: Integer;
  public
    constructor Create(AValue: Int64; ALevel: Integer); reintroduce;
    property Value: Int64 read FValue;
    property Level: Integer read FLevel;
  end;

  EFaultOdd = class(EFaultValue);
  EFaultEven = class(EFaultValue);

  { Объект, который заводит жильца и обязан похоронить его при любом исходе. }
  TFaultHolder = class
  private
    FTally: PResidentTally;
    FInner: TStringList;
  public
    constructor Create(ATally: PResidentTally);
    destructor Destroy; override;
    procedure Work(Value: Integer; Explode: Boolean);
  end;

constructor EFaultValue.Create(AValue: Int64; ALevel: Integer);
begin
  inherited Create('resident: fault carrier');
  FValue := AValue;
  FLevel := ALevel;
end;

constructor TFaultHolder.Create(ATally: PResidentTally);
begin
  inherited Create;
  FTally := ATally;
  FInner := TStringList.Create;
  Inc(FTally^.Born);
end;

destructor TFaultHolder.Destroy;
begin
  FreeAndNil(FInner);
  Inc(FTally^.Gone);
  inherited Destroy;
end;

procedure TFaultHolder.Work(Value: Integer; Explode: Boolean);
begin
  FInner.Add(IntToStr(Value));
  if Explode then
    raise EFaultValue.Create(Value, 1);
end;

{ Часть слагаемых доезжает обычным путём, часть — через раскрутку. Сумма
  обязана быть та же, что у прямой формулы. }
procedure StageSumThroughRaise(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Bound: Integer;
  Live, Mirror: Int64;

  function Deliver(Value: Integer): Int64;
  begin
    if (Value mod 3) = 0 then
      raise EFaultValue.Create(Int64(Value) * 10, 1);
    Result := Value;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  Bound := 12 + Integer(ResidentNext(State) and 7);

  Live := 0;
  for I := 1 to Bound do
    try
      Live := Live + Deliver(I);
    except
      on E: EFaultValue do
        Live := Live + E.Value;
    end;

  Mirror := 0;
  for I := 1 to Bound do
    if (I mod 3) = 0 then
      Mirror := Mirror + Int64(I) * 10
    else
      Mirror := Mirror + I;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'fault: value delivered through unwinding was lost');
end;

{ Сделанное до `raise` обязано остаться сделанным. Присваивание, которое дальше
  по прямому пути никто не читает, мёртвым не является: его читает
  обработчик. }
procedure StagePartialEffects(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Seen, Touched: Integer;
  Live, Mirror: Int64;

  procedure Half(Value: Integer);
  begin
    Inc(Touched);
    Seen := Value * 2;
    if (Value and 1) = 1 then
      raise EFaultOdd.Create(Seen, 2);
    Seen := Seen + 1;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Touched := 0;
  Seen := 0;
  Live := 0;

  for I := 1 to Steps do
    begin
      try
        Half(I);
      except
        on E: EFaultOdd do
          Live := Live + E.Value;
      end;
      { То, что успела записать половина работы, видно и снаружи. }
      Live := Live + Seen;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 1) = 1 then
      Mirror := Mirror + Int64(I) * 2 + Int64(I) * 2
    else
      Mirror := Mirror + Int64(I) * 2 + 1;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(Touched)));
  Carrier.Claim(Touched = Steps, 'fault: a step did not run at all');
  Carrier.Claim(Live = Mirror, 'fault: effects made before raise were dropped');
end;

{ `finally` правит накопитель и на прямом пути, и на исключительном. }
procedure StageFinallyAdjusts(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  Steps := 10 + Integer(ResidentNext(State) and 5);
  Live := 0;

  for I := 1 to Steps do
    try
      try
        if (I mod 4) = 0 then
          raise EFaultEven.Create(100, 3);
        Live := Live + I;
      finally
        Live := Live + 1;
      end;
    except
      on E: EFaultEven do
        Live := Live + E.Value;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    begin
      if (I mod 4) = 0 then
        Mirror := Mirror + 100
      else
        Mirror := Mirror + I;
      Mirror := Mirror + 1;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'fault: finally did not adjust on both paths');
end;

{ Выход из середины блока: `finally` обязан отработать до того, как значение
  уедет наружу. }
procedure StageExitThroughFinally(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;
  Ledger: Int64;

  function Leave(Value: Integer): Int64;
  begin
    Result := 0;
    try
      if (Value and 1) = 0 then
        begin
          Result := Value;
          Exit;
        end;
      Result := Value * 3;
    finally
      Ledger := Ledger + 1;
    end;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Ledger := 0;
  Live := 0;

  for I := 1 to Steps do
    Live := Live + Leave(I);

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 1) = 0 then
      Mirror := Mirror + I
    else
      Mirror := Mirror + Int64(I) * 3;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Ledger));
  Carrier.Claim(Live = Mirror, 'fault: exit through finally changed the result');
  Carrier.Claim(Ledger = Steps, 'fault: finally skipped on the exit path');
end;

{ Вложенные обработчики: внутренний правит данные и передаёт дальше, внешний
  считает по исправленным. }
procedure StageNestedHandlers(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  Steps := 9 + Integer(ResidentNext(State) and 6);
  Live := 0;

  for I := 1 to Steps do
    try
      try
        if (I mod 3) = 1 then
          raise EFaultOdd.Create(I, 1)
        else if (I mod 3) = 2 then
          raise EFaultEven.Create(I, 2);
        Live := Live + I * 100;
      except
        on E: EFaultOdd do
          raise EFaultValue.Create(E.Value * 7, E.Level + 10);
      end;
    except
      on E: EFaultValue do
        Live := Live + E.Value + E.Level;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    case I mod 3 of
      1: Mirror := Mirror + Int64(I) * 7 + 11;
      2: Mirror := Mirror + Int64(I) + 2;
    else
      Mirror := Mirror + Int64(I) * 100;
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'fault: nested handlers rebuilt the value wrongly');
end;

{ Повторный бросок того же объекта: значение обязано пережить второй пролёт. }
procedure StageReraiseCarries(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Passes: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 13 + 7);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Passes := 0;
  Live := 0;

  for I := 1 to Steps do
    try
      try
        raise EFaultValue.Create(Int64(I) * 5, I);
      except
        on E: EFaultValue do
          begin
            Inc(Passes);
            raise;
          end;
      end;
    except
      on E: EFaultValue do
        Live := Live + E.Value + E.Level;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    Mirror := Mirror + Int64(I) * 5 + I;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(Passes)));
  Carrier.Claim(Passes = Steps, 'fault: reraise path not taken every time');
  Carrier.Claim(Live = Mirror, 'fault: reraised exception arrived with a different payload');
end;

{ Исключение внутри цикла не должно портить ни счётчик, ни накопитель:
  оборот продолжается со следующего значения. }
procedure StageLoopResume(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Laps: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 17 + 9);
  Steps := 12 + Integer(ResidentNext(State) and 7);
  Laps := 0;
  Live := 0;

  for I := 1 to Steps do
    begin
      Inc(Laps);
      try
        if (I mod 5) = 0 then
          raise EFaultEven.Create(Int64(I) * 2, 4);
        Live := Live + I;
        Continue;
      except
        on E: EFaultEven do
          Live := Live - E.Value;
      end;
      Live := Live + 1000;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I mod 5) = 0 then
      Mirror := Mirror - Int64(I) * 2 + 1000
    else
      Mirror := Mirror + I;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(Laps)));
  Carrier.Claim(Laps = Steps, 'fault: loop lost a lap around the handler');
  Carrier.Claim(Live = Mirror, 'fault: continue and handler paths mixed up the total');
end;

{ Деление, где ноль отсечён не проверкой, а обработчиком. Оба способа обязаны
  дать одно и то же. }
procedure StageDivideGuard(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Denom, Caught: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 19 + 11);
  Steps := 10 + Integer(ResidentNext(State) and 5);
  Caught := 0;
  Live := 0;

  for I := 1 to Steps do
    begin
      Denom := (I mod 4) - 1;
      try
        Live := Live + (1000 div Denom);
      except
        on E: EDivByZero do
          begin
            Inc(Caught);
            Live := Live + 7;
          end;
      end;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    begin
      Denom := (I mod 4) - 1;
      if Denom = 0 then
        Mirror := Mirror + 7
      else
        Mirror := Mirror + (1000 div Denom);
    end;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(Caught)));
  Carrier.Claim(Live = Mirror, 'fault: guarded division disagrees with checked division');
  Carrier.Claim(Caught > 0, 'fault: division by zero never happened');
end;

{ Управляемые значения на пути раскрутки: строка, собранная до броска, обязана
  доехать целой, а временные — исчезнуть. }
procedure StageManagedUnwind(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;
  Kept: string;

  procedure Grow(Value: Integer);
  var
    Local: string;
  begin
    Local := StringOfChar('x', Value);
    Kept := Kept + Local;
    if (Value and 3) = 3 then
      raise EFaultValue.Create(Length(Local), 5);
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 23 + 13);
  Steps := 6 + Integer(ResidentNext(State) and 3);
  Kept := '';
  Live := 0;

  for I := 1 to Steps do
    try
      Grow(I);
    except
      on E: EFaultValue do
        Live := Live + E.Value;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 3) = 3 then
      Mirror := Mirror + I;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Cardinal(Length(Kept))));
  Carrier.FeedWide(Kept);
  Carrier.Claim(Live = Mirror, 'fault: length carried out of unwinding is wrong');
  Carrier.Claim(Length(Kept) = Steps * (Steps + 1) div 2,
    'fault: string built before the raise lost characters');
end;

{ Объект, заведённый до броска, обязан быть похоронен, а его жилец — вместе с
  ним. Баланс входит в результат стадии, а не проверяется отдельно. }
procedure StageObjectUnwind(Carrier: TResidentCarrier);
var
  State: UInt64;
  Tally: TResidentTally;
  Holder: TFaultHolder;
  I, Steps, Caught: Integer;
  Live, Mirror: Int64;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 29 + 17);
  Steps := 6 + Integer(ResidentNext(State) and 3);
  Tally := Default(TResidentTally);
  Caught := 0;
  Live := 0;

  for I := 1 to Steps do
    begin
      Holder := TFaultHolder.Create(@Tally);
      try
        try
          Holder.Work(I, (I and 1) = 1);
          Live := Live + I;
        except
          on E: EFaultValue do
            begin
              Inc(Caught);
              Live := Live + E.Value * 2;
            end;
        end;
      finally
        FreeAndNil(Holder);
      end;
    end;

  Mirror := 0;
  for I := 1 to Steps do
    if (I and 1) = 1 then
      Mirror := Mirror + Int64(I) * 2
    else
      Mirror := Mirror + I;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Feed(UInt64(Tally.Born));
  Carrier.Feed(UInt64(Tally.Gone));
  Carrier.Claim(Live = Mirror, 'fault: value from an unwound object is wrong');
  Carrier.Claim(Tally.Alive = 0, 'fault: object survived the unwinding');
  Carrier.Claim(Tally.Born = Steps, 'fault: not every object was built');
end;

{ Три уровня, и на каждом решение принимается по коду, приехавшему снизу. }
procedure StageCascade(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps: Integer;
  Live, Mirror: Int64;

  function Third(Value: Integer): Int64;
  begin
    if (Value mod 2) = 0 then
      raise EFaultEven.Create(Value, 3);
    Result := Value;
  end;

  function Second(Value: Integer): Int64;
  begin
    try
      Result := Third(Value) * 2;
    except
      on E: EFaultEven do
        raise EFaultOdd.Create(E.Value + 1, E.Level + 1);
    end;
  end;

  function First(Value: Integer): Int64;
  begin
    try
      Result := Second(Value) + 1;
    except
      on E: EFaultOdd do
        Result := E.Value * 10 + E.Level;
    end;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 31 + 19);
  Steps := 8 + Integer(ResidentNext(State) and 7);
  Live := 0;

  for I := 1 to Steps do
    Live := Live + First(I);

  Mirror := 0;
  for I := 1 to Steps do
    if (I mod 2) = 0 then
      Mirror := Mirror + (Int64(I) + 1) * 10 + 4
    else
      Mirror := Mirror + Int64(I) * 2 + 1;

  Carrier.Feed(UInt64(Live));
  Carrier.Feed(UInt64(Mirror));
  Carrier.Claim(Live = Mirror, 'fault: cascade of handlers produced a different total');
end;

{ Один и тот же алгоритм, записанный дважды: через исключения и обычными
  ветвлениями. Это главная проверка семейства — она не смотрит на путь вовсе,
  только на ответ. }
procedure StageTwoForms(Carrier: TResidentCarrier);
var
  State: UInt64;
  I, Steps, Limit: Integer;
  ByFault, ByBranch, Acc: Int64;

  function Classify(Value: Integer): Int64;
  begin
    if Value > Limit then
      raise EFaultValue.Create(Int64(Value) - Limit, 1);
    if (Value and 1) = 0 then
      raise EFaultEven.Create(Int64(Value) div 2, 2);
    Result := Int64(Value) * 3;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 37 + 23);
  Steps := 14 + Integer(ResidentNext(State) and 7);
  Limit := 6 + Integer(ResidentNext(State) and 3);

  ByFault := 0;
  for I := 1 to Steps do
    try
      ByFault := ByFault + Classify(I);
    except
      on E: EFaultEven do
        ByFault := ByFault + E.Value + 1;
      on E: EFaultValue do
        ByFault := ByFault - E.Value;
    end;

  ByBranch := 0;
  for I := 1 to Steps do
    begin
      if I > Limit then
        Acc := -(Int64(I) - Limit)
      else if (I and 1) = 0 then
        Acc := Int64(I) div 2 + 1
      else
        Acc := Int64(I) * 3;
      ByBranch := ByBranch + Acc;
    end;

  Carrier.Feed(UInt64(ByFault));
  Carrier.Feed(UInt64(ByBranch));
  Carrier.Claim(ByFault = ByBranch,
    'fault: the same algorithm gives different answers with and without exceptions');
end;

initialization
  ResidentRegisterStage('fault-cascade', @StageCascade);
  ResidentRegisterStage('fault-divide-guard', @StageDivideGuard);
  ResidentRegisterStage('fault-exit-through-finally', @StageExitThroughFinally);
  ResidentRegisterStage('fault-finally-adjusts', @StageFinallyAdjusts);
  ResidentRegisterStage('fault-loop-resume', @StageLoopResume);
  ResidentRegisterStage('fault-managed-unwind', @StageManagedUnwind);
  ResidentRegisterStage('fault-nested-handlers', @StageNestedHandlers);
  ResidentRegisterStage('fault-object-unwind', @StageObjectUnwind);
  ResidentRegisterStage('fault-partial-effects', @StagePartialEffects);
  ResidentRegisterStage('fault-reraise-carries', @StageReraiseCarries);
  ResidentRegisterStage('fault-sum-through-raise', @StageSumThroughRaise);
  ResidentRegisterStage('fault-two-forms', @StageTwoForms);

end.
