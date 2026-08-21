unit resident_algo;

{ Графы и сортировки — плоскость с самым сильным видом оракула, какой вообще
  бывает: **два разных алгоритма обязаны дать один ответ**.

  Это лучше эталона. Эталон говорит «должно быть так», и если он ошибочен,
  ошибка тихо закрепляется. А два независимых пути к одному ответу проверяют
  друг друга: совпали — почти наверняка оба правы, разошлись — виноват кто-то
  один, и это видно сразу.

  Пары здесь такие:

    * кратчайшие пути — по возрастанию расстояния против последовательного
      ослабления рёбер против попарного обхода через промежуточные вершины: три
      разных способа, один ответ;
    * остовное дерево наименьшего веса — наращиванием от вершины против
      слияния множеств по возрастанию веса;
    * сортировка — быстрая против слияния против пирамидальной против вставок:
      четыре разных способа, одна перестановка.

  Сверх того у каждой задачи есть свои проверяемые свойства: у кратчайших путей
  — условие оптимальности на каждом ребре, у остовного дерева — связность и
  число рёбер, у сортировки — сохранение состава. }

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
  Far_ = High(Int64) div 4;

type
  TEdge = record
    A, B: Integer;
    Weight: Int64;
  end;

  TGraph = record
    Count: Integer;
    Edges: System.TArray<TEdge>;
    Matrix: System.TArray<System.TArray<Int64>>;
  end;

  TResidentAlgoPocket = class(TResidentPocket)
  private
    FTotal: Int64;
    FRounds: Int64;
  end;

{ Связный граф со случайными весами: сначала остов, чтобы связность была
  гарантирована, потом лишние рёбра. }
function MakeGraph(Carrier: TResidentCarrier; N, Extra: Integer): TGraph;
var
  State: UInt64;
  I, J, A, B: Integer;
  W: Int64;

  procedure AddEdge(P, Q: Integer; Weight: Int64);
  begin
    SetLength(Result.Edges, Length(Result.Edges) + 1);
    Result.Edges[High(Result.Edges)].A := P;
    Result.Edges[High(Result.Edges)].B := Q;
    Result.Edges[High(Result.Edges)].Weight := Weight;
    if Weight < Result.Matrix[P][Q] then
    begin
      Result.Matrix[P][Q] := Weight;
      Result.Matrix[Q][P] := Weight;
    end;
  end;

begin
  Result.Count := N;
  SetLength(Result.Edges, 0);
  SetLength(Result.Matrix, N);
  for I := 0 to N - 1 do
  begin
    SetLength(Result.Matrix[I], N);
    for J := 0 to N - 1 do
      if I = J then
        Result.Matrix[I][J] := 0
      else
        Result.Matrix[I][J] := Far_;
  end;

  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 71 + Carrier.Lap)));
  { Остов: каждая следующая вершина цепляется к какой-то из предыдущих. }
  for I := 1 to N - 1 do
  begin
    A := Integer(ResidentNext(State) mod UInt64(I));
    W := Int64(ResidentNext(State) mod 100) + 1;
    AddEdge(A, I, W);
  end;

  for I := 1 to Extra do
  begin
    A := Integer(ResidentNext(State) mod UInt64(N));
    B := Integer(ResidentNext(State) mod UInt64(N));
    if A <> B then
    begin
      W := Int64(ResidentNext(State) mod 100) + 1;
      AddEdge(A, B, W);
    end;
  end;
end;

{ Кратчайшие пути по возрастанию расстояния: на каждом шаге забирается ближайшая
  ещё не обработанная вершина. Выбор перебором — медленно, зато без кучи. }
function ShortestByNearest(const G: TGraph; From_: Integer): System.TArray<Int64>;
var
  Done: System.TArray<Boolean>;
  I, J, Best: Integer;
begin
  SetLength(Result, G.Count);
  SetLength(Done, G.Count);
  for I := 0 to G.Count - 1 do
    Result[I] := Far_;
  Result[From_] := 0;

  for I := 0 to G.Count - 1 do
  begin
    Best := -1;
    for J := 0 to G.Count - 1 do
      if not Done[J] and ((Best < 0) or (Result[J] < Result[Best])) then
        Best := J;
    if (Best < 0) or (Result[Best] >= Far_) then
      Break;
    Done[Best] := True;
    for J := 0 to G.Count - 1 do
      if G.Matrix[Best][J] < Far_ then
        if Result[Best] + G.Matrix[Best][J] < Result[J] then
          Result[J] := Result[Best] + G.Matrix[Best][J];
  end;
end;

{ Тот же ответ последовательным ослаблением рёбер: столько проходов, сколько
  вершин без одной. }
function ShortestByRelax(const G: TGraph; From_: Integer): System.TArray<Int64>;
var
  I, K, E: Integer;
  Changed: Boolean;
begin
  SetLength(Result, G.Count);
  for I := 0 to G.Count - 1 do
    Result[I] := Far_;
  Result[From_] := 0;

  for K := 1 to G.Count - 1 do
  begin
    Changed := False;
    for E := 0 to High(G.Edges) do
    begin
      if Result[G.Edges[E].A] < Far_ then
        if Result[G.Edges[E].A] + G.Edges[E].Weight < Result[G.Edges[E].B] then
        begin
          Result[G.Edges[E].B] := Result[G.Edges[E].A] + G.Edges[E].Weight;
          Changed := True;
        end;
      if Result[G.Edges[E].B] < Far_ then
        if Result[G.Edges[E].B] + G.Edges[E].Weight < Result[G.Edges[E].A] then
        begin
          Result[G.Edges[E].A] := Result[G.Edges[E].B] + G.Edges[E].Weight;
          Changed := True;
        end;
    end;
    if not Changed then
      Break;
  end;
end;

{ И третий способ: расстояния между всеми парами через промежуточные вершины. }
function ShortestByPairs(const G: TGraph): System.TArray<System.TArray<Int64>>;
var
  I, J, K: Integer;
begin
  SetLength(Result, G.Count);
  for I := 0 to G.Count - 1 do
    Result[I] := System.Copy(G.Matrix[I], 0, G.Count);
  for K := 0 to G.Count - 1 do
    for I := 0 to G.Count - 1 do
      for J := 0 to G.Count - 1 do
        if (Result[I][K] < Far_) and (Result[K][J] < Far_) then
          if Result[I][K] + Result[K][J] < Result[I][J] then
            Result[I][J] := Result[I][K] + Result[K][J];
end;

{ Остовное дерево наращиванием от вершины. }
function SpanByGrowth(const G: TGraph; out Edges: Integer): Int64;
var
  InTree: System.TArray<Boolean>;
  Best: System.TArray<Int64>;
  I, J, Pick: Integer;
begin
  SetLength(InTree, G.Count);
  SetLength(Best, G.Count);
  for I := 0 to G.Count - 1 do
    Best[I] := Far_;
  Best[0] := 0;
  Result := 0;
  Edges := 0;

  for I := 0 to G.Count - 1 do
  begin
    Pick := -1;
    for J := 0 to G.Count - 1 do
      if not InTree[J] and ((Pick < 0) or (Best[J] < Best[Pick])) then
        Pick := J;
    if (Pick < 0) or (Best[Pick] >= Far_) then
      Break;
    InTree[Pick] := True;
    Result := Result + Best[Pick];
    if Best[Pick] > 0 then
      Inc(Edges);
    for J := 0 to G.Count - 1 do
      if not InTree[J] and (G.Matrix[Pick][J] < Best[J]) then
        Best[J] := G.Matrix[Pick][J];
  end;
end;

{ Он же слиянием множеств по возрастанию веса. }
function SpanByMerge(const G: TGraph; out Edges: Integer): Int64;
var
  Parent: System.TArray<Integer>;
  Order: System.TArray<Integer>;
  I, J, Tmp, RootA, RootB: Integer;

  function Find(V: Integer): Integer;
  begin
    while Parent[V] <> V do
      V := Parent[V];
    Result := V;
  end;

begin
  SetLength(Parent, G.Count);
  for I := 0 to G.Count - 1 do
    Parent[I] := I;

  SetLength(Order, Length(G.Edges));
  for I := 0 to High(Order) do
    Order[I] := I;
  { Пузырьком по весу: порядок равных весов не важен, вес дерева от него не
    зависит. }
  for I := 0 to High(Order) - 1 do
    for J := 0 to High(Order) - 1 - I do
      if G.Edges[Order[J]].Weight > G.Edges[Order[J + 1]].Weight then
      begin
        Tmp := Order[J];
        Order[J] := Order[J + 1];
        Order[J + 1] := Tmp;
      end;

  Result := 0;
  Edges := 0;
  for I := 0 to High(Order) do
  begin
    RootA := Find(G.Edges[Order[I]].A);
    RootB := Find(G.Edges[Order[I]].B);
    if RootA <> RootB then
    begin
      Parent[RootA] := RootB;
      Result := Result + G.Edges[Order[I]].Weight;
      Inc(Edges);
    end;
  end;
end;

{ ------------------------------------------------------------ сортировки -- }

procedure SortByInsert(var A: System.TArray<Int64>);
var
  I, J: Integer;
  V: Int64;
begin
  for I := 1 to High(A) do
  begin
    V := A[I];
    J := I - 1;
    while (J >= 0) and (A[J] > V) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := V;
  end;
end;

procedure SortByQuick(var A: System.TArray<Int64>; Low_, High_: Integer);
var
  I, J: Integer;
  Pivot, Tmp: Int64;
begin
  if Low_ >= High_ then
    Exit;
  Pivot := A[(Low_ + High_) div 2];
  I := Low_;
  J := High_;
  while I <= J do
  begin
    while A[I] < Pivot do
      Inc(I);
    while A[J] > Pivot do
      Dec(J);
    if I <= J then
    begin
      Tmp := A[I];
      A[I] := A[J];
      A[J] := Tmp;
      Inc(I);
      Dec(J);
    end;
  end;
  SortByQuick(A, Low_, J);
  SortByQuick(A, I, High_);
end;

procedure SortByMerge(var A: System.TArray<Int64>);
var
  Buf: System.TArray<Int64>;

  procedure Run(Low_, High_: Integer);
  var
    Mid, I, J, K: Integer;
  begin
    if Low_ >= High_ then
      Exit;
    Mid := (Low_ + High_) div 2;
    Run(Low_, Mid);
    Run(Mid + 1, High_);
    I := Low_;
    J := Mid + 1;
    K := Low_;
    while (I <= Mid) and (J <= High_) do
    begin
      if A[I] <= A[J] then
      begin
        Buf[K] := A[I];
        Inc(I);
      end
      else
      begin
        Buf[K] := A[J];
        Inc(J);
      end;
      Inc(K);
    end;
    while I <= Mid do
    begin
      Buf[K] := A[I];
      Inc(I);
      Inc(K);
    end;
    while J <= High_ do
    begin
      Buf[K] := A[J];
      Inc(J);
      Inc(K);
    end;
    for K := Low_ to High_ do
      A[K] := Buf[K];
  end;

begin
  SetLength(Buf, Length(A));
  Run(0, High(A));
end;

procedure SortByHeap(var A: System.TArray<Int64>);
var
  N, I: Integer;
  Tmp: Int64;

  procedure Sift(Root, Size: Integer);
  var
    Child, Pick: Integer;
    Swap: Int64;
  begin
    while True do
    begin
      Child := Root * 2 + 1;
      if Child >= Size then
        Break;
      Pick := Child;
      if (Child + 1 < Size) and (A[Child + 1] > A[Child]) then
        Pick := Child + 1;
      if A[Root] >= A[Pick] then
        Break;
      Swap := A[Root];
      A[Root] := A[Pick];
      A[Pick] := Swap;
      Root := Pick;
    end;
  end;

begin
  N := Length(A);
  for I := N div 2 - 1 downto 0 do
    Sift(I, N);
  for I := N - 1 downto 1 do
  begin
    Tmp := A[0];
    A[0] := A[I];
    A[I] := Tmp;
    Sift(0, I);
  end;
end;

function SameOrder(const A, B: System.TArray<Int64>): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
  Result := True;
end;

{ Свёртка состава, не зависящая от порядка: если две последовательности —
  перестановки друг друга, она совпадёт. }
function Composition(const A: System.TArray<Int64>): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(A) do
    Result := Result + ResidentMix(ResidentOffset, UInt64(A[I]));
end;

{ ------------------------------------------------------------- стадии ----- }

{ Кратчайшие пути тремя способами: все три обязаны совпасть, и каждый обязан
  удовлетворять условию оптимальности на каждом ребре. }
procedure StageShortest(Carrier: TResidentCarrier);
var
  G: TGraph;
  ByNearest, ByRelax: System.TArray<Int64>;
  Pairs: System.TArray<System.TArray<Int64>>;
  N, I, E, From_: Integer;
  Ok: Boolean;
begin
  N := 12 + (Carrier.Lap mod 5) * 6;
  G := MakeGraph(Carrier, N, N * 2);
  From_ := Carrier.Serial mod N;

  ByNearest := ShortestByNearest(G, From_);
  ByRelax := ShortestByRelax(G, From_);
  Pairs := ShortestByPairs(G);

  { Три разных способа — один ответ. }
  Ok := True;
  for I := 0 to N - 1 do
  begin
    if ByNearest[I] <> ByRelax[I] then
      Ok := False;
    if ByNearest[I] <> Pairs[From_][I] then
      Ok := False;
  end;
  Carrier.Claim(Ok, 'shortest: three algorithms disagree');
  Carrier.Feed(UInt64(Cardinal(N)));
  for I := 0 to N - 1 do
    Carrier.Feed(UInt64(ByNearest[I]));

  { Условие оптимальности: ни одно ребро не даёт короткого пути в обход. }
  Ok := True;
  for E := 0 to High(G.Edges) do
  begin
    if ByNearest[G.Edges[E].A] + G.Edges[E].Weight < ByNearest[G.Edges[E].B] then
      Ok := False;
    if ByNearest[G.Edges[E].B] + G.Edges[E].Weight < ByNearest[G.Edges[E].A] then
      Ok := False;
  end;
  Carrier.Claim(Ok, 'shortest: an edge violates the optimality condition');

  { Граф связен по построению, значит все вершины достижимы. }
  Ok := True;
  for I := 0 to N - 1 do
    if ByNearest[I] >= Far_ then
      Ok := False;
  Carrier.Claim(Ok, 'shortest: a vertex is unreachable in a connected graph');
  Carrier.Claim(ByNearest[From_] = 0, 'shortest: distance to itself is not zero');

  { Неравенство треугольника на всех парах. }
  Ok := True;
  for I := 0 to N - 1 do
    for E := 0 to N - 1 do
      if Pairs[From_][I] + Pairs[I][E] < Pairs[From_][E] then
        Ok := False;
  Carrier.Claim(Ok, 'shortest: triangle inequality violated');
end;

{ Остовное дерево двумя способами: вес обязан совпасть, и рёбер обязано быть
  ровно на одно меньше числа вершин. }
procedure StageSpanning(Carrier: TResidentCarrier);
var
  G: TGraph;
  N, EdgesA, EdgesB: Integer;
  WeightA, WeightB: Int64;
begin
  N := 10 + (Carrier.Lap mod 6) * 5;
  G := MakeGraph(Carrier, N, N * 3);

  WeightA := SpanByGrowth(G, EdgesA);
  WeightB := SpanByMerge(G, EdgesB);

  Carrier.Claim(WeightA = WeightB, 'spanning tree: two algorithms disagree on weight');
  Carrier.Claim(EdgesA = N - 1, 'spanning tree: growth used the wrong edge count');
  Carrier.Claim(EdgesB = N - 1, 'spanning tree: merge used the wrong edge count');
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(WeightA));

  { Вес остова не может превышать сумму всех рёбер и не может быть меньше
    наибольшего из минимальных рёбер каждой вершины. }
  var Total: Int64 := 0;
  for var E := 0 to High(G.Edges) do
    Total := Total + G.Edges[E].Weight;
  Carrier.Claim(WeightA <= Total, 'spanning tree: weight exceeds all edges');
  Carrier.Claim(WeightA > 0, 'spanning tree: weight is not positive');
end;

{ Четыре сортировки: одна перестановка, один состав. }
procedure StageSorting(Carrier: TResidentCarrier);
var
  Source, A, B, C, D: System.TArray<Int64>;
  N, I: Integer;
  State: UInt64;
  Before: UInt64;
  Ordered: Boolean;
begin
  N := 200 + (Carrier.Lap mod 9) * 100;
  SetLength(Source, N);
  State := ResidentMix(Carrier.Seed,
                       UInt64(Cardinal(Carrier.Serial * 97 + Carrier.Lap)));
  for I := 0 to N - 1 do
    Source[I] := Int64(ResidentNext(State) mod 10000) - 5000;
  Before := Composition(Source);

  A := System.Copy(Source, 0, N);
  B := System.Copy(Source, 0, N);
  C := System.Copy(Source, 0, N);
  D := System.Copy(Source, 0, N);

  SortByInsert(A);
  SortByQuick(B, 0, N - 1);
  SortByMerge(C);
  SortByHeap(D);

  { Четыре разных пути — одна перестановка. }
  Carrier.Claim(SameOrder(A, B), 'sort: insert and quick disagree');
  Carrier.Claim(SameOrder(A, C), 'sort: insert and merge disagree');
  Carrier.Claim(SameOrder(A, D), 'sort: insert and heap disagree');

  { Порядок и состав. }
  Ordered := True;
  for I := 1 to N - 1 do
    if A[I] < A[I - 1] then
      Ordered := False;
  Carrier.Claim(Ordered, 'sort: result is not ordered');
  Carrier.Claim(Composition(A) = Before, 'sort: the multiset changed');

  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(A[0]));
  Carrier.Feed(UInt64(A[N - 1]));
  Carrier.Feed(Before);

  { Уже отсортированное и обратно отсортированное — худшие случаи для быстрой
    сортировки, и они обязаны отработать так же верно. }
  B := System.Copy(A, 0, N);
  SortByQuick(B, 0, N - 1);
  Carrier.Claim(SameOrder(A, B), 'sort: sorting an already sorted array broke it');
  for I := 0 to N - 1 do
    B[I] := A[N - 1 - I];
  SortByQuick(B, 0, N - 1);
  Carrier.Claim(SameOrder(A, B), 'sort: sorting a reversed array broke it');
end;

{ Двоичный поиск против прямого перебора: два способа найти одно и то же. }
procedure StageSearch(Carrier: TResidentCarrier);
var
  Data: System.TArray<Int64>;
  N, I, Lo, Hi, Mid, Found, Direct: Integer;
  State: UInt64;
  Want: Int64;
begin
  N := 500 + (Carrier.Lap mod 7) * 200;
  SetLength(Data, N);
  State := ResidentMix(Carrier.Seed, UInt64(Cardinal(Carrier.Lap * 13 + 7)));
  for I := 0 to N - 1 do
    Data[I] := Int64(ResidentNext(State) mod 100000);
  SortByMerge(Data);

  for I := 1 to 20 do
  begin
    { Половина запросов — заведомо присутствующие значения, половина — какие
      придётся. }
    if I mod 2 = 0 then
      Want := Data[Integer(ResidentNext(State) mod UInt64(N))]
    else
      Want := Int64(ResidentNext(State) mod 100000);

    Lo := 0;
    Hi := N - 1;
    Found := -1;
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if Data[Mid] = Want then
      begin
        Found := Mid;
        Break;
      end
      else if Data[Mid] < Want then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
    end;

    Direct := -1;
    for var K := 0 to N - 1 do
      if Data[K] = Want then
      begin
        Direct := K;
        Break;
      end;

    { Оба способа обязаны сойтись в том, есть ли значение вообще. }
    Carrier.Claim((Found >= 0) = (Direct >= 0),
                  'search: binary and linear disagree on presence');
    if Found >= 0 then
      Carrier.Claim(Data[Found] = Want, 'search: binary search found the wrong value');
  end;
  Carrier.Feed(UInt64(Cardinal(N)));
end;

{ Граф, растущий между оборотами: к нему добавляются вершины, и вес остова
  обязан расти вместе с ними, никогда не убывая. }
procedure StageRunningGraph(Carrier: TResidentCarrier);
var
  Pocket: TResidentAlgoPocket;
  G: TGraph;
  N, Edges: Integer;
  Weight: Int64;
begin
  Pocket := Carrier.PocketAs<TResidentAlgoPocket>('algo-running');
  N := 8 + Integer(Pocket.FRounds) * 2;
  if N > 60 then
  begin
    N := 8;
    Pocket.FTotal := 0;
    Pocket.FRounds := 0;
  end;

  G := MakeGraph(Carrier, N, N);
  Weight := SpanByGrowth(G, Edges);
  Carrier.Claim(Edges = N - 1, 'running graph: wrong edge count in the tree');
  Carrier.Claim(Weight = SpanByMerge(G, Edges),
                'running graph: two algorithms disagree');

  Pocket.FTotal := Pocket.FTotal + Weight;
  Carrier.Feed(UInt64(Cardinal(N)));
  Carrier.Feed(UInt64(Weight));
  Carrier.Feed(UInt64(Pocket.FTotal));
  Inc(Pocket.FRounds);
  Carrier.Feed(UInt64(Pocket.FRounds));
end;

initialization
  ResidentRegisterStage('algo-running-graph', @StageRunningGraph);
  ResidentRegisterStage('algo-search', @StageSearch);
  ResidentRegisterStage('algo-shortest', @StageShortest);
  ResidentRegisterStage('algo-sorting', @StageSorting);
  ResidentRegisterStage('algo-spanning', @StageSpanning);

end.
