unit resident_maze;

{ Семейство `maze` — поиск с возвратами против волны.

  Один и тот же вопрос — есть ли путь и какой он длины — решается здесь двумя
  способами, у которых нет ничего общего, кроме ответа. Первый идёт вглубь с
  возвратами: рекурсия, отметки посещения, откат при тупике, а найденный выход
  сообщается броском наружу через все кадры разом. Второй разливает волну от
  старта вширь, обычным циклом по очереди, без рекурсии и без исключений.

  Совпадение ответов — сильная проверка. Поиск вглубь нагружает кадры, отметки
  и раскрутку; волна — только память и циклы. Ошибка в кадрах видна как
  расхождение с волной, ошибка в индексной арифметике — как расхождение обоих с
  третьим наблюдением: числом достижимых клеток, которое обе стороны считают
  независимо.

  Лабиринт строится от сида носителя, поэтому каждый оборот — новый; а чтобы
  ответ не зависел от удачи, отдельно строятся заведомо проходимый и заведомо
  закрытый — на них обе стороны обязаны сойтись во мнении заранее известном. }

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

const
  Side = 12;
  Cells = Side * Side;
  Far = 1000000;

type
  TGrid = array[0 .. Cells - 1] of Boolean;   { True — стена }
  TMarks = array[0 .. Cells - 1] of Boolean;
  TDist = array[0 .. Cells - 1] of Integer;

  EMazeFound = class(Exception)
  private
    FSteps: Integer;
  public
    constructor Create(ASteps: Integer); reintroduce;
    property Steps: Integer read FSteps;
  end;

constructor EMazeFound.Create(ASteps: Integer);
begin
  inherited Create('resident: maze found');
  FSteps := ASteps;
end;

{ Стены ставятся от сида, но вход, выход и края коридора остаются свободными:
  лабиринт обязан быть проходимым, иначе проверять нечего. }
procedure BuildGrid(var Grid: TGrid; var State: UInt64; Density: Integer);
var
  I, R, C: Integer;
begin
  for I := 0 to Cells - 1 do
    Grid[I] := Integer(ResidentNext(State) and 15) < Density;

  { Свободный коридор по краю: сверху направо, потом справа вниз. }
  for C := 0 to Side - 1 do
    Grid[C] := False;
  for R := 0 to Side - 1 do
    Grid[R * Side + Side - 1] := False;

  Grid[0] := False;
  Grid[Cells - 1] := False;
end;

{ Волна: расстояние от старта до каждой клетки, обычной очередью. }
procedure Flood(const Grid: TGrid; Start: Integer; var Dist: TDist);
var
  Queue: array[0 .. Cells - 1] of Integer;
  Head, Tail, At_, R, C, Near_, I: Integer;
begin
  for I := 0 to Cells - 1 do
    Dist[I] := Far;
  if Grid[Start] then
    Exit;

  Head := 0;
  Tail := 0;
  Dist[Start] := 0;
  Queue[Tail] := Start;
  Inc(Tail);

  while Head < Tail do
    begin
      At_ := Queue[Head];
      Inc(Head);
      R := At_ div Side;
      C := At_ mod Side;

      for I := 0 to 3 do
        begin
          case I of
            0: if R = 0 then Continue else Near_ := At_ - Side;
            1: if R = Side - 1 then Continue else Near_ := At_ + Side;
            2: if C = 0 then Continue else Near_ := At_ - 1;
          else
            if C = Side - 1 then
              Continue
            else
              Near_ := At_ + 1;
          end;

          if (not Grid[Near_]) and (Dist[Near_] = Far) then
            begin
              Dist[Near_] := Dist[At_] + 1;
              Queue[Tail] := Near_;
              Inc(Tail);
            end;
        end;
    end;
end;

{ Поиск вглубь с возвратами. Найденный выход сообщается броском: он проходит
  через все открытые кадры разом, и отметки при этом обязаны остаться теми,
  какими были на момент находки. }
function Dive(const Grid: TGrid; var Marks: TMarks; At_, Goal, Depth: Integer;
  var Visited: Integer): Boolean;
var
  R, C, I, Near_: Integer;
begin
  Result := False;
  if Marks[At_] or Grid[At_] then
    Exit;

  Marks[At_] := True;
  Inc(Visited);
  if At_ = Goal then
    raise EMazeFound.Create(Depth);

  R := At_ div Side;
  C := At_ mod Side;
  for I := 0 to 3 do
    begin
      case I of
        0: if C = Side - 1 then Continue else Near_ := At_ + 1;
        1: if R = Side - 1 then Continue else Near_ := At_ + Side;
        2: if C = 0 then Continue else Near_ := At_ - 1;
      else
        if R = 0 then
          Continue
        else
          Near_ := At_ - Side;
      end;
      Dive(Grid, Marks, Near_, Goal, Depth + 1, Visited);
    end;
end;

{ Проходимый лабиринт: обе стороны обязаны найти выход и сойтись в том, сколько
  клеток достижимо. }
procedure StageBacktracking(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: TGrid;
  Marks: TMarks;
  Dist: TDist;
  I, Visited, Found, Reach, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap);
  BuildGrid(Grid, State, 4 + Integer(ResidentNext(State) and 3));
  Bad := 0;
  Visited := 0;
  Found := -1;

  for I := 0 to Cells - 1 do
    Marks[I] := False;

  try
    Dive(Grid, Marks, 0, Cells - 1, 0, Visited);
  except
    on E: EMazeFound do
      Found := E.Steps;
  end;

  Flood(Grid, 0, Dist);

  { Обе стороны сходятся в главном: выход достижим. }
  if Found < 0 then Inc(Bad);
  if Dist[Cells - 1] = Far then Inc(Bad);

  { Путь, найденный вглубь, не короче кратчайшего. }
  if (Found >= 0) and (Dist[Cells - 1] <> Far) and (Found < Dist[Cells - 1]) then
    Inc(Bad);

  { Отмеченное поиском — ровно то, до чего дошла волна: до находки поиск
    успевает пройти не дальше достижимого. }
  Reach := 0;
  for I := 0 to Cells - 1 do
    begin
      if Dist[I] <> Far then
        Inc(Reach);
      if Marks[I] and (Dist[I] = Far) then
        Inc(Bad);
    end;
  if Visited > Reach then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Found)));
  Carrier.Feed(UInt64(Cardinal(Reach)));
  Carrier.Feed(UInt64(Cardinal(Visited)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'maze: depth-first search and flood disagree about the way out');
end;

{ Волна обязана быть согласована сама с собой: у каждой достижимой клетки есть
  сосед на единицу ближе, и ни один сосед не дальше чем на единицу. }
procedure StageWaveConsistency(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: TGrid;
  Dist: TDist;
  I, R, C, K, Near_, Bad, Reach: Integer;
  HasCloser: Boolean;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 3 + 1);
  BuildGrid(Grid, State, 4 + Integer(ResidentNext(State) and 3));
  Flood(Grid, 0, Dist);
  Bad := 0;
  Reach := 0;

  for I := 0 to Cells - 1 do
    begin
      if Dist[I] = Far then
        Continue;
      Inc(Reach);
      R := I div Side;
      C := I mod Side;
      HasCloser := I = 0;

      for K := 0 to 3 do
        begin
          case K of
            0: if R = 0 then Continue else Near_ := I - Side;
            1: if R = Side - 1 then Continue else Near_ := I + Side;
            2: if C = 0 then Continue else Near_ := I - 1;
          else
            if C = Side - 1 then
              Continue
            else
              Near_ := I + 1;
          end;

          if Grid[Near_] then
            Continue;

          { Сосед не может быть дальше чем на шаг. }
          if (Dist[Near_] <> Far) and (Abs(Dist[Near_] - Dist[I]) > 1) then
            Inc(Bad);

          { Проходимый сосед достижимой клетки обязан быть достижим. }
          if Dist[Near_] = Far then
            Inc(Bad);

          if Dist[Near_] = Dist[I] - 1 then
            HasCloser := True;
        end;

      { У каждой достижимой клетки, кроме старта, есть шаг назад к старту. }
      if not HasCloser then
        Inc(Bad);
    end;

  Carrier.Feed(UInt64(Cardinal(Reach)));
  Carrier.Feed(UInt64(Cardinal(Dist[Cells - 1])));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Dist[0] = 0, 'maze: the start is not at distance zero from itself');
  Carrier.Claim(Bad = 0, 'maze: flood distances contradict each other');
end;

{ Закрытый выход: обе стороны обязаны сказать «нет», и ни одна не имеет права
  дойти до цели окольным путём. }
procedure StageBlocked(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: TGrid;
  Marks: TMarks;
  Dist: TDist;
  I, Visited, Found, Bad: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 5 + 2);
  BuildGrid(Grid, State, 3);
  Bad := 0;
  Visited := 0;
  Found := -1;

  { Замуровываем цель со всех сторон, оставив её саму свободной. }
  Grid[Cells - 2] := True;
  Grid[Cells - 1 - Side] := True;

  for I := 0 to Cells - 1 do
    Marks[I] := False;

  try
    Dive(Grid, Marks, 0, Cells - 1, 0, Visited);
  except
    on E: EMazeFound do
      Found := E.Steps;
  end;

  Flood(Grid, 0, Dist);

  if Found >= 0 then Inc(Bad);
  if Dist[Cells - 1] <> Far then Inc(Bad);
  if Marks[Cells - 1] then Inc(Bad);

  { А выход из старта в остальную часть поля никуда не делся. }
  if Visited < 2 then Inc(Bad);

  Carrier.Feed(UInt64(Cardinal(Visited)));
  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'maze: a walled-off goal was reached anyway');
end;

{ Лабиринт перестраивается между попытками: состояние поиска обязано
  сбрасываться целиком, иначе прошлая попытка потянет за собой отметки. }
procedure StageRebuild(Carrier: TResidentCarrier);
var
  State: UInt64;
  Grid: TGrid;
  Marks: TMarks;
  Dist: TDist;
  Round_, I, Visited, Found, Bad, Reach: Integer;
  FirstReach: Integer;
begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 7 + 3);
  Bad := 0;
  FirstReach := -1;

  for Round_ := 1 to 4 do
    begin
      BuildGrid(Grid, State, 3 + Integer(ResidentNext(State) and 3));

      for I := 0 to Cells - 1 do
        Marks[I] := False;
      Visited := 0;
      Found := -1;

      try
        Dive(Grid, Marks, 0, Cells - 1, 0, Visited);
      except
        on E: EMazeFound do
          Found := E.Steps;
      end;

      Flood(Grid, 0, Dist);

      Reach := 0;
      for I := 0 to Cells - 1 do
        if Dist[I] <> Far then
          Inc(Reach);

      { Ответы двух сторон согласованы на каждом круге. }
      if (Found >= 0) <> (Dist[Cells - 1] <> Far) then
        Inc(Bad);
      if Visited > Reach then
        Inc(Bad);

      { Отметки не пережили сброс: посещено не больше, чем достижимо. }
      if Round_ = 1 then
        FirstReach := Reach;

      Carrier.Feed(UInt64(Cardinal(Reach)));
      Carrier.Feed(UInt64(Cardinal(Visited)));
    end;

  Carrier.Feed(UInt64(Cardinal(Bad)));
  Carrier.Claim(Bad = 0, 'maze: state leaked between rebuilds');
  Carrier.Claim(FirstReach > 0, 'maze: nothing was reachable on the first round');
end;

{ Число путей ограниченной длины: считается рекурсией с возвратами и
  раскладкой по шагам. Разные машины, один ответ. }
procedure StageCountPaths(Carrier: TResidentCarrier);
const
  Small = 5;
  SmallCells = Small * Small;
  Limit = 8;
var
  State: UInt64;
  Wall: array[0 .. SmallCells - 1] of Boolean;
  Ways: array[0 .. Limit, 0 .. SmallCells - 1] of Int64;
  I, K, R, C, Near_, Step: Integer;
  ByRecursion, ByLayers: Int64;

  function Count(At_, Left: Integer): Int64;
  var
    RR, CC, J, Next_: Integer;
  begin
    if Wall[At_] then
      Exit(0);
    if At_ = SmallCells - 1 then
      Exit(1);
    if Left = 0 then
      Exit(0);

    Result := 0;
    RR := At_ div Small;
    CC := At_ mod Small;
    for J := 0 to 1 do
      begin
        if J = 0 then
          begin
            if CC = Small - 1 then
              Continue;
            Next_ := At_ + 1;
          end
        else
          begin
            if RR = Small - 1 then
              Continue;
            Next_ := At_ + Small;
          end;
        Result := Result + Count(Next_, Left - 1);
      end;
  end;

begin
  State := Carrier.Seed xor UInt64(Carrier.Lap * 11 + 5);
  for I := 0 to SmallCells - 1 do
    Wall[I] := Integer(ResidentNext(State) and 15) < 3;
  Wall[0] := False;
  Wall[SmallCells - 1] := False;

  ByRecursion := Count(0, Limit);

  { Раскладка по шагам: сколько путей длины ровно K доходит до каждой клетки.
    Ходы те же — вправо и вниз. }
  for K := 0 to Limit do
    for I := 0 to SmallCells - 1 do
      Ways[K, I] := 0;
  if not Wall[0] then
    Ways[0, 0] := 1;

  for Step := 0 to Limit - 1 do
    for I := 0 to SmallCells - 1 do
      begin
        if (Ways[Step, I] = 0) or Wall[I] or (I = SmallCells - 1) then
          Continue;
        R := I div Small;
        C := I mod Small;
        if C < Small - 1 then
          begin
            Near_ := I + 1;
            if not Wall[Near_] then
              Ways[Step + 1, Near_] := Ways[Step + 1, Near_] + Ways[Step, I];
          end;
        if R < Small - 1 then
          begin
            Near_ := I + Small;
            if not Wall[Near_] then
              Ways[Step + 1, Near_] := Ways[Step + 1, Near_] + Ways[Step, I];
          end;
      end;

  ByLayers := 0;
  for K := 0 to Limit do
    ByLayers := ByLayers + Ways[K, SmallCells - 1];

  Carrier.Feed(UInt64(ByRecursion));
  Carrier.Feed(UInt64(ByLayers));
  Carrier.Claim(ByRecursion = ByLayers, 'maze: recursive path count disagrees with the layered one');
end;

initialization
  ResidentRegisterStage('maze-backtracking', @StageBacktracking);
  ResidentRegisterStage('maze-blocked', @StageBlocked);
  ResidentRegisterStage('maze-count-paths', @StageCountPaths);
  ResidentRegisterStage('maze-rebuild', @StageRebuild);
  ResidentRegisterStage('maze-wave-consistency', @StageWaveConsistency);

end.
