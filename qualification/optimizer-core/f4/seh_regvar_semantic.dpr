program seh_regvar_semantic;

{$mode unleashed}
{$Q-}{$R-}

uses
  SysUtils;

var
  Finalized: Integer;

type
  TCountedEnumerator = class
  private
    FCurrent, FLast: Integer;
  public
    class var Alive, Destroyed: Integer;
    constructor Create(ALast: Integer);
    destructor Destroy; override;
    function MoveNext: Boolean;
    property Current: Integer read FCurrent;
  end;

  TCountedRange = record
    Last: Integer;
    function GetEnumerator: TCountedEnumerator;
  end;

  TResultCarrier = class
  private
    FHeld: Pointer;
    FCleanups: Integer;
    procedure Leave; noinline;
  public
    constructor Create;
    function Take(out Value: Pointer): Boolean; noinline;
    property Cleanups: Integer read FCleanups;
  end;

constructor TCountedEnumerator.Create(ALast: Integer);
begin
  inherited Create;
  Inc(Alive);
  FCurrent := 0;
  FLast := ALast;
end;

destructor TCountedEnumerator.Destroy;
begin
  Dec(Alive);
  Inc(Destroyed);
  inherited;
end;

function TCountedEnumerator.MoveNext: Boolean;
begin
  Inc(FCurrent);
  Result := FCurrent <= FLast;
end;

function TCountedRange.GetEnumerator: TCountedEnumerator;
begin
  Result := TCountedEnumerator.Create(Last);
end;

constructor TResultCarrier.Create;
begin
  inherited Create;
  FHeld := Pointer(1234);
end;

procedure TResultCarrier.Leave;
begin
  Inc(FCleanups);
end;

function TResultCarrier.Take(out Value: Pointer): Boolean;
begin
  Value := nil;
  try
    if FHeld <> nil then
    begin
      Value := FHeld;
      FHeld := nil;
      Exit(True);
    end;
  finally
    Leave;
  end;
  Result := False;
end;

function LiveThroughAV(P: PInteger): Integer; noinline;
var
  X, Y, Z: Integer;
begin
  X := 42;
  Y := 1000;
  Z := 7;
  try
    P^ := 1;
  except
    on EAccessViolation do
      ;
  end;
  Result := X + Y * 2 + Z * 3;
end;

function AssignedInsideReadAfter(P: PInteger; Bias: Integer): Integer; noinline;
var
  Acc, I: Integer;
begin
  Acc := 0;
  try
    for I := 1 to 10 do
      Acc := Acc + I * Bias;
    P^ := Acc;
  except
    on EAccessViolation do
      ;
  end;
  Result := Acc;
end;

function FirstAssignedInsideReadAfter(P: PInteger; Bias: Integer): Integer; noinline;
var
  Acc: Integer;
begin
  try
    Acc := Bias * 11;
    P^ := Acc;
  except
    on EAccessViolation do
      ;
  end;
  Result := Acc;
end;

function FinallySeesLatest(Limit: Integer): Integer; noinline;
var
  I, Steps, Seen: Integer;
begin
  Seen := -1;
  Steps := 0;
  try
    try
      for I := 1 to Limit do begin
        Inc(Steps);
        If I = 7 then
          raise EAbort.Create('stop');
      end;
    finally
      Seen := Steps;
    end;
  except
    on EAbort do
      ;
  end;
  Result := Seen;
end;

function ExitThroughFinally(Limit: Integer): Integer; noinline;
var
  I, Acc: Integer;
begin
  Acc := 5;
  for I := 1 to Limit do begin
    try
      Inc(Acc, I);
      If I = 4 then
        Exit(Acc);
    finally
      Inc(Finalized);
    end;
  end;
  Result := -1;
end;

function NestedRecordFallback(Seed: Integer): Integer; noinline;
type
  TPair = record
    A, B: Integer;
  end;
var
  Pair: TPair;

  procedure Touch;
  begin
    Inc(Pair.A);
  end;

begin
  Pair.A := Seed;
  Pair.B := Seed * 3;
  try
    Touch;
  except
    Pair.B := -1;
  end;
  Result := Pair.A + Pair.B;
end;

function NestedHandlerStaticChain(Seed: Integer; RaiseIt: Boolean): Integer; noinline;
type
  TPair = record
    A, B: Integer;
  end;
var
  Pair: TPair;

  procedure Execute;
  begin
    try
      Inc(Pair.A, 5);
      If RaiseIt then
        raise EAbort.Create('nested-handler');
      Inc(Pair.B, 7);
    except
      on EAbort do
        Pair.B := Pair.B + Pair.A * 2;
    end;
  end;

begin
  Pair.A := Seed;
  Pair.B := Seed * 3;
  Execute;
  Result := Pair.A + Pair.B;
end;

function NestedHardwareTrapStaticChain(Seed: Integer): Integer; noinline;
var
  Captured, Calls, First, Second: Integer;

  function DivideOrAdd(X: Integer): Integer;
  begin
    Inc(Calls);
    try
      Result := Captured div (X and 3);
    except
      Result := Captured + X;
    end;
  end;

begin
  Captured := Seed;
  Calls := 0;
  First := DivideOrAdd(4);
  Second := DivideOrAdd(3);
  Result := First + Second * 1000 + Captured * 100000 + Calls * 10000000;
end;

function GeneratedCleanupComplete(Limit: Integer): Integer; noinline;
var
  Range: TCountedRange;
  Value, Sum: Integer;
begin
  Range.Last := Limit;
  Sum := 0;
  for Value in Range do
    Inc(Sum, Value * 3);
  Result := Sum;
end;

function GeneratedCleanupBreak(Limit: Integer): Integer; noinline;
var
  Range: TCountedRange;
  Value, Sum: Integer;
begin
  Range.Last := Limit;
  Sum := 0;
  for Value in Range do begin
    Inc(Sum, Value);
    If Value = 4 then
      Break;
  end;
  Result := Sum;
end;

procedure GeneratedCleanupRaise(Limit: Integer); noinline;
var
  Range: TCountedRange;
  Value, Sum: Integer;
begin
  Range.Last := Limit;
  Sum := 0;
  for Value in Range do begin
    Inc(Sum, Value);
    If Value = 3 then
      raise EAbort.Create('generated-cleanup');
  end;
  If Sum = -1 then
    Halt(2);
end;

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Halt(1);
  end;
end;

var
  Sink: Integer;
  ResultCarrier: TResultCarrier;
  Taken: Pointer;
begin
  Check('live/av', LiveThroughAV(nil), 2063);
  Check('live/ok', LiveThroughAV(@Sink), 2063);
  Check('assigned/av', AssignedInsideReadAfter(nil, 2), 110);
  Check('assigned/ok', AssignedInsideReadAfter(@Sink, 2), 110);
  Check('first-assigned/av', FirstAssignedInsideReadAfter(nil, 3), 33);
  Check('first-assigned/ok', FirstAssignedInsideReadAfter(@Sink, 3), 33);
  Check('finally/latest', FinallySeesLatest(100), 7);
  Finalized := 0;
  Check('exit/finally', ExitThroughFinally(100), 15);
  Check('exit/count', Finalized, 4);
  ResultCarrier := TResultCarrier.Create;
  try
    Check('exit-result/value', Ord(ResultCarrier.Take(Taken)), 1);
    Check('exit-result/payload', Integer(PtrUInt(Taken)), 1234);
    Check('exit-result/cleanup', ResultCarrier.Cleanups, 1);
  finally
    ResultCarrier.Free;
  end;
  Check('nested-record-fallback', NestedRecordFallback(11), 45);
  Check('nested-handler/static-chain/normal',
    NestedHandlerStaticChain(11, False), 56);
  Check('nested-handler/static-chain/raise',
    NestedHandlerStaticChain(11, True), 81);
  Check('nested-hardware-trap/static-chain',
    NestedHardwareTrapStaticChain(215), 41571219);
  TCountedEnumerator.Alive := 0;
  TCountedEnumerator.Destroyed := 0;
  Check('generated/complete', GeneratedCleanupComplete(5), 45);
  Check('generated/complete-alive', TCountedEnumerator.Alive, 0);
  Check('generated/complete-destroyed', TCountedEnumerator.Destroyed, 1);
  Check('generated/break', GeneratedCleanupBreak(20), 10);
  Check('generated/break-alive', TCountedEnumerator.Alive, 0);
  Check('generated/break-destroyed', TCountedEnumerator.Destroyed, 2);
  try
    GeneratedCleanupRaise(20);
  except
    on EAbort do
      ;
  end;
  Check('generated/raise-alive', TCountedEnumerator.Alive, 0);
  Check('generated/raise-destroyed', TCountedEnumerator.Destroyed, 3);
  WriteLn('SEHREGVAR:PASS');
end.
