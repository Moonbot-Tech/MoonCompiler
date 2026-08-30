unit chimera_life;

{ Орган «время жизни»: невидимый код, который вставляет компилятор.

  Все прежние работы химеры проверяли ЗНАЧЕНИЯ — число, байты, строку. Здесь
  предмет другой: **побочные действия, которых в исходнике не написано**.
  Присваивание переменной со счётчиком ссылок разворачивается в пару вызовов
  учёта; выход из процедуры, где живёт управляемое значение, — в скрытую
  защиту с освобождением; исключение посреди тела — в раскрутку кадров, где
  каждый уровень обязан отпустить своё.

  Ошибка в этом коде не даёт неверного числа. Она даёт утечку — или, что хуже,
  освобождение того, чем ещё пользуются: обращение по памяти, которую уже
  вернули распределителю. Проявляется это не там, где случилось, и не сразу.

  Источники формы:

    * `MoonBot/MyListHelper.pas` — правленый помощник списков из
      состава языка. Там обмен элемента идёт с ЗАПАСАНИЕМ прежнего значения:
      сперва прежнее уводится в сторону, потом на его место кладётся новое, и
      лишь после оповещений прежнее отпускается. Порядок важен: отпусти
      прежнее раньше — и оповещение получит мёртвое;
    * `MoonBot/Bworks.pas` — сто шестнадцать защит и девяносто
      девять перехватов в одном юните: исключение может прийти с любой
      глубины, и каждый уровень обязан отпустить своё.

  Оракул: **явный учёт против неявного**. Одна дорога живёт на счётчике
  ссылок, который ведёт язык; вторая делает ту же работу над теми же
  предметами, но захват и отпускание пишет руками. Обе ведут ленту событий —
  кто родился, кто умер, в каком порядке. Ленты обязаны совпасть посимвольно,
  а число живых после всего — вернуться к нулю.

  Сверх лент проверяется то, чего лента не покажет: что после раскрутки
  предметы не воскресают, что защита выполняется даже при выходе из середины,
  и что исключение из чужого потока не оставляет живых. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Classes, chimera_body;

function ChiLifeRun: Int64;

implementation

const
  IdLife = 'CHI-MB-LIFE-001';

{ ═══ Лента событий ═══════════════════════════════════════════════════════ }

var
  Trace:  string;
  Alive:  Integer;
  Births: Integer;
  Deaths: Integer;

procedure ResetTrace;
begin
  Trace := '';
  Alive := 0;
  Births := 0;
  Deaths := 0;
end;

procedure Born(const AName: string);
begin
  Trace := Trace + '+' + AName + ' ';
  Inc(Alive);
  Inc(Births);
end;

procedure Died(const AName: string);
begin
  Trace := Trace + '-' + AName + ' ';
  Dec(Alive);
  Inc(Deaths);
end;

{ ═══ Дорога первая: учёт ведёт язык ══════════════════════════════════════ }

type
  IChiThing = interface
    ['{6F1C2B70-6A3E-4C5D-9A21-0E7B5F3D8A11}']
    function Name: string;
    procedure Touch;
    function Touches: Integer;
  end;

  TChiThing = class(TInterfacedObject, IChiThing)
  private
    FName: string;
    FTouches: Integer;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    function Name: string;
    procedure Touch;
    function Touches: Integer;
  end;

constructor TChiThing.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  Born(FName);
end;

destructor TChiThing.Destroy;
begin
  Died(FName);
  inherited Destroy;
end;

function TChiThing.Name: string;
begin
  Result := FName;
end;

procedure TChiThing.Touch;
begin
  Inc(FTouches);
end;

function TChiThing.Touches: Integer;
begin
  Result := FTouches;
end;

{ ═══ Дорога вторая: учёт ведём руками ════════════════════════════════════ }

type
  { Тот же предмет без участия языка: счётчик ссылок — обычное поле, захват и
    отпускание пишутся явно, освобождение тоже. }
  TChiManual = class
  private
    FName: string;
    FRefs: Integer;
    FTouches: Integer;
  public
    constructor Create(const AName: string);
    procedure Grab;
    procedure Drop;
    procedure Touch;
    property Refs: Integer read FRefs;
    property Touches: Integer read FTouches;
    property Name: string read FName;
  end;

constructor TChiManual.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FRefs := 1;
  Born(FName);
end;

procedure TChiManual.Grab;
begin
  Inc(FRefs);
end;

procedure TChiManual.Drop;
begin
  Dec(FRefs);
  if FRefs = 0 then
  begin
    Died(FName);
    Free;
  end;
end;

procedure TChiManual.Touch;
begin
  Inc(FTouches);
end;

{ ═══ Работа первая: глубокая цепочка с исключением ═══════════════════════ }

procedure DeepAuto(Level, ThrowAt: Integer);
var
  Thing: IChiThing;
begin
  Thing := TChiThing.Create('A' + IntToStr(Level));
  Thing.Touch;
  if Level = ThrowAt then
    raise Exception.Create('глубина ' + IntToStr(Level));
  if Level < 6 then
    DeepAuto(Level + 1, ThrowAt);
  Thing.Touch;
end;

procedure DeepManual(Level, ThrowAt: Integer);
var
  Thing: TChiManual;
begin
  Thing := TChiManual.Create('A' + IntToStr(Level));
  try
    Thing.Touch;
    if Level = ThrowAt then
      raise Exception.Create('глубина ' + IntToStr(Level));
    if Level < 6 then
      DeepManual(Level + 1, ThrowAt);
    Thing.Touch;
  finally
    Thing.Drop;
  end;
end;

{ ═══ Работа вторая: обмен в хранилище ════════════════════════════════════ }

type
  TChiSlotsAuto = array [0 .. 7] of IChiThing;
  TChiSlotsManual = array [0 .. 7] of TChiManual;

{ Форма помощника списков: прежнее уводится в сторону, новое встаёт на место,
  оповещения получают ОБА, и лишь потом прежнее отпускается. }
procedure SetSlotAuto(var Slots: TChiSlotsAuto; Index: Integer; const Value: IChiThing);
var
  Old: IChiThing;
begin
  Old := Slots[Index];
  Slots[Index] := Value;
  if Old <> nil then Old.Touch;
  if Value <> nil then Value.Touch;
  Old := nil;
end;

procedure SetSlotManual(var Slots: TChiSlotsManual; Index: Integer; Value: TChiManual);
var
  Old: TChiManual;
begin
  Old := Slots[Index];
  if Value <> nil then Value.Grab;
  Slots[Index] := Value;
  if Old <> nil then Old.Touch;
  if Value <> nil then Value.Touch;
  if Old <> nil then Old.Drop;
end;

procedure ClearSlotsAuto(var Slots: TChiSlotsAuto);
begin
  for var I := 0 to High(Slots) do Slots[I] := nil;
end;

procedure ClearSlotsManual(var Slots: TChiSlotsManual);
begin
  for var I := 0 to High(Slots) do
    if Slots[I] <> nil then
    begin
      Slots[I].Drop;
      Slots[I] := nil;
    end;
end;

{ ═══ Работа третья: исключение из потока ═════════════════════════════════ }

type
  TChiWorker = class(TThread)
  private
    FThrow: Boolean;
    FDone:  Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AThrow: Boolean);
    property Done: Boolean read FDone;
  end;

constructor TChiWorker.Create(AThrow: Boolean);
begin
  FThrow := AThrow;
  inherited Create(False);
end;

procedure TChiWorker.Execute;
var
  Thing: IChiThing;
begin
  try
    Thing := TChiThing.Create('T');
    Thing.Touch;
    if FThrow then
      raise Exception.Create('из потока');
    Thing.Touch;
  except
    { перехвачено внутри потока: предмет всё равно обязан уйти на выходе }
  end;
  FDone := True;
end;

{ ═══ Работа четвёртая: управляемая запись ════════════════════════════════ }

type
  { Запись, где сходятся три управляемых вида сразу: строка, счётчик ссылок и
    динамический массив. Компилятор обязан обойти их все — и при копировании
    записи, и при её уходе. }
  TChiParcel = record
    Tag:   string;
    Thing: IChiThing;
    Data:  TArray<Integer>;
  end;

procedure FillParcel(out P: TChiParcel; const AName: string);
begin
  P.Tag := 'тег-' + AName;
  P.Thing := TChiThing.Create(AName);
  SetLength(P.Data, 4);
  for var I := 0 to 3 do P.Data[I] := I;
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiLifeRun: Int64;
var
  Acc:      UInt64;
  AutoTrace, ManualTrace: string;
  SA:       TChiSlotsAuto;
  SM:       TChiSlotsManual;
  Caught:   Boolean;
  W:        TChiWorker;
begin
  Acc := 0;
  ChiCovered(IdLife);

  { ── Глубокая цепочка: раскрутка обязана отпустить всё в обратном порядке ── }
  for var ThrowAt := 1 to 6 do
  begin
    ResetTrace;
    Caught := False;
    try
      DeepAuto(1, ThrowAt);
    except
      Caught := True;
    end;
    AutoTrace := Trace;
    ChiClaim(Caught, 'цепочка: исключение не дошло до вершины');
    ChiClaim(Alive = 0, 'цепочка: после раскрутки остались живые (учёт языка)');
    ChiClaim(Births = ThrowAt, 'цепочка: родилось не столько, сколько уровней');
    ChiClaim(Deaths = ThrowAt, 'цепочка: умерло не столько, сколько родилось');

    ResetTrace;
    Caught := False;
    try
      DeepManual(1, ThrowAt);
    except
      Caught := True;
    end;
    ManualTrace := Trace;
    ChiClaim(Alive = 0, 'цепочка: после раскрутки остались живые (ручной учёт)');
    ChiClaim(AutoTrace = ManualTrace,
      'цепочка: лента языка разошлась с ручной на глубине ' + IntToStr(ThrowAt));
    Acc := ChiMix(Acc, Length(AutoTrace));
  end;
  ChiBranch(IdLife, 'deep-unwind');

  { Без исключения лента обязана быть иной, но тоже сойтись между дорогами. }
  ResetTrace;
  DeepAuto(1, 0);
  AutoTrace := Trace;
  ChiClaim(Alive = 0, 'цепочка без исключения: остались живые');
  ChiClaim(Births = 6, 'цепочка без исключения: родилось не шесть');
  ResetTrace;
  DeepManual(1, 0);
  ChiClaim(AutoTrace = Trace, 'цепочка без исключения: ленты разошлись');
  ChiClaim(Pos('-A6', AutoTrace) < Pos('-A1', AutoTrace),
    'цепочка: глубокий уровень отпущен не раньше мелкого');
  ChiBranch(IdLife, 'deep-normal');

  { ── Обмен в хранилище: прежнее живо до конца оповещений ── }
  ResetTrace;
  FillChar(SA, SizeOf(SA), 0);
  for var I := 0 to 7 do SetSlotAuto(SA, I, TChiThing.Create('S' + IntToStr(I)));
  ChiClaim(Alive = 8, 'хранилище: живых не восемь');
  { замена каждого второго }
  for var I := 0 to 3 do SetSlotAuto(SA, I * 2, TChiThing.Create('N' + IntToStr(I)));
  ChiClaim(Alive = 8, 'хранилище: замена изменила число живых');
  ClearSlotsAuto(SA);
  ChiClaim(Alive = 0, 'хранилище: очистка оставила живых');
  AutoTrace := Trace;

  ResetTrace;
  FillChar(SM, SizeOf(SM), 0);
  for var I := 0 to 7 do
  begin
    var M := TChiManual.Create('S' + IntToStr(I));
    SetSlotManual(SM, I, M);
    M.Drop;   { отдали владение хранилищу }
  end;
  ChiClaim(Alive = 8, 'хранилище: ручной учёт дал не восемь живых');
  for var I := 0 to 3 do
  begin
    var M := TChiManual.Create('N' + IntToStr(I));
    SetSlotManual(SM, I * 2, M);
    M.Drop;
  end;
  ChiClaim(Alive = 8, 'хранилище: ручная замена изменила число живых');
  ClearSlotsManual(SM);
  ChiClaim(Alive = 0, 'хранилище: ручная очистка оставила живых');
  ChiClaim(AutoTrace = Trace, 'хранилище: ленты дорог разошлись');
  ChiBranch(IdLife, 'slot-replace');
  Acc := ChiMix(Acc, Length(Trace));

  { Присваивание слота самому себе не имеет права убить предмет. }
  ResetTrace;
  FillChar(SA, SizeOf(SA), 0);
  SetSlotAuto(SA, 0, TChiThing.Create('X'));
  SetSlotAuto(SA, 0, SA[0]);
  ChiClaim(Alive = 1, 'хранилище: присваивание самому себе убило предмет');
  ChiClaim(SA[0] <> nil, 'хранилище: слот опустел после присваивания себе');
  ClearSlotsAuto(SA);
  ChiClaim(Alive = 0, 'хранилище: после очистки остались живые');
  ChiBranch(IdLife, 'self-assign');

  { ── Защита выполняется при выходе из середины ── }
  ResetTrace;
  var Ran := False;
  try
    var Thing: IChiThing := TChiThing.Create('E');
    try
      Thing.Touch;
      raise Exception.Create('середина');
    finally
      Ran := True;
    end;
  except
  end;
  ChiClaim(Ran, 'защита: не выполнилась при исключении');
  ChiClaim(Alive = 0, 'защита: предмет пережил раскрутку');
  ChiBranch(IdLife, 'finally-runs');

  { Исключение ВНУТРИ защиты вытесняет исходное, но живых не оставляет. }
  ResetTrace;
  Caught := False;
  try
    var Guard: IChiThing := TChiThing.Create('F');
    try
      raise Exception.Create('первое');
    finally
      Guard.Touch;
      raise Exception.Create('второе');
    end;
  except
    on E: Exception do
      Caught := Pos('второе', E.Message) > 0;
  end;
  ChiClaim(Caught, 'защита: наверх пришло не то исключение');
  ChiClaim(Alive = 0, 'защита: исключение из защиты оставило живых');
  ChiBranch(IdLife, 'raise-in-finally');

  { ── Повторный бросок сохраняет предмет исключения ── }
  ResetTrace;
  Caught := False;
  try
    try
      var Held: IChiThing := TChiThing.Create('R');
      Held.Touch;
      raise Exception.Create('исходное');
    except
      raise;
    end;
  except
    on E: Exception do
      Caught := E.Message = 'исходное';
  end;
  ChiClaim(Caught, 'повторный бросок: сообщение изменилось');
  ChiClaim(Alive = 0, 'повторный бросок: остались живые');
  ChiBranch(IdLife, 'reraise');

  { ── Управляемая запись: три вида сразу ── }
  ResetTrace;
  var P1, P2: TChiParcel;
  FillParcel(P1, 'P');
  ChiClaim(Alive = 1, 'запись: предмет не родился');
  P2 := P1;                       { копирование записи со всеми управляемыми }
  ChiClaim(Alive = 1, 'запись: копирование родило второй предмет');
  ChiClaim(P2.Tag = P1.Tag, 'запись: строка не скопировалась');
  ChiClaim(Length(P2.Data) = 4, 'запись: массив не скопировался');
  P1 := Default(TChiParcel);
  ChiClaim(Alive = 1, 'запись: сброс одной копии убил предмет раньше времени');
  P2 := Default(TChiParcel);
  ChiClaim(Alive = 0, 'запись: сброс последней копии не убил предмет');
  ChiBranch(IdLife, 'managed-record');

  { Запись внутри динамического массива: рост, усадка и очистка. }
  ResetTrace;
  var Box: TArray<TChiParcel>;
  SetLength(Box, 5);
  for var I := 0 to 4 do FillParcel(Box[I], 'B' + IntToStr(I));
  ChiClaim(Alive = 5, 'массив записей: живых не пять');
  SetLength(Box, 2);
  ChiClaim(Alive = 2, 'массив записей: усадка не отпустила хвост');
  SetLength(Box, 6);
  ChiClaim(Alive = 2, 'массив записей: рост что-то родил');
  Box := nil;
  ChiClaim(Alive = 0, 'массив записей: очистка оставила живых');
  ChiBranch(IdLife, 'managed-array');
  Acc := ChiMix(Acc, Births);

  { ── Исключение в чужом потоке ── }
  ResetTrace;
  W := TChiWorker.Create(True);
  try
    W.WaitFor;
    ChiClaim(W.Done, 'поток: не дошёл до конца');
  finally
    W.Free;
  end;
  ChiClaim(Alive = 0, 'поток: исключение оставило живых');
  ChiClaim(Births = 1, 'поток: предмет не рождался');

  ResetTrace;
  W := TChiWorker.Create(False);
  try
    W.WaitFor;
  finally
    W.Free;
  end;
  ChiClaim(Alive = 0, 'поток: спокойный ход оставил живых');
  ChiBranch(IdLife, 'thread-unwind');

  { ── Передача доводом: по значению, как неизменяемый, по ссылке ── }
  ResetTrace;
  var Keep: IChiThing := TChiThing.Create('K');
  ChiClaim(Alive = 1, 'доводы: предмет не родился');
  SetSlotAuto(SA, 1, Keep);
  ChiClaim(Alive = 1, 'доводы: передача как неизменяемого родила второй');
  Keep := nil;
  ChiClaim(Alive = 1, 'доводы: хранилище не удержало предмет');
  ClearSlotsAuto(SA);
  ChiClaim(Alive = 0, 'доводы: после очистки остались живые');
  ChiBranch(IdLife, 'passing');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
