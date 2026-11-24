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
    TBreadthTransformStep = reference to function(const Value: T; Delta: Integer): T;
    TRun = reference to function(Delta: Integer): T;
  public
    class function Start(Initial: T; const Apply: TBreadthTransformStep): TRun; static;
  end;

class function TBreadthTransform<T>.Start(Initial: T; const Apply: TBreadthTransformStep): TRun;
var
  Current: T;
  Step: TBreadthTransformStep;
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

type
  TBreadthRawLookup = function(Key: Int64; Scale: Double): TCrossEntry of object;
  TBreadthRefLookup = reference to function(Key: Int64; Scale: Double): TCrossEntry;

  TBreadthLookupSource = class
    Caption: AnsiString;
    Bias: Int64;
    function Lookup(Key: Int64; Scale: Double): TCrossEntry; virtual;
  end;

  TBreadthLookupDerived = class(TBreadthLookupSource)
    function Lookup(Key: Int64; Scale: Double): TCrossEntry; override;
  end;

function TBreadthLookupSource.Lookup(Key: Int64; Scale: Double): TCrossEntry;
begin
  Result.Code := Key + Bias + Trunc(Scale * 16.0);
  Result.Text := Caption + '!';
end;

function TBreadthLookupDerived.Lookup(Key: Int64; Scale: Double): TCrossEntry;
begin
  Result := inherited Lookup(Key, Scale);
  Inc(Result.Code, 101);
  Result.Text := Result.Text + '^';
end;

procedure RunBreadthMethodReferenceBinding;
var
  First, Second: TBreadthLookupSource;
  Raw, Independent: TBreadthRawLookup;
  Saved, Other: TBreadthRefLookup;
  Actual: TCrossEntry;
begin
  First := TBreadthLookupSource.Create;
  try
    Second := TBreadthLookupDerived.Create;
    try
      First.Caption := 'original';
      First.Bias := OpaqueI(546);
      Second.Caption := 'replacement';
      Second.Bias := OpaqueI(-217);
      Raw := First.Lookup;
      Saved := Raw;
      Raw := Second.Lookup;
      Independent := First.Lookup;
      Other := Independent;
      { Converting a method variable captures its slot. A second variable
        supplies an independent receiver even after Raw gets rebound. }
      Actual := Saved(OpaqueI(47000000019), OpaqueD(0.5));
      Check((Actual.Code = 46999999911) and (Actual.Text = AnsiString('replacement!^')),
        'breadth-method-ref-follows-method-variable-rebind');
      Actual := Other(OpaqueI(-16000000071), OpaqueD(-1.75));
      Check((Actual.Code = -15999999553) and (Actual.Text = AnsiString('original!')),
        'breadth-method-ref-keeps-separate-target');
      Raw := First.Lookup;
      First.Caption := 'updated';
      Actual := Saved(OpaqueI(17), OpaqueD(0.25));
      Check((Actual.Code = 567) and (Actual.Text = AnsiString('updated!')), 'breadth-method-ref-binds-live-instance-state');
      Mix(UInt64(Actual.Code));
    finally
      Saved := nil;
      Other := nil;
      Second.Free;
    end;
  finally
    First.Free;
  end;
end;

procedure RunBreadthCapturedGenericSort;
const
  Names: array[0..3] of AnsiString = ('b', 'x', 'a', 'r');
  Codes: array[0..3] of Int64 = (90000000003, -41, 90000000003, 17);
  Ascending: array[0..3] of Integer = (1, 3, 2, 0);
  Descending: array[0..3] of Integer = (0, 2, 3, 1);
var
  List: TList<TCrossEntry>;
  Comparison: TComparison<TCrossEntry>;
  Comparer: IComparer<TCrossEntry>;
  Saved: TArray<TCrossEntry>;
  Item: TCrossEntry;
  Direction, Calls, I: Integer;
begin
  Direction := 1;
  Calls := 0;
  Comparison := function(const L, R: TCrossEntry): Integer
    begin
      Inc(Calls);
      If L.Code < R.Code then
        Exit(-Direction);
      If L.Code > R.Code then
        Exit(Direction);
      Result := Direction * CompareStr(string(L.Text), string(R.Text));
    end;
  Comparer := TComparer<TCrossEntry>.Construct(Comparison);
  List := TList<TCrossEntry>.Create;
  try
    for I := Low(Names) to High(Names) do begin
      Item.Code := OpaqueI(Codes[I]);
      Item.Text := Names[I];
      List.Add(Item);
    end;
    List.Sort(Comparer);
    Check(Calls > 0, 'breadth-closure-sort-uses-captured-comparer');
    Saved := List.ToArray;
    Calls := 0;
    Direction := -1;
    List.Sort(Comparer);
    Check(Calls > 0, 'breadth-closure-sort-recalls-same-comparer');
    for I := Low(Names) to High(Names) do begin
      Check((Saved[I].Code = Codes[Ascending[I]]) and (Saved[I].Text = Names[Ascending[I]]),
        'breadth-closure-sort-preserves-first-managed-snapshot');
      Item := List[I];
      Check((Item.Code = Codes[Descending[I]]) and (Item.Text = Names[Descending[I]]),
        'breadth-closure-sort-captures-changed-direction');
      Mix(UInt64(Item.Code));
    end;
  finally
    List.Free;
  end;
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

{$I mega_modern_shadowed.inc}
{$I mega_modern_assign.inc}
{$I mega_modern_iteration.inc}
{$I mega_modern_textreader.inc}
{$I mega_modern_textwriter.inc}
{$I mega_modern_rttipacket.inc}
{$I mega_modern_boxedcast.inc}
{$I mega_modern_queuedclosure.inc}
{$I mega_modern_outclosure.inc}
{$I mega_modern_indexedrtti.inc}
{$I mega_modern_reflectwire.inc}
{$I mega_modern_atomicwrappers.inc}

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
  RunBreadthManagedAssign;
{$endif}
{$ifdef HAS_ANON}
  RunBreadthMethodReferenceBinding;
  RunBreadthCapturedGenericSort;
{$endif}
{$if defined(HAS_ANON) and defined(HAS_INLINEVAR)}
  RunBreadthShadowedClosure;
  RunBreadthHandlerClosure;
  RunBreadthLoopCapture;
{$ifend}
{$if defined(HAS_ANON) and defined(BREADTH_MAIN_FORCE_QUEUE)}
  RunBreadthQueuedClosure;
{$ifend}
{$ifdef BREADTH_HAS_TEXT_STREAMS}
  RunBreadthBufferedTextReader;
  RunBreadthBufferedTextWriter;
{$endif}
{$ifdef BREADTH_HAS_EXTENDED_METHODS}
  RunBreadthRttiEndpoint;
{$endif}
{$ifdef BREADTH_HAS_TVALUE_CAST}
  RunBreadthBoxedClassCast;
{$endif}
{$ifdef HAS_ANON}
  RunBreadthManagedOutClosure;
{$endif}
{$ifdef BREADTH_HAS_EXTENDED_METHODS}
  RunBreadthIndexedRtti;
  RunBreadthReflectSettingsWire;
{$endif}
{$ifdef BREADTH_HAS_TYPED_INTERLOCKED}
  RunBreadthAtomicObjects;
  RunBreadthAtomicFloating;
{$endif}
end;
