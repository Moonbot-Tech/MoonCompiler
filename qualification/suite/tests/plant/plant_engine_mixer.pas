unit plant_engine_mixer;

{ Порода движка, которая сама вписывает себя в реестр при инициализации.

  Так делают все плагинные схемы: юнит подключён — порода доступна, юнит не
  подключён — её нет, и ни одной строки в приложении менять не надо. Для
  компилятора это значит, что состав реестра складывается до входа в главную
  программу, в порядке, который он же и выбрал. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  plant_types, plant_engine;

type
  TPlantMixer = class(TPlantEngine)
  private
    class var FSteps: Int64;
  public
    function Step(const Ticket: TPlantTicket): Int64; override;
    class function Steps: Int64;
  end;

implementation

uses
  plant_factory;

function TPlantMixer.Step(const Ticket: TPlantTicket): Int64;
begin
  Inc(FSteps);
  { Смешивает вес с номером — своя арифметика вместо унаследованной. }
  Result := inherited Step(Ticket) + Ticket.Serial * 2;
  FTotal := Result;
end;

class function TPlantMixer.Steps: Int64;
begin
  Result := FSteps;
end;

initialization
  FactoryRegister('mixer', TPlantMixer);

end.
