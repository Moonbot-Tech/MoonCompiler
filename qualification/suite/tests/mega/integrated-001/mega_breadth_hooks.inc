{ Construction hooks and packed Boolean ABIs. }

type
  TBreadthHookObject = class;
  PBreadthHookSlot = ^TBreadthHookObject;

  TBreadthHookObject = class
  private
    FOwner: IInterface;
    FSlot: PBreadthHookSlot;
    FThrow: Boolean;
  public
    class var AfterCalls, BeforeCalls, DestructorCalls: Integer;
    constructor Create(Slot: PBreadthHookSlot; ThrowInHook: Boolean);
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    destructor Destroy; override;
  end;

constructor TBreadthHookObject.Create(Slot: PBreadthHookSlot; ThrowInHook: Boolean);
begin
  inherited Create;
  FSlot := Slot;
  FOwner := TIntersectionOwner.Create;
  FThrow := ThrowInHook;
end;

procedure TBreadthHookObject.AfterConstruction;
begin
  inherited;
  Inc(AfterCalls);
  Check((FSlot^ = nil) and (FOwner <> nil), 'breadth-after-construction-runs-before-publication');
  If FThrow then
    raise EAbort.Create('after construction');
end;

procedure TBreadthHookObject.BeforeDestruction;
begin
  Inc(BeforeCalls);
  inherited;
end;

destructor TBreadthHookObject.Destroy;
begin
  Check((FSlot^ = nil) and (FOwner <> nil), 'breadth-destructor-observes-cleared-slot-and-live-owner');
  Inc(DestructorCalls);
  inherited;
end;

procedure RunBreadthConstructionHooks;
var
  Obj: TBreadthHookObject;
  Caught: Boolean;
begin
  TBreadthHookObject.AfterCalls := 0;
  TBreadthHookObject.BeforeCalls := 0;
  TBreadthHookObject.DestructorCalls := 0;
  TIntersectionOwner.Destroyed := 0;
  Obj := nil;
  Caught := False;
  try
    Obj := TBreadthHookObject.Create(@Obj, True);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Obj = nil), 'breadth-after-construction-failure-leaves-slot-nil');
  Check((TBreadthHookObject.AfterCalls = 1) and (TBreadthHookObject.BeforeCalls = 1)
    and (TBreadthHookObject.DestructorCalls = 1), 'breadth-after-construction-failure-runs-destruction-hooks');
  Check(TIntersectionOwner.Destroyed = 1, 'breadth-after-construction-failure-releases-interface');
  If not Caught and Assigned(Obj) then
    FreeAndNil(Obj);

  Obj := TBreadthHookObject.Create(@Obj, False);
  Check((Obj <> nil) and (TBreadthHookObject.AfterCalls = 2) and (TIntersectionOwner.Destroyed = 1),
    'breadth-after-construction-success-publishes-instance');
  FreeAndNil(Obj);
  Check((Obj = nil) and (TBreadthHookObject.BeforeCalls = 2) and (TBreadthHookObject.DestructorCalls = 2)
    and (TIntersectionOwner.Destroyed = 2), 'breadth-free-and-nil-after-success-cleans-once');
  Mix(UInt64(TIntersectionOwner.Destroyed));
end;

type
  TBreadthFlags = packed record
    Head: Byte;
    Narrow: ByteBool;
    Middle: WordBool;
    Wide: LongBool;
    Tail: Word;
  end;

  TBreadthReadFlags = function(Value: TBreadthFlags; Extra: Integer): Integer; cdecl;

function BreadthReadFlags(Value: TBreadthFlags; Extra: Integer): Integer; cdecl;
begin
  Result := Value.Head + Value.Tail + Extra;
  If Value.Narrow then Inc(Result, 1);
  If Value.Middle then Inc(Result, 2);
  If not Value.Wide then Dec(Result, 4);
end;

procedure RunBreadthPackedFlags;
const
  Bytes: array[0..4] of Byte = (0, $80, 0, 0, $FE);
  Words: array[0..4] of Word = (0, 0, $8000, 0, $D123);
  Longs: array[0..4] of Cardinal = (0, 0, 0, $80000000, $00010000);
  Expected: array[0..4] of Integer = (798, 799, 800, 802, 805);
var
  F: TBreadthFlags;
  Read: TBreadthReadFlags;
  I, Answer: Integer;
  RawByte: Byte;
  RawWord: Word;
  RawLong: Cardinal;
begin
  Read := BreadthReadFlags;
  F.Head := 181;
  F.Tail := 598;
  for I := Low(Expected) to High(Expected) do begin
    RawByte := Byte(OpaqueI(Bytes[I]));
    RawWord := Word(OpaqueI(Words[I]));
    RawLong := Cardinal(OpaqueI(Longs[I]));
    Move(RawByte, F.Narrow, SizeOf(RawByte));
    Move(RawWord, F.Middle, SizeOf(RawWord));
    Move(RawLong, F.Wide, SizeOf(RawLong));
    Answer := Read(F, Integer(OpaqueI(23)));
    Check(Answer = Expected[I], 'breadth-packed-c-style-booleans-normalize-in-branches');
    Check((F.Head = 181) and (F.Tail = 598), 'breadth-packed-c-style-booleans-preserve-guards');
    Mix(UInt64(Answer));
  end;
end;

type
  TBreadthSliceMethod = function(var Entries: array of TCrossEntry; Addend: Int64; Scale: Double): TCrossEntry of object;

  TBreadthSliceReceiver = class
    Bias: Int64;
    function Apply(var Entries: array of TCrossEntry; Addend: Int64; Scale: Double): TCrossEntry;
  end;

function TBreadthSliceReceiver.Apply(var Entries: array of TCrossEntry; Addend: Int64; Scale: Double): TCrossEntry;
var
  I: Integer;
begin
  Result.Code := Bias + Addend + Trunc(Scale * 8.0) + High(Entries);
  Result.Text := '';
  If (High(Entries) < -1) or (High(Entries) > 2) then begin
    Check(False, 'breadth-open-array-method-invalid-hidden-bound');
    Exit;
  end;
  for I := Low(Entries) to High(Entries) do begin
    Inc(Entries[I].Code, Addend);
    Entries[I].Text := Entries[I].Text + '!';
    Result.Text := Result.Text + Entries[I].Text;
  end;
end;

procedure RunBreadthOpenArrayMethod;
var
  Receiver: TBreadthSliceReceiver;
  Apply: TBreadthSliceMethod;
  Entries: array[-2..0] of TCrossEntry;
  Empty: TCrossEntries;
  Count: Integer;
  Actual: TCrossEntry;
begin
  Receiver := TBreadthSliceReceiver.Create;
  try
    Receiver.Bias := OpaqueI(76000000013);
    Apply := Receiver.Apply;
    Entries[-2].Code := 13;
    Entries[-2].Text := 'A';
    Entries[-1].Code := -71;
    Entries[-1].Text := 'B';
    Entries[0].Code := -131;
    Entries[0].Text := 'C';
    Count := Integer(OpaqueI(0));
    Actual := Apply(Slice(Entries, Count), OpaqueI(41000000059), OpaqueD(1.625));
    Check((Actual.Code = 117000000084) and (Actual.Text = AnsiString('')), 'breadth-open-array-method-zero-slice-bound');
    Check((Entries[-2].Code = 13) and (Entries[-2].Text = AnsiString('A')), 'breadth-open-array-method-empty-slice-no-write');
    Empty := nil;
    Actual := Apply(Empty, OpaqueI(41000000059), OpaqueD(1.625));
    Check((Actual.Code = 117000000084) and (Actual.Text = AnsiString('')), 'breadth-open-array-method-nil-dynamic-bound');
    Count := Integer(OpaqueI(2));
    Actual := Apply(Slice(Entries, Count), OpaqueI(41000000059), OpaqueD(-0.625));
    Check((Actual.Code = 117000000068) and (Actual.Text = AnsiString('A!B!')), 'breadth-open-array-method-mixed-abi-result');
    Check((Entries[-2].Code = 41000000072) and (Entries[-1].Code = 40999999988), 'breadth-open-array-method-updates-slice');
    Check((Entries[0].Code = -131) and (Entries[0].Text = AnsiString('C')), 'breadth-open-array-method-preserves-tail');
    Mix(UInt64(Actual.Code));
  finally
    Receiver.Free;
  end;
end;

function BreadthQuotientWithOwner(Denominator: Double; var Cleanups: Integer): Double;
var
  Owner: IInterface;
begin
  Owner := TIntersectionOwner.Create;
  try
    Result := 7.0 / Denominator;
  finally
    Check(Owner <> nil, 'breadth-fp-trap-finally-still-owns-local');
    Inc(Cleanups);
  end;
end;

procedure RunBreadthHardwareFloatTrap;
var
  PreviousMask: TFPUExceptionMask;
  Attempt, Cleanups, Traps: Integer;
  Divisor, Answer: Double;
begin
  TIntersectionOwner.Destroyed := 0;
  Cleanups := 0;
  Traps := 0;
  Answer := 191.25;
  PreviousMask := GetExceptionMask;
  SetExceptionMask(PreviousMask - [exZeroDivide]);
  try
    for Attempt := 0 to 1 do begin
      Divisor := OpaqueD(0.0);
      If Attempt = 1 then
        Divisor := -Divisor;
      try
        Answer := BreadthQuotientWithOwner(Divisor, Cleanups);
      except
        on EZeroDivide do Inc(Traps);
      end;
      Check(Answer = 191.25, 'breadth-fp-trap-prevents-result-store');
    end;
    Answer := BreadthQuotientWithOwner(OpaqueD(2.0), Cleanups);
    Check(Answer = 3.5, 'breadth-fp-trap-next-call-completes');
  finally
    SetExceptionMask(PreviousMask);
  end;
  Check(Traps = 2, 'breadth-fp-trap-both-signed-zeros');
  Check((Cleanups = 3) and (TIntersectionOwner.Destroyed = 3), 'breadth-fp-trap-unwinds-managed-local');
  Check(GetExceptionMask = PreviousMask, 'breadth-fp-trap-restores-caller-mask');
  Mix(DoubleBits(Answer));
end;

procedure RunBreadthHookForms;
begin
  RunBreadthConstructionHooks;
  RunBreadthPackedFlags;
  RunBreadthOpenArrayMethod;
  RunBreadthHardwareFloatTrap;
end;
