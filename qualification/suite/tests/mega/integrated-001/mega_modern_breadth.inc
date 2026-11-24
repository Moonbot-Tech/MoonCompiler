{ The same feature gates as the original Modern Forms corpus. }

{$ifdef HAS_ANON}
type
  TBreadthClosure = reference to function(Delta: Integer; AbortCall: Boolean): AnsiString;
  TBreadthClosures = array of TBreadthClosure;

function BreadthMakeManagedClosure(Text: AnsiString; Start: Integer; Owner: IInterface): TBreadthClosure;
var
  Value: Integer;
begin
  Value := Start;
  Result := function(Delta: Integer; AbortCall: Boolean): AnsiString
    begin
      Inc(Value, Delta);
      If AbortCall then
        raise EAbort.Create('managed closure invocation');
      Check(Owner <> nil, 'breadth-closure-captured-owner-live-during-call');
      Result := Text + AnsiString(IntToStr(Value));
    end;
end;

procedure BreadthReduceClosureContainer(var Kept: TBreadthClosure);
var
  Cells: TBreadthClosures;
  A, B: IInterface;
  Text: AnsiString;
begin
  SetLength(Cells, 3);
  Text := 'left:';
  A := TIntersectionOwner.Create;
  Cells[0] := BreadthMakeManagedClosure(Text, Integer(OpaqueI(15)), A);
  Cells[1] := Cells[0];
  Text[1] := 'X';
  B := TIntersectionOwner.Create;
  Cells[0] := BreadthMakeManagedClosure(Text, Integer(OpaqueI(-30)), B);
  Cells[2] := Cells[0];
  A := nil;
  B := nil;
  Kept := Cells[1];
  Check(Kept(2, False) = AnsiString('left:17'), 'breadth-closure-value-parameter-retains-original-string');
  Check(Cells[2](5, False) = AnsiString('Xeft:-25'), 'breadth-closure-independent-container-alias');
  SetLength(Cells, 1);
  Check(Kept(-3, False) = AnsiString('left:14'), 'breadth-closure-kept-after-shrink');
end;

procedure BreadthInvokeRetainedClosure;
var
  Kept: TBreadthClosure;
  Last: AnsiString;
  Caught: Boolean;
begin
  BreadthReduceClosureContainer(Kept);
  Check(TIntersectionOwner.Destroyed = 1, 'breadth-closure-container-releases-one-owner');
  Caught := False;
  try
    Kept(100, True);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught, 'breadth-closure-throws-after-captured-mutation');
  Last := Kept(-5, False);
  Check(Last = AnsiString('left:109'), 'breadth-closure-retains-mutation-after-exception');
  Mix(UInt64(Length(Last)));
end;

procedure RunBreadthClosureLifetime;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthInvokeRetainedClosure;
  Check(TIntersectionOwner.Destroyed = 2, 'breadth-closure-final-frame-releases-owner');
end;

type
  TBreadthTransform<T> = class
  type
    TStep = reference to function(const Value: T; Delta: Integer): T;
    TRun = reference to function(Delta: Integer): T;
  public
    class function Start(Initial: T; const Apply: TStep): TRun; static;
  end;

class function TBreadthTransform<T>.Start(Initial: T; const Apply: TStep): TRun;
var
  Current: T;
  Step: TStep;
begin
  Current := Initial;
  Step := Apply;
  Result := function(Delta: Integer): T
    begin
      Current := Step(Current, Delta);
      Result := Current;
    end;
end;

type
  TBreadthEntryTransform = TBreadthTransform<TCrossEntry>;
  TBreadthIntTransform = TBreadthTransform<Int64>;

function BreadthMakeEntryRunner(Scale: Integer): TBreadthEntryTransform.TRun;
var
  Start: TCrossEntry;
begin
  Start.Code := OpaqueI(-71);
  Start.Text := 'tag';
  Result := TBreadthEntryTransform.Start(Start,
    function(const Value: TCrossEntry; Delta: Integer): TCrossEntry
    begin
      Result.Code := Value.Code + Delta * Scale;
      Result.Text := Value.Text + AnsiChar(Ord('A') + Delta);
    end);
end;

procedure RunBreadthGenericClosureResult;
var
  Managed: TBreadthEntryTransform.TRun;
  Number: TBreadthIntTransform.TRun;
  First, Next: TCrossEntry;
  Actual: Int64;
begin
  Managed := BreadthMakeEntryRunner(Integer(OpaqueI(11)));
  Number := TBreadthIntTransform.Start(OpaqueI(92000000007),
    function(const Value: Int64; Delta: Integer): Int64
    begin
      Result := Value + Int64(Delta) * 1000000007;
    end);
  First := Managed(3);
  Actual := Number(-17);
  Next := Managed(5);
  Check((First.Code = -38) and (First.Text = AnsiString('tagD')), 'breadth-generic-closure-first-result-snapshot');
  Check((Next.Code = 17) and (Next.Text = AnsiString('tagDF')), 'breadth-generic-closure-nested-managed-return');
  Check(Actual = 74999999888, 'breadth-generic-closure-unmanaged-specialization');
  Actual := Number(19);
  Check(Actual = 94000000021, 'breadth-generic-closure-specialization-keeps-own-state');
  Mix(UInt64(Actual));
end;
{$endif}

{$ifdef HAS_INLINEVAR}
procedure BreadthInlineUnwindBody(AbortLoop: Boolean; var Trace, Cleanup: Integer);
begin
  for var Step := 1 to 4 do
  begin
    var Guard: IInterface := TIntersectionOwner.Create;
    var LabelText := UnicodeString('step-') + UnicodeString(IntToStr(Step));
    try
      case Step of
        1: Continue;
        2: Trace := Length(LabelText);
        3:
          If AbortLoop then
            raise EAbort.Create('inline variable scope')
          else
            Break;
      end;
    finally
      Check((Guard <> nil) and (LabelText[6] = WideChar(Ord('0') + Step)), 'breadth-inline-var-finally-sees-live-values');
      Cleanup := Cleanup * 10 + Step;
    end;
  end;
end;

procedure RunBreadthInlineCleanup;
var
  Trace, Cleanup: Integer;
  Caught: Boolean;
begin
  TIntersectionOwner.Destroyed := 0;
  Trace := 0;
  Cleanup := 0;
  BreadthInlineUnwindBody(False, Trace, Cleanup);
  Check((Trace = 6) and (Cleanup = 123), 'breadth-inline-var-continue-break-finally');
  Check(TIntersectionOwner.Destroyed = 3, 'breadth-inline-var-break-releases-all');
  Trace := 0;
  Cleanup := 0;
  Caught := False;
  try
    BreadthInlineUnwindBody(True, Trace, Cleanup);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Trace = 6) and (Cleanup = 123), 'breadth-inline-var-throw-finally');
  Check(TIntersectionOwner.Destroyed = 6, 'breadth-inline-var-unwind-releases-all');
  Mix(UInt64(Cleanup));
end;
{$endif}

{$ifdef HAS_MREC}
type
  TBreadthOperatorCell = record
    Token: Integer;
    class operator Initialize(out Value: TBreadthOperatorCell);
    class operator Finalize(var Value: TBreadthOperatorCell);
  end;

  TBreadthOperatorEnvelope = record
    Anchor: TBreadthOperatorCell;
    Grid: array[2..3, -1..0] of TBreadthOperatorCell;
  end;

  TBreadthOperatorClass = class
    Envelope: TBreadthOperatorEnvelope;
    constructor Create(AbortConstruction: Boolean);
  end;

  TBreadthOperatorSubclass = class(TBreadthOperatorClass)
    Tail: array[0..2] of TBreadthOperatorCell;
  end;

var
  BreadthAllocated, BreadthFinalized: Integer;
  BreadthInitAttempts, BreadthFailOnInitialize, BreadthConstructorBodies: Integer;
  BreadthLiveOperatorTokens: set of Byte;

class operator TBreadthOperatorCell.Initialize(out Value: TBreadthOperatorCell);
begin
  Inc(BreadthInitAttempts);
  If BreadthInitAttempts = BreadthFailOnInitialize then
    raise EAbort.Create('custom array element Initialize');
  Inc(BreadthAllocated);
  Value.Token := BreadthAllocated + 10;
  Include(BreadthLiveOperatorTokens, Value.Token);
end;

class operator TBreadthOperatorCell.Finalize(var Value: TBreadthOperatorCell);
begin
  Check(Value.Token in BreadthLiveOperatorTokens, 'breadth-mrec-finalize-matches-live-token');
  Exclude(BreadthLiveOperatorTokens, Value.Token);
  Inc(BreadthFinalized);
end;

constructor TBreadthOperatorClass.Create(AbortConstruction: Boolean);
var
  Total, Row, Column: Integer;
begin
  inherited Create;
  Inc(BreadthConstructorBodies);
  Total := Envelope.Anchor.Token;
  for Row := Low(Envelope.Grid) to High(Envelope.Grid) do
    for Column := Low(Envelope.Grid[Row]) to High(Envelope.Grid[Row]) do
      Inc(Total, Envelope.Grid[Row, Column].Token);
  Check(Total = 65 + BreadthFinalized * 5, 'breadth-mrec-class-array-fields-initialized');
  If AbortConstruction then
    raise EAbort.Create('custom managed array construction');
end;

procedure BreadthResetOperatorLifetime;
begin
  BreadthAllocated := 0;
  BreadthFinalized := 0;
  BreadthInitAttempts := 0;
  BreadthFailOnInitialize := 0;
  BreadthConstructorBodies := 0;
  BreadthLiveOperatorTokens := [];
end;

procedure RunBreadthOperatorArrayLifecycle;
var
  Obj: TBreadthOperatorClass;
  Caught: Boolean;
begin
  BreadthResetOperatorLifetime;
  Obj := nil;
  Caught := False;
  try
    Obj := TBreadthOperatorClass.Create(True);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Obj = nil), 'breadth-mrec-class-constructor-exception');
  Obj.Free;
  Check((BreadthAllocated = 5) and (BreadthFinalized = 5) and (BreadthLiveOperatorTokens = []),
    'breadth-mrec-class-constructor-unwinds-array');
  Obj := TBreadthOperatorClass.Create(False);
  try
    Check((BreadthAllocated = 10) and (BreadthFinalized = 5), 'breadth-mrec-class-field-initialization-count');
  finally
    Obj.Free;
  end;
  Check((BreadthFinalized = 10) and (BreadthLiveOperatorTokens = []), 'breadth-mrec-class-field-finalization-count');
  Mix(UInt64(BreadthFinalized));
end;

procedure RunBreadthOperatorCallerStorage;
const
  LeftGuard = UInt64($A1B7C3D4E5098172);
  RightGuard = UInt64($7183C9DE02154BA6);
var
  Storage: array[0..15] of UInt64;
  Obj: TObject;
  Caught: Boolean;
begin
  BreadthResetOperatorLifetime;
  BreadthFailOnInitialize := 3;
  Storage[0] := LeftGuard;
  Storage[High(Storage)] := RightGuard;
  Obj := nil;
  Caught := False;
  try
    Obj := TBreadthOperatorClass.InitInstance(@Storage[1]);
  except
    on EAbort do Caught := True;
  end;
  If Obj <> nil then
    Obj.CleanupInstance;
  Check(Caught and (Obj = nil), 'breadth-mrec-initinstance-preserves-caller-ownership-on-failure');
  Check((BreadthInitAttempts = 3) and (BreadthAllocated = 2), 'breadth-mrec-initinstance-fails-at-third-field');
  Check((BreadthFinalized = 2) and (BreadthLiveOperatorTokens = []), 'breadth-mrec-initinstance-unwinds-partial-fields');
  Check((Storage[0] = LeftGuard) and (Storage[High(Storage)] = RightGuard), 'breadth-mrec-initinstance-guard-values');

  BreadthResetOperatorLifetime;
  Obj := TBreadthOperatorSubclass.InitInstance(@Storage[1]);
  Check((Pointer(Obj) = @Storage[1]) and (BreadthAllocated = 8) and (BreadthFinalized = 0),
    'breadth-mrec-initinstance-uses-caller-storage-with-inheritance');
  If Obj <> nil then
    Obj.CleanupInstance;
  Check((BreadthFinalized = 8) and (BreadthLiveOperatorTokens = []), 'breadth-mrec-cleanupinstance-releases-hierarchy');
  Check((Storage[0] = LeftGuard) and (Storage[High(Storage)] = RightGuard), 'breadth-mrec-cleanupinstance-guard-values');
  Mix(UInt64(BreadthFinalized));
end;

procedure RunBreadthOperatorInitializationFailure;
var
  Obj: TBreadthOperatorClass;
  Caught, StackBodyReached: Boolean;

  procedure InitializeStack;
  var
    Grid: array[2..3, -1..0] of TBreadthOperatorCell;
  begin
    StackBodyReached := Grid[2, -1].Token <> 0;
  end;

begin
  BreadthResetOperatorLifetime;
  BreadthFailOnInitialize := 3;
  StackBodyReached := False;
  Caught := False;
  try
    InitializeStack;
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and not StackBodyReached, 'breadth-mrec-stack-failed-initialize-before-body');
  Check((BreadthInitAttempts = 3) and (BreadthAllocated = 2), 'breadth-mrec-stack-stops-after-third-attempt');
  Check((BreadthFinalized = 2) and (BreadthLiveOperatorTokens = []), 'breadth-mrec-stack-unwinds-partial-initialize');

  BreadthResetOperatorLifetime;
  BreadthFailOnInitialize := 3;
  Obj := nil;
  Caught := False;
  try
    Obj := TBreadthOperatorClass.Create(False);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Obj = nil) and (BreadthConstructorBodies = 0), 'breadth-mrec-failed-initialize-prevents-constructor');
  If not Caught then
    Obj.Free;
  Check((BreadthInitAttempts = 3) and (BreadthAllocated = 2), 'breadth-mrec-failed-initialize-stops-after-third-attempt');
  Check((BreadthFinalized = 2) and (BreadthLiveOperatorTokens = []), 'breadth-mrec-failed-initialize-releases-previous-fields');
  Mix(UInt64(BreadthFinalized));
end;
{$endif}

procedure RunModernBreadthForms;
begin
{$ifdef HAS_ANON}
  RunBreadthClosureLifetime;
  RunBreadthGenericClosureResult;
{$endif}
{$ifdef HAS_INLINEVAR}
  RunBreadthInlineCleanup;
{$endif}
{$ifdef HAS_MREC}
  RunBreadthOperatorArrayLifecycle;
  RunBreadthOperatorInitializationFailure;
  RunBreadthOperatorCallerStorage;
{$endif}
end;
