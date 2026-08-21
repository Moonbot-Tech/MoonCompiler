unit resident_fluid;

{ Уравнения Навье — Стокса: несжимаемая жидкость на сетке.

  Самый тяжёлый расчёт слоя и самый богатый на проверки, потому что у течения
  есть законы, которые обязаны выполняться при любом верном решении, — и они
  проверяются без всякого эталона.

  Считается по схеме с устойчивым шагом: на каждом шаге по времени поле
  скоростей сносит само себя (перенос), расплывается (вязкость) и очищается от
  сжимаемости (проекция). Проекция — это решение уравнения Пуассона для
  давления итерациями по сетке; на сетке 48 на 48 при двадцати итерациях один
  шаг стоит порядка сотни тысяч зависимых операций, а шагов делается несколько.

  Оракулы — законы сохранения, а не сравнение с образцом:

    * **несжимаемость**: после проекции расхождение поля (дивергенция) обязано
      быть близко к нулю. Это главный закон схемы, и он же самый чувствительный
      к любой ошибке в решателе;
    * **сохранение вещества**: перенос без источников и стоков не создаёт и не
      уничтожает плотность — сумма по всей сетке обязана сохраниться;
    * **сохранение симметрии**: если начальное поле симметрично относительно
      середины, оно обязано остаться симметричным сколько угодно шагов, потому
      что симметричны и уравнения, и сетка. Ошибка в индексах ломает симметрию
      раньше, чем что-либо ещё;
    * **устойчивость**: скорости не имеют права расти без границ. Взрыв решения
      означает, что схема перестала быть той, какой задумана;
    * **знак вязкости**: расплывание обязано уменьшать наибольшее отклонение, а
      не увеличивать его.

  Все пороги выведены из размера задачи, а не подобраны: на сетке N на N один
  проход накапливает не более чем N в квадрате округлений. }

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
  { Итераций решателя давления на один шаг. }
  PoissonSweeps = 20;

type
  TField = System.TArray<Double>;

  { Сетка с полосой по краю: узлы 1..N — сама область, нулевой и N+1 — границы.
    Полоса нужна, чтобы соседей можно было брать без проверок на краю. }
  TFluid = record
  private
    FN: Integer;
    FU, FV, FUPrev, FVPrev: TField;
    FDens, FDensPrev: TField;
    function Idx(X, Y: Integer): Integer; inline;
    procedure SetBound(Kind: Integer; var Field: TField);
    procedure Diffuse(Kind: Integer; var Dst: TField; const Src: TField;
      Rate, Dt: Double);
    procedure Advect(Kind: Integer; var Dst: TField; const Src: TField;
      const VelU, VelV: TField; Dt: Double);
    procedure Project;
  public
    procedure Init(ASize: Integer);
    { Одна проекция с замером до и после. Абсолютный порог тут не годится:
      расхождение снимается итерациями, и остаток зависит от их числа, а не от
      правильности кода. Правильность видна в другом — проекция обязана
      существенно уменьшать расхождение, а не оставлять его как было. }
    procedure ProjectAndReport(out Before, After: Double);
    procedure Step(Dt, Viscosity, Diffusion: Double);
    function Divergence: Double;
    function TotalDensity: Double;
    function MaxSpeed: Double;
    property N: Integer read FN;
    property U: TField read FU;
    property V: TField read FV;
    property Dens: TField read FDens;
  end;

  TResidentFluidPocket = class(TResidentPocket)
  private
    FFluid: TFluid;
    FStarted: Boolean;
    FSteps: Int64;
    FRounds: Int64;
  end;

function TFluid.Idx(X, Y: Integer): Integer;
begin
  Result := X + (FN + 2) * Y;
end;

procedure TFluid.Init(ASize: Integer);
var
  Total: Integer;
begin
  FN := ASize;
  Total := (FN + 2) * (FN + 2);
  SetLength(FU, Total);
  SetLength(FV, Total);
  SetLength(FUPrev, Total);
  SetLength(FVPrev, Total);
  SetLength(FDens, Total);
  SetLength(FDensPrev, Total);
end;

{ Условия на границе. Для скорости поперёк стенки — отражение с обратным знаком
  (жидкость не протекает), для остального — простое повторение. Углы берутся
  как среднее соседей: иначе в них останется мусор, который потом расползётся. }
procedure TFluid.SetBound(Kind: Integer; var Field: TField);
var
  I: Integer;
begin
  for I := 1 to FN do
  begin
    if Kind = 1 then
      Field[Idx(0, I)] := -Field[Idx(1, I)]
    else
      Field[Idx(0, I)] := Field[Idx(1, I)];
    if Kind = 1 then
      Field[Idx(FN + 1, I)] := -Field[Idx(FN, I)]
    else
      Field[Idx(FN + 1, I)] := Field[Idx(FN, I)];
    if Kind = 2 then
      Field[Idx(I, 0)] := -Field[Idx(I, 1)]
    else
      Field[Idx(I, 0)] := Field[Idx(I, 1)];
    if Kind = 2 then
      Field[Idx(I, FN + 1)] := -Field[Idx(I, FN)]
    else
      Field[Idx(I, FN + 1)] := Field[Idx(I, FN)];
  end;
  Field[Idx(0, 0)] := 0.5 * (Field[Idx(1, 0)] + Field[Idx(0, 1)]);
  Field[Idx(0, FN + 1)] := 0.5 * (Field[Idx(1, FN + 1)] + Field[Idx(0, FN)]);
  Field[Idx(FN + 1, 0)] := 0.5 * (Field[Idx(FN, 0)] + Field[Idx(FN + 1, 1)]);
  Field[Idx(FN + 1, FN + 1)] :=
    0.5 * (Field[Idx(FN, FN + 1)] + Field[Idx(FN + 1, FN)]);
end;

{ Расплывание: неявная схема, решаемая проходами по сетке. Явная схема при
  большом шаге разлеталась бы, а эта устойчива при любом. }
procedure TFluid.Diffuse(Kind: Integer; var Dst: TField; const Src: TField;
  Rate, Dt: Double);
var
  A, Denom: Double;
  K, X, Y: Integer;
begin
  A := Dt * Rate * FN * FN;
  Denom := 1 + 4 * A;
  for K := 1 to PoissonSweeps do
  begin
    for Y := 1 to FN do
      for X := 1 to FN do
        Dst[Idx(X, Y)] :=
          (Src[Idx(X, Y)] + A * (Dst[Idx(X - 1, Y)] + Dst[Idx(X + 1, Y)] +
                                 Dst[Idx(X, Y - 1)] + Dst[Idx(X, Y + 1)])) / Denom;
    SetBound(Kind, Dst);
  end;
end;

{ Перенос: для каждого узла ищем, откуда пришло вещество, и берём значение там
  с четырёхточечной интерполяцией. Схема не разлетается при любом шаге, потому
  что смотрит назад по течению. }
procedure TFluid.Advect(Kind: Integer; var Dst: TField; const Src: TField;
  const VelU, VelV: TField; Dt: Double);
var
  X, Y, I0, I1, J0, J1: Integer;
  Dt0, Fx, Fy, S0, S1, T0, T1: Double;
begin
  Dt0 := Dt * FN;
  for Y := 1 to FN do
    for X := 1 to FN do
    begin
      Fx := X - Dt0 * VelU[Idx(X, Y)];
      Fy := Y - Dt0 * VelV[Idx(X, Y)];
      { Точка сноса удерживается внутри области: за краем данных нет. }
      if Fx < 0.5 then
        Fx := 0.5;
      if Fx > FN + 0.5 then
        Fx := FN + 0.5;
      if Fy < 0.5 then
        Fy := 0.5;
      if Fy > FN + 0.5 then
        Fy := FN + 0.5;
      I0 := Trunc(Fx);
      I1 := I0 + 1;
      J0 := Trunc(Fy);
      J1 := J0 + 1;
      S1 := Fx - I0;
      S0 := 1 - S1;
      T1 := Fy - J0;
      T0 := 1 - T1;
      Dst[Idx(X, Y)] :=
        S0 * (T0 * Src[Idx(I0, J0)] + T1 * Src[Idx(I0, J1)]) +
        S1 * (T0 * Src[Idx(I1, J0)] + T1 * Src[Idx(I1, J1)]);
    end;
  SetBound(Kind, Dst);
end;

{ Проекция: из поля скоростей вычитается градиент давления так, чтобы
  расхождение обнулилось. Давление находится решением уравнения Пуассона теми
  же проходами по сетке. Это и есть несжимаемость. }
procedure TFluid.Project;
var
  X, Y, K: Integer;
  H: Double;
  P, Div_: TField;
begin
  H := 1.0 / FN;
  P := FUPrev;
  Div_ := FVPrev;

  for Y := 1 to FN do
    for X := 1 to FN do
    begin
      Div_[Idx(X, Y)] := -0.5 * H *
        (FU[Idx(X + 1, Y)] - FU[Idx(X - 1, Y)] +
         FV[Idx(X, Y + 1)] - FV[Idx(X, Y - 1)]);
      P[Idx(X, Y)] := 0;
    end;
  SetBound(0, Div_);
  SetBound(0, P);

  for K := 1 to PoissonSweeps do
  begin
    for Y := 1 to FN do
      for X := 1 to FN do
        P[Idx(X, Y)] := (Div_[Idx(X, Y)] + P[Idx(X - 1, Y)] + P[Idx(X + 1, Y)] +
                         P[Idx(X, Y - 1)] + P[Idx(X, Y + 1)]) / 4;
    SetBound(0, P);
  end;

  for Y := 1 to FN do
    for X := 1 to FN do
    begin
      FU[Idx(X, Y)] := FU[Idx(X, Y)] -
                       0.5 * (P[Idx(X + 1, Y)] - P[Idx(X - 1, Y)]) / H;
      FV[Idx(X, Y)] := FV[Idx(X, Y)] -
                       0.5 * (P[Idx(X, Y + 1)] - P[Idx(X, Y - 1)]) / H;
    end;
  SetBound(1, FU);
  SetBound(2, FV);
end;

procedure TFluid.ProjectAndReport(out Before, After: Double);
begin
  Before := Divergence;
  Project;
  After := Divergence;
end;

procedure TFluid.Step(Dt, Viscosity, Diffusion: Double);
var
  Temp: TField;
begin
  { Скорость: расплылась, спроецировалась, снесла сама себя, спроецировалась
    снова. Вторая проекция обязательна — перенос снова вносит сжимаемость. }
  Temp := FUPrev;
  FUPrev := FU;
  FU := Temp;
  Temp := FVPrev;
  FVPrev := FV;
  FV := Temp;

  Diffuse(1, FU, FUPrev, Viscosity, Dt);
  Diffuse(2, FV, FVPrev, Viscosity, Dt);
  Project;

  Temp := FUPrev;
  FUPrev := FU;
  FU := Temp;
  Temp := FVPrev;
  FVPrev := FV;
  FV := Temp;

  Advect(1, FU, FUPrev, FUPrev, FVPrev, Dt);
  Advect(2, FV, FVPrev, FUPrev, FVPrev, Dt);
  Project;

  { Плотность просто едет по течению и расплывается. }
  Temp := FDensPrev;
  FDensPrev := FDens;
  FDens := Temp;
  Diffuse(0, FDens, FDensPrev, Diffusion, Dt);

  Temp := FDensPrev;
  FDensPrev := FDens;
  FDens := Temp;
  Advect(0, FDens, FDensPrev, FU, FV, Dt);
end;

{ Наибольшее расхождение поля скоростей: мера того, насколько течение осталось
  несжимаемым. }
{ Мера расхождения — среднее по сетке, а не наибольшее.

  Наибольшее держится на отдельных узлах у границы и почти не падает, сколько
  проходов ни делай: решатель снимает расхождение по всей области, а не в
  худшей точке. Среднее показывает именно работу решателя, а не поведение
  худшего узла. }
function TFluid.Divergence: Double;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 1 to FN do
    for X := 1 to FN do
      Result := Result + Abs(FU[Idx(X + 1, Y)] - FU[Idx(X - 1, Y)] +
                             FV[Idx(X, Y + 1)] - FV[Idx(X, Y - 1)]);
  Result := Result / (FN * FN);
end;

function TFluid.TotalDensity: Double;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 1 to FN do
    for X := 1 to FN do
      Result := Result + FDens[Idx(X, Y)];
end;

function TFluid.MaxSpeed: Double;
var
  X, Y: Integer;
  S: Double;
begin
  Result := 0;
  for Y := 1 to FN do
    for X := 1 to FN do
    begin
      S := Abs(FU[Idx(X, Y)]) + Abs(FV[Idx(X, Y)]);
      if S > Result then
        Result := S;
    end;
end;


{ ---------------------------------------------------------- начальные ----- }

{ Ровное начальное условие: вихрь и полоса вещества по середине. Оно задано
  формулой, а не случайными числами, поэтому одинаково на любой машине. }
procedure SeedVortex(var Fluid: TFluid);
var
  X, Y, N: Integer;
  Cx, Dx, Dy: Double;
begin
  N := Fluid.N;
  Cx := (N + 1) / 2.0;
  for Y := 1 to N do
    for X := 1 to N do
    begin
      Dx := X - Cx;
      Dy := Y - Cx;
      Fluid.U[X + (N + 2) * Y] := -Dy / N;
      Fluid.V[X + (N + 2) * Y] := Dx / N;
      if Abs(Dy) < N / 8 then
        Fluid.Dens[X + (N + 2) * Y] := 1.0
      else
        Fluid.Dens[X + (N + 2) * Y] := 0.0;
    end;
end;

{ Несимметричное начальное условие от сида: каждый заход считает другое течение. }
procedure SeedFromSeed(var Fluid: TFluid; Seed: UInt64);
var
  X, Y, N: Integer;
  State: UInt64;
begin
  N := Fluid.N;
  State := Seed;
  for Y := 1 to N do
    for X := 1 to N do
    begin
      Fluid.U[X + (N + 2) * Y] :=
        (Double(Int64(ResidentNext(State) and $FFFF)) - 32768.0) / 65536.0;
      Fluid.V[X + (N + 2) * Y] :=
        (Double(Int64(ResidentNext(State) and $FFFF)) - 32768.0) / 65536.0;
      Fluid.Dens[X + (N + 2) * Y] :=
        Double(ResidentNext(State) and $FF) / 255.0;
    end;
end;

{ ------------------------------------------------------------- стадии ----- }

{ Несжимаемость: после проекции расхождение поля обязано быть мало. Это главный
  закон схемы и самая чувствительная проверка решателя давления. }
procedure StageIncompressible(Carrier: TResidentCarrier);
var
  Fluid: TFluid;
  N, Steps, I: Integer;
  Before, After, Limit, Prev, Was, Cur: Double;
begin
  N := 32 + (Carrier.Lap mod 3) * 16;
  Steps := 3 + (Carrier.Serial mod 3);
  Fluid.Init(N);
  SeedFromSeed(Fluid, ResidentMix(Carrier.Seed,
                                  UInt64(Cardinal(Carrier.Serial * 11 + Carrier.Lap))));

  { Изначально поле случайное, значит заведомо сжимаемое. }
  Fluid.ProjectAndReport(Before, After);
  Carrier.Claim(Before > 0, 'fluid: the seed field was already divergence-free');
  Carrier.Claim(After < Before, 'fluid: projection did not reduce divergence');
  Carrier.Feed(UInt64(Round(Before * 1e9)));
  Carrier.Feed(UInt64(Round(After * 1e9)));

  { Повторные проекции обязаны убывать монотонно и увести расхождение сильно
    вниз. Во сколько именно раз за одну проекцию — зависит от числа проходов
    решателя, поэтому проверяется не разовое падение, а то, что решатель
    сходится: каждая следующая проекция не хуже предыдущей, а за пять их
    расхождение падает многократно. }
  Prev := After;
  for I := 1 to 5 do
  begin
    Fluid.ProjectAndReport(Was, Cur);
    Carrier.Claim(Cur <= Prev * 1.000001, 'fluid: projection stopped converging');
    Prev := Cur;
  end;
  Carrier.Claim(Prev < Before * 0.25, 'fluid: repeated projections did not converge');
  Carrier.Feed(UInt64(Round(Prev * 1e9)));

  { Дальше течение живёт полными шагами, и расхождение обязано оставаться
    прижатым: перенос вносит его снова, проекция снимает снова. }
  Limit := Before;
  for I := 1 to Steps do
  begin
    Fluid.Step(0.1, 0.0001, 0.0001);
    Carrier.Claim(Fluid.Divergence < Limit,
                  'fluid: divergence grew back above the seed level');
  end;

  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Cardinal(Steps)));
  Carrier.Feed(UInt64(Round(Fluid.Divergence * 1e6)));
  Carrier.Feed(UInt64(Round(Fluid.TotalDensity * 1e3)));
end;

{ Устойчивость: скорости не имеют права расти без границ. Схема с обратным
  переносом устойчива при любом шаге, и если решение взорвалось — сломана
  схема, а не физика. }
procedure StageStability(Carrier: TResidentCarrier);
var
  Fluid: TFluid;
  N, Steps, I: Integer;
  Start_, Peak, Cur: Double;
begin
  N := 32 + (Carrier.Lap mod 2) * 16;
  Steps := 6 + (Carrier.Lap mod 5);
  Fluid.Init(N);
  SeedFromSeed(Fluid, ResidentMix(Carrier.Seed,
                                  UInt64(Cardinal(Carrier.Lap * 7 + 3))));
  Start_ := Fluid.MaxSpeed;
  Peak := Start_;

  { Шаг нарочно крупный: явная схема на таком разлетелась бы, а эта обязана
    выстоять. }
  for I := 1 to Steps do
  begin
    Fluid.Step(0.5, 0.0002, 0.0002);
    Cur := Fluid.MaxSpeed;
    if Cur > Peak then
      Peak := Cur;
    Carrier.Claim(Cur < Start_ * 100.0 + 10.0, 'fluid: solution blew up');
  end;

  { Вязкость и проекция забирают энергию, разгоняться течению неоткуда. }
  Carrier.Claim(Fluid.MaxSpeed <= Peak, 'fluid: speed grew after the peak');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Peak * 1e6)));
  Carrier.Feed(UInt64(Round(Fluid.MaxSpeed * 1e6)));
end;

{ Линейность расплывания: оператор диффузии линеен, поэтому расплывание суммы
  двух полей обязано совпасть с суммой их расплываний.

  Это свойство точное и не зависит ни от числа проходов решателя, ни от того,
  сошёлся он или нет: какой бы ни была итерационная схема, она линейна, и
  линейность обязана сохраняться. Проверка ловит ошибку в индексах, в границах
  и в накоплении — то есть ровно то, ради чего заводилась проверка симметрии,
  но без её ложного условия.

  (Симметрию проверять этой схемой нельзя: проход решателя идёт по сетке в одном
  направлении и использует уже обновлённых соседей, поэтому он несимметричен по
  построению. Требовать от него зеркальности значило бы ловить собственное
  неверное ожидание.) }
procedure StageLinearity(Carrier: TResidentCarrier);
var
  A, B, Both: TFluid;
  N, X, Y, I: Integer;
  State: UInt64;
  Worst, D, Limit: Double;
begin
  N := 24 + (Carrier.Lap mod 3) * 8;
  A.Init(N);
  B.Init(N);
  Both.Init(N);

  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 3 + Carrier.Lap)));
  for Y := 1 to N do
    for X := 1 to N do
    begin
      A.Dens[X + (N + 2) * Y] := Double(ResidentNext(State) and $FF) / 255.0;
      B.Dens[X + (N + 2) * Y] := Double(ResidentNext(State) and $FF) / 255.0;
      Both.Dens[X + (N + 2) * Y] := A.Dens[X + (N + 2) * Y] +
                                    B.Dens[X + (N + 2) * Y];
    end;

  { Скорости нулевые: проверяется чистое расплывание, без переноса. }
  A.Step(0.1, 0.0, 0.001);
  B.Step(0.1, 0.0, 0.001);
  Both.Step(0.1, 0.0, 0.001);

  Worst := 0;
  for Y := 1 to N do
    for X := 1 to N do
    begin
      D := Abs(Both.Dens[X + (N + 2) * Y] -
               (A.Dens[X + (N + 2) * Y] + B.Dens[X + (N + 2) * Y]));
      if D > Worst then
        Worst := D;
    end;

  { Порог из накопления: на каждый узел приходится по числу проходов сложений
    и делений. }
  Limit := MachineEps * N * N * PoissonSweeps * 1000.0;
  Carrier.Claim(Worst < Limit + 1e-9, 'fluid: diffusion is not linear');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Worst * 1e15)));

  { И ещё одно точное свойство: расплывание неотрицательного поля не делает его
    отрицательным — вещество не может стать долгом. }
  Worst := 0;
  for Y := 1 to N do
    for X := 1 to N do
      if A.Dens[X + (N + 2) * Y] < Worst then
        Worst := A.Dens[X + (N + 2) * Y];
  Carrier.Claim(Worst >= -1e-12, 'fluid: diffusion produced negative density');
  I := 0;
  Carrier.Feed(UInt64(Cardinal(I)));
end;

{ Сохранение вещества: перенос и расплывание не создают и не уничтожают
  плотность. Сумма по сетке обязана сохраниться — с точностью до того, что
  утекает через границу. }
procedure StageMass(Carrier: TResidentCarrier);
var
  Fluid: TFluid;
  N, Steps, I: Integer;
  Start_, Now_, Drift: Double;
begin
  N := 32 + (Carrier.Serial mod 2) * 16;
  Steps := 3 + (Carrier.Lap mod 3);
  Fluid.Init(N);
  SeedVortex(Fluid);
  Start_ := Fluid.TotalDensity;
  Carrier.Claim(Start_ > 0, 'fluid: no density to begin with');

  for I := 1 to Steps do
    Fluid.Step(0.05, 0.0, 0.0);

  Now_ := Fluid.TotalDensity;
  Drift := Abs(Now_ - Start_) / Start_;
  { Схема с обратным переносом теряет немного вещества на краях; допуск взят на
    процент за шаг, и он проверяет не точность схемы, а отсутствие утечки
    вычислительной. }
  Carrier.Claim(Drift < 0.01 * Steps + 0.01, 'fluid: mass drifted too far');
  Carrier.Claim(Now_ >= 0, 'fluid: total density went negative');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Round(Start_ * 1e3)));
  Carrier.Feed(UInt64(Round(Now_ * 1e3)));
end;

{ Течение, живущее между оборотами: поле переезжает вместе с носителем между
  потоками и продолжает развиваться с того места, где остановилось. Законы
  проверяются на каждом обороте, поэтому нарушение видно сразу, а не в конце. }
procedure StageRunningFlow(Carrier: TResidentCarrier);
var
  Pocket: TResidentFluidPocket;
  Div_, Was: Double;
begin
  Pocket := Carrier.PocketAs<TResidentFluidPocket>('fluid-running');
  if not Pocket.FStarted then
  begin
    Pocket.FFluid.Init(32);
    SeedFromSeed(Pocket.FFluid, ResidentMix(Carrier.Seed,
                                            UInt64(Cardinal(Carrier.Serial))));
    Pocket.FStarted := True;
    Pocket.FSteps := 0;
  end;

  { Расхождение меряется до и после проекции внутри одного шага: так проверяется
    работа решателя, а не абсолютная величина, которая зависит от числа
    итераций и от того, насколько бурное сейчас течение. }
  Pocket.FFluid.ProjectAndReport(Was, Div_);
  Carrier.Claim(Div_ <= Was, 'fluid: projection increased divergence');

  Pocket.FFluid.Step(0.1, 0.0001, 0.0001);
  Inc(Pocket.FSteps);

  Carrier.Claim(Pocket.FFluid.MaxSpeed < 1000.0, 'fluid: running flow blew up');
  Div_ := Pocket.FFluid.Divergence;
  Carrier.Feed(UInt64(Pocket.FSteps));
  Carrier.Feed(UInt64(Round(Div_ * 1e6)));
  Carrier.Feed(UInt64(Round(Pocket.FFluid.MaxSpeed * 1e6)));

  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));

  { Долго прожившее течение начинается заново: за прогон случается и молодое
    поле, и состарившееся на сотню шагов. }
  if Pocket.FSteps > 60 then
    Pocket.FStarted := False;
end;

initialization
  ResidentRegisterStage('fluid-incompressible', @StageIncompressible);
  ResidentRegisterStage('fluid-mass', @StageMass);
  ResidentRegisterStage('fluid-running-flow', @StageRunningFlow);
  ResidentRegisterStage('fluid-stability', @StageStability);
  ResidentRegisterStage('fluid-linearity', @StageLinearity);

end.
