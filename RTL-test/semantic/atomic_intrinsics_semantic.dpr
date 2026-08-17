program atomic_intrinsics_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the x86-64 inline code generation of the atomic
  intrinsics: exact return-value contracts (Increment/Decrement return the
  new value, Exchange/CmpExchange the old one), memory results, the
  InterLocked* wrappers built on top, and a multi-threaded increment race
  that must lose no updates. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils, Classes;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

var
  L32: LongInt;
  L64: Int64;
  Old32: LongInt;
  Old64: Int64;

type
  TIncThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  SharedCounter: LongInt;
  Shared64: Int64;

procedure TIncThread.Execute;
var
  I: Integer;
begin
  for I := 1 to 100000 do
  begin
    InterlockedIncrement(SharedCounter);
    InterlockedIncrement64(Shared64);
  end;
end;

var
  Threads: array[0..3] of TIncThread;
  I: Integer;
begin
  { 32-bit contracts }
  L32 := 5;
  If AtomicIncrement(L32) <> 6 then
    Fail('AtomicIncrement returns new');
  If L32 <> 6 then
    Fail('AtomicIncrement memory');
  If AtomicDecrement(L32) <> 5 then
    Fail('AtomicDecrement returns new');
  If AtomicIncrement(L32, 10) <> 15 then
    Fail('AtomicIncrement delta returns new');
  If L32 <> 15 then
    Fail('AtomicIncrement delta memory');
  If AtomicDecrement(L32, 7) <> 8 then
    Fail('AtomicDecrement delta returns new');
  Old32 := AtomicExchange(L32, 100);
  If (Old32 <> 8) or (L32 <> 100) then
    Fail('AtomicExchange');
  Old32 := AtomicCmpExchange(L32, 200, 100);
  If (Old32 <> 100) or (L32 <> 200) then
    Fail('AtomicCmpExchange hit');
  Old32 := AtomicCmpExchange(L32, 300, 100);
  If (Old32 <> 200) or (L32 <> 200) then
    Fail('AtomicCmpExchange miss');

  { 64-bit contracts with values beyond 32 bits }
  L64 := Int64($100000000);
  If AtomicIncrement(L64) <> Int64($100000001) then
    Fail('AtomicIncrement64 returns new');
  If AtomicDecrement(L64, 2) <> Int64($FFFFFFFF) then
    Fail('AtomicDecrement64 delta');
  Old64 := AtomicExchange(L64, Int64($200000000));
  If (Old64 <> Int64($FFFFFFFF)) or (L64 <> Int64($200000000)) then
    Fail('AtomicExchange64');
  Old64 := AtomicCmpExchange(L64, Int64($300000000), Int64($200000000));
  If (Old64 <> Int64($200000000)) or (L64 <> Int64($300000000)) then
    Fail('AtomicCmpExchange64');

  { InterLocked wrappers keep their historical contracts }
  L32 := 10;
  If InterlockedIncrement(L32) <> 11 then
    Fail('InterlockedIncrement');
  If InterlockedDecrement(L32) <> 10 then
    Fail('InterlockedDecrement');
  If InterlockedExchange(L32, 55) <> 10 then
    Fail('InterlockedExchange returns old');
  If InterlockedExchangeAdd(L32, 5) <> 55 then
    Fail('InterlockedExchangeAdd returns old');
  If L32 <> 60 then
    Fail('InterlockedExchangeAdd memory');
  If InterlockedCompareExchange(L32, 70, 60) <> 60 then
    Fail('InterlockedCompareExchange');
  If L32 <> 70 then
    Fail('InterlockedCompareExchange memory');

  { negative crossings }
  L32 := 0;
  If AtomicDecrement(L32) <> -1 then
    Fail('AtomicDecrement below zero');
  If AtomicIncrement(L32) <> 0 then
    Fail('AtomicIncrement back to zero');

  { four threads, no lost updates }
  SharedCounter := 0;
  Shared64 := 0;
  for I := 0 to 3 do
    Threads[I] := TIncThread.Create(False);
  for I := 0 to 3 do
  begin
    Threads[I].WaitFor;
    FreeAndNil(Threads[I]);
  end;
  If SharedCounter <> 400000 then
    Fail(Format('threaded 32-bit count %d', [SharedCounter]));
  If Shared64 <> 400000 then
    Fail(Format('threaded 64-bit count %d', [Shared64]));

  WriteLn('ATOMIC_INTRINSICS_OK');
end.
