program string_refcount_concurrency_semantic;

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
{$ifdef unix}
  cthreads,
{$endif}
  SysUtils,
  Classes;

const
  ThreadCount = 16;
  IterationCount = 2000;

type
  TCopyThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  SharedText: UnicodeString;
  ArrivedCount: LongInt;
  HeldCount: LongInt;
  DoneCount: LongInt;
  StartGeneration: LongInt;
  ReleaseGeneration: LongInt;
  ResetGeneration: LongInt;

function AtomicRead(var Value: LongInt): LongInt; inline;
begin
  Result := InterlockedCompareExchange(Value, 0, 0);
end;

procedure SpinUntil(var Value: LongInt; Expected: LongInt); inline;
begin
  while AtomicRead(Value) < Expected do
    TThread.Yield;
end;

procedure TCopyThread.Execute;
var
  I: Integer;
  LocalText: UnicodeString;
begin
  for I := 1 to IterationCount do
    begin
      InterlockedIncrement(ArrivedCount);
      SpinUntil(StartGeneration, I);
      LocalText := SharedText;
      InterlockedIncrement(HeldCount);
      SpinUntil(ReleaseGeneration, I);
      if (Length(LocalText) <> 256) or (LocalText[1] <> 'x') then
        Halt(2);
      LocalText := '';
      InterlockedIncrement(DoneCount);
      SpinUntil(ResetGeneration, I);
    end;
end;

var
  Threads: array[0..ThreadCount - 1] of TCopyThread;
  I, J: Integer;
  HeldRefCount: SizeInt;
  Failures: Integer;
  ExpectedCount: LongInt;
begin
  { Build the shared value in place.  A function-result temporary may remain
    alive to the end of the surrounding scope and would add an unrelated
    owner to the exact refcount checked by this concurrency test. }
  SetLength(SharedText, 256);
  for I := 1 to Length(SharedText) do
    SharedText[I] := 'x';
  if StringRefCount(SharedText) <> 1 then
    Halt(3);
  for J := 0 to High(Threads) do
    Threads[J] := TCopyThread.Create(True);
  try
    for J := 0 to High(Threads) do
      Threads[J].Start;
    Failures := 0;
    for I := 1 to IterationCount do
      begin
        ExpectedCount := I * ThreadCount;
        SpinUntil(ArrivedCount, ExpectedCount);
        InterlockedExchange(StartGeneration, I);
        SpinUntil(HeldCount, ExpectedCount);
        HeldRefCount := StringRefCount(SharedText);
        if HeldRefCount <> ThreadCount + 1 then
          begin
            Inc(Failures);
            { Keep the test process memory-safe even when run against the
              rejected non-atomic increment experiment. }
            InterlockedExchange(PLongInt(PByte(Pointer(SharedText)) - 12)^,
              ThreadCount + 1);
          end;
        InterlockedExchange(ReleaseGeneration, I);
        SpinUntil(DoneCount, ExpectedCount);
        if StringRefCount(SharedText) <> 1 then
          Halt(4);
        InterlockedExchange(ResetGeneration, I);
      end;
    for J := 0 to High(Threads) do
      Threads[J].WaitFor;
    if Failures <> 0 then
      begin
        WriteLn('FAIL lost-refcount-increments=', Failures);
        Halt(1);
      end;
  finally
    for J := 0 to High(Threads) do
      Threads[J].Free;
  end;
  WriteLn('STRING_REFCOUNT_CONCURRENCY_OK');
end.
