unit plant_glue;

{ Обёртка над чужой библиотекой — вторая половина цикла заголовков.

  Это самое опасное место всей программы, и опасно оно не арифметикой. Здесь
  сходятся сразу все неудобные для компилятора вещи, которые в живом коде
  ходят вместе:

  * реестр обратных вызовов лежит в **закрытом статическом поле класса** —
    снаружи его не видно, а телам, которые его трогают, он нужен;
  * тела эти короткие и потому охотно переносятся в место вызова, а место
    вызова — в соседнем юните, который в этот момент ещё не дособран;
  * инициализация ленивая: настоящая обёртка не грузит библиотеку заранее;
  * обратный вызов уходит наружу указателем, то есть его адрес обязан пережить
    любую перестановку кода;
  * юнит называет соседа в **интерфейсе**, а сосед его — в реализации.

  Ни одна из этих черт не придумана: так устроены заголовки к криптографии, к
  сетевым библиотекам, к любой обёртке над сишным кодом. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  plant_types;

function GlueOpen(Seed: Int64): Int64;
function GluePush(Value: Int64): Int64;
function GlueHookCount: Int64;
function GlueLastTicket: TPlantTicket;
procedure GlueReset;

implementation

uses
  plant_api;

type
  { Реестр обратных вызовов. Всё закрытое и статическое — как в настоящей
    обёртке, где такой реестр один на процесс. }
  TGlueRegistry = class
  private
    class var FExports: TPlantExports;
    class var FReady: Boolean;
    class var FHandle: TPlantHandle;
    class var FHooked: Int64;
    class var FLast: TPlantTicket;
  end;

{ Обратный вызов, который «библиотека» дёргает сама. Его адрес уходит наружу,
  а тело трогает закрытое статическое поле. }
function GlueHook(Handle: TPlantHandle; Value: Int64): Int64; cdecl;
begin
  Inc(TGlueRegistry.FHooked);
  Result := Value + 1;
end;

{ Ленивая установка: настоящая обёртка не грузит библиотеку заранее. }
procedure EnsureReady;
begin
  if TGlueRegistry.FReady then
    Exit;
  TGlueRegistry.FExports := PlantApi;
  TGlueRegistry.FReady := True;
end;

function GlueOpen(Seed: Int64): Int64;
begin
  EnsureReady;
  TGlueRegistry.FHandle := TGlueRegistry.FExports.Open(Seed);
  TGlueRegistry.FExports.SetHook(TGlueRegistry.FHandle, GlueHook);
  TGlueRegistry.FLast := PlantMakeTicket(Seed, pkFeeder);
  Result := PlantHandleValue(TGlueRegistry.FHandle);
end;

function GluePush(Value: Int64): Int64;
begin
  EnsureReady;
  Result := TGlueRegistry.FExports.Feed(TGlueRegistry.FHandle, Value);
end;

function GlueHookCount: Int64;
begin
  Result := TGlueRegistry.FHooked;
end;

function GlueLastTicket: TPlantTicket;
begin
  Result := TGlueRegistry.FLast;
end;

procedure GlueReset;
begin
  if TGlueRegistry.FReady and (TGlueRegistry.FHandle <> nil) then
    TGlueRegistry.FExports.Close(TGlueRegistry.FHandle);
  TGlueRegistry.FHandle := nil;
  TGlueRegistry.FHooked := 0;
end;

end.
