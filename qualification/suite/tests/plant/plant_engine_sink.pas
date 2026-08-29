unit plant_engine_sink;

{ Вторая порода движка. Отличается от первой не только арифметикой, но и тем,
  что держит собственную очередь и освобождает её в деструкторе — то есть
  ведёт себя как обычный объект приложения, а не как расчётная заглушка. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, plant_types, plant_engine;

type
  TPlantSink = class(TPlantEngine)
  private
    FSeen: TStringList;
  public
    constructor Create(ASerial: Int64); override;
    destructor Destroy; override;
    function Step(const Ticket: TPlantTicket): Int64; override;
    function SeenCount: Integer;
  end;

implementation

uses
  plant_factory;

constructor TPlantSink.Create(ASerial: Int64);
begin
  inherited Create(ASerial);
  FSeen := TStringList.Create;
end;

destructor TPlantSink.Destroy;
begin
  FreeAndNil(FSeen);
  inherited Destroy;
end;

function TPlantSink.Step(const Ticket: TPlantTicket): Int64;
begin
  FSeen.Add(IntToStr(Ticket.Serial));
  { Стоку важен не вес, а количество: он считает штуки и добавляет номер. }
  FTotal := FTotal + FSeen.Count + Ticket.Serial;
  Result := FTotal;
end;

function TPlantSink.SeenCount: Integer;
begin
  Result := FSeen.Count;
end;

initialization
  FactoryRegister('sink', TPlantSink);

end.
