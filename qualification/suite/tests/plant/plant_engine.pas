unit plant_engine;

{ Базовый движок — и половина второго цикла: «элемент и его менеджер».

  Пара, в которой элемент знает менеджера, а менеджер — элемента, встречается в
  каждом втором приложении: фабрика создаёт объекты, объекты при рождении и
  смерти отмечаются в фабрике. Менеджер обязан называть тип элемента в своём
  интерфейсе; элемент обращается к менеджеру только из реализации. Снова цикл,
  снова неудобная середина. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  plant_types;

type
  TPlantEngine = class
  private
    FSerial: Int64;
  protected
    { Наследники живут в других юнитах, поэтому накопитель им доступен, а
      номер — нет: его выдают при рождении и менять некому. }
    FTotal: Int64;
  public
    { Виртуальный не для красоты: движки заводит фабрика через метакласс, а
      она умеет звать только то, что объявлено виртуальным. }
    constructor Create(ASerial: Int64); virtual;
    destructor Destroy; override;
    { Шаг движка виртуален: за одной ссылкой стоят разные породы. }
    function Step(const Ticket: TPlantTicket): Int64; virtual;
    function Total: Int64;
    property Serial: Int64 read FSerial;
  end;

  TPlantEngineClass = class of TPlantEngine;

implementation

uses
  plant_factory;

constructor TPlantEngine.Create(ASerial: Int64);
begin
  inherited Create;
  FSerial := ASerial;
  FTotal := 0;
  { Рождение отмечается у менеджера — вызов идёт в юнит, который знает нас в
    своём интерфейсе. }
  FactoryNoteBorn;
end;

destructor TPlantEngine.Destroy;
begin
  FactoryNoteGone;
  inherited Destroy;
end;

function TPlantEngine.Step(const Ticket: TPlantTicket): Int64;
begin
  FTotal := FTotal + PlantWeigh(Ticket);
  Result := FTotal;
end;

function TPlantEngine.Total: Int64;
begin
  Result := FTotal;
end;

end.
