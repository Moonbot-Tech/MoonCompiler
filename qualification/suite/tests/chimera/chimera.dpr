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
  chimera_ring;

var
  Tape: TChiTape;
  Tally, RingTally: Int64;
begin
  Tape := ChiMakeTape(6000, 20260830);
  Tally := ChiTapeRun(Tape);

  RingTally := ChiRingRun;

  if ChiFailures = 0 then
    WriteLn('CHIMERA_OK tape=', Tally, ' ring=', RingTally)
  else
    WriteLn('CHIMERA_BAD claims=', ChiFailures,
            ' tape=', Tally, ' ring=', RingTally, ChiFailureList);
end.
