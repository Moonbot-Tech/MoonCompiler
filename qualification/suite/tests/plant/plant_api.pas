unit plant_api;

{ Слой «чужая библиотека»: так выглядит заголовок к внешнему коду.

  Настоящие заголовки чужих библиотек устроены одинаково: непрозрачный хэндл,
  таблица указателей на функции, обратные вызовы, которые библиотека дёргает
  сама, и ленивая установка всего этого при первом обращении. Ни одной такой
  формы нельзя придумать «из головы» — их приносит жизнь, и ломается компилятор
  ровно на них.

  Библиотеки здесь нет: её роль играют обычные функции этого юнита. Важна не
  библиотека, а форма — указатели, хэндлы, таблица и обратные вызовы, живущие
  в статических полях. }

{$mode delphi}
{$Q-}{$R-}

interface

type
  { Непрозрачный хэндл: снаружи это просто указатель. }
  TPlantHandle = type Pointer;

  { Обратный вызов, который «библиотека» зовёт сама. }
  TPlantCallback = function(Handle: TPlantHandle; Value: Int64): Int64; cdecl;

  { Таблица экспорта — то, что в настоящем заголовке заполняется адресами из
    загруженной библиотеки. }
  TPlantExports = record
    Open: function(Seed: Int64): TPlantHandle; cdecl;
    Close: procedure(Handle: TPlantHandle); cdecl;
    Feed: function(Handle: TPlantHandle; Value: Int64): Int64; cdecl;
    SetHook: procedure(Handle: TPlantHandle; Hook: TPlantCallback); cdecl;
  end;

function PlantApi: TPlantExports;
function PlantHandleValue(Handle: TPlantHandle): Int64;

implementation

type
  { «Объект библиотеки»: снаружи виден только как указатель. }
  PPlantState = ^TPlantState;
  TPlantState = record
    Value: Int64;
    Hook: TPlantCallback;
  end;

var
  { Пул состояний вместо кучи: адрес хэндла обязан пережить дорогу туда и
    обратно, а лишний вид памяти тут ни к чему. }
  Pool: array[0 .. 15] of TPlantState;
  PoolUsed: Integer;

function ApiOpen(Seed: Int64): TPlantHandle; cdecl;
begin
  if PoolUsed > High(Pool) then
    Exit(nil);
  Pool[PoolUsed].Value := Seed;
  Pool[PoolUsed].Hook := nil;
  Result := TPlantHandle(@Pool[PoolUsed]);
  Inc(PoolUsed);
end;

procedure ApiClose(Handle: TPlantHandle); cdecl;
begin
  if Handle <> nil then
    PPlantState(Handle)^.Hook := nil;
end;

function ApiFeed(Handle: TPlantHandle; Value: Int64): Int64; cdecl;
var
  State: PPlantState;
begin
  State := PPlantState(Handle);
  State^.Value := State^.Value + Value;
  { Библиотека сама зовёт то, что ей отдали. }
  if Assigned(State^.Hook) then
    State^.Value := State^.Hook(Handle, State^.Value);
  Result := State^.Value;
end;

procedure ApiSetHook(Handle: TPlantHandle; Hook: TPlantCallback); cdecl;
begin
  PPlantState(Handle)^.Hook := Hook;
end;

function PlantApi: TPlantExports;
begin
  Result.Open := ApiOpen;
  Result.Close := ApiClose;
  Result.Feed := ApiFeed;
  Result.SetHook := ApiSetHook;
end;

function PlantHandleValue(Handle: TPlantHandle): Int64;
begin
  Result := PPlantState(Handle)^.Value;
end;

end.
