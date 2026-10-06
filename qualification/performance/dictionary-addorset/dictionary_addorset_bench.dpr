program dictionary_addorset_bench;

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  SysUtils,
  Generics.Defaults,
  Generics.Collections,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas';

const
  SampleCount = 11;

type
  TConstantIntegerComparer = class(TInterfacedObject,
    IEqualityComparer<Integer>)
  public
    function Equals(const ALeft, ARight: Integer): Boolean;
    function GetHashCode(const AValue: Integer): Integer;
  end;

function TConstantIntegerComparer.Equals(
  const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft = ARight;
end;

function TConstantIntegerComparer.GetHashCode(
  const AValue: Integer): Integer;
begin
  Result := 1;
end;

function Minimum(A, B: Integer): Integer; inline;
begin
  If A < B then
    Result := A
  else
    Result := B;
end;

var
  OperationName, HashName, ScenarioName: string;
  RequestedCapacity, FillPercent, FillCount, OperationCount: Integer;
  Dictionary: TDictionary<Integer, Integer>;
  Comparer: IEqualityComparer<Integer>;

procedure PrepareDictionary;
var
  Key: Integer;
begin
  If HashName = 'collision' then
    Comparer := TConstantIntegerComparer.Create
  else
    Comparer := nil;
  If Comparer <> nil then
    Dictionary := TDictionary<Integer, Integer>.Create(Comparer)
  else
    Dictionary := TDictionary<Integer, Integer>.Create;
  Dictionary.Capacity := RequestedCapacity;
  FillCount := RequestedCapacity * FillPercent div 100;
  for Key := 0 to FillCount - 1 do
    Dictionary.Add(Key, Key xor $55AA);
end;

function ExecuteBatch: UInt64;
var
  Index, Key, NewIndex, Value: Integer;
begin
  Result := 0;
  If OperationName = 'update' then
    for Index := 0 to OperationCount - 1 do
    begin
      Key := Index mod FillCount;
      Dictionary.AddOrSetValue(Key, Index);
    end
  else If OperationName = 'insert' then
    for Index := 0 to OperationCount - 1 do
      Dictionary.AddOrSetValue(FillCount + Index, Index)
  else If OperationName = 'mixed' then
  begin
    NewIndex := 0;
    for Index := 0 to OperationCount - 1 do
      If (Index and 1) = 0 then
      begin
        Key := (Index shr 1) mod FillCount;
        Dictionary.AddOrSetValue(Key, Index);
      end
      else
      begin
        Dictionary.AddOrSetValue(FillCount + NewIndex, Index);
        Inc(NewIndex);
      end;
  end
  else
    raise EArgumentException.Create('unknown operation');
  Dictionary.TryGetValue(0, Value);
  Result := UInt64(Cardinal(Value)) xor UInt64(Dictionary.Count);
end;

procedure SelectOperationCount;
var
  Available: Integer;
begin
  If OperationName = 'update' then
  begin
    If HashName = 'collision' then
      OperationCount := 262144 * 64 div RequestedCapacity
    else
      OperationCount := 1048576;
  end
  else
  begin
    Available := RequestedCapacity - FillCount;
    If OperationName = 'insert' then
      OperationCount := Minimum(262144, Available)
    else
      OperationCount := Minimum(262144, Available * 2);
  end;
  If OperationCount < 1024 then
    OperationCount := Minimum(1024, RequestedCapacity - FillCount);
  If OperationCount <= 0 then
    raise EArgumentException.Create('scenario has no available operations');
end;

procedure Warmup;
begin
  PrepareDictionary;
  try
    ExecuteBatch;
  finally
    Dictionary.Free;
    Dictionary := nil;
    Comparer := nil;
  end;
end;

procedure RunSample(Sample: Integer);
var
  Started: TPerfStamp;
  Delta: TPerfDelta;
  ProcessStarted, CyclesStarted, ProcessNs, Cycles, Digest: UInt64;
  HeapBefore, HeapAfter: THeapStatus;
  ObjectAddress: NativeUInt;
begin
  PrepareDictionary;
  try
    ObjectAddress := NativeUInt(Pointer(Dictionary));
    HeapBefore := System.GetHeapStatus;
    ProcessStarted := PulseReadProcessCpuNs;
    CyclesStarted := PulseReadThreadCycles;
    Started := BeginPerfStamp;
    Digest := ExecuteBatch;
    Delta := EndPerfStamp(Started);
    Cycles := PulseReadThreadCycles - CyclesStarted;
    ProcessNs := PulseReadProcessCpuNs - ProcessStarted;
    HeapAfter := System.GetHeapStatus;
    WriteLn(
      'DICT_SAMPLE scenario=', ScenarioName,
      ' sample=', Sample,
      ' operations=', OperationCount,
      ' wall_ns=', Delta.WallNs,
      ' thread_cpu_ns=', Delta.ThreadCpuNs,
      ' process_cpu_ns=', ProcessNs,
      ' thread_cycles=', Cycles,
      ' tsc_ticks=', Delta.TscTicks,
      ' heap_delta=', Int64(HeapAfter.TotalAllocated) -
        Int64(HeapBefore.TotalAllocated),
      ' object_mod4096=', ObjectAddress and 4095,
      ' digest=', IntToHex(Digest, 16));
  finally
    Dictionary.Free;
    Dictionary := nil;
    Comparer := nil;
  end;
end;

var
  Sample, AffinityCpu: Integer;
begin
  If ParamCount <> 4 then
  begin
    WriteLn('usage: dictionary_addorset_bench update|insert|mixed ',
      'capacity fill-percent default|collision');
    Halt(2);
  end;
  OperationName := LowerCase(ParamStr(1));
  RequestedCapacity := StrToInt(ParamStr(2));
  FillPercent := StrToInt(ParamStr(3));
  HashName := LowerCase(ParamStr(4));
  If (RequestedCapacity <= 0) or (FillPercent <= 0) or
     (FillPercent >= 100) then
    raise EArgumentException.Create('bad capacity/fill');
  If (HashName <> 'default') and (HashName <> 'collision') then
    raise EArgumentException.Create('bad hash mode');
  ScenarioName := OperationName + '-c' + IntToStr(RequestedCapacity) +
    '-f' + IntToStr(FillPercent) + '-' + HashName;
  SelectOperationCount;
  InitializePerfClock;
  AffinityCpu := PinBenchmarkThread;
  Warmup;
  WriteLn('DICT_BEGIN scenario=', ScenarioName,
    ' operations=', OperationCount, ' affinity_cpu=', AffinityCpu);
  for Sample := 1 to SampleCount do
    RunSample(Sample);
  WriteLn('DICT_END scenario=', ScenarioName, ' status=PASS');
end.
