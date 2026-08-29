unit plant_factory;

{ Менеджер движков: реестр пород, счёт живых, создание по имени.

  Реестр заполняется не здесь, а в секциях инициализации тех юнитов, где
  породы объявлены. Значит состав реестра зависит от порядка, в котором
  компилятор расставил инициализацию, — а сам порядок задан графом зависимостей.
  Приложение обязано работать при любом законном порядке, и это здесь
  проверяется прямо: сначала спрашивается, сколько пород зарегистрировано.

  Счётчики живых — закрытые статические поля, а трогают их короткие тела,
  которые зовутся из юнита, стоящего с этим в цикле. }

{$mode delphi}
{$Q-}{$R-}

interface

uses
  plant_types, plant_engine;

procedure FactoryRegister(const Name: string; Kind: TPlantEngineClass);
function FactoryCount: Integer;
function FactoryMake(Index: Integer; Serial: Int64): TPlantEngine;
function FactoryNameAt(Index: Integer): string;

procedure FactoryNoteBorn;
procedure FactoryNoteGone;
function FactoryAlive: Int64;
function FactoryBorn: Int64;

implementation

type
  TFactorySlot = record
    Name: string;
    Kind: TPlantEngineClass;
  end;

  TFactoryBook = class
  private
    class var FSlots: array[0 .. 7] of TFactorySlot;
    class var FCount: Integer;
    class var FBorn: Int64;
    class var FGone: Int64;
  end;

procedure FactoryRegister(const Name: string; Kind: TPlantEngineClass);
begin
  if TFactoryBook.FCount > High(TFactoryBook.FSlots) then
    Exit;
  TFactoryBook.FSlots[TFactoryBook.FCount].Name := Name;
  TFactoryBook.FSlots[TFactoryBook.FCount].Kind := Kind;
  Inc(TFactoryBook.FCount);
end;

function FactoryCount: Integer;
begin
  Result := TFactoryBook.FCount;
end;

function FactoryMake(Index: Integer; Serial: Int64): TPlantEngine;
begin
  if (Index < 0) or (Index >= TFactoryBook.FCount) then
    Exit(nil);
  Result := TFactoryBook.FSlots[Index].Kind.Create(Serial);
end;

function FactoryNameAt(Index: Integer): string;
begin
  if (Index < 0) or (Index >= TFactoryBook.FCount) then
    Exit('');
  Result := TFactoryBook.FSlots[Index].Name;
end;

procedure FactoryNoteBorn;
begin
  Inc(TFactoryBook.FBorn);
end;

procedure FactoryNoteGone;
begin
  Inc(TFactoryBook.FGone);
end;

function FactoryAlive: Int64;
begin
  Result := TFactoryBook.FBorn - TFactoryBook.FGone;
end;

function FactoryBorn: Int64;
begin
  Result := TFactoryBook.FBorn;
end;

end.
