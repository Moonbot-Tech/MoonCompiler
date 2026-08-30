program chimera;

{             Quidquid latet apparebit, nil inultum remanebit.
                            Festina lente.

  Третья большая программа Devil. У резидента предмет проверки — счёт под
  нагрузкой, у завода — устройство приложения. Здесь — КОДОФОРМЫ ДВУХ ЖИВЫХ
  ПРОЕКТОВ: Арбитража и MoonBot. Ничего не придумано: каждый орган химеры
  сшит из настоящего куска настоящего кода, и вместе они обязаны покрыть всё,
  из чего эти два приложения состоят.

  Каждая перенесённая работа живёт здесь не одним телом, а несколькими — от
  монолита с сорока живыми значениями до дробления на вставляемые шаги, — и
  все обязаны дать один ответ. Дробить вместо целого нельзя: баг, который
  живёт только на большом теле, на мелких кусках не рождается. }

{$mode delphi}{$Q-}{$R-}{$APPTYPE CONSOLE}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils,
  chimera_body,
  chimera_tape_types,
  chimera_tape_leaf,
  chimera_tape_ring_far,
  chimera_tape_v3,
  chimera_tape_v4,
  chimera_tape,
  chimera_crew,
  chimera_ring,
  chimera_sort,
  chimera_agg,
  chimera_code,
  chimera_name,
  chimera_wire,
  chimera_pairs,
  chimera_hands,
  chimera_buf,
  chimera_sign,
  chimera_hold,
  chimera_proto,
  chimera_book,
  chimera_task,
  chimera_json,
  chimera_stream,
  chimera_group,
  chimera_hl,
  chimera_strat,
  chimera_users,
  chimera_pack,
  chimera_text,
  chimera_shake,
  chimera_state,
  chimera_field,
  chimera_life;

{ Отбор органа для быстрой разработки: `chimera --focus <ID или орган>`.
  Отбор НЕ убирает орган из общего прогона — он только позволяет не ждать
  остальные, пока чинишь один. Без параметра работают все. }
function Wanted(const AId, AOrgan: string): Boolean;
var
  I: Integer;
  Focus: string;
begin
  Result := True;
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--focus' then
    begin
      Focus := ParamStr(I + 1);
      Result := (Focus = AId) or (Focus = AOrgan);
      Exit;
    end;
end;

var
  Tape: TChiTape;
  Tally, RingTally, SortTally, AggTally, CodeTally, NameTally, WireTally,
    PairTally, HandsTally, BufTally, SignTally, HoldTally, ProtoTally,
    BookTally, TaskTally, JsonTally, StreamTally, GroupTally, HlTally,
    StratTally, UsersTally, PackTally, TextTally, ShakeTally, StateTally,
    FieldTally, LifeTally: Int64;
begin
  Tally := 0;
  RingTally := 0;
  SortTally := 0;
  AggTally := 0;
  CodeTally := 0;
  NameTally := 0;
  WireTally := 0;
  PairTally := 0;
  HandsTally := 0;
  BufTally := 0;
  SignTally := 0;
  HoldTally := 0;
  ProtoTally := 0;
  BookTally := 0;
  TaskTally := 0;
  JsonTally := 0;
  StreamTally := 0;
  GroupTally := 0;
  HlTally := 0;
  StratTally := 0;
  UsersTally := 0;
  PackTally := 0;
  TextTally := 0;
  ShakeTally := 0;
  StateTally := 0;
  FieldTally := 0;
  LifeTally := 0;

  if Wanted('CHI-MB-TAPE-001', 'tape') then
  begin
    Tape := ChiMakeTape(6000, 20260830);
    Tally := ChiTapeRun(Tape);
  end;

  if Wanted('CHI-MB-RING-001', 'ring') then
    RingTally := ChiRingRun;

  if Wanted('CHI-MB-SORT-001', 'sort') then
    SortTally := ChiSortRun;

  if Wanted('CHI-MB-TRADE-002', 'agg') then
    AggTally := ChiAggRun;

  if Wanted('CHI-MB-CODE-001', 'code') then
    CodeTally := ChiCodeRun;

  if Wanted('CHI-ARB-NAME-001', 'name') then
    NameTally := ChiNameRun;

  if Wanted('CHI-ARB-WIRE-001', 'wire') then
    WireTally := ChiWireRun;

  if Wanted('CHI-ARB-PAIR-001', 'pairs') then
    PairTally := ChiPairsRun;

  if Wanted('CHI-MB-CLOS-001', 'hands') then
    HandsTally := ChiHandsRun;

  if Wanted('CHI-MB-BUF-001', 'buf') then
    BufTally := ChiBufRun;

  if Wanted('CHI-MB-SIGN-001', 'sign') then
    SignTally := ChiSignRun;

  if Wanted('CHI-ARB-BUF-001', 'hold') then
    HoldTally := ChiHoldRun;

  if Wanted('CHI-MB-PROTO-001', 'proto') then
    ProtoTally := ChiProtoRun;

  if Wanted('CHI-MB-BOOK-001', 'book') then
    BookTally := ChiBookRun;

  if Wanted('CHI-MB-TASK-001', 'task') then
    TaskTally := ChiTaskRun;

  if Wanted('CHI-MB-JSON-001', 'json') then
    JsonTally := ChiJsonRun;

  if Wanted('CHI-ARB-STREAM-001', 'stream') then
    StreamTally := ChiStreamRun;

  if Wanted('CHI-ARB-GROUP-001', 'group') then
    GroupTally := ChiGroupRun;

  if Wanted('CHI-MB-HL-001', 'hl') then
    HlTally := ChiHlRun;

  if Wanted('CHI-MB-STRAT-001', 'strat') then
    StratTally := ChiStratRun;

  if Wanted('CHI-ARB-USERS-001', 'users') then
    UsersTally := ChiUsersRun;

  if Wanted('CHI-MB-PACK-001', 'pack') then
    PackTally := ChiPackRun;

  if Wanted('CHI-ARB-TEXT-001', 'text') then
    TextTally := ChiTextRun;

  if Wanted('CHI-MB-SHAKE-001', 'shake') then
    ShakeTally := ChiShakeRun;

  if Wanted('CHI-MB-STATE-001', 'state') then
    StateTally := ChiStateRun;

  if Wanted('CHI-MB-FIELD-001', 'field') then
    FieldTally := ChiFieldRun;

  if Wanted('CHI-MB-LIFE-001', 'life') then
    LifeTally := ChiLifeRun;

  { Отчёт покрытия печатается ВСЕГДА, в том числе при нарушенных
    утверждениях: гейту нужно знать, что успело исполниться, даже когда
    что-то сломалось. }
  Write(ChiCoverageReport);

  if ChiFailures = 0 then
    WriteLn('CHIMERA_OK tape=', Tally, ' ring=', RingTally,
            ' sort=', SortTally, ' agg=', AggTally, ' code=', CodeTally,
            ' name=', NameTally, ' wire=', WireTally, ' pairs=', PairTally,
            ' hands=', HandsTally, ' buf=', BufTally, ' sign=', SignTally,
            ' hold=', HoldTally, ' proto=', ProtoTally, ' book=', BookTally,
            ' task=', TaskTally, ' json=', JsonTally, ' stream=', StreamTally,
            ' group=', GroupTally, ' hl=', HlTally, ' strat=', StratTally,
            ' users=', UsersTally, ' pack=', PackTally, ' text=', TextTally,
            ' shake=', ShakeTally, ' state=', StateTally,
            ' field=', FieldTally, ' life=', LifeTally)
  else
  begin
    WriteLn('CHIMERA_BAD claims=', ChiFailures,
            ' tape=', Tally, ' ring=', RingTally,
            ' sort=', SortTally, ' agg=', AggTally, ' code=', CodeTally,
            ' name=', NameTally, ' wire=', WireTally, ' pairs=', PairTally,
            ' hands=', HandsTally, ' buf=', BufTally, ' sign=', SignTally,
            ' hold=', HoldTally, ' proto=', ProtoTally, ' book=', BookTally,
            ' task=', TaskTally, ' json=', JsonTally, ' stream=', StreamTally,
            ' group=', GroupTally, ' hl=', HlTally, ' strat=', StratTally,
            ' users=', UsersTally, ' pack=', PackTally, ' text=', TextTally,
            ' shake=', ShakeTally, ' state=', StateTally,
            ' field=', FieldTally, ' life=', LifeTally,
            ChiFailureList);
    Halt(1);
  end;
end.
