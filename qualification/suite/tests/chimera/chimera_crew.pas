unit chimera_crew;

{ Бригада: общая оснастка для прогона органов в несколько потоков.

  В живых проектах потоки не изолированы аккуратными очередями — работа
  разбирается из общего счётчика, а состояние гуляет между потоками с очень
  лёгким отношением к блокировкам: где-то атомарный инкремент, где-то честная
  критическая секция, а где-то просто запись в поле, которую читает соседний
  поток. Химера повторяет это как есть, но с одной обязательной оговоркой:
  **оракул не имеет права зависеть от порядка потоков**. Иначе тест начнёт
  «находить» дефекты планировщика.

  Отсюда разделение, которое соблюдают все органы:

  * точное число берётся из детерминированного прогона — один поток, порядок
    задан сидом;
  * многопоточный прогон проверяет то, что верно при ЛЮБОМ порядке: цела ли
    запись, сошёлся ли счёт поданного и принятого, не съедено ли что-то
    дважды.

  Работа раздаётся замыканием — той самой формой, которой в живом коде
  запускают фоновые задачи: безымянный поток получает замыкание, замыкание
  тащит с собой захваченные значения. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, SyncObjs, chimera_body;

type
  { Единица работы. Номер — то, что раздаётся; всё остальное замыкание тащит
    с собой из места, где было создано. }
  TChiJob = reference to procedure(Index: Integer);

{ Разобрать Count единиц работы Threads потоками. Номера раздаются общим
  счётчиком, поэтому кто какую возьмёт — заранее неизвестно; это и нужно.
  Исключение из потока не теряется: оно превращается в нарушенное
  утверждение, а не в тихо пропавшую работу. }
procedure ChiParallel(Count, Threads: Integer; const Job: TChiJob);

{ Сколько потоков заводить по умолчанию: достаточно, чтобы они реально
  перемешивались, и не столько, чтобы прогон превратился в ожидание. }
function ChiThreadCount: Integer;

implementation

type
  TChiWorker = class(TThread)
  private
    FJob: TChiJob;
    FCounter: PInteger;
    FCount: Integer;
    FFailed: Boolean;
    FMessage: string;
  protected
    procedure Execute; override;
  end;

procedure TChiWorker.Execute;
var
  Index: Integer;
begin
  try
    repeat
      { Общий счётчик — единственная синхронизация между работниками. }
      Index := AtomicIncrement(FCounter^) - 1;
      if Index >= FCount then Break;
      FJob(Index);
    until False;
  except
    on E: Exception do
    begin
      FFailed := True;
      FMessage := string(E.ClassName) + ': ' + E.Message;
    end;
  end;
end;

function ChiThreadCount: Integer;
begin
  Result := TThread.ProcessorCount;
  if Result < 2 then Result := 2;
  if Result > 8 then Result := 8;
end;

procedure ChiParallel(Count, Threads: Integer; const Job: TChiJob);
var
  Workers: array of TChiWorker;
  Counter: Integer;
  I: Integer;
begin
  if Count <= 0 then Exit;
  if Threads < 1 then Threads := 1;
  Counter := 0;
  SetLength(Workers, Threads);
  for I := 0 to Threads - 1 do
  begin
    Workers[I] := TChiWorker.Create(True);
    Workers[I].FreeOnTerminate := False;
    Workers[I].FJob := Job;
    Workers[I].FCounter := @Counter;
    Workers[I].FCount := Count;
  end;
  try
    for I := 0 to Threads - 1 do Workers[I].Start;
    for I := 0 to Threads - 1 do Workers[I].WaitFor;
    for I := 0 to Threads - 1 do
      ChiClaim(not Workers[I].FFailed,
        'бригада: поток упал — ' + Workers[I].FMessage);
    ChiClaim(Counter >= Count,
      'бригада: счётчик работы не дошёл до конца');
  finally
    for I := 0 to Threads - 1 do
      FreeAndNil(Workers[I]);
  end;
end;

end.
