program tinlineblock1;

{$mode delphi}
{$inline on}
{$optimization autoinline}
{$optimization dfa}
{$optimization deadstore}
{$optimization deadvalues}
{$optimization constprop}
{$optimization cse}

uses
  uinlineblock1;

var
  Wrapper: TWrapper;
  SourceA,
  SourceB,
  AReads,
  BReads,
  CallbackCalls: LongInt;

function ReadA: LongInt; noinline;
begin
  Inc(AReads);
  Result := SourceA;
end;

function ReadB: LongInt; noinline;
begin
  Inc(BReads);
  Result := SourceB;
end;

function Callback(ARequired: LongInt): LongInt; noinline;
begin
  Inc(CallbackCalls);
  Result := ARequired + 100;
end;

procedure Reset(const A, B: LongInt);
begin
  SourceA := A;
  SourceB := B;
  AReads := 0;
  BReads := 0;
  CallbackCalls := 0;
end;

procedure CheckReads(const Code: LongInt);
begin
  if AReads <> 1 then
    Halt(Code);
  if BReads <> 1 then
    Halt(Code + 1);
end;

begin
  Wrapper.Callback := nil;

  Reset(3, 20);
  if Wrapper.Shrink(ReadA, ReadB) <> 6 then
    Halt(1);
  CheckReads(2);

  Reset(5, 20);
  if Wrapper.Shrink(ReadA, ReadB) <> -1 then
    Halt(4);
  CheckReads(5);

  Reset(-3, -10);
  if Wrapper.Shrink(ReadA, ReadB) <> -6 then
    Halt(7);
  CheckReads(8);

  Reset(High(LongInt), High(LongInt));
  if Wrapper.Shrink(ReadA, ReadB) <> -1 then
    Halt(10);
  CheckReads(11);

  Wrapper.Callback := @Callback;
  Reset(7, 99);
  if Wrapper.Shrink(ReadA, ReadB) <> 107 then
    Halt(13);
  CheckReads(14);
  if CallbackCalls <> 1 then
    Halt(16);

  Wrapper.Callback := nil;
  if Wrapper.Shrink(3, 20) <> 6 then
    Halt(17);
  if TFallback.Shrink(5, 20) <> -1 then
    Halt(18);
end.
