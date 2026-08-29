unit plant_service;

{ Слой сервисов: интерфейсы со счётчиком ссылок и менеджер, который их
  раздаёт.

  Так устроена любая программа, где части не должны знать друг о друге:
  запрашивают у менеджера интерфейс по имени, работают через него, отпускают.
  Владение при этом считает не программист, а счётчик — и вот тут появляется
  своя топология: менеджер держит сервисы, сервис знает менеджера, чтобы
  отметиться при рождении и смерти.

  Отдельная тонкость — сервис, который держит ссылку на другой сервис. Если
  такую пару освободить в неверном порядке, второй умрёт раньше первого; здесь
  это проверяется счётом живых, а не наблюдением. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  SysUtils, plant_types;

type
  IPlantService = interface
    ['{4D5A0007-0000-0000-0000-0000504C4E54}']
    function Name: string;
    function Handle(const Ticket: TPlantTicket): Int64;
    function Served: Int64;
  end;

function ServiceGet(const AName: string): IPlantService;
function ServiceLive: Int64;
function ServiceBorn: Int64;
procedure ServiceReset;

implementation

type
  TPlantService = class(TInterfacedObject, IPlantService)
  private
    FName: string;
    FServed: Int64;
    FTotal: Int64;
    FNext: IPlantService;
  public
    constructor Create(const AName: string; const ANext: IPlantService);
    destructor Destroy; override;
    function Name: string;
    function Handle(const Ticket: TPlantTicket): Int64;
    function Served: Int64;
  end;

  { Счётчики живут в закрытых статических полях: один экземпляр на программу,
    как у настоящего менеджера. }
  TServiceBook = class
  private
    class var FBorn: Int64;
    class var FGone: Int64;
    class var FWeigher: IPlantService;
    class var FCounter: IPlantService;
  end;

constructor TPlantService.Create(const AName: string; const ANext: IPlantService);
begin
  inherited Create;
  FName := AName;
  FNext := ANext;
  Inc(TServiceBook.FBorn);
end;

destructor TPlantService.Destroy;
begin
  FNext := nil;
  Inc(TServiceBook.FGone);
  inherited Destroy;
end;

function TPlantService.Name: string;
begin
  Result := FName;
end;

function TPlantService.Handle(const Ticket: TPlantTicket): Int64;
begin
  Inc(FServed);
  FTotal := FTotal + PlantWeigh(Ticket);
  { Цепочка: сервис передаёт работу дальше, если ему есть кому. }
  if FNext <> nil then
    Result := FTotal + FNext.Handle(Ticket)
  else
    Result := FTotal;
end;

function TPlantService.Served: Int64;
begin
  Result := FServed;
end;

function ServiceGet(const AName: string): IPlantService;
begin
  { Ленивая раздача: сервис заводится при первом спросе, дальше отдаётся тот
    же самый. }
  if AName = 'counter' then
  begin
    if TServiceBook.FCounter = nil then
      TServiceBook.FCounter := TPlantService.Create('counter', nil);
    Exit(TServiceBook.FCounter);
  end;

  if TServiceBook.FWeigher = nil then
    TServiceBook.FWeigher := TPlantService.Create('weigher', ServiceGet('counter'));
  Result := TServiceBook.FWeigher;
end;

function ServiceLive: Int64;
begin
  Result := TServiceBook.FBorn - TServiceBook.FGone;
end;

function ServiceBorn: Int64;
begin
  Result := TServiceBook.FBorn;
end;

procedure ServiceReset;
begin
  { Порядок важен: сначала отпускаем того, кто держит другого. }
  TServiceBook.FWeigher := nil;
  TServiceBook.FCounter := nil;
end;

end.
