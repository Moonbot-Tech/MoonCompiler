{ Operations whose implicit registers, hidden arguments or exceptional exits
  must preserve other state in the same routine. }

type
  TIntersectionDivision = record
    Dividend, FirstDivisor, SecondDivisor: Int64;
    FirstQuotient, FirstRemainder, SecondQuotient, SecondRemainder: Int64;
  end;

function IntersectionDivide(V, D, E: Int64; Count: Integer; const Expected: TIntersectionDivision): Int64;
var
  A, B, C, F, G, H, J, K: Int64;
  Q1, R1, Q2, R2: Int64;
begin
  A := OpaqueI(5);
  B := OpaqueI(-19);
  C := OpaqueI(31);
  F := OpaqueI(-73);
  G := OpaqueI(113);
  H := OpaqueI(173);
  J := OpaqueI(-211);
  K := OpaqueI(307);

  Q1 := V div D;
  R1 := V mod D;
  Q2 := V div E;
  R2 := V mod E;
  { A variable shift also needs CL on targets without BMI2. }
  Result := (A shl Count) + B + C - F + G * H + J + K;
  Check(Q1 = Expected.FirstQuotient, 'cross-div-first-quotient');
  Check(R1 = Expected.FirstRemainder, 'cross-div-first-remainder');
  Check(Q2 = Expected.SecondQuotient, 'cross-div-second-quotient');
  Check(R2 = Expected.SecondRemainder, 'cross-div-second-remainder');
  Mix(UInt64(Q1));
  Mix(UInt64(R1));
  Mix(UInt64(Q2));
  Mix(UInt64(R2));
end;

procedure RunIntersectionDivisionForms;
const
  Cases: array[0..3] of TIntersectionDivision = (
    (Dividend: 1234567890123456789; FirstDivisor: 10000019; SecondDivisor: 65537;
     FirstQuotient: 123456554444; FirstRemainder: 8922353; SecondQuotient: 18837723577879; SecondRemainder: 766),
    (Dividend: -9012345678901234567; FirstDivisor: 32771; SecondDivisor: -65539;
     FirstQuotient: -275009785447536; FirstRemainder: -32311; SecondQuotient: 137511186910102; SecondRemainder: -59589),
    (Dividend: High(Int64); FirstDivisor: -104729; SecondDivisor: 17;
     FirstQuotient: -88068940187099; FirstRemainder: 84636; SecondQuotient: 542551296285575047; SecondRemainder: 8),
    (Dividend: Low(Int64); FirstDivisor: -33; SecondDivisor: 104729;
     FirstQuotient: 279496122328932600; FirstRemainder: -8; SecondQuotient: -88068940187099; SecondRemainder: -84637));
var
  I: Integer;
  Actual: Int64;
begin
  for I := Low(Cases) to High(Cases) do
  begin
    Actual := IntersectionDivide(OpaqueI(Cases[I].Dividend), OpaqueI(Cases[I].FirstDivisor),
      OpaqueI(Cases[I].SecondDivisor), Integer(OpaqueI(6)), Cases[I]);
    Check(Actual = 20050, 'cross-div-preserves-live-values');
    Mix(UInt64(Actual));
  end;
end;

{$Q+}{$R+}
procedure RunIntersectionCheckedForms;
var
  Slots: array[-1..1] of Int64;
  I, Index, Finishes, Overflows, Bounds: Integer;
  V: Int64;
begin
  Slots[-1] := -29;
  Slots[0] := 107;
  Slots[1] := 313;
  Finishes := 0;
  Overflows := 0;
  Bounds := 0;
  for I := 0 to 2 do
  begin
    Index := Integer(OpaqueI(0));
    V := High(Int64) - I;
    If I = 1 then
      Index := Integer(OpaqueI(2));
    try
      try
        Slots[Index] := V + OpaqueI(1);
      finally
        Inc(Finishes);
      end;
    except
      on EIntOverflow do Inc(Overflows);
      on ERangeError do Inc(Bounds);
    end;
    If I < 2 then
      Check(Slots[0] = 107, 'cross-checked-no-store-on-exception');
    Check((Slots[-1] = -29) and (Slots[1] = 313), 'cross-checked-neighbor-guards');
  end;
  Check((Overflows = 1) and (Bounds = 1), 'cross-checked-exception-kinds');
  Check(Finishes = 3, 'cross-checked-finally-each-path');
  Check(Slots[0] = High(Int64) - 1, 'cross-checked-next-store');
  Mix(UInt64(Slots[0]));
end;
{$Q-}{$R-}

type
  TIntersectionResult = record
    Text: AnsiString;
    Owner: IInterface;
    Fingerprint: Int64;
    Value: Double;
  end;

  TIntersectionOwner = class(TInterfacedObject)
  public
    class var Destroyed: Integer;
    destructor Destroy; override;
  end;

  TIntersectionMethod = function(A: Int64; B: Double; C: Int64; D: Double;
    E: Int64; F: Double; G: Int64; H: Double; Stop: Boolean): TIntersectionResult of object;

  TIntersectionReceiver = class
    Prefix: AnsiString;
    Bias: Int64;
    Calls: Integer;
    function Combine(A: Int64; B: Double; C: Int64; D: Double;
      E: Int64; F: Double; G: Int64; H: Double; Stop: Boolean): TIntersectionResult;
  end;

destructor TIntersectionOwner.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TIntersectionReceiver.Combine(A: Int64; B: Double; C: Int64; D: Double;
  E: Int64; F: Double; G: Int64; H: Double; Stop: Boolean): TIntersectionResult;
begin
  Inc(Calls);
  Result.Text := Prefix + ' payload';
  Result.Owner := TIntersectionOwner.Create;
  Result.Fingerprint := Bias + A + 3 * C + 5 * E + 7 * G;
  If Stop then
    raise EAbort.Create('intersection managed return');
  Result.Value := B + 3 * D + 5 * F + 7 * H;
end;

procedure RunIntersectionMethodForms;
var
  Receiver: TIntersectionReceiver;
  Method: TIntersectionMethod;
  Dest: TIntersectionResult;
  Caught: Boolean;

  procedure CompleteCall(var Output: TIntersectionResult; Stop: Boolean);
  var
    Pending: TIntersectionResult;
  begin
    Pending := Method(OpaqueI(11), OpaqueD(0.5), OpaqueI(-13), OpaqueD(-1.25),
      OpaqueI(101), OpaqueD(3.75), OpaqueI(-173), OpaqueD(-15.5), Stop);
    Output := Pending;
  end;

begin
  TIntersectionOwner.Destroyed := 0;
  Receiver := TIntersectionReceiver.Create;
  try
    Receiver.Prefix := 'first';
    Receiver.Bias := OpaqueI(17);
    Method := Receiver.Combine;
    Dest.Text := 'old destination';
    CompleteCall(Dest, False);
    Check(Dest.Text = 'first payload', 'cross-method-managed-result-text');
    Check(Dest.Fingerprint = -717, 'cross-method-mixed-abi-integer');
    Check(Dest.Value = -93.0, 'cross-method-mixed-abi-float');
    Check((Dest.Owner <> nil) and (TIntersectionOwner.Destroyed = 0), 'cross-method-owner-moved');

    Receiver.Prefix := 'second';
    Receiver.Bias := OpaqueI(109);
    Caught := False;
    try
      CompleteCall(Dest, True);
    except
      on EAbort do Caught := True;
    end;
    Check(Caught and (Receiver.Calls = 2), 'cross-method-managed-result-throws');
    Check(Dest.Text = 'first payload', 'cross-method-throw-preserves-text');
    Check((Dest.Fingerprint = -717) and (Dest.Value = -93.0), 'cross-method-throw-preserves-fields');
    Check(TIntersectionOwner.Destroyed = 1, 'cross-method-unwind-releases-owner');
    Dest.Owner := nil;
    Check(TIntersectionOwner.Destroyed = 2, 'cross-method-result-releases-owner');
    Mix(UInt64(Dest.Fingerprint));
    Mix(DoubleBits(Dest.Value));
  finally
    Receiver.Free;
  end;
end;

{ Cross storage, control-flow and lifetime boundaries. }

type
  TCrossLoopItem = record
    Key: Integer;
    Text: AnsiString;
  end;

  TCrossLoopEnumerator = class
  private
    FKey: Integer;
    function GetCurrent: TCrossLoopItem;
  public
    class var Constructed, Destroyed, Advances, Reads: Integer;
    constructor Create;
    destructor Destroy; override;
    function MoveNext: Boolean;
    property Current: TCrossLoopItem read GetCurrent;
  end;

  TCrossLoopRange = record
    function GetEnumerator: TCrossLoopEnumerator;
  end;

constructor TCrossLoopEnumerator.Create;
begin
  inherited;
  Inc(Constructed);
end;

destructor TCrossLoopEnumerator.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TCrossLoopEnumerator.MoveNext: Boolean;
begin
  Inc(Advances);
  Inc(FKey);
  Result := FKey <= 4;
end;

function TCrossLoopEnumerator.GetCurrent: TCrossLoopItem;
begin
  Inc(Reads);
  Result.Key := FKey;
  Result.Text := AnsiString('item-') + AnsiChar(Ord('0') + FKey);
end;

function TCrossLoopRange.GetEnumerator: TCrossLoopEnumerator;
begin
  Result := TCrossLoopEnumerator.Create;
end;

procedure RunCrossLoopLifetimeForms;
var
  Range: TCrossLoopRange;
  Item: TCrossLoopItem;
  CaseIndex, FinalCount, Calls: Integer;
  Trace, SavedFirst: AnsiString;
  Caught: Boolean;
begin
  TCrossLoopEnumerator.Constructed := 0;
  TCrossLoopEnumerator.Destroyed := 0;
  TCrossLoopEnumerator.Advances := 0;
  TCrossLoopEnumerator.Reads := 0;
  FinalCount := 0;
  for CaseIndex := 0 to 2 do
  begin
    Trace := '';
    Caught := False;
    try
      for Item in Range do
        try
          If Item.Key = 1 then begin
            SavedFirst := Item.Text;
            Continue;
          end;
          If (Item.Key = 3) and (CaseIndex = 0) then
            Break;
          If (Item.Key = 3) and (CaseIndex = 1) then
            raise EAbort.Create('enumeration body');
          Trace := Trace + Item.Text[Length(Item.Text)];
        finally
          Inc(FinalCount);
        end;
    except
      on EAbort do Caught := True;
    end;
    Check(Caught = (CaseIndex = 1), 'cross-forin-body-exception');
    Check(SavedFirst = 'item-1', 'cross-forin-managed-current-snapshot');
    Check(TCrossLoopEnumerator.Destroyed = CaseIndex + 1, 'cross-forin-enumerator-cleanup');
    If CaseIndex = 2 then
      Check(Trace = '234', 'cross-forin-normal-trace')
    else
      Check(Trace = '2', 'cross-forin-early-trace');
  end;
  Calls := TCrossLoopEnumerator.Advances;
  Check(Calls = 11, 'cross-forin-move-next-count');
  Check(TCrossLoopEnumerator.Reads = 10, 'cross-forin-current-count');
  Check(TCrossLoopEnumerator.Constructed = 3, 'cross-forin-enumerator-created-once');
  Check(FinalCount = 10, 'cross-forin-finally-count');
  Mix(UInt64(Calls));
end;

type
  TCrossPacked = packed record
    Prefix: Byte;
    Value: Int64;
    Marker: Word;
  end;

  TCrossPackedEdit = procedure(var Items: array of TCrossPacked; var Cell: Int64; var Marker: Word);

procedure CrossPackedEdit(var Items: array of TCrossPacked; var Cell: Int64; var Marker: Word);
begin
  Check((Low(Items) = 0) and (High(Items) = 2), 'cross-packed-open-array-bounds');
  Cell := Cell + Items[0].Value;
  Items[1].Value := Items[1].Value * 3;
  Marker := Word(Cell);
  Inc(Items[2].Marker, 1);
  Cell := Cell - Marker;
end;

procedure RunCrossPackedAliasForms;
var
  Base: array[-3..-1] of TCrossPacked;
  Edit: TCrossPackedEdit;
  Item: Integer;
begin
  Base[-3].Prefix := $B6;
  Base[-3].Value := 17;
  Base[-3].Marker := $C715;
  Base[-2].Prefix := $69;
  Base[-2].Value := OpaqueI(65537);
  Base[-2].Marker := $FC03;
  Base[-1].Prefix := $77;
  Base[-1].Value := -33;
  Base[-1].Marker := 1100;
  Item := Integer(OpaqueI(-2));
  Edit := CrossPackedEdit;
  Edit(Base, Base[Item].Value, Base[Item].Marker);
  Check((Base[-2].Value = 196608) and (Base[-2].Marker = 54), 'cross-packed-overlapping-var');
  Check((Base[-1].Value = -33) and (Base[-1].Marker = 1101), 'cross-packed-neighbor-write');
  Check((Base[-3].Value = 17) and (Base[-3].Marker = $C715), 'cross-packed-untouched-record');
  Check((Base[-3].Prefix = $B6) and (Base[-2].Prefix = $69) and (Base[-1].Prefix = $77),
    'cross-packed-prefix-guards');
  Mix(UInt64(Base[-2].Value) + Base[-2].Marker);
end;

function CrossDenseSignedSelector(K: Int64; Value: Integer): Integer;
begin
  { Validate full width before entering the dense 32-bit dispatch. }
  If (K < -6) or (K > 5) then
    Exit(-919);
  case Integer(K) of
    -6: Result := Value xor 5;
    -5: Result := Value + 7;
    -4: Result := Value * 3;
    -3: Result := Value shr 2;
    -2: Result := Value - 11;
    -1: Result := Value xor 31;
     0: Result := Value shl 1;
     1: Result := Value and 9;
     2: Result := Value * 5;
     3: Result := Value + 37;
     4: Result := Value xor 17;
     5: Result := Value + 61;
  else
    Result := -919;
  end;
end;

procedure RunCrossDenseCaseForms;
const
  Results: array[-6..5] of Integer = (18, 30, 69, 5, 12, 8, 46, 1, 115, 60, 6, 84);
  Wrap32 = Int64(4294967296);
var
  Item, Value, Actual: Integer;
begin
  Value := Integer(OpaqueI(23));
  for Item := Low(Results) to High(Results) do
  begin
    Actual := CrossDenseSignedSelector(OpaqueI(Item), Value);
    Check(Actual = Results[Item], 'cross-dense-i64-all-arms');
    Check(CrossDenseSignedSelector(OpaqueI(Item + Wrap32), Value) = -919, 'cross-dense-i64-high-alias');
    Check(CrossDenseSignedSelector(OpaqueI(Item - Wrap32), Value) = -919, 'cross-dense-i64-low-alias');
    Mix(UInt64(Actual));
  end;
  Check(CrossDenseSignedSelector(OpaqueI(-7), Value) = -919, 'cross-dense-i64-lower-bound');
  Check(CrossDenseSignedSelector(OpaqueI(6), Value) = -919, 'cross-dense-i64-upper-bound');
end;

{ Borrowed locations, cleanup and compiler-generated array addressing. }

type
  TCrossEntry = record
    Code: Int64;
    Text: AnsiString;
  end;
  TCrossEntries = array of TCrossEntry;

procedure CrossDetachDuringEdit(var All: TCrossEntries; var OldCell: TCrossEntry; NewCount: Integer);
begin
  SetLength(All, NewCount);
  All[0].Code := -801;
  All[0].Text := 'new zero';
  OldCell.Code := OldCell.Code + 19;
  OldCell.Text := OldCell.Text + '!';
end;

procedure RunCrossDetachAliasForms;
var
  Active, Saved: TCrossEntries;
  Index, NewCount: Integer;
begin
  SetLength(Active, 3);
  Active[0].Code := 33;
  Active[0].Text := 'old zero';
  Active[1].Code := -509;
  Active[1].Text := 'victim';
  Active[2].Code := 81;
  Active[2].Text := 'tail';
  Saved := Active;  { keeps the original allocation alive across SetLength }
  Index := Integer(OpaqueI(1));
  NewCount := Integer(OpaqueI(4));
  CrossDetachDuringEdit(Active, Active[Index], NewCount);
  Check((Length(Active) = 4) and (Length(Saved) = 3), 'cross-detach-distinct-bounds');
  Check((Saved[1].Code = -490) and (Saved[1].Text = AnsiString('victim!')), 'cross-detach-old-cell-write');
  Check((Active[1].Code = -509) and (Active[1].Text = AnsiString('victim')), 'cross-detach-new-cell-snapshot');
  Check((Active[0].Code = -801) and (Active[0].Text = AnsiString('new zero')), 'cross-detach-new-array-write');
  Check((Saved[0].Code = 33) and (Saved[0].Text = AnsiString('old zero')), 'cross-detach-old-array-snapshot');
  Check((Active[2].Code = 81) and (Active[2].Text = AnsiString('tail')), 'cross-detach-copied-tail');
  Check((Active[3].Code = 0) and (Active[3].Text = AnsiString('')), 'cross-detach-zeroed-new-tail');
  Saved := nil;
  Check(Active[1].Text = AnsiString('victim'), 'cross-detach-releasing-original-owner');
  Mix(UInt64(Active[0].Code + Active[1].Code + Active[2].Code));
end;

procedure RunCrossVariantArrayForms;
const
  Expected: array[-2..0, 5..7] of Integer = (
    (-185, -182, -179), (-85, -82, -79), (15, 18, 21));
var
  Values, Saved, Leaf: Variant;
  I, J, A, B, Actual: Integer;
  BadIndex: Boolean;
begin
  Values := VarArrayCreate([-2, 0, 5, 7], varVariant);
  for I := -2 to 0 do
    for J := 5 to 7 do
    begin
      A := Integer(OpaqueI(I));
      B := Integer(OpaqueI(J));
      Values[A, B] := A * 100 + B * 3;
    end;
  Check((VarArrayDimCount(Values) = 2) and (VarArrayLowBound(Values, 1) = -2)
    and (VarArrayHighBound(Values, 2) = 7), 'cross-variant-array-shape');

  Leaf := VarArrayCreate([9, 10], varInteger);
  Leaf[9] := Integer(OpaqueI(1021));
  Leaf[10] := Integer(OpaqueI(-401));
  Values[-1, 6] := Leaf;
  Saved := Values;
  Values[-1, 6] := Integer(OpaqueI(-313));
  Leaf := Saved[-1, 6];
  Check(VarIsArray(Leaf), 'cross-variant-array-nested-snapshot');
  If VarIsArray(Leaf) then begin
    Check((Integer(Leaf[9]) = 1021) and (Integer(Leaf[10]) = -401), 'cross-variant-array-nested-values');
    Leaf[9] := 13;
    Leaf := Saved[-1, 6];
    Check(Integer(Leaf[9]) = 1021, 'cross-variant-array-extraction-is-snapshot');
  end;

  J := Integer(OpaqueI(8));
  BadIndex := False;
  try
    Values[0, J] := 907;
  except
    on EVariantError do BadIndex := True;
  end;
  Check(BadIndex, 'cross-variant-array-range-exception');
  for I := -2 to 0 do
    for J := 5 to 7 do
    begin
      Actual := Integer(Values[I, J]);
      If (I = -1) and (J = 6) then
        Check(Actual = -313, 'cross-variant-array-overwrite')
      else
        Check(Actual = Expected[I, J], 'cross-variant-array-index-oracle');
      Mix(UInt64(Actual));
    end;
end;

type
  TCrossPayload = class(Exception)
    Code: Integer;
  end;
  TCrossExceptionTransform = function(Err: TCrossPayload; Delta: Integer): Integer of object;

  TCrossExceptionHandler = class
    Calls: Integer;
    function Transform(Err: TCrossPayload; Delta: Integer): Integer;
  end;

function TCrossExceptionHandler.Transform(Err: TCrossPayload; Delta: Integer): Integer;
begin
  Inc(Calls);
  try
    raise EAbort.Create('nested status');
  except
    on Inner: EAbort do
    begin
      Check(ExceptObject = Inner, 'cross-exception-inner-object');
      Err.Code := Err.Code * 3 + Delta;
    end;
  end;
  Check(ExceptObject = Err, 'cross-exception-outer-object-restored');
  Result := Err.Code;
end;

procedure RunCrossExceptionStateForms;
var
  Handler: TCrossExceptionHandler;
  Call: TCrossExceptionTransform;
  Primary: TCrossPayload;
  FinCount, Code: Integer;
begin
  Handler := TCrossExceptionHandler.Create;
  try
    Call := Handler.Transform;
    Primary := TCrossPayload.Create('original status');
    Primary.Code := Integer(OpaqueI(-101));
    FinCount := 0;
    Code := 0;
    try
      try
        raise Primary;
      except
        on Outer: TCrossPayload do
        begin
          try
            Code := Call(Outer, Integer(OpaqueI(67)));
          finally
            Inc(FinCount);
          end;
          raise;
        end;
      end;
    except
      on Reraised: TCrossPayload do
      begin
        Check((Reraised = Primary) and (Reraised = ExceptObject), 'cross-exception-reraise-identity');
        Check(Reraised.Code = -236, 'cross-exception-reraise-payload');
      end;
    end;
    Check((Handler.Calls = 1) and (FinCount = 1), 'cross-exception-handler-finally-count');
    Check(Code = -236, 'cross-exception-callback-result');
    Check(ExceptObject = nil, 'cross-exception-no-active-object');
    Mix(UInt64(Code));
  finally
    Handler.Free;
  end;
end;

procedure RunCrossRoundEnvironmentForms;
const
  Modes: array[0..3] of TFPURoundingMode = (rmNearest, rmDown, rmUp, rmTruncate);
  Expected: array[0..3, 0..3] of Integer = ((2, -2, 2, -2), (1, -2, 2, -3), (2, -1, 3, -2), (1, -1, 2, -2));
var
  Previous: TFPURoundingMode;
  V: array[0..3] of Double;
  I, J: Integer;
  Rounded: Int64;
begin
  V[0] := OpaqueD(1.5);
  V[1] := OpaqueD(-1.5);
  V[2] := OpaqueD(2.5);
  V[3] := OpaqueD(-2.5);
  Previous := GetRoundMode;
  try
    for I := Low(Modes) to High(Modes) do
    begin
      SetRoundMode(Modes[I]);
      for J := Low(V) to High(V) do
      begin
        Rounded := Round(V[J]);
        Check(Rounded = Expected[I, J], 'cross-round-observes-current-mode');
        Check(Trunc(V[J]) = Expected[3, J], 'cross-trunc-ignores-current-mode');
        Mix(UInt64(Rounded));
      end;
    end;
  finally
    SetRoundMode(Previous);
  end;
end;

type
  TCrossFloatInteger = record
    FloatPart: Double;
    IntegerPart: Int64;
  end;

  TCrossIntegerFloat = record
    IntegerPart: Int64;
    FloatPart: Double;
  end;

  TCrossMixedCall = function(A, B, C, D, E: Int64; P: TCrossFloatInteger; F, G: Int64;
    H: Double; Q: TCrossIntegerFloat; I, J: Double): TCrossFloatInteger; cdecl;

function CrossMixedCall(A, B, C, D, E: Int64; P: TCrossFloatInteger; F, G: Int64;
  H: Double; Q: TCrossIntegerFloat; I, J: Double): TCrossFloatInteger; cdecl;
begin
  Result.IntegerPart := A + 2 * B + 3 * C + 5 * D + 7 * E + 11 * F + 13 * G;
  Result.IntegerPart := Result.IntegerPart + 17 * P.IntegerPart - 19 * Q.IntegerPart;
  Result.FloatPart := P.FloatPart + 3 * H - 5 * Q.FloatPart + 7 * I - 11 * J;
end;

procedure RunCrossMixedCallForms;
var
  Call: TCrossMixedCall;
  P, Actual: TCrossFloatInteger;
  Q: TCrossIntegerFloat;
begin
  Call := CrossMixedCall;
  P.FloatPart := OpaqueD(-3.75);
  P.IntegerPart := OpaqueI(101);
  Q.IntegerPart := OpaqueI(-113);
  Q.FloatPart := OpaqueD(17.25);
  Actual := Call(OpaqueI(7), OpaqueI(-11), OpaqueI(13), OpaqueI(-17), OpaqueI(19), P,
    OpaqueI(-23), OpaqueI(29), OpaqueD(-0.5), Q, OpaqueD(2.25), OpaqueD(-7.5));
  Check(Actual.IntegerPart = 4060, 'cross-cdecl-mixed-aggregate-gp');
  Check(Actual.FloatPart = 6.75, 'cross-cdecl-mixed-aggregate-simd');
  Mix(UInt64(Actual.IntegerPart));
  Mix(DoubleBits(Actual.FloatPart));
end;

function CrossSetSideEffect(var Calls: Integer; Value: Boolean): Boolean;
begin
  Inc(Calls);
  Result := Value;
end;

{$B-}
function CrossSetLazy(V: Byte; const SetA, SetB: TByteSet; var Calls: Integer): Integer;
begin
  Result := 0;
  If (V in (SetA - SetB)) and CrossSetSideEffect(Calls, True) then
    Inc(Result, 1);
  If (V in (SetA * SetB)) or CrossSetSideEffect(Calls, False) then
    Inc(Result, 2);
end;

{$B+}
function CrossSetEager(V: Byte; const SetA, SetB: TByteSet; var Calls: Integer): Integer;
begin
  Result := 0;
  If (V in (SetA - SetB)) and CrossSetSideEffect(Calls, True) then
    Inc(Result, 1);
  If (V in (SetA * SetB)) or CrossSetSideEffect(Calls, False) then
    Inc(Result, 2);
end;
{$B-}

procedure RunCrossSetEvaluationForms;
const
  Probes: array[0..7] of Byte = (0, 1, 63, 64, 127, 128, 254, 255);
  Expected: array[0..7] of Integer = (0, 1, 2, 1, 0, 1, 1, 2);
  LazyCalls: array[0..7] of Integer = (1, 2, 0, 2, 1, 2, 2, 0);
var
  A, B: TByteSet;
  I, Calls, Actual: Integer;
  V: Byte;
begin
  A := [1, 63..64, 128, 254..255];
  B := [0, 63, 127, 255];
  for I := Low(Probes) to High(Probes) do
  begin
    V := Byte(OpaqueI(Probes[I]));
    Calls := 0;
    Actual := CrossSetLazy(V, A, B, Calls);
    Check(Actual = Expected[I], 'cross-set-lazy-result');
    Check(Calls = LazyCalls[I], 'cross-set-lazy-evaluation-count');
    Calls := 0;
    Actual := CrossSetEager(V, A, B, Calls);
    Check(Actual = Expected[I], 'cross-set-complete-result');
    Check(Calls = 2, 'cross-set-complete-evaluation-count');
    Mix(UInt64(Actual));
  end;
end;

type
  TCrossUTF16 = procedure(var First, Second: WideChar);

procedure CrossReplacePair(var First, Second: WideChar);
begin
  First := WideChar($D83D);
  Second := WideChar($DE03);
end;

procedure RunCrossUnicodeCowForms;
var
  Before, After, Tail: UnicodeString;
  Original: PWideChar;
  Edit: TCrossUTF16;
  I: Integer;
begin
  SetLength(Before, 6);
  Before[1] := 'A';
  Before[2] := #0;
  Before[3] := WideChar($D834);
  Before[4] := WideChar($DD1E);
  Before[5] := WideChar($0301);
  Before[6] := 'Z';
  After := Before;
  Original := PWideChar(Before);
  I := Integer(OpaqueI(3));
  Edit := CrossReplacePair;
  Edit(After[I], After[I + 1]);
  Check((Ord(Original[2]) = $D834) and (Ord(Original[3]) = $DD1E), 'cross-utf16-cow-preserves-borrow');
  Check((Ord(After[3]) = $D83D) and (Ord(After[4]) = $DE03), 'cross-utf16-cow-both-var-writes');
  Check((After[2] = #0) and (Ord(After[5]) = $0301) and (After[6] = 'Z'), 'cross-utf16-cow-neighbor-units');
  Tail := Copy(After, I, 3);
  Delete(After, I, 2);
  Insert(Tail, After, I);
  Check((Length(After) = 7) and (After[2] = #0) and (After[7] = 'Z'), 'cross-utf16-nul-is-code-unit');
  Check((After[5] = WideChar($0301)) and (After[6] = WideChar($0301)), 'cross-utf16-slice-splice');
  Check((Length(Before) = 6) and (Before[3] = WideChar($D834)), 'cross-utf16-cow-source-retained');
  Mix(UInt64(Ord(Tail[1])) shl 16 or UInt64(Ord(Tail[2])));
end;

type
  TCrossVarRecCall = procedure(const Args: array of const);

procedure CrossReceiveVarRec(const Args: array of const);
begin
  Check((Low(Args) = 0) and (High(Args) = 2), 'cross-varrec-call-shape');
  Check((Args[0].VType = vtInt64) and (Args[1].VType = vtInterface)
    and (Args[2].VType = vtUnicodeString), 'cross-varrec-call-tags');
  If (Args[0].VType = vtInt64) and (Args[1].VType = vtInterface) and (Args[2].VType = vtUnicodeString) then begin
    Check(Args[0].VInt64^ = -861234567890, 'cross-varrec-call-live-integer');
    Check((Args[1].VInterface <> nil) and (TIntersectionOwner.Destroyed = 0), 'cross-varrec-call-live-interface');
    Check(UnicodeString(Args[2].VUnicodeString) = UnicodeString('item!'), 'cross-varrec-call-live-string');
  end;
  raise EAbort.Create('array of const consumer');
end;

procedure RunCrossVarRecUnwindForms;
var
  Call: TCrossVarRecCall;
  Caught: Boolean;

  function MakeOwner: IInterface;
  begin
    Result := TIntersectionOwner.Create;
  end;

  procedure ForwardArgs(const Args: array of const);
  begin
    Call(Args);
  end;

  procedure TemporaryArgs;
  var
    Text: UnicodeString;
  begin
    Text := 'item';
    ForwardArgs([OpaqueI(-861234567890), MakeOwner, Text + '!']);
  end;

begin
  TIntersectionOwner.Destroyed := 0;
  Call := CrossReceiveVarRec;
  Caught := False;
  try
    TemporaryArgs;
  except
    on EAbort do Caught := True;
  end;
  Check(Caught, 'cross-varrec-unwind-caught');
  Check(TIntersectionOwner.Destroyed = 1, 'cross-varrec-unwind-releases-temporary');
  Mix(UInt64(TIntersectionOwner.Destroyed));
end;

type
  TCrossPair<T, U> = record
    First: T;
    Second: U;
    class procedure SwapFields(var A: T; var B: U; var Item: TCrossPair<T, U>); static;
  end;

class procedure TCrossPair<T, U>.SwapFields(var A: T; var B: U; var Item: TCrossPair<T, U>);
var
  Old: TCrossPair<T, U>;
begin
  Old := Item;
  Item.First := A;
  Item.Second := B;
  A := Old.First;
  B := Old.Second;
end;

procedure RunCrossGenericAliasForms;
type
  TTextNumber = TCrossPair<AnsiString, Int64>;
  TNumberText = TCrossPair<Int64, AnsiString>;
var
  R: TTextNumber;
  S: TNumberText;
  Text: AnsiString;
  Number: Int64;
begin
  R.First := 'x';
  R.Second := OpaqueI(-227);
  S.First := OpaqueI(646);
  S.Second := 'y';
  Text := 'start';
  Number := OpaqueI(9000000099);
  TTextNumber.SwapFields(Text, Number, R);
  Check((R.First = AnsiString('start')) and (R.Second = 9000000099), 'cross-generic-managed-first');
  Check((Text = AnsiString('x')) and (Number = -227), 'cross-generic-first-snapshot');
  TNumberText.SwapFields(Number, Text, S);
  Check((S.First = -227) and (S.Second = AnsiString('x')), 'cross-generic-managed-second');
  Check((Text = AnsiString('y')) and (Number = 646), 'cross-generic-second-snapshot');
  TTextNumber.SwapFields(R.First, Number, R);
  Check((R.First = AnsiString('start')) and (R.Second = 646), 'cross-generic-var-overlaps-record');
  Check(Number = 9000000099, 'cross-generic-var-snapshot');
  Mix(UInt64(Number) xor UInt64(S.First));
end;

type
  TCrossCtorBase = class
  private
    FOwner: IInterface;
  public
    Stamp: Integer;
    class var BaseDestructions, Completed: Integer;
    constructor Create(Value: Integer); virtual;
    destructor Destroy; override;
    procedure AfterConstruction; override;
  end;

  TCrossCtorDerived = class(TCrossCtorBase)
  private
    FPartial: AnsiString;
  public
    class var DerivedDestructions: Integer;
    constructor Create(Value: Integer); override;
    destructor Destroy; override;
  end;

  TCrossCtorClass = class of TCrossCtorBase;

constructor TCrossCtorBase.Create(Value: Integer);
begin
  inherited Create;
  FOwner := TIntersectionOwner.Create;
  Stamp := Value;
end;

destructor TCrossCtorBase.Destroy;
begin
  Inc(BaseDestructions);
  inherited;
end;

procedure TCrossCtorBase.AfterConstruction;
begin
  inherited;
  Inc(Completed);
end;

constructor TCrossCtorDerived.Create(Value: Integer);
begin
  inherited Create(Value);
  FPartial := AnsiString('constructor payload');
  Stamp := Value * 3 + 7;
  If Value < 0 then
    raise EAbort.Create('virtual constructor failure');
end;

destructor TCrossCtorDerived.Destroy;
begin
  Check(FPartial = AnsiString('constructor payload'), 'cross-constructor-destructor-sees-initialized-part');
  Inc(DerivedDestructions);
  inherited;
end;

procedure RunCrossConstructorForms;
var
  Cls: TCrossCtorClass;
  Obj: TCrossCtorBase;
  Caught: Boolean;
begin
  TIntersectionOwner.Destroyed := 0;
  TCrossCtorBase.BaseDestructions := 0;
  TCrossCtorBase.Completed := 0;
  TCrossCtorDerived.DerivedDestructions := 0;
  Cls := TCrossCtorBase;
  If OpaqueI(9) = 9 then
    Cls := TCrossCtorDerived;
  Obj := nil;
  Caught := False;
  try
    Obj := Cls.Create(Integer(OpaqueI(-5)));
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Obj = nil), 'cross-constructor-no-instance-on-failure');
  If not Caught then
    Obj.Free;
  Check(TCrossCtorBase.Completed = 0, 'cross-constructor-failure-skips-after-construction');
  Check((TCrossCtorBase.BaseDestructions = 1) and (TCrossCtorDerived.DerivedDestructions = 1),
    'cross-constructor-failure-runs-destructor-chain');
  Check(TIntersectionOwner.Destroyed = 1, 'cross-constructor-failure-finalizes-fields');
  Obj := Cls.Create(Integer(OpaqueI(31)));
  try
    Check(Obj.Stamp = 100, 'cross-constructor-virtual-success');
    Check(TCrossCtorBase.Completed = 1, 'cross-constructor-success-after-construction');
    Check(TIntersectionOwner.Destroyed = 1, 'cross-constructor-success-owner-alive');
  finally
    Obj.Free;
  end;
  Check((TCrossCtorBase.BaseDestructions = 2) and (TCrossCtorDerived.DerivedDestructions = 2)
    and (TIntersectionOwner.Destroyed = 2), 'cross-constructor-success-cleanup');
  Mix(UInt64(TCrossCtorBase.Completed * 10 + TIntersectionOwner.Destroyed));
end;

{$R+}
procedure RunCrossCheckedPackedForms;
const
  Offsets: array[0..5] of Int64 = (0, -1, 127, -128, 4294967297, -4294967298);
  Targets: array[0..5] of Integer = (256, 511, 383, 384, 257, 510);
  Expected: array[0..5] of Int64 = (70000000001, -70000000003, 50000000009,
    -50000000021, 30000000011, -30000000037);
var
  Slots: array[256..511] of TCrossPacked;
  I, J, Probe: Integer;
  Found: Boolean;
begin
  for I := Low(Slots) to High(Slots) do
  begin
    Slots[I].Prefix := $A5;
    Slots[I].Marker := $DEAD;
    Slots[I].Value := -9001;
  end;
  for I := Low(Offsets) to High(Offsets) do
    Slots[256 + Byte(OpaqueI(Offsets[I]))].Value := OpaqueI(Expected[I]);
  for I := Low(Slots) to High(Slots) do
  begin
    Found := False;
    for J := Low(Targets) to High(Targets) do
      If Targets[J] = I then begin
        Check(Slots[I].Value = Expected[J], 'cross-packed-checked-narrow-index');
        Mix(UInt64(Slots[I].Value));
        Found := True;
        Break;
      end;
    If not Found then
      Check(Slots[I].Value = -9001, 'cross-packed-checked-no-unintended-store');
    Check((Slots[I].Prefix = $A5) and (Slots[I].Marker = $DEAD), 'cross-packed-checked-byte-guards');
  end;
  Probe := Integer(OpaqueI(-1));
  Check(Slots[256 + Byte(Probe)].Value = -70000000003, 'cross-packed-checked-runtime-load');
end;
{$R-}

function CrossWritableFrame(var Slots: array of TCrossEntry; Step: Integer): Int64;
var
  Total: Int64;

  procedure Walk(L, R: Integer);
  var
    Middle: Integer;
  begin
    If L > R then
      Exit;
    Middle := (L + R) div 2;
    Slots[Middle].Code := Slots[Middle].Code + Step * (Middle + 1);
    Slots[Middle].Text := Slots[Middle].Text + AnsiChar(Ord('0') + Middle);
    Total := Total * 100 + Slots[Middle].Code;
    Walk(L, Middle - 1);
    Walk(Middle + 1, R);
  end;

begin
  Total := 0;
  Walk(Low(Slots), High(Slots));
  Result := Total;
end;

procedure RunCrossWritableFrameForms;
const
  Before: array[0..4] of Integer = (1, 4, 5, 8, 11);
  After: array[0..4] of Integer = (4, 10, 14, 20, 26);
  Names: array[0..4] of AnsiString = ('slot-0', 'slot-1', 'slot-2', 'slot-3', 'slot-4');
var
  Slots: array[-9..-5] of TCrossEntry;
  Empty: TCrossEntries;
  I: Integer;
  WalkCode: Int64;
begin
  for I := Low(Before) to High(Before) do
  begin
    Slots[I - 9].Code := Before[I];
    Slots[I - 9].Text := 'slot-';
  end;
  Empty := nil;
  Check(CrossWritableFrame(Empty, 3) = 0, 'cross-nested-writable-open-array-empty');
  WalkCode := CrossWritableFrame(Slots, Integer(OpaqueI(3)));
  Check(WalkCode = 1404102026, 'cross-nested-writable-open-array-walk-order');
  for I := Low(After) to High(After) do
  begin
    Check(Slots[I - 9].Code = After[I], 'cross-nested-writable-open-array-code');
    Check(Slots[I - 9].Text = Names[I], 'cross-nested-writable-open-array-strings');
  end;
  Mix(UInt64(WalkCode));
end;

{$I mega_breadth_optimizer.inc}
{$I mega_breadth_calls.inc}
{$I mega_breadth_runtime.inc}
{$I mega_breadth_modules.inc}
{$I mega_breadth_numbers.inc}
{$I mega_breadth_text.inc}
{$I mega_breadth_dispatch.inc}
{$I mega_breadth_arrays.inc}
{$I mega_breadth_boundaries.inc}
{$I mega_breadth_transfers.inc}
{$I mega_breadth_bindings.inc}
{$I mega_breadth_consumers.inc}
{$I mega_breadth_destinations.inc}
{$I mega_breadth_callbacks.inc}
{$I mega_breadth_keys.inc}
{$I mega_breadth_language.inc}
{$I mega_breadth_interfaces.inc}
{$I mega_breadth_hooks.inc}
{$I mega_breadth_fpabi.inc}
{$I mega_breadth_guards.inc}
{$I mega_breadth_records.inc}
{$I mega_breadth_resource.inc}
{$I mega_breadth_specialization.inc}
{$I mega_breadth_queue.inc}
{$I mega_breadth_varargs.inc}
{$I mega_breadth_operator.inc}
{$I mega_breadth_fpstore.inc}
{$I mega_breadth_codepage.inc}
{$I mega_breadth_cursor.inc}
{$I mega_breadth_varray.inc}
{$I mega_breadth_ownership.inc}
{$I mega_breadth_ccallbacks.inc}
{$I mega_breadth_rtti.inc}
{$I mega_breadth_oletext.inc}
{$I mega_breadth_inherited.inc}
{$I mega_breadth_aliasedref.inc}
{$I mega_breadth_selfinsert.inc}
{$I mega_breadth_shortabi.inc}
{$I mega_breadth_streamcopy.inc}
{$I mega_breadth_assert.inc}
{$I mega_breadth_fixup.inc}
{$I mega_breadth_timestamps.inc}
{$I mega_breadth_threadlocal.inc}
{$I mega_breadth_ifinherit.inc}
{$I mega_breadth_sliceowners.inc}
{$I mega_breadth_cscan.inc}
{$I mega_breadth_classdelegate.inc}
{$I mega_breadth_setabi.inc}
{$I mega_breadth_builder.inc}
{$I mega_breadth_val.inc}
{$I mega_breadth_listevents.inc}
{$I mega_breadth_unitcalls.inc}
{$I mega_breadth_tvalue.inc}
{$I mega_breadth_pairs.inc}
{$I mega_breadth_events.inc}
{$I mega_breadth_format.inc}
{$I mega_breadth_sharedrows.inc}
{$I mega_breadth_olecurrency.inc}
{$I mega_breadth_repeat.inc}
{$I mega_breadth_istream.inc}
{$I mega_breadth_variantowners.inc}
{$I mega_breadth_widertti.inc}
{$I mega_breadth_setstring.inc}
{$I mega_breadth_compabi.inc}
{$I mega_breadth_str.inc}
{$I mega_breadth_variantref.inc}
{$I mega_breadth_twoout.inc}
{$I mega_breadth_extract.inc}
{$I mega_breadth_encoding.inc}
{$I mega_breadth_sortslice.inc}
{$I mega_breadth_decimalargs.inc}
{$I mega_breadth_collection.inc}
{$I mega_breadth_adaptercopy.inc}
{$I mega_breadth_queueremove.inc}
{$I mega_breadth_variantplane.inc}
{$I mega_breadth_persistent.inc}
{$I mega_breadth_stringlistsort.inc}
{$I mega_breadth_cunsigned.inc}
{$I mega_breadth_scalar.inc}
{$I mega_breadth_subcomponent.inc}
{$I mega_breadth_bom.inc}
{$I mega_breadth_cfloat.inc}
{$I mega_breadth_listduplicate.inc}
{$I mega_breadth_filer.inc}
{$I mega_breadth_datetext.inc}
{$I mega_breadth_tvaluedynamic.inc}
{$I mega_breadth_resaddress.inc}
{$I mega_breadth_rtarray.inc}
{$I mega_breadth_linebreaks.inc}
{$I mega_breadth_projectors.inc}
{$I mega_breadth_logicop.inc}
{$I mega_breadth_streamrecovery.inc}
{$I mega_breadth_indexeffects.inc}
{$I mega_breadth_workerqueue.inc}
{$I mega_breadth_monitorhandoff.inc}
{$I mega_breadth_dictionaryrecovery.inc}
{$I mega_breadth_readerrecovery.inc}
{$I mega_breadth_transferstate.inc}
{$I mega_breadth_sharedgeneric.inc}
{$I mega_breadth_stackowners.inc}
{$I mega_breadth_ini_transfer.inc}

procedure RunBreadthForms;
begin
  RunIntersectionDivisionForms;
  RunIntersectionCheckedForms;
  RunIntersectionMethodForms;
  RunCrossLoopLifetimeForms;
  RunCrossPackedAliasForms;
  RunCrossDenseCaseForms;
  RunCrossDetachAliasForms;
  RunCrossVariantArrayForms;
  RunCrossExceptionStateForms;
  RunCrossRoundEnvironmentForms;
  RunCrossMixedCallForms;
  RunCrossSetEvaluationForms;
  RunCrossUnicodeCowForms;
  RunCrossVarRecUnwindForms;
  RunCrossGenericAliasForms;
  RunCrossConstructorForms;
  RunCrossCheckedPackedForms;
  RunCrossWritableFrameForms;
  RunBreadthOptimizerForms;
  RunBreadthCallForms;
  RunBreadthRuntimeForms;
  RunBreadthModuleForms;
  RunBreadthNumericForms;
  RunBreadthTextForms;
  RunBreadthDispatchForms;
  RunBreadthArrayForms;
  RunBreadthBoundaryForms;
  RunBreadthTransferForms;
  RunBreadthBindingForms;
  RunBreadthConsumerForms;
  RunBreadthDestinationForms;
  RunBreadthCallbackForms;
  RunBreadthKeyForms;
  RunBreadthLanguageForms;
  RunBreadthInterfaceForms;
  RunBreadthCapturedResult;
  RunBreadthHookForms;
  RunBreadthFloatingABIForms;
  RunBreadthInterfaceCastFailure;
  RunBreadthEvaluationGuards;
  RunBreadthPackedEnums;
  RunBreadthRecordConstructor;
  RunBreadthResourceDispatch;
  RunBreadthSpecializedStorage;
  RunBreadthManagedQueue;
  RunBreadthCVarargs;
  RunBreadthManagedOperator;
  RunBreadthPackedFloatStore;
  RunBreadthCodePageDetach;
  RunBreadthEnumeratorFailures;
  RunBreadthLockedVariantArray;
  RunBreadthObjectDictionary;
  RunBreadthCCallbacks;
  RunBreadthPublishedSet;
  RunBreadthOleWideString;
  RunBreadthInheritedProperty;
  RunBreadthByValueInterface;
  RunBreadthSelfInsert;
  RunBreadthAliasedShortString;
  RunBreadthStreamCopy;
  RunBreadthAssertionControl;
  RunBreadthComponentFixup;
  RunBreadthCalendarBoundary;
  RunBreadthInheritedInterface;
  RunBreadthCopiedOwners;
  RunBreadthCScan;
  RunBreadthClassDelegate;
  RunBreadthByValueSet;
  RunBreadthUnicodeBuilder;
  RunBreadthPackedVal;
  RunBreadthListEvents;
  RunBreadthCompiledCallback;
  RunBreadthBoxedValues;
  RunBreadthTemporaryPairs;
  RunBreadthEventPolling;
  RunBreadthPositionalFormat;
  RunBreadthSharedRows;
  RunBreadthVariantCurrency;
  RunBreadthRepeatEdges;
  RunBreadthStreamAdapter;
  RunBreadthBoxedFloatKinds;
  RunBreadthVariantArrayOwners;
  RunBreadthWideReflection;
  RunBreadthCountedUnicodeSpan;
  RunBreadthCompPacket;
  RunBreadthPackedStr;
  RunBreadthByRefInt64Variant;
  RunBreadthTwoOutParameters;
  RunBreadthListExtract;
  RunBreadthEncodingStream;
  RunBreadthGenericSortSlice;
  RunBreadthDecimalVarRecs;
  RunBreadthCollectionStream;
  RunBreadthAdapterCopy;
{$ifdef BREADTH_MAIN_FORCE_QUEUE}
  RunBreadthQueueRemoval;
{$endif}
  RunBreadthVariantPlane;
  RunBreadthPersistentAssign;
  RunBreadthStringListAttachments;
  RunBreadthUnsignedCParse;
  RunBreadthUnicodeScalar;
  RunBreadthReadonlySubcomponent;
  RunBreadthEncodingDetection;
  RunBreadthCFloatSplit;
  RunBreadthSortedDuplicate;
  RunBreadthPrivateFiler;
  RunBreadthLocalDateText;
  RunBreadthDynamicValue;
  RunBreadthResourceAddress;
  RunBreadthRttiDynamicProperty;
  RunBreadthLineNormalization;
  RunBreadthDualProjector;
  RunBreadthLogicalOverload;
  RunBreadthShortReads;
  RunBreadthShortWrites;
  RunBreadthStringStreamWire;
  RunBreadthIndexedPropertyEffects;
{$ifdef BREADTH_MAIN_FORCE_QUEUE}
  RunBreadthWorkerQueue;
{$endif}
{$ifdef BREADTH_HAS_MONITOR}
  RunBreadthMonitorHandoff;
{$endif}
  RunBreadthDictionaryRecovery;
  RunBreadthReaderRecovery;
  RunBreadthThreadListSnapshot;
  RunBreadthKeyedStrings;
  RunBreadthEncodingSpan;
  RunBreadthSharedGeneric;
  RunBreadthStackOwners;
  RunBreadthIniTransfer;
  RunBreadthProtocolTimestamps;
  RunBreadthThreadLocalTokens;
end;
