program rtl_api_surface;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch advancedrecords}
  {$modeswitch arrayoperators}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch implicitgenerics}
  {$modeswitch inlinevars}
{$endif}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  fpmonitor,
  {$else}
  fpwinmonitor,
  {$endif}
{$endif}
  SysUtils,
  System.Classes,
  System.Generics.Defaults,
  System.Generics.Collections,
  System.SyncObjs,
  System.Diagnostics,
  System.DateUtils,
  System.IOUtils,
  System.StrUtils,
  System.TypInfo,
  System.Rtti;

type
  TProbeEnum = (peZero, peOne, peTwo);

  TProbeObject = class
  strict private
    class var FAlive: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    class property Alive: Integer read FAlive;
  end;

  TProbeThread = class(TThread)
  strict private
    FValue: Integer;
  protected
    procedure Execute; override;
  public
    property Value: Integer read FValue;
  end;

  TProbeMemoryStream = class(TMemoryStream)
  strict private
    FCapacityCalls: Integer;
  protected
    procedure SetCapacity(NewCapacity: NativeInt); override;
  public
    procedure Reserve(NewCapacity: NativeInt);
    property CapacityCalls: Integer read FCapacityCalls;
  end;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

constructor TProbeObject.Create;
begin
  inherited Create;
  Inc(FAlive);
end;

destructor TProbeObject.Destroy;
begin
  Dec(FAlive);
  inherited Destroy;
end;

procedure TProbeThread.Execute;
begin
  FValue := 42;
end;

procedure TProbeMemoryStream.SetCapacity(NewCapacity: NativeInt);
begin
  Inc(FCapacityCalls);
  inherited SetCapacity(NewCapacity);
end;

procedure TProbeMemoryStream.Reserve(NewCapacity: NativeInt);
begin
  SetCapacity(NewCapacity);
end;

function CompareInteger(const ALeft, ARight: Integer): Integer;
begin
  If ALeft < ARight then begin
    Result := -1;
  end else If ALeft > ARight then begin
    Result := 1;
  end else begin
    Result := 0;
  end;
end;

procedure CheckThreadsAndSync;
var
  AnonymousDone: TEvent;
  AnonymousThread: TThread;
  CriticalSection: TCriticalSection;
  LockObject: TObject;
  Thread: TProbeThread;
  TickBefore: UInt64;
  Value: Integer;
begin
  Thread := TProbeThread.Create;
  try
    Thread.WaitFor;
    Check(Thread.Value = 42, 'thread-create-default');
  finally
    Thread.Free;
  end;

  Thread := TProbeThread.Create(True);
  try
    Thread.Start;
    Thread.WaitFor;
    Check(Thread.Value = 42, 'thread-create-suspended');
  finally
    Thread.Free;
  end;

  Value := 0;
  AnonymousDone := TEvent.Create(nil, True, False, '');
  try
    AnonymousThread := TThread.CreateAnonymousThread(
      procedure
      begin
        Value := 73;
        AnonymousDone.SetEvent;
      end);
    AnonymousThread.FreeOnTerminate := False;
    try
      AnonymousThread.Start;
      Check(AnonymousDone.WaitFor(5000) = wrSignaled,
        'thread-anonymous-signal');
      AnonymousThread.WaitFor;
      Check(Value = 73, 'thread-anonymous-capture');
    finally
      AnonymousThread.Free;
    end;
    AnonymousDone.ResetEvent;
    Check(AnonymousDone.WaitFor(0) = wrTimeout, 'event-reset');
    AnonymousDone.SetEvent;
    Check(AnonymousDone.WaitFor(0) = wrSignaled, 'event-set');
  finally
    AnonymousDone.Free;
  end;

  CriticalSection := TCriticalSection.Create;
  try
    CriticalSection.Enter;
    CriticalSection.Leave;
    CriticalSection.Acquire;
    CriticalSection.Release;
    Check(CriticalSection.TryEnter, 'critical-section-try-enter');
    CriticalSection.Leave;
  finally
    CriticalSection.Free;
  end;

  LockObject := TObject.Create;
  try
    TMonitor.Enter(LockObject);
    try
      Value := 91;
    finally
      TMonitor.Exit(LockObject);
    end;
    Check(Value = 91, 'monitor-enter-exit');
    Check(TMonitor.TryEnter(LockObject), 'monitor-try-enter');
    TMonitor.Exit(LockObject);
  finally
    LockObject.Free;
  end;

  Value := 0;
  TThread.Queue(nil,
    procedure
    begin
      Value := 92;
    end);
  Check(Value = 92, 'thread-queue-main');
  TThread.Synchronize(nil,
    procedure
    begin
      Value := 93;
    end);
  Check(Value = 93, 'thread-synchronize-main');
  TThread.ForceQueue(nil,
    procedure
    begin
      Value := 94;
    end);
  Check(CheckSynchronize(1000) and (Value = 94), 'thread-force-queue');

  Check(TThread.ProcessorCount > 0, 'thread-processor-count');
  TickBefore := TThread.GetTickCount64;
  TThread.Sleep(0);
  Check(TThread.GetTickCount64 >= TickBefore, 'thread-tick-count64');
  TThread.NameThreadForDebugging('rtl-api-main');
  TThread.Yield;
end;

procedure CheckListsAndArrays;
var
  CopyList: TList<Integer>;
  FoundIndex: Integer;
  IntegerArray: TArray<Integer>;
  IntegerList: TList<Integer>;
  Item: Integer;
  ManagedArray: TArray<string>;
  ManagedList: TList<string>;
  ObjectList: TObjectList<TProbeObject>;
  ProbeObject: TProbeObject;
  Sum: Integer;
begin
  IntegerList := TList<Integer>.Create;
  try
    IntegerList.Add(30);
    IntegerList.AddRange([10, 40]);
    IntegerList.Insert(1, 20);
    IntegerList.InsertRange(4, [50, 60]);
    Check(IntegerList.Count = 6, 'list-count');
    Check(IntegerList.Contains(40) and (IntegerList.IndexOf(40) = 3),
      'list-lookup');
    IntegerList.Delete(5);
    Check(IntegerList.Remove(50) = 4, 'list-remove');
    IntegerList.AddRange([5, 15]);
    IntegerList.Sort(TComparer<Integer>.Construct(CompareInteger));
    Check(IntegerList.BinarySearch(20, FoundIndex) and (FoundIndex = 3),
      'list-binary-search');
    IntegerArray := IntegerList.ToArray;
    Check((Length(IntegerArray) = 6) and (IntegerArray[0] = 5) and
      (IntegerArray[5] = 40), 'list-to-array');
    Sum := 0;
    for Item in IntegerList do begin
      Inc(Sum, Item);
    end;
    Check(Sum = 120, 'list-enumerator');

    CopyList := TList<Integer>.Create(IntegerList);
    try
      Check((CopyList.Count = IntegerList.Count) and
        (CopyList[2] = IntegerList[2]), 'list-copy-constructor');
    finally
      CopyList.Free;
    end;
  finally
    IntegerList.Free;
  end;

  IntegerArray := TArray<Integer>.Create(9, 1, 5, 3);
  TArray.Sort<Integer>(IntegerArray);
  Check(TArray.BinarySearch<Integer>(IntegerArray, 5, FoundIndex) and
    (FoundIndex = 2), 'array-sort-search');

  ManagedList := TList<string>.Create;
  try
    ManagedList.AddRange(['alpha', 'gamma']);
    ManagedList.Insert(1, 'beta');
    ManagedList[2] := 'delta';
    ManagedArray := ManagedList.ToArray;
    Check((Length(ManagedArray) = 3) and (ManagedArray[0] = 'alpha') and
      (ManagedArray[2] = 'delta'), 'list-managed-values');
    ManagedList.DeleteRange(1, 2);
    Check((ManagedList.Count = 1) and (ManagedList[0] = 'alpha'),
      'list-managed-delete-range');
  finally
    ManagedList.Free;
  end;

  ObjectList := TObjectList<TProbeObject>.Create(True);
  try
    ObjectList.Add(TProbeObject.Create);
    ProbeObject := TProbeObject.Create;
    ObjectList.Add(ProbeObject);
    Check(TProbeObject.Alive = 2, 'object-list-add');
    ProbeObject := ObjectList.Extract(ProbeObject);
    Check((ProbeObject <> nil) and (TProbeObject.Alive = 2),
      'object-list-extract');
    ProbeObject.Free;
    ObjectList.Delete(0);
    Check(TProbeObject.Alive = 0, 'object-list-ownership');
  finally
    ObjectList.Free;
  end;
end;

procedure CheckDictionariesQueuesAndStacks;
var
  Dictionary: TDictionary<string, Integer>;
  Key: string;
  KeyCount: Integer;
  NumericDictionary: TDictionary<UInt64, string>;
  ObjectDictionary: TObjectDictionary<string, TProbeObject>;
  Pair: TPair<string, Integer>;
  Stack: TStack<Integer>;
  Value: Integer;
begin
  Dictionary := TDictionary<string, Integer>.Create(16);
  try
    Check(Dictionary.IsEmpty, 'dictionary-empty');
    Dictionary.Add('one', 1);
    Check(not Dictionary.IsEmpty, 'dictionary-not-empty');
    Dictionary.AddOrSetValue('two', 2);
    Dictionary.AddOrSetValue('two', 22);
    Check(Dictionary.TryAdd('three', 3), 'dictionary-try-add');
    Check(not Dictionary.TryAdd('three', 33), 'dictionary-try-add-duplicate');
    Check(Dictionary.TryGetValue('two', Value) and (Value = 22),
      'dictionary-lookup');
    Check(Dictionary.ContainsKey('one') and Dictionary.ContainsValue(3),
      'dictionary-contains');
    Value := 0;
    for Pair in Dictionary do begin
      Inc(Value, Pair.Value);
    end;
    Check(Value = 26, 'dictionary-pair-enumerator');
    KeyCount := 0;
    for Key in Dictionary.Keys do begin
      Inc(KeyCount);
    end;
    Check(KeyCount = 3, 'dictionary-key-enumerator');
    Dictionary.Remove('one');
    Check((Dictionary.Count = 2) and not Dictionary.ContainsKey('one'),
      'dictionary-remove');
    Dictionary.Clear;
    Check(Dictionary.IsEmpty, 'dictionary-empty-after-clear');
  finally
    Dictionary.Free;
  end;

  NumericDictionary := TDictionary<UInt64, string>.Create;
  try
    NumericDictionary.AddOrSetValue(UInt64(1) shl 40, 'large-key');
    Check(NumericDictionary.TryGetValue(UInt64(1) shl 40, Key) and
      (Key = 'large-key'), 'dictionary-uint64-string');
  finally
    NumericDictionary.Free;
  end;

  ObjectDictionary := TObjectDictionary<string, TProbeObject>.Create(
    [doOwnsValues]);
  try
    ObjectDictionary.Add('owned', TProbeObject.Create);
    Check(TProbeObject.Alive = 1, 'object-dictionary-add');
    ObjectDictionary.Remove('owned');
    Check(TProbeObject.Alive = 0, 'object-dictionary-ownership');
  finally
    ObjectDictionary.Free;
  end;

  Stack := TStack<Integer>.Create;
  try
    Stack.Push(10);
    Stack.Push(20);
    Check((Stack.Count = 2) and (Stack.Peek = 20), 'stack-peek');
    Check((Stack.Pop = 20) and (Stack.Pop = 10) and (Stack.Count = 0),
      'stack-pop');
  finally
    Stack.Free;
  end;
end;

procedure CheckStringsAndStreams;
var
  Buffer: array[0..3] of Byte;
  Bytes: TBytes;
  BytesStream: TBytesStream;
  FileName: string;
  FileStream: TFileStream;
  List: TStringList;
  MemoryStream: TProbeMemoryStream;
  ReadBuffer: array[0..3] of Byte;
  StringBuilder: TStringBuilder;
  StringStream: TStringStream;
begin
  List := TStringList.Create;
  try
    List.BeginUpdate;
    try
      List.Add('plain');
      List.Add('name=value');
      List.Insert(1, 'middle');
    finally
      List.EndUpdate;
    end;
    Check((List.Count = 3) and (List[1] = 'middle'), 'string-list-basic');
    Check((List.IndexOfName('name') = 2) and (List.Values['name'] = 'value'),
      'string-list-name-value');
    List.Delimiter := ',';
    List.StrictDelimiter := True;
    List.DelimitedText := 'a,b,c';
    Check((List.Count = 3) and (List[2] = 'c'), 'string-list-delimited');
    List.CaseSensitive := False;
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    List.Add('B');
    List.Add('b');
    Check(List.Count = 3, 'string-list-sorted-duplicates');
  finally
    List.Free;
  end;

  StringBuilder := TStringBuilder.Create(32);
  try
    StringBuilder.Append('alpha');
    StringBuilder.Append('-');
    StringBuilder.Append(42);
    StringBuilder.AppendLine;
    Check(StartsText('alpha-42', StringBuilder.ToString),
      'string-builder-append');
    StringBuilder.Clear;
    StringBuilder.Append('reset');
    Check(StringBuilder.ToString = 'reset', 'string-builder-clear');
  finally
    StringBuilder.Free;
  end;

  Buffer[0] := 1;
  Buffer[1] := 2;
  Buffer[2] := 3;
  Buffer[3] := 4;
  MemoryStream := TProbeMemoryStream.Create;
  try
    MemoryStream.Reserve(4096);
    Check((MemoryStream.Capacity >= 4096) and
      (MemoryStream.CapacityCalls = 1), 'memory-stream-capacity-virtual');
    MemoryStream.WriteBuffer(Buffer, SizeOf(Buffer));
    Check(MemoryStream.Size = 4, 'memory-stream-write');
    MemoryStream.Position := 0;
    MemoryStream.ReadBuffer(ReadBuffer, SizeOf(ReadBuffer));
    Check(CompareMem(@Buffer[0], @ReadBuffer[0], SizeOf(Buffer)),
      'memory-stream-read');
    MemoryStream.SetSize(8);
    Check(MemoryStream.Size = 8, 'memory-stream-set-size-integer');
  finally
    MemoryStream.Free;
  end;

  Bytes := TEncoding.UTF8.GetBytes('hello');
  BytesStream := TBytesStream.Create;
  try
    Check(BytesStream.Size = 0, 'bytes-stream-default-create');
  finally
    BytesStream.Free;
  end;
  BytesStream := TBytesStream.Create(Bytes);
  try
    Check((BytesStream.Size = Length(Bytes)) and
      (TEncoding.UTF8.GetString(BytesStream.Bytes) = 'hello'),
      'bytes-stream');
  finally
    BytesStream.Free;
  end;

  StringStream := TStringStream.Create('', TEncoding.UTF8);
  try
    StringStream.WriteString('unicode-' + #$416);
    StringStream.Position := 0;
    Check(StringStream.ReadString(StringStream.Size) = 'unicode-' + #$416,
      'string-stream-utf8');
  finally
    StringStream.Free;
  end;

  FileName := ChangeFileExt(ParamStr(0), '.tmp');
  DeleteFile(FileName);
  Check(TFile.GetSize(FileName) = -1, 'file-size-missing');
  try
    FileStream := TFileStream.Create(FileName, fmCreate or fmShareDenyWrite);
    try
      FileStream.WriteBuffer(Buffer, SizeOf(Buffer));
    finally
      FileStream.Free;
    end;
    Check(TFile.GetSize(FileName) = SizeOf(Buffer), 'file-size');
    FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      FileStream.ReadBuffer(ReadBuffer, SizeOf(ReadBuffer));
      Check(CompareMem(@Buffer[0], @ReadBuffer[0], SizeOf(Buffer)),
        'file-stream-roundtrip');
    finally
      FileStream.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
  Check(TFile.GetSize(FileName) = -1, 'file-size-after-delete');
end;

procedure CheckUtilitiesAndRtti;
var
  Context: TRttiContext;
  DateTime: TDateTime;
  FloatValue: Double;
  AnsiMatch: PAnsiChar;
  AnsiNeedle,
  AnsiText: AnsiString;
  IntValue: Integer;
  Int64Value: Int64;
  ObjectValue: TObject;
  RttiType: TRttiType;
  Stopwatch: TStopwatch;
  UInt64Value: UInt64;
  Value: TValue;
  WideMatch: PWideChar;
  WideNeedle,
  WideText: UnicodeString;
begin
  If ParamCount < 0 then begin
    SysUtils.DeleteFile('never-created');
    System.SysUtils.DeleteFile('never-created');
  end;
  Check(Format('%s:%d', ['value', 7]) = 'value:7', 'format');
  Check((IntToStr(-42) = '-42') and (UIntToStr(UInt64(42)) = '42') and
    (IntToHex(255, 4) = '00FF'), 'integer-formatting');
  Check(TryStrToInt('-42', IntValue) and (IntValue = -42),
    'try-str-to-int');
  Check(TryStrToInt64('9223372036854775807', Int64Value) and
    (Int64Value = High(Int64)), 'try-str-to-int64');
  Check(TryStrToUInt64('18446744073709551615', UInt64Value) and
    (UInt64Value = High(UInt64)), 'try-str-to-uint64');
  Check(TryStrToFloat('12.5', FloatValue, TFormatSettings.Invariant) and
    (Abs(FloatValue - 12.5) < 0.000001), 'try-str-to-float');
  Check(SameText('Moon', 'moon') and StartsText('Moon', 'MoonCompiler') and
    EndsText('Compiler', 'MoonCompiler'), 'string-comparison');

  AnsiText := 'abCDef';
  AnsiNeedle := 'cd';
  AnsiMatch := TextPos(PAnsiChar(AnsiText), PAnsiChar(AnsiNeedle));
  Check((AnsiMatch <> nil) and ((AnsiMatch - PAnsiChar(AnsiText)) = 2),
    'text-pos-ansi');
  Check(TextPos(PAnsiChar(AnsiText), PAnsiChar('xy')) = nil,
    'text-pos-ansi-missing');
  WideText := 'abCDef';
  WideNeedle := 'cd';
  WideMatch := TextPos(PWideChar(WideText), PWideChar(WideNeedle));
  Check((WideMatch <> nil) and ((WideMatch - PWideChar(WideText)) = 2),
    'text-pos-wide');
  Check(TextPos(PWideChar(WideText), PWideChar('xy')) = nil,
    'text-pos-wide-missing');

  Stopwatch := TStopwatch.StartNew;
  TThread.Sleep(1);
  Stopwatch.Stop;
  Check((TStopwatch.Frequency > 0) and (Stopwatch.ElapsedTicks >= 0),
    'stopwatch');

  DateTime := UnixToDateTime(1700000000, False);
  Check(DateTimeToUnix(DateTime, False) = 1700000000, 'date-time-unix');
  Check(MilliSecondsBetween(IncMilliSecond(DateTime, 125), DateTime) = 125,
    'date-time-milliseconds');

  Check(GetEnumName(TypeInfo(TProbeEnum), Ord(peTwo)) = 'peTwo',
    'typinfo-enum-name');
  Check(GetEnumValue(TypeInfo(TProbeEnum), 'peOne') = Ord(peOne),
    'typinfo-enum-value');

  Context := TRttiContext.Create;
  try
    RttiType := Context.GetType(TypeInfo(TProbeEnum));
    Check((RttiType <> nil) and (RttiType.TypeKind = tkEnumeration),
      'rtti-get-type');
    Value := TValue.From<Integer>(77);
    Check((Value.Kind = tkInteger) and (Value.AsInteger = 77),
      'rtti-value-integer');
  finally
    Context.Free;
  end;

  ObjectValue := TProbeObject.Create;
  Check(TProbeObject.Alive = 1, 'free-and-nil-before');
  FreeAndNil(ObjectValue);
  Check((ObjectValue = nil) and (TProbeObject.Alive = 0),
    'free-and-nil-after');
end;

begin
  CheckThreadsAndSync;
  CheckListsAndArrays;
  CheckDictionariesQueuesAndStacks;
  CheckStringsAndStreams;
  CheckUtilitiesAndRtti;
  WriteLn('RTL_API_SURFACE_OK');
end.
