program plant;

{ Вторая большая программа комплекта. У резидента предмет проверки — счёт;
  здесь — **устройство**.

  Приложение собрано так, как собирают настоящие: обёртка над чужой
  библиотекой с обратными вызовами и статическим реестром, менеджер движков со
  своими породами, регистрирующимися в секциях инициализации, слой сервисов на
  интерфейсах со счётчиком ссылок, общие типы — и легальные циклы заголовков
  между всем этим. Ни одна такая связка не придумана: они приходят из живого
  кода и, как показала практика, ломают компилятор именно там.

  Считает программа немного, зато ответ известен точно: те же величины
  пересчитываются здесь плоской арифметикой, без единого слоя. Расхождение
  означает, что где-то по дороге через слои значение потерялось.

  Вердикт печатается одной строкой, чтобы прогонять программу в матрице ключей
  оптимизации и сравнивать вывод глазами или скриптом. }

{$mode delphi}
{$Q-}{$R-}
{$APPTYPE CONSOLE}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils,
  plant_api,
  plant_types,
  plant_glue,
  plant_engine,
  plant_factory,
  plant_engine_mixer,
  plant_engine_sink,
  plant_service,
  plant_app;

const
  Tickets = 12;

var
  Report: TPlantReport;
  I, Bad: Integer;
  Weighed, Serials, WantWeight, WantChannel, WantServices: Int64;

{ Плоское повторение правил: вес тикета считается прямо здесь, без типов и
  слоёв. }
function FlatWeigh(Serial: Int64): Int64;
var
  Kind: Int64;
begin
  Kind := Serial mod 4;
  Result := Serial * (Kind + 1) + Kind;
end;

begin
  Report := PlantRun(Tickets);
  Bad := 0;

  Weighed := 0;
  Serials := 0;
  for I := 1 to Tickets do
  begin
    Weighed := Weighed + FlatWeigh(I);
    Serials := Serials + I;
  end;

  { Канал: начальное значение, плюс всё, что через него прошло, плюс по
    единице за каждый обратный вызов. }
  WantChannel := 100 + Weighed + Tickets;

  { Движки: смеситель добавляет удвоенный номер тикета, сток — номер по
    порядку и номер тикета, то есть тоже удвоенный номер. }
  WantWeight := Weighed + 4 * Serials;

  { Сервисы: оба звена цепочки накопили одну и ту же сумму весов, и внешнее
    отдаёт их сложенными. }
  WantServices := 2 * Weighed;

  if Report.Tickets <> Tickets then Inc(Bad);
  if Report.Kinds <> 2 then Inc(Bad);
  if Report.Hooked <> Tickets then Inc(Bad);
  if Report.Channel <> WantChannel then Inc(Bad);
  if Report.Weight <> WantWeight then Inc(Bad);
  if Report.Services <> WantServices then Inc(Bad);
  if PlantAliveAfterRun <> 0 then Inc(Bad);

  if Bad = 0 then
    WriteLn('PLANT_OK kinds=', Report.Kinds, ' hooked=', Report.Hooked,
            ' channel=', Report.Channel, ' weight=', Report.Weight,
            ' services=', Report.Services)
  else
    WriteLn('PLANT_BAD problems=', Bad,
            ' kinds=', Report.Kinds, ' want=2',
            ' hooked=', Report.Hooked, ' want=', Tickets,
            ' channel=', Report.Channel, ' want=', WantChannel,
            ' weight=', Report.Weight, ' want=', WantWeight,
            ' services=', Report.Services, ' want=', WantServices,
            ' alive=', PlantAliveAfterRun, ' want=0');
end.
