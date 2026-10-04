program dict_bench;

{ Flat-dictionary stand: the AddOrSetValue black-box benchmark extended with
  key kinds and lookups.  Same output contract as dictionary_addorset_bench
  (DICT_SAMPLE lines with thread_cycles and operations), so abrun.py works.

    dict_bench <op> <capacity> <fill-percent> <kind> <hash>
      op:   update | insert | mixed | lookup | miss
      kind: int | i64 | str | obj
      hash: default | collision        (collision: Integer keys only)
}

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$ifdef FPC}
  {$I pulse_placement_uses.inc}
  {$endif}
  SysUtils,
  Generics.Defaults,
  Generics.Collections,
  perf_clock in 'perf_clock.pas',
  pulse_process_metrics in 'pulse_process_metrics.pas';

{$ifdef FPC}
{$I pulse_program_prefix.inc}
{$endif}

const
  SampleCount = 11;

type
  TConstantIntegerComparer = class(TInterfacedObject, IEqualityComparer<Integer>)
  public
    function Equals(const ALeft, ARight: Integer): Boolean;
    function GetHashCode(const AValue: Integer): {$ifdef FPC}UInt32{$else}Integer{$endif};
  end;

function TConstantIntegerComparer.Equals(const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft = ARight;
end;

function TConstantIntegerComparer.GetHashCode(const AValue: Integer): {$ifdef FPC}UInt32{$else}Integer{$endif};
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
  OperationName, HashName, KindName, ScenarioName: string;
  RequestedCapacity, FillPercent, FillCount, OperationCount: Integer;
  DictInt: TDictionary<Integer, Integer>;
  DictI64: TDictionary<Int64, Integer>;
  DictStr: TDictionary<string, TObject>;
  DictObj: TDictionary<TObject, Integer>;
  Comparer: IEqualityComparer<Integer>;
  StrKeys: TArray<string>;          // FillCount + OperationCount keys
  ObjKeys: TArray<TObject>;
  KeyCount: Integer;

procedure PrepareKeys;
var
  i: Integer;
begin
  KeyCount := FillCount + Minimum(OperationCount, RequestedCapacity);
  If KindName = 'str' then
  begin
    SetLength(StrKeys, KeyCount);
    for i := 0 to KeyCount - 1 do
      StrKeys[i] := 'K' + IntToStr(i * 7919) + 'USDT';   // 6..12 chars, symbol-like
  end
  else If KindName = 'obj' then
  begin
    SetLength(ObjKeys, KeyCount);
    for i := 0 to KeyCount - 1 do
      ObjKeys[i] := TObject.Create;
  end;
end;

procedure ReleaseKeys;
var
  i: Integer;
begin
  for i := 0 to High(ObjKeys) do
    ObjKeys[i].Free;
  ObjKeys := nil;
  StrKeys := nil;
end;

procedure PrepareDictionary;
var
  Key: Integer;
begin
  If HashName = 'collision' then
    Comparer := TConstantIntegerComparer.Create
  else
    Comparer := nil;
  If KindName = 'int' then
  begin
    If Comparer <> nil then
      DictInt := TDictionary<Integer, Integer>.Create(Comparer)
    else
      DictInt := TDictionary<Integer, Integer>.Create;
    DictInt.Capacity := RequestedCapacity;
    for Key := 0 to FillCount - 1 do
      DictInt.Add(Key, Key xor $55AA);
  end
  else If KindName = 'i64' then
  begin
    DictI64 := TDictionary<Int64, Integer>.Create;
    DictI64.Capacity := RequestedCapacity;
    for Key := 0 to FillCount - 1 do
      DictI64.Add(Int64(Key) * 1000003, Key xor $55AA);
  end
  else If KindName = 'str' then
  begin
    DictStr := TDictionary<string, TObject>.Create;
    DictStr.Capacity := RequestedCapacity;
    for Key := 0 to FillCount - 1 do
      DictStr.Add(StrKeys[Key], TObject(NativeUInt(Key + 1)));
  end
  else
  begin
    DictObj := TDictionary<TObject, Integer>.Create;
    DictObj.Capacity := RequestedCapacity;
    for Key := 0 to FillCount - 1 do
      DictObj.Add(ObjKeys[Key], Key xor $55AA);
  end;
end;

procedure FreeDictionary;
begin
  FreeAndNil(DictInt);
  FreeAndNil(DictI64);
  FreeAndNil(DictStr);
  FreeAndNil(DictObj);
  Comparer := nil;
end;

function ExecuteInt: UInt64;
var
  Index, Key, NewIndex, Value: Integer;
begin
  Result := 0;
  If OperationName = 'update' then
    for Index := 0 to OperationCount - 1 do
      DictInt.AddOrSetValue(Index mod FillCount, Index)
  else If OperationName = 'insert' then
    for Index := 0 to OperationCount - 1 do
      DictInt.AddOrSetValue(FillCount + Index, Index)
  else If OperationName = 'mixed' then
  begin
    NewIndex := 0;
    for Index := 0 to OperationCount - 1 do
      If (Index and 1) = 0 then
        DictInt.AddOrSetValue((Index shr 1) mod FillCount, Index)
      else
      begin
        DictInt.AddOrSetValue(FillCount + NewIndex, Index);
        Inc(NewIndex);
      end;
  end
  else If OperationName = 'lookup' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictInt.TryGetValue(Index mod FillCount, Value) then
        Result := Result + Cardinal(Value);
    end
  else If OperationName = 'miss' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictInt.TryGetValue(FillCount + (Index mod FillCount), Value) then
        Result := Result + Cardinal(Value);
    end
  else
    raise EArgumentException.Create('unknown operation');
  DictInt.TryGetValue(0, Value);
  Result := Result xor UInt64(Cardinal(Value)) xor UInt64(DictInt.Count);
end;

function ExecuteI64: UInt64;
var
  Index, NewIndex, Value: Integer;
  Key: Int64;
begin
  Result := 0;
  If OperationName = 'update' then
    for Index := 0 to OperationCount - 1 do
      DictI64.AddOrSetValue(Int64(Index mod FillCount) * 1000003, Index)
  else If OperationName = 'insert' then
    for Index := 0 to OperationCount - 1 do
      DictI64.AddOrSetValue(Int64(FillCount + Index) * 1000003, Index)
  else If OperationName = 'mixed' then
  begin
    NewIndex := 0;
    for Index := 0 to OperationCount - 1 do
      If (Index and 1) = 0 then
        DictI64.AddOrSetValue(Int64((Index shr 1) mod FillCount) * 1000003, Index)
      else
      begin
        DictI64.AddOrSetValue(Int64(FillCount + NewIndex) * 1000003, Index);
        Inc(NewIndex);
      end;
  end
  else If OperationName = 'lookup' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictI64.TryGetValue(Int64(Index mod FillCount) * 1000003, Value) then
        Result := Result + Cardinal(Value);
    end
  else If OperationName = 'miss' then
    for Index := 0 to OperationCount - 1 do
    begin
      Key := Int64(FillCount + (Index mod FillCount)) * 1000003;
      If DictI64.TryGetValue(Key, Value) then
        Result := Result + Cardinal(Value);
    end
  else
    raise EArgumentException.Create('unknown operation');
  DictI64.TryGetValue(0, Value);
  Result := Result xor UInt64(Cardinal(Value)) xor UInt64(DictI64.Count);
end;

function ExecuteStr: UInt64;
var
  Index, NewIndex: Integer;
  Value: TObject;
begin
  Result := 0;
  If OperationName = 'update' then
    for Index := 0 to OperationCount - 1 do
      DictStr.AddOrSetValue(StrKeys[Index mod FillCount], TObject(NativeUInt(Index)))
  else If OperationName = 'insert' then
    for Index := 0 to OperationCount - 1 do
      DictStr.AddOrSetValue(StrKeys[FillCount + Index], TObject(NativeUInt(Index)))
  else If OperationName = 'mixed' then
  begin
    NewIndex := 0;
    for Index := 0 to OperationCount - 1 do
      If (Index and 1) = 0 then
        DictStr.AddOrSetValue(StrKeys[(Index shr 1) mod FillCount], TObject(NativeUInt(Index)))
      else
      begin
        DictStr.AddOrSetValue(StrKeys[FillCount + NewIndex], TObject(NativeUInt(Index)));
        Inc(NewIndex);
      end;
  end
  else If OperationName = 'lookup' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictStr.TryGetValue(StrKeys[Index mod FillCount], Value) then
        Result := Result + NativeUInt(Value);
    end
  else If OperationName = 'miss' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictStr.TryGetValue(StrKeys[FillCount + (Index mod FillCount)], Value) then
        Result := Result + NativeUInt(Value);
    end
  else
    raise EArgumentException.Create('unknown operation');
  DictStr.TryGetValue(StrKeys[0], Value);
  Result := Result xor UInt64(NativeUInt(Value)) xor UInt64(DictStr.Count);
end;

function ExecuteObj: UInt64;
var
  Index, NewIndex, Value: Integer;
begin
  Result := 0;
  If OperationName = 'update' then
    for Index := 0 to OperationCount - 1 do
      DictObj.AddOrSetValue(ObjKeys[Index mod FillCount], Index)
  else If OperationName = 'insert' then
    for Index := 0 to OperationCount - 1 do
      DictObj.AddOrSetValue(ObjKeys[FillCount + Index], Index)
  else If OperationName = 'mixed' then
  begin
    NewIndex := 0;
    for Index := 0 to OperationCount - 1 do
      If (Index and 1) = 0 then
        DictObj.AddOrSetValue(ObjKeys[(Index shr 1) mod FillCount], Index)
      else
      begin
        DictObj.AddOrSetValue(ObjKeys[FillCount + NewIndex], Index);
        Inc(NewIndex);
      end;
  end
  else If OperationName = 'lookup' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictObj.TryGetValue(ObjKeys[Index mod FillCount], Value) then
        Result := Result + Cardinal(Value);
    end
  else If OperationName = 'miss' then
    for Index := 0 to OperationCount - 1 do
    begin
      If DictObj.TryGetValue(ObjKeys[FillCount + (Index mod FillCount)], Value) then
        Result := Result + Cardinal(Value);
    end
  else
    raise EArgumentException.Create('unknown operation');
  DictObj.TryGetValue(ObjKeys[0], Value);
  Result := Result xor UInt64(Cardinal(Value)) xor UInt64(DictObj.Count);
end;

function ExecuteBatch: UInt64;
begin
  If KindName = 'int' then
    Result := ExecuteInt
  else If KindName = 'i64' then
    Result := ExecuteI64
  else If KindName = 'str' then
    Result := ExecuteStr
  else
    Result := ExecuteObj;
end;

procedure SelectOperationCount;
var
  Available: Integer;
begin
  If (OperationName = 'update') or (OperationName = 'lookup') or (OperationName = 'miss') then
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
    FreeDictionary;
  end;
end;

procedure RunSample(Sample: Integer);
var
  Started: TPerfStamp;
  Delta: TPerfDelta;
  ProcessStarted, CyclesStarted, ProcessNs, Cycles, Digest: UInt64;
  HeapBefore, HeapAfter: THeapStatus;
begin
  PrepareDictionary;
  try
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
      ' digest=', IntToHex(Digest, 16));
  finally
    FreeDictionary;
  end;
end;

var
  Sample, AffinityCpu: Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  If ParamCount <> 5 then
  begin
    WriteLn('usage: dict_bench update|insert|mixed|lookup|miss capacity fill-percent int|i64|str|obj default|collision');
    Halt(2);
  end;
  OperationName := LowerCase(ParamStr(1));
  RequestedCapacity := StrToInt(ParamStr(2));
  FillPercent := StrToInt(ParamStr(3));
  KindName := LowerCase(ParamStr(4));
  HashName := LowerCase(ParamStr(5));
  If (RequestedCapacity <= 0) or (FillPercent <= 0) or (FillPercent >= 100) then
    raise EArgumentException.Create('bad capacity/fill');
  If (HashName <> 'default') and (HashName <> 'collision') then
    raise EArgumentException.Create('bad hash mode');
  If (HashName = 'collision') and (KindName <> 'int') then
    raise EArgumentException.Create('collision hash is for int keys only');
  If (KindName <> 'int') and (KindName <> 'i64') and (KindName <> 'str') and (KindName <> 'obj') then
    raise EArgumentException.Create('bad key kind');
  ScenarioName := OperationName + '-c' + IntToStr(RequestedCapacity) +
    '-f' + IntToStr(FillPercent) + '-' + KindName + '-' + HashName;
  FillCount := RequestedCapacity * FillPercent div 100;
  SelectOperationCount;
  PrepareKeys;
  InitializePerfClock;
  AffinityCpu := PinBenchmarkThread;
  Warmup;
  WriteLn('DICT_BEGIN scenario=', ScenarioName,
    ' operations=', OperationCount, ' affinity_cpu=', AffinityCpu);
  for Sample := 1 to SampleCount do
    RunSample(Sample);
  ReleaseKeys;
  WriteLn('DICT_END scenario=', ScenarioName, ' status=PASS');
end.
