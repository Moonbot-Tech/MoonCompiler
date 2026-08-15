program generic_services_semantic;

{$mode delphi}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Classes,
  Math,
  Generics.Defaults,
  Generics.Collections;

type
  TPackedKey = packed record
    Number: Integer;
    Kind: Byte;
  end;
  TIntArray = array of Integer;

  TTracked = class(TInterfacedObject)
  public
    destructor Destroy; override;
  end;

  TCompareProbe = class
  private
    FCalls: Integer;
  public
    function Compare(const Left, Right: Integer): Integer;
    property Calls: Integer read FCalls;
  end;

  TAdderThread = class(TThread)
  private
    FList: TThreadList<Integer>;
    FBase: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AList: TThreadList<Integer>; ABase: Integer);
  end;

var
  Destroyed: Integer;

destructor TTracked.Destroy;
begin
  InterlockedIncrement(Destroyed);
  inherited Destroy;
end;

function TCompareProbe.Compare(const Left, Right: Integer): Integer;
begin
  Inc(FCalls);
  if Left < Right then
    Result := -1
  else if Left > Right then
    Result := 1
  else
    Result := 0;
end;

constructor TAdderThread.Create(AList: TThreadList<Integer>; ABase: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FList := AList;
  FBase := ABase;
end;

procedure TAdderThread.Execute;
var
  I: Integer;
begin
  for I := 0 to 999 do
    FList.Add(FBase + I);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('GENERIC_SERVICES_FAIL: ' + AMessage);
end;

procedure TestComparers;
var
  IntComparer: IComparer<Integer>;
  DoubleComparer: IComparer<Double>;
  StringComparer: IComparer<UnicodeString>;
  IntEquality: IEqualityComparer<Integer>;
  DoubleEquality: IEqualityComparer<Double>;
  StringEquality: IEqualityComparer<UnicodeString>;
  RecordEquality: IEqualityComparer<TPackedKey>;
  ArrayEquality: IEqualityComparer<TIntArray>;
  Custom: IEqualityComparer<UnicodeString>;
  EventComparer: IComparer<Integer>;
  EventCallback: TOnComparison<Integer>;
  Probe: TCompareProbe;
  Key1, Key2, Key3: TPackedKey;
  Array1, Array2, Array3: TIntArray;
  PositiveZero, NegativeZero: Double;
begin
  IntComparer := TComparer<Integer>.Default;
  Check((IntComparer.Compare(Low(Integer), High(Integer)) < 0) and
    (IntComparer.Compare(7, 7) = 0) and
    (IntComparer.Compare(9, -4) > 0), 'ordinal comparer');
  IntEquality := TEqualityComparer<Integer>.Default;
  Check(IntEquality.Equals(42, 42) and not IntEquality.Equals(42, 43),
    'ordinal equality');
  Check(IntEquality.GetHashCode(42) = IntEquality.GetHashCode(42),
    'ordinal hash stability');

  DoubleComparer := TComparer<Double>.Default;
  Check((DoubleComparer.Compare(-Infinity, 0.0) < 0) and
    (DoubleComparer.Compare(1.5, 1.5) = 0) and
    (DoubleComparer.Compare(Infinity, 1.5) > 0), 'float comparer');
  PositiveZero := 0.0;
  NegativeZero := -PositiveZero;
  DoubleEquality := TEqualityComparer<Double>.Default;
  Check(DoubleEquality.Equals(PositiveZero, NegativeZero), 'signed-zero equality');
  Check(DoubleEquality.GetHashCode(PositiveZero) =
    DoubleEquality.GetHashCode(NegativeZero), 'signed-zero hash');

  StringComparer := TComparer<UnicodeString>.Default;
  Check((StringComparer.Compare('abc','abc')=0) and
    (StringComparer.Compare('abc','abcd')<0) and
    (StringComparer.Compare('abcd','abc')>0) and
    (StringComparer.Compare(#$0416,#$042F)<0),
    'Unicode comparer equality/prefix/order');
  StringEquality := TEqualityComparer<UnicodeString>.Default;
  Check(StringEquality.Equals('a'#0'b', 'a'#0'b') and
    not StringEquality.Equals('a'#0'b', 'a'#0'c'), 'Unicode equality');
  Check(StringEquality.GetHashCode('moon') =
    StringEquality.GetHashCode('moon'), 'Unicode hash stability');

  FillChar(Key1, SizeOf(Key1), 0);
  Key1.Number := 17;
  Key1.Kind := 3;
  Key2 := Key1;
  Key3 := Key1;
  Key3.Kind := 4;
  RecordEquality := TEqualityComparer<TPackedKey>.Default;
  Check(RecordEquality.Equals(Key1, Key2) and
    not RecordEquality.Equals(Key1, Key3), 'record equality');
  Check(RecordEquality.GetHashCode(Key1) = RecordEquality.GetHashCode(Key2),
    'record hash');

  Array1 := TIntArray.Create(1, 2, 3, 5);
  Array2 := TIntArray.Create(1, 2, 3, 5);
  Array3 := TIntArray.Create(1, 2, 3, 6);
  ArrayEquality := TEqualityComparer<TIntArray>.Default;
  Check(ArrayEquality.Equals(Array1, Array2) and
    not ArrayEquality.Equals(Array1, Array3), 'dynamic-array equality');
  Check(ArrayEquality.GetHashCode(Array1) = ArrayEquality.GetHashCode(Array2),
    'dynamic-array hash');

  Custom := TEqualityComparer<UnicodeString>.Construct(
    function(const Left, Right: UnicodeString): Boolean
    begin
      Result := SameText(Left, Right);
    end,
    function(const Value: UnicodeString): Integer
    begin
      Result := Length(Value) + 100;
    end);
  Check(Custom.Equals('Moon', 'moon') and
    (Custom.GetHashCode('abc') = 103), 'custom comparer/hash');

  Probe := TCompareProbe.Create;
  try
    EventCallback := Probe.Compare;
    EventComparer := TComparer<Integer>.Construct(EventCallback);
    Check((EventComparer.Compare(1, 2) < 0) and (Probe.Calls = 1),
      'event comparer invocation');
  finally
    EventComparer := nil;
    EventCallback := nil;
    Probe.Free;
  end;
end;

procedure TestThreadList;
var
  List: TThreadList<Integer>;
  ManagedList: TThreadList<IInterface>;
  Locked: TList<Integer>;
  Threads: array[0..3] of TAdderThread;
  Seen: array[0..3999] of Boolean;
  I, Value: Integer;
  Raised: Boolean;
  Item: IInterface;
begin
  List := TThreadList<Integer>.Create;
  try
    List.Add(7);
    List.Add(7);
    Locked := List.LockList;
    try
      Check((Locked.Count = 1) and (Locked[0] = 7), 'dupIgnore');
    finally
      List.UnlockList;
    end;
    List.Duplicates := dupError;
    Raised := False;
    try
      List.Add(7);
    except
      on EArgumentException do
        Raised := True;
    end;
    Check(Raised, 'dupError');
    List.Clear;
    List.Duplicates := dupAccept;
    for I := 0 to High(Threads) do
    begin
      Threads[I] := TAdderThread.Create(List, I * 1000);
      Threads[I].Start;
    end;
    for I := 0 to High(Threads) do
    begin
      Threads[I].WaitFor;
      Check(Threads[I].FatalException = nil, 'adder exception');
      Threads[I].Free;
    end;
    FillChar(Seen, SizeOf(Seen), 0);
    Locked := List.LockList;
    try
      Check(Locked.Count = Length(Seen), 'contended count');
      for I := 0 to Locked.Count - 1 do
      begin
        Value := Locked[I];
        Check((Value >= 0) and (Value <= High(Seen)) and not Seen[Value],
          'contended values');
        Seen[Value] := True;
      end;
    finally
      List.UnlockList;
    end;
    List.Remove(17);
    Locked := List.LockList;
    try
      Check((Locked.Count = Length(Seen) - 1) and
        (Locked.IndexOf(17) = -1), 'remove');
    finally
      List.UnlockList;
    end;
  finally
    List.Free;
  end;

  Destroyed := 0;
  ManagedList := TThreadList<IInterface>.Create;
  try
    Item := TTracked.Create;
    ManagedList.Add(Item);
    Item := nil;
    Check(Destroyed = 0, 'managed item retained');
    ManagedList.Clear;
    Check(Destroyed = 1, 'managed item finalized by clear');
  finally
    ManagedList.Free;
  end;
end;

begin
  try
    TestComparers;
    TestThreadList;
    WriteLn('GENERIC_SERVICES_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
