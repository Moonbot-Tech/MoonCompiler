unit resident_ode;

{ Уравнения движения: численное интегрирование с проверкой по законам физики.

  Это семейство ценно тем, что у него есть оракулы **трёх разных сортов**, и все
  без эталонных массивов чисел.

  **Точное решение.** У колебаний под силой, пропорциональной отклонению,
  решение известно в замкнутом виде. Численный ответ обязан совпасть с ним с
  точностью, которую даёт порядок схемы: у выбранной он второй, значит ошибка
  падает вчетверо при вдвое меньшем шаге — и это тоже проверяется.

  **Обратимость по времени.** Схема Верле симметрична: если в какой-то момент
  повернуть скорости вспять и сделать столько же шагов назад, система обязана
  вернуться в исходную точку. Это свойство самой схемы, и оно ловит малейшую
  несимметричность в порядке действий.

  **Сохранение.** Симплектическая схема не даёт энергии уходить: она колеблется
  около начальной, но не сползает. Это её главное отличие от простой явной
  схемы, и разница между ними тоже проверяется — если бы наша схема на деле
  оказалась явной, дрейф выдал бы её сразу.

  Пороги выведены из числа шагов и порядка схемы, а не подобраны. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, Classes, Generics.Collections, resident_core;

implementation

const
  MachineEps = 2.220446049250313e-16;

type
  { Тело на плоскости. }
  TBody = record
    X, Y, VX, VY: Double;
  end;

  TResidentOdePocket = class(TResidentPocket)
  private
    FBody: TBody;
    FEnergy0: Double;
    FSteps: Int64;
    FRounds: Int64;
  end;

{ ------------------------------------------------- гармонические колебания - }

{ Шаг схемы Верле для силы, пропорциональной отклонению: ускорение равно минус
  квадрату частоты на координату. }
procedure VerletStep(var X, V: Double; Omega2, Dt: Double);
var
  A0, A1: Double;
begin
  A0 := -Omega2 * X;
  X := X + V * Dt + 0.5 * A0 * Dt * Dt;
  A1 := -Omega2 * X;
  V := V + 0.5 * (A0 + A1) * Dt;
end;

{ Простая явная схема — для сравнения. Она того же порядка по одному шагу, но
  не симплектическая, и энергия у неё уползает. }
procedure EulerStep(var X, V: Double; Omega2, Dt: Double);
var
  A: Double;
begin
  A := -Omega2 * X;
  X := X + V * Dt;
  V := V + A * Dt;
end;

function OscEnergy(X, V, Omega2: Double): Double;
begin
  Result := 0.5 * V * V + 0.5 * Omega2 * X * X;
end;

{ ------------------------------------------------------- движение по орбите - }

{ Притяжение к началу координат по закону обратных квадратов. }
procedure Accel(const B: TBody; Mu: Double; out AX, AY: Double);
var
  R2, R, Inv: Double;
begin
  R2 := B.X * B.X + B.Y * B.Y;
  R := Sqrt(R2);
  Inv := Mu / (R2 * R);
  AX := -B.X * Inv;
  AY := -B.Y * Inv;
end;

procedure OrbitStep(var B: TBody; Mu, Dt: Double);
var
  AX0, AY0, AX1, AY1: Double;
begin
  Accel(B, Mu, AX0, AY0);
  B.X := B.X + B.VX * Dt + 0.5 * AX0 * Dt * Dt;
  B.Y := B.Y + B.VY * Dt + 0.5 * AY0 * Dt * Dt;
  Accel(B, Mu, AX1, AY1);
  B.VX := B.VX + 0.5 * (AX0 + AX1) * Dt;
  B.VY := B.VY + 0.5 * (AY0 + AY1) * Dt;
end;

{ Полная энергия и момент количества движения — две сохраняющиеся величины. }
function OrbitEnergy(const B: TBody; Mu: Double): Double;
begin
  Result := 0.5 * (B.VX * B.VX + B.VY * B.VY) -
            Mu / Sqrt(B.X * B.X + B.Y * B.Y);
end;

function OrbitMomentum(const B: TBody): Double;
begin
  Result := B.X * B.VY - B.Y * B.VX;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Совпадение с точным решением и падение ошибки при уменьшении шага. }
procedure StageExactSolution(Carrier: TResidentCarrier);
var
  X, V, Dt, Omega, Omega2, T, Want, Coarse_, Fine, Ratio: Double;
  Steps, I, K: Integer;
begin
  Omega := 1.0 + Double(Carrier.Serial mod 5) * 0.3;
  Omega2 := Omega * Omega;
  T := 2.0 + Double(Carrier.Lap mod 4) * 0.5;

  { Дважды: с крупным шагом и вдвое мельче. }
  Coarse_ := 0;
  Fine := 0;
  for K := 0 to 1 do
  begin
    Steps := 2000 shl K;
    Dt := T / Steps;
    X := 1.0;
    V := 0.0;
    for I := 1 to Steps do
      VerletStep(X, V, Omega2, Dt);
    { Точное решение для этих начальных условий. }
    Want := Cos(Omega * T);
    if K = 0 then
      Coarse_ := Abs(X - Want)
    else
      Fine := Abs(X - Want);
  end;

  Carrier.Claim(Coarse_ < 1e-4, 'ode: coarse step missed the exact solution');
  Carrier.Claim(Fine < Coarse_, 'ode: halving the step did not help');

  { Схема второго порядка: вдвое меньший шаг обязан дать вчетверо меньшую
    ошибку. Проверяется с большим запасом — важно, что порядок именно второй, а
    не первый. }
  if Fine > 1e-15 then
  begin
    Ratio := Coarse_ / Fine;
    Carrier.Claim(Ratio > 2.5, 'ode: convergence is slower than second order');
    Carrier.Feed(UInt64(Round(Ratio * 1000)));
  end;
  Carrier.Feed(UInt64(Round(Coarse_ * 1e12)));
  Carrier.Feed(UInt64(Round(Fine * 1e12)));
end;

{ Обратимость по времени: шаги вперёд, разворот скоростей, столько же назад —
  и система обязана вернуться туда, откуда вышла. }
procedure StageReversible(Carrier: TResidentCarrier);
var
  X, V, X0, V0, Dt, Omega2: Double;
  Steps, I: Integer;
begin
  Omega2 := 1.0 + Double(Carrier.Lap mod 7) * 0.25;
  Dt := 0.01;
  Steps := 500 + (Carrier.Serial mod 5) * 200;

  X0 := 1.0;
  V0 := 0.3;
  X := X0;
  V := V0;
  for I := 1 to Steps do
    VerletStep(X, V, Omega2, Dt);

  { Разворот и столько же шагов обратно. }
  V := -V;
  for I := 1 to Steps do
    VerletStep(X, V, Omega2, Dt);
  V := -V;

  { Возврат обязан быть точным до накопления округлений. }
  Carrier.Claim(Abs(X - X0) < MachineEps * Steps * 10000.0 + 1e-9,
                'ode: time reversal did not return the position');
  Carrier.Claim(Abs(V - V0) < MachineEps * Steps * 10000.0 + 1e-9,
                'ode: time reversal did not return the velocity');
  Carrier.Feed(UInt64(Cardinal(Steps)));
  Carrier.Feed(UInt64(Round(Abs(X - X0) * 1e15)));
end;

{ Энергия у симплектической схемы колеблется, но не сползает — в отличие от
  простой явной, где она уходит монотонно. Разница между ними и проверяется. }
procedure StageEnergyDrift(Carrier: TResidentCarrier);
var
  X, V, Dt, Omega2, E0, E, Worst: Double;
  Xe, Ve, Ee: Double;
  Steps, I: Integer;
begin
  Omega2 := 1.0;
  Dt := 0.05;
  Steps := 4000 + (Carrier.Lap mod 5) * 1000;

  X := 1.0;
  V := 0.0;
  E0 := OscEnergy(X, V, Omega2);
  Worst := 0;
  for I := 1 to Steps do
  begin
    VerletStep(X, V, Omega2, Dt);
    E := OscEnergy(X, V, Omega2);
    if Abs(E - E0) > Worst then
      Worst := Abs(E - E0);
  end;

  { У симплектической схемы отклонение энергии ограничено величиной порядка
    квадрата шага и НЕ растёт с числом шагов. }
  Carrier.Claim(Worst < 0.01 * E0 + 1e-6,
                'ode: symplectic scheme let the energy drift');
  Carrier.Feed(UInt64(Cardinal(Steps)));
  Carrier.Feed(UInt64(Round(Worst * 1e9)));

  { Та же задача простой явной схемой: энергия обязана уползти заметно. Если и
    здесь она сохранилась — значит схемы не различаются, и проверка выше
    ничего не значила. }
  Xe := 1.0;
  Ve := 0.0;
  for I := 1 to Steps do
    EulerStep(Xe, Ve, Omega2, Dt);
  Ee := OscEnergy(Xe, Ve, Omega2);
  Carrier.Claim(Ee > E0 * 2.0,
                'ode: the explicit scheme did not drift, so the schemes are the same');
  Carrier.Feed(UInt64(Round(Ee / E0 * 1000)));
end;

{ Движение по орбите: две сохраняющиеся величины разом. Момент количества
  движения у центральной силы сохраняется гораздо точнее энергии — это разные
  законы, и требования к ним разные. }
procedure StageOrbit(Carrier: TResidentCarrier);
var
  B: TBody;
  Mu, Dt, E0, L0, WorstE, WorstL, R, RMin, RMax: Double;
  Steps, I: Integer;
begin
  Mu := 1.0;
  Dt := 0.001;
  Steps := 3000 + (Carrier.Lap mod 4) * 1000;

  { Начальные условия для вытянутой орбиты: скорость меньше круговой. }
  B.X := 1.0;
  B.Y := 0.0;
  B.VX := 0.0;
  B.VY := 0.8 + Double(Carrier.Serial mod 4) * 0.05;

  E0 := OrbitEnergy(B, Mu);
  L0 := OrbitMomentum(B);
  Carrier.Claim(E0 < 0, 'ode: orbit is not bound');

  WorstE := 0;
  WorstL := 0;
  RMin := 1e30;
  RMax := 0;
  for I := 1 to Steps do
  begin
    OrbitStep(B, Mu, Dt);
    if Abs(OrbitEnergy(B, Mu) - E0) > WorstE then
      WorstE := Abs(OrbitEnergy(B, Mu) - E0);
    if Abs(OrbitMomentum(B) - L0) > WorstL then
      WorstL := Abs(OrbitMomentum(B) - L0);
    R := Sqrt(B.X * B.X + B.Y * B.Y);
    if R < RMin then
      RMin := R;
    if R > RMax then
      RMax := R;
  end;

  Carrier.Claim(WorstE < Abs(E0) * 0.02, 'ode: orbit energy drifted');
  Carrier.Claim(WorstL < Abs(L0) * 1e-6, 'ode: angular momentum was not conserved');
  { Тело обязано оставаться связанным: расстояние не уходит в бесконечность и не
    падает в центр. }
  Carrier.Claim(RMax < 100.0, 'ode: orbit escaped');
  Carrier.Claim(RMin > 1e-3, 'ode: orbit fell into the centre');
  Carrier.Feed(UInt64(Cardinal(Steps)));
  Carrier.Feed(UInt64(Round(WorstE * 1e12)));
  Carrier.Feed(UInt64(Round(WorstL * 1e15)));
  Carrier.Feed(UInt64(Round(RMax * 1e6)));
end;

{ Круговая орбита: при точно круговой скорости расстояние обязано оставаться
  постоянным, а полный оборот занимать известное время. }
procedure StageCircular(Carrier: TResidentCarrier);
var
  B: TBody;
  Mu, Dt, R0, R, Worst, Period, Angle0, Angle: Double;
  Steps, I, Crossings: Integer;
  WasPositive: Boolean;
begin
  Mu := 1.0;
  R0 := 1.0 + Double(Carrier.Serial mod 3) * 0.5;
  Dt := 0.0005;

  { Круговая скорость на этом расстоянии. }
  B.X := R0;
  B.Y := 0.0;
  B.VX := 0.0;
  B.VY := Sqrt(Mu / R0);

  { Период по третьему закону: квадрат периода пропорционален кубу расстояния. }
  Period := 2 * Pi * Sqrt(R0 * R0 * R0 / Mu);
  Steps := Round(Period / Dt);

  Worst := 0;
  Crossings := 0;
  WasPositive := B.Y >= 0;
  Angle0 := ArcTan2(B.Y, B.X);
  for I := 1 to Steps do
  begin
    OrbitStep(B, Mu, Dt);
    R := Sqrt(B.X * B.X + B.Y * B.Y);
    if Abs(R - R0) > Worst then
      Worst := Abs(R - R0);
    { Пересечение оси считается для проверки числа оборотов. }
    if (B.Y >= 0) <> WasPositive then
    begin
      Inc(Crossings);
      WasPositive := B.Y >= 0;
    end;
  end;

  { Расстояние обязано остаться тем же: орбита круговая. }
  Carrier.Claim(Worst < R0 * 1e-4, 'ode: circular orbit changed its radius');
  { За период тело обязано вернуться примерно в ту же точку. }
  Angle := ArcTan2(B.Y, B.X);
  Carrier.Claim(Abs(Angle - Angle0) < 0.05,
                'ode: after one period the body is not back');
  { Число пересечений оси в утверждения не идёт: тело стартует ровно на оси, и
    последнее пересечение приходится точно на границу периода — попадёт оно
    внутрь счёта или нет, решает округление, а не правильность кода. Величина
    наблюдается, но приговором не служит. }
  Carrier.Feed(UInt64(Cardinal(Steps)));
  Carrier.Feed(UInt64(Round(Worst * 1e12)));
  Carrier.Feed(UInt64(Cardinal(Crossings)));

  { Зато обязана сохраниться скорость: на круговой орбите она постоянна. }
  Carrier.Claim(Abs(Sqrt(B.VX * B.VX + B.VY * B.VY) - Sqrt(Mu / R0)) <
                Sqrt(Mu / R0) * 1e-4,
                'ode: speed changed on a circular orbit');
end;

{ Движение, продолжающееся между оборотами: тело летит по орбите сотни шагов за
  оборот кольца и переезжает вместе с носителем между потоками. Сохраняющиеся
  величины проверяются на каждом обороте. }
procedure StageRunningOrbit(Carrier: TResidentCarrier);
var
  Pocket: TResidentOdePocket;
  I: Integer;
  E: Double;
begin
  Pocket := Carrier.PocketAs<TResidentOdePocket>('ode-running');
  if Pocket.FSteps = 0 then
  begin
    Pocket.FBody.X := 1.0;
    Pocket.FBody.Y := 0.0;
    Pocket.FBody.VX := 0.0;
    Pocket.FBody.VY := 0.9;
    Pocket.FEnergy0 := OrbitEnergy(Pocket.FBody, 1.0);
  end;

  for I := 1 to 400 do
    OrbitStep(Pocket.FBody, 1.0, 0.001);
  Inc(Pocket.FSteps, 400);

  E := OrbitEnergy(Pocket.FBody, 1.0);
  Carrier.Claim(Abs(E - Pocket.FEnergy0) < Abs(Pocket.FEnergy0) * 0.05,
                'ode: running orbit lost its energy');
  Carrier.Claim(Sqrt(Pocket.FBody.X * Pocket.FBody.X +
                     Pocket.FBody.Y * Pocket.FBody.Y) < 100.0,
                'ode: running orbit escaped');
  Carrier.Feed(UInt64(Pocket.FSteps));
  Carrier.Feed(UInt64(Round(Abs(E - Pocket.FEnergy0) * 1e12)));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
  if Pocket.FSteps > 40000 then
    Pocket.FSteps := 0;
end;

initialization
  ResidentRegisterStage('ode-circular', @StageCircular);
  ResidentRegisterStage('ode-energy-drift', @StageEnergyDrift);
  ResidentRegisterStage('ode-exact-solution', @StageExactSolution);
  ResidentRegisterStage('ode-orbit', @StageOrbit);
  ResidentRegisterStage('ode-reversible', @StageReversible);
  ResidentRegisterStage('ode-running-orbit', @StageRunningOrbit);

end.
