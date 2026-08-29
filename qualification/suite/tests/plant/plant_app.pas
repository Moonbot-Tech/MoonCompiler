unit plant_app;

{ Слой приложения: собирает всё вместе и считает.

  Здесь нет ни одной новой механики — только сборка. Приложение спрашивает у
  фабрики, какие породы движков вообще есть (а это зависит от того, какие юниты
  подключены и в каком порядке отработала их инициализация), заводит по одному
  каждой, открывает канал в чужую библиотеку, гоняет через всё это партию
  тикетов и отдаёт отчёт.

  Порядок действий такой же, как в живой программе: сначала спросить, что
  доступно, потом создать, потом работать, потом убрать за собой и проверить,
  что счёт живых сошёлся. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  SysUtils, plant_types, plant_engine, plant_factory, plant_service;

function PlantRun(Count: Integer): TPlantReport;
function PlantAliveAfterRun: Int64;

implementation

function PlantRun(Count: Integer): TPlantReport;
var
  Engines: array of TPlantEngine;
  Ticket: TPlantTicket;
  Weigher: IPlantService;
  I, K: Integer;
begin
  Result := Default(TPlantReport);
  Result.Tickets := Count;
  Result.Kinds := FactoryCount;

  { Канал в чужую библиотеку: открывается лениво, обратный вызов ставится
    внутри обёртки. }
  PlantResetChannels;
  Result.Channel := PlantOpenChannel(100);

  SetLength(Engines, FactoryCount);
  for K := 0 to High(Engines) do
    Engines[K] := FactoryMake(K, K + 1);

  Weigher := ServiceGet('weigher');
  try
    for I := 1 to Count do
    begin
      Ticket := PlantMakeTicket(I, TPlantKind(I mod 4));

      { Через чужую библиотеку. }
      Result.Channel := PlantPushThrough(PlantWeigh(Ticket));

      { Через движки — у каждого своя порода и своя арифметика. }
      for K := 0 to High(Engines) do
        Engines[K].Step(Ticket);

      { Через цепочку сервисов. }
      Result.Services := Weigher.Handle(Ticket);
    end;

    for K := 0 to High(Engines) do
      Result.Weight := Result.Weight + Engines[K].Total;
    Result.Hooked := PlantHookedCount;
  finally
    Weigher := nil;
    for K := 0 to High(Engines) do
      FreeAndNil(Engines[K]);
    Engines := nil;
    ServiceReset;
    PlantResetChannels;
  end;
end;

function PlantAliveAfterRun: Int64;
begin
  { После уборки не должно остаться ни одного живого движка и ни одного
    живого сервиса. }
  Result := FactoryAlive + ServiceLive;
end;

end.
