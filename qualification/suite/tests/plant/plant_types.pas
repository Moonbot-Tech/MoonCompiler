unit plant_types;

{ Общие типы приложения — и одна половина легального цикла заголовков.

  Так выходит само собой: типы нужны всем, а обёртке над чужой библиотекой
  нужны эти же типы в её интерфейсе. Обратно — этому юниту нужна обёртка, но
  только в реализации. Получается цикл, который язык разрешает, а компилятор
  обязан разобрать в правильном порядке: интерфейс соседа к этому моменту
  готов, реализация — ещё нет. }

{$mode delphi}
{$Q-}{$R-}

interface

type
  TPlantKind = (pkIdle, pkFeeder, pkMixer, pkSink);

  TPlantTicket = record
    Serial: Int64;
    Kind: TPlantKind;
    Weight: Int64;
  end;

  TPlantReport = record
    Tickets: Int64;
    Weight: Int64;      { сумма по движкам }
    Hooked: Int64;      { сколько раз «библиотека» дёрнула обратный вызов }
    Channel: Int64;     { что осталось в канале }
    Services: Int64;    { сумма по цепочке сервисов }
    Kinds: Int64;       { сколько пород движков нашлось в реестре }
  end;

function PlantMakeTicket(Serial: Int64; Kind: TPlantKind): TPlantTicket;
function PlantWeigh(const Ticket: TPlantTicket): Int64;

{ Зовут обёртку — их тела компилятор вправе перенести туда, где цикл ещё не
  дособран. }
function PlantOpenChannel(Seed: Int64): Int64;
function PlantPushThrough(Value: Int64): Int64;
function PlantHookedCount: Int64;
procedure PlantResetChannels;

implementation

uses
  plant_glue;

function PlantMakeTicket(Serial: Int64; Kind: TPlantKind): TPlantTicket;
begin
  Result.Serial := Serial;
  Result.Kind := Kind;
  Result.Weight := Serial * (Ord(Kind) + 1);
end;

function PlantWeigh(const Ticket: TPlantTicket): Int64;
begin
  Result := Ticket.Weight + Ord(Ticket.Kind);
end;

function PlantOpenChannel(Seed: Int64): Int64;
begin
  Result := GlueOpen(Seed);
end;

function PlantPushThrough(Value: Int64): Int64;
begin
  Result := GluePush(Value);
end;

function PlantHookedCount: Int64;
begin
  Result := GlueHookCount;
end;

procedure PlantResetChannels;
begin
  GlueReset;
end;

end.
