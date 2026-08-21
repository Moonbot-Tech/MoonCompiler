unit resident_queue;

{ Передача владения между стадиями.

  Это то место, где слой обязан быть безупречным, иначе он будет ловить сам
  себя. Правило одно и оно жёсткое: **после публикации продюсер носитель не
  трогает**. Никаких «загляну ещё разок», никаких ссылок, оставленных на
  память. Владение переходит целиком и в один момент.

  Никакого перемешивания сном: интерливинг создают настоящие очереди и число
  потоков, а не `Sleep(Random)`. Случайность в слое только одна — от сида, и
  она сидит в маршрутах и данных носителей, а не в расписании. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}

interface

uses
  SysUtils, Classes, SyncObjs, Generics.Collections, resident_core;

type
  { Очередь передачи владения. Закрывается один раз; после закрытия и
    опустошения `Take` возвращает False, и потребитель честно уходит. }
  TResidentQueue = class
  private
    FLock: TCriticalSection;
    FReady: TEvent;
    FItems: TQueue<TResidentCarrier>;
    FClosed: Boolean;
    FPassed: Int64;
  public
    constructor Create;
    destructor Destroy; override;

    { Передать владение. После возврата вызывающая сторона носитель не трогает. }
    procedure Put(Carrier: TResidentCarrier);

    { Принять владение. False означает «очередь закрыта и пуста». }
    function Take(out Carrier: TResidentCarrier): Boolean;

    { Одна попытка с коротким ожиданием: False означает «сейчас пусто». Нужна
      сборщику, которому нельзя вставать намертво. }
    function TryTake(out Carrier: TResidentCarrier): Boolean;

    procedure Close;
    function Count: Integer;
    property Passed: Int64 read FPassed;
  end;

implementation

constructor TResidentQueue.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  { Ручной сброс не годится: разбудить нужно ровно столько потребителей,
    сколько положили носителей, иначе один заберёт, а прочие закрутятся. }
  FReady := TEvent.Create(nil, False, False, '');
  FItems := TQueue<TResidentCarrier>.Create;
end;

destructor TResidentQueue.Destroy;
var
  Left: TResidentCarrier;
begin
  { Очередь владеет тем, что в ней осталось: иначе носители утекут и баланс
    покажет утечку, которой компилятор не делал. }
  while FItems.Count > 0 do
  begin
    Left := FItems.Dequeue;
    Left.Free;
  end;
  FItems.Free;
  FReady.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TResidentQueue.Put(Carrier: TResidentCarrier);
begin
  FLock.Enter;
  try
    FItems.Enqueue(Carrier);
    Inc(FPassed);
  finally
    FLock.Leave;
  end;
  FReady.SetEvent;
end;

function TResidentQueue.Take(out Carrier: TResidentCarrier): Boolean;
var
  Empty: Boolean;
  Closed: Boolean;
begin
  Carrier := nil;
  while True do
  begin
    FLock.Enter;
    try
      if FItems.Count > 0 then
      begin
        Carrier := FItems.Dequeue;
        Exit(True);
      end;
      Empty := True;
      Closed := FClosed;
    finally
      FLock.Leave;
    end;

    if Empty and Closed then
      Exit(False);

    { Ожидание с потолком: без него закрытие очереди в момент между проверкой
      и ожиданием оставило бы потребителя висеть навсегда. Потолок не создаёт
      недетерминизма в оракуле — он влияет только на расписание, а дайджест
      снимается с носителя, а не с порядка событий. }
    FReady.WaitFor(20);
  end;
end;

function TResidentQueue.TryTake(out Carrier: TResidentCarrier): Boolean;
begin
  Carrier := nil;
  FLock.Enter;
  try
    if FItems.Count > 0 then
    begin
      Carrier := FItems.Dequeue;
      Exit(True);
    end;
  finally
    FLock.Leave;
  end;
  FReady.WaitFor(20);
  Result := False;
end;

procedure TResidentQueue.Close;
begin
  FLock.Enter;
  try
    FClosed := True;
  finally
    FLock.Leave;
  end;
  { Разбудить всех, кто ждёт: событие с автосбросом будит по одному, поэтому
    закрытие сигналит столько раз, сколько потребителей может спать. }
  FReady.SetEvent;
end;

function TResidentQueue.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FItems.Count;
  finally
    FLock.Leave;
  end;
end;

end.
