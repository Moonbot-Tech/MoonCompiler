{ Interface and indexed property dispatch exercise both hidden arguments
  and language-specific forwarding rules. }

type
  IBreadthSafeCall = interface
    ['{29D6E326-F49D-4AF5-8420-4F8784A99EA6}']
    function ReadValue(Key: Int64; Factor: Double; Fail: Boolean): UnicodeString; safecall;
  end;

  TBreadthSafeCall = class(TInterfacedObject, IBreadthSafeCall)
  public
    Calls, Exceptions: Integer;
    SeenOriginalException: Boolean;
    function ReadValue(Key: Int64; Factor: Double; Fail: Boolean): UnicodeString; safecall;
    function SafeCallException(ExceptObject: TObject; ExceptAddr: Pointer): HResult; override;
  end;

function TBreadthSafeCall.ReadValue(Key: Int64; Factor: Double; Fail: Boolean): UnicodeString;
begin
  Inc(Calls);
  If Fail then
    raise EAbort.Create('safecall source exception');
  Result := UnicodeString(IntToStr(Key + Trunc(Factor * 16.0))) + '!';
end;

function TBreadthSafeCall.SafeCallException(ExceptObject: TObject; ExceptAddr: Pointer): HResult;
begin
  Inc(Exceptions);
  SeenOriginalException := ExceptObject is EAbort;
  Result := HResult($80004005);
end;

procedure RunBreadthSafeCall;
var
  Anchor: IBreadthSafeCall;
  Handler: TBreadthSafeCall;
  Data: UnicodeString;
  Caught: Boolean;
begin
  Handler := TBreadthSafeCall.Create;
  Anchor := Handler;
  Data := Anchor.ReadValue(OpaqueI(90000000001), OpaqueD(2.5), False);
  Check(Data = '90000000041!', 'breadth-safecall-managed-result');
  Caught := False;
  try
    Data := Anchor.ReadValue(OpaqueI(-90000000001), OpaqueD(-0.5), True);
  except
    on Exception do Caught := True;
  end;
  Check(Caught and (Handler.Exceptions = 1) and Handler.SeenOriginalException, 'breadth-safecall-exception-bridge');
  Data := Anchor.ReadValue(OpaqueI(-90000000001), OpaqueD(-0.5), False);
  Check((Handler.Calls = 3) and (Data = '-90000000009!'), 'breadth-safecall-recovery');
  Mix(UInt64(Length(Data)));
end;

type
  TBreadthCoordinate = record
  private
    FRaw: Int64;
    procedure Put(Value: Integer);
    function Take: Integer;
  public
    LabelText: AnsiString;
    property Position: Integer read Take write Put;
  end;

  TBreadthNavigation = class
  private
    FItems: array[0..2] of TBreadthCoordinate;
    function GetCoord(Index: Integer): TBreadthCoordinate; virtual;
    procedure SetCoord(Index: Integer; const Value: TBreadthCoordinate); virtual;
  public
    Writes, Reads: Integer;
    property Items[Index: Integer]: TBreadthCoordinate read GetCoord write SetCoord; default;
  end;

procedure TBreadthCoordinate.Put(Value: Integer);
begin
  FRaw := Int64(Value) * 1000000007 + 19;
end;

function TBreadthCoordinate.Take: Integer;
begin
  Result := Integer((FRaw - 19) div 1000000007);
end;

function TBreadthNavigation.GetCoord(Index: Integer): TBreadthCoordinate;
begin
  Inc(Reads);
  Result := FItems[Index];
end;

procedure TBreadthNavigation.SetCoord(Index: Integer; const Value: TBreadthCoordinate);
begin
  Inc(Writes);
  FItems[Index] := Value;
end;

function BreadthEditCoordinate(Item: TBreadthCoordinate; Delta: Integer): TBreadthCoordinate;
begin
  Item.Position := Item.Position + Delta;
  Item.LabelText := Item.LabelText + AnsiChar('!');
  Result := Item;
end;

procedure RunBreadthPropertySnapshots;
var
  Nav: TBreadthNavigation;
  Initial, Source, Target: TBreadthCoordinate;
  First, Second: Integer;
begin
  Nav := TBreadthNavigation.Create;
  try
    First := Integer(OpaqueI(1));
    Second := Integer(OpaqueI(2));
    Initial.Position := Integer(OpaqueI(-37));
    Initial.LabelText := 'shared coordinate';
    Nav[First] := Initial;
    Nav[Second] := BreadthEditCoordinate(Nav[First], Integer(OpaqueI(109)));
    Source := Nav[First];
    Target := Nav[Second];
    Check((Source.Position = -37) and (Source.LabelText = AnsiString('shared coordinate')),
      'breadth-property-return-detaches-by-value-edit');
    Check((Target.Position = 72) and (Target.LabelText = AnsiString('shared coordinate!')),
      'breadth-property-record-write-through-setter');
    Check(Target.FRaw = 72000000523, 'breadth-property-exact-wide-internal-state');
    Check((Nav.Writes = 2) and (Nav.Reads = 3), 'breadth-property-virtual-dispatch-counts');
    Mix(UInt64(Target.FRaw));
  finally
    Nav.Free;
  end;
end;

type
  TBreadthTypeCalculation = class
    class function Bias: Integer; virtual;
    class function Compute(Key: Int64; Fraction: Double): TCrossEntry; virtual;
  end;

  TBreadthDerivedCalculation = class(TBreadthTypeCalculation)
    class function Bias: Integer; override;
  end;

  TBreadthAlternateCalculation = class(TBreadthTypeCalculation)
    class function Compute(Key: Int64; Fraction: Double): TCrossEntry; override;
  end;

  TBreadthCalculationClass = class of TBreadthTypeCalculation;
  TBreadthClassMethod = function(Key: Int64; Fraction: Double): TCrossEntry of object;

class function TBreadthTypeCalculation.Bias: Integer;
begin
  Result := 11;
end;

class function TBreadthTypeCalculation.Compute(Key: Int64; Fraction: Double): TCrossEntry;
begin
  Result.Code := Key * Bias + Trunc(Fraction * 8.0);
  Result.Text := AnsiString('type-') + AnsiString(IntToStr(Bias));
end;

class function TBreadthDerivedCalculation.Bias: Integer;
begin
  Result := -17;
end;

class function TBreadthAlternateCalculation.Compute(Key: Int64; Fraction: Double): TCrossEntry;
begin
  Result.Code := Key + Bias + Trunc(Fraction * 16.0);
  Result.Text := AnsiString('alternate');
end;

procedure RunBreadthBoundClassReceivers;
const
  Kinds: array[0..1] of TBreadthCalculationClass = (TBreadthDerivedCalculation, TBreadthAlternateCalculation);
var
  Readers: array[0..1] of TBreadthClassMethod;
  Selected: TBreadthCalculationClass;
  I: Integer;
  RecordResult: TCrossEntry;
begin
  for I := Low(Kinds) to High(Kinds) do
  begin
    Selected := Kinds[Integer(OpaqueI(I))];
    Readers[I] := Selected.Compute;
    Check(TMethod(Readers[I]).Data = Pointer(Selected), 'breadth-class-method-pointer-binds-metaclass');
  end;
  RecordResult := Readers[0](OpaqueI(9000000041), OpaqueD(0.625));
  Check((RecordResult.Code = -153000000692) and (RecordResult.Text = AnsiString('type--17')),
    'breadth-class-method-pointer-inherited-receiver-bias');
  RecordResult := Readers[1](OpaqueI(-9000000041), OpaqueD(-0.625));
  Check((RecordResult.Code = -9000000040) and (RecordResult.Text = AnsiString('alternate')),
    'breadth-class-method-pointer-overridden-managed-result');
  Mix(UInt64(RecordResult.Code));
end;

type
  PBreadthLegacy = ^TBreadthLegacy;
  PBreadthLegacyChild = ^TBreadthLegacyChild;

  TBreadthLegacy = object
    BaseOwner: IInterface;
    Key: Integer;
    constructor Init(AKey: Integer);
    destructor Done; virtual;
    function Size: Integer; virtual;
  end;

  TBreadthLegacyChild = object(TBreadthLegacy)
    ChildOwner: IInterface;
    Text: AnsiString;
    constructor Init(AKey: Integer; const AText: AnsiString);
    destructor Done; virtual;
    function Size: Integer; virtual;
  end;

var
  BreadthLegacyDone: Integer;

constructor TBreadthLegacy.Init(AKey: Integer);
begin
  Key := AKey;
  BaseOwner := TIntersectionOwner.Create;
end;

destructor TBreadthLegacy.Done;
begin
  Check((BaseOwner <> nil) and (Key = 79), 'breadth-legacy-inherited-destructor-live-base-fields');
  Inc(BreadthLegacyDone);
end;

function TBreadthLegacy.Size: Integer;
begin
  Result := Key;
end;

constructor TBreadthLegacyChild.Init(AKey: Integer; const AText: AnsiString);
begin
  inherited Init(AKey);
  ChildOwner := TIntersectionOwner.Create;
  Text := AText + '!';
end;

destructor TBreadthLegacyChild.Done;
begin
  Check((ChildOwner <> nil) and (Text = AnsiString('legacy!')), 'breadth-legacy-virtual-destructor-live-derived-fields');
  { Dispose is called through the base type. Finish the derived-owned
    state explicitly before returning to the base destructor. }
  ChildOwner := nil;
  Text := '';
  Inc(BreadthLegacyDone, 20);
  inherited Done;
end;

function TBreadthLegacyChild.Size: Integer;
begin
  Result := inherited Size * 3 + Length(Text);
end;

procedure RunBreadthLegacyHeapObject;
var
  Child: PBreadthLegacyChild;
  BaseView: PBreadthLegacy;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthLegacyDone := 0;
  New(Child, Init(Integer(OpaqueI(79)), AnsiString('legacy')));
  BaseView := Child;
  try
    Check(BaseView^.Size = 244, 'breadth-legacy-new-object-dispatches-through-base');
    Check(TIntersectionOwner.Destroyed = 0, 'breadth-legacy-heap-owners-live-after-constructor');
  finally
    Dispose(BaseView, Done);
  end;
  Check(BreadthLegacyDone = 21, 'breadth-legacy-dispose-both-destructors');
  Check(TIntersectionOwner.Destroyed = 2, 'breadth-legacy-dispose-releases-owners');
  Mix(UInt64(BreadthLegacyDone));
end;

procedure RunBreadthDispatchForms;
begin
  RunBreadthSafeCall;
  RunBreadthPropertySnapshots;
  RunBreadthBoundClassReceivers;
  RunBreadthLegacyHeapObject;
end;
