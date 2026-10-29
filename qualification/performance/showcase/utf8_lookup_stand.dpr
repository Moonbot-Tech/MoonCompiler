program utf8_lookup_stand;

{$mode delphiunicode}
{$H+}
{$codepage utf8}

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes, Diagnostics, Generics.Collections,
  {$ifdef MSWINDOWS}Windows,{$endif}
  mormot.core.base, Utf8Lookup, Utf8LookupAstra;

type
  TLookupClass = class of TUtf8Lookup;
  TQuery = record
    Buffer, Plain: RawUtf8;
    View: TUtf8KeyView;
    Expected: UInt64;
  end;

const
  Implementations: array[0..4] of TLookupClass =
    (TUtf8ViewDictionary, TUtf8ExternalTable, TUtf8ArenaTable, TUtf8InlineTable, TUtf8HybridTable);
  Names: array[0..5] of string = ('generic-view', 'external', 'arena', 'inline16', 'hybrid32', 'generic-owned');

var
  OriginalMM, MeterMM: TMemoryManager;
  Metering: Boolean;
  Allocations, Frees, Requested, LiveBytes, PeakBytes: Int64;

procedure RecordAllocation(P: Pointer; N: PtrUInt);
begin
  If Metering and (P <> nil) then begin
    Inc(Allocations);
    Inc(Requested, N);
    Inc(LiveBytes, OriginalMM.MemSize(P));
    If LiveBytes > PeakBytes then PeakBytes := LiveBytes;
  end;
end;

procedure RecordFree(P: Pointer);
begin
  If Metering and (P <> nil) then begin
    Inc(Frees);
    Dec(LiveBytes, OriginalMM.MemSize(P));
  end;
end;

function MeterGet(N: PtrUInt): Pointer;
begin
  Result := OriginalMM.GetMem(N);
  RecordAllocation(Result, N);
end;

function MeterAlloc(N: PtrUInt): Pointer;
begin
  Result := OriginalMM.AllocMem(N);
  RecordAllocation(Result, N);
end;

function MeterFree(P: Pointer): PtrUInt;
begin
  RecordFree(P);
  Result := OriginalMM.FreeMem(P);
end;

function MeterFreeSize(P: Pointer; N: PtrUInt): PtrUInt;
begin
  RecordFree(P);
  Result := OriginalMM.FreeMemSize(P, N);
end;

function MeterRealloc(var P: Pointer; N: PtrUInt): Pointer;
begin
  RecordFree(P);
  Result := OriginalMM.ReAllocMem(P, N);
  RecordAllocation(Result, N);
end;

procedure StartMeter;
begin
  Allocations := 0;
  Frees := 0;
  Requested := 0;
  LiveBytes := 0;
  PeakBytes := 0;
  Metering := True;
end;

procedure Require(OK: Boolean; const Reason: string);
begin
  If not OK then raise Exception.Create(Reason);
end;

function KeyFor(Index, Profile: Integer): RawUtf8;
begin
  // Fixed-width unique suffix; profiles change storage, not the lookup algorithm.
  Result := RawUtf8(Format('SYM%.12d', [Index]));
  case Profile of
    1: Result := RawUtf8('рынок😀') + Result;
    2: Result := RawUtf8(StringOfChar('p', Index mod 114)) + Result;
  end;
end;

procedure CheckContracts(C: TLookupClass);
var
  Table: TUtf8Lookup;
  Keys: TArray<RawUtf8>;
  Source, Query: RawUtf8;
  Value: UInt64;
  DuplicateRaised, CapacityRaised: Boolean;
begin
  SetLength(Keys, 270);
  Keys[0] := '';
  Keys[1] := #0;
  Keys[2] := RawUtf8('Ключ😀');
  Keys[3] := 'a'#0'b';
  for var I := 4 to High(Keys) do
    Keys[I] := RawUtf8(StringOfChar('x', I - 4)) + RawUtf8(IntToStr(I));
  Table := C.Create(Length(Keys));
  for var I := 0 to High(Keys) do begin
    Source := Copy(Keys[I], 1, MaxInt);
    Table.Add(Pointer(Source), Length(Source), UInt64(I) + 1);
    // The table must own a copy. Mutating/destroying the source cannot alter it.
    If Source <> '' then Source[1] := '?';
    Source := '';
  end;
  for var I := High(Keys) downto 0 do begin
    Query := '!' + Keys[I] + '!poison';
    Require(Table.TryGetValue(PAnsiChar(Query) + 1, Length(Keys[I]), Value), 'Subview miss');
    Require(Value = UInt64(I) + 1, 'Wrong subview value');
  end;
  Require(Table.TryGetValue(nil, 0, Value) and (Value = 1), 'Empty key');
  Query := 'absent';
  Require(not Table.TryGetValue(Pointer(Query), Length(Query), Value), 'False hit');
  CapacityRaised := False;
  try
    Table.Add(Pointer(Query), Length(Query), 999);
  except
    on E: EArgumentException do CapacityRaised := True;
  end;
  Require(CapacityRaised and (Table.Count = Length(Keys)), 'Capacity contract');
  Table.Free;

  Table := C.Create(2);
  Source := 'dup';
  Table.Add(Pointer(Source), Length(Source), 7);
  DuplicateRaised := False;
  try
    Table.Add(Pointer(Source), Length(Source), 8);
  except
    on E: EArgumentException do DuplicateRaised := True;
    on E: EListError do DuplicateRaised := True;
  end;
  Require(DuplicateRaised and (Table.Count = 1), 'Duplicate contract');
  Require(Table.TryGetValue(Pointer(Source), Length(Source), Value) and (Value = 7), 'Duplicate overwrote');
  Source := 'next';
  Table.Add(Pointer(Source), Length(Source), 9);
  Require(Table.TryGetValue(Pointer(Source), Length(Source), Value) and (Value = 9), 'Insert after duplicate');
  Table.Free;

  // Force an initial-bucket chain to cross slot zero in the 128-slot table.
  Table := C.Create(64);
  var Candidate := 0;
  SetLength(Keys, 40);
  for var I := 0 to High(Keys) do begin
    repeat
      Keys[I] := KeyFor(Candidate, 0);
      Inc(Candidate);
    until Utf8KeyHash(Pointer(Keys[I]), Length(Keys[I])) and 127 = 127;
    Table.Add(Pointer(Keys[I]), Length(Keys[I]), UInt64(I) + 1);
  end;
  for var I := 0 to High(Keys) do
    Require(Table.TryGetValue(Pointer(Keys[I]), Length(Keys[I]), Value) and (Value = UInt64(I) + 1), 'Collision chain');
  Table.Free;
end;

{$ifdef UNIX}
type TTimespec = record Seconds, Nanoseconds: Int64; end;
function clock_gettime(Id: LongInt; var Time: TTimespec): LongInt; cdecl; external 'c';
function mmap(P: Pointer; Size: PtrUInt; Protection, Flags, FD: LongInt; Offset: Int64): Pointer; cdecl; external 'c';
function mprotect(P: Pointer; Size: PtrUInt; Protection: LongInt): LongInt; cdecl; external 'c';
function munmap(P: Pointer; Size: PtrUInt): LongInt; cdecl; external 'c';
function getpagesize: LongInt; cdecl; external 'c';
{$endif}

function CpuNs: Int64;
{$ifdef UNIX}
var Time: TTimespec;
begin
  Require(clock_gettime(2, Time) = 0, 'Process CPU clock');
  Result := Time.Seconds * 1000000000 + Time.Nanoseconds;
end;
{$else}
var Creation, Finished, Kernel, UserTime: TFileTime;
begin
  Require(GetProcessTimes(GetCurrentProcess, Creation, Finished, Kernel, UserTime), 'Process CPU clock');
  Result := ((Int64(Kernel.dwHighDateTime) shl 32) + Kernel.dwLowDateTime +
    (Int64(UserTime.dwHighDateTime) shl 32) + UserTime.dwLowDateTime) * 100;
end;
{$endif}

procedure CheckGuardPage(C: TLookupClass);
var
  Page: PtrUInt;
  Region, P: PByte;
  Table: TUtf8Lookup;
  Value: UInt64;
  {$ifdef MSWINDOWS}Info: TSystemInfo; OldProtection: DWORD;{$endif}
begin
  {$ifdef MSWINDOWS}
  GetSystemInfo(Info);
  Page := Info.dwPageSize;
  Region := VirtualAlloc(nil, Page * 2, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  Require(Region <> nil, 'VirtualAlloc');
  Require(VirtualProtect(Region + Page, Page, PAGE_NOACCESS, OldProtection), 'VirtualProtect');
  {$else}
  Page := getpagesize;
  Region := mmap(nil, Page * 2, 3, $22, -1, 0);
  Require(PtrUInt(Region) <> High(PtrUInt), 'mmap');
  Require(mprotect(Region + Page, Page, 0) = 0, 'mprotect');
  {$endif}
  // Every tested view ends exactly at the inaccessible page, no terminator.
  for var N := 0 to 96 do begin
    Table := C.Create(1);
    P := Region + Page - N;
    for var I := 0 to N - 1 do P[I] := Byte(I + 1);
    Table.Add(P, N, 123);
    Require(Table.TryGetValue(P, N, Value) and (Value = 123), 'Guard-page hit');
    If N <> 0 then begin
      P[N - 1] := 0;
      Require(not Table.TryGetValue(P, N, Value), 'Guard-page miss');
    end;
    Table.Free;
  end;
  {$ifdef MSWINDOWS}
  Require(VirtualFree(Region, 0, MEM_RELEASE), 'VirtualFree');
  {$else}
  Require(munmap(Region, Page * 2) = 0, 'munmap');
  {$endif}
end;

procedure Measure(Kind, Profile, Count, Passes: Integer);
var
  Keys: TArray<RawUtf8>;
  Queries: TArray<TQuery>;
  Table: TUtf8Lookup;
  Owned: TDictionary<RawUtf8, UInt64>;
  Value, Checksum, Expected: UInt64;
  Started, BuildTicks, LookupTicks, CpuStarted, BuildCpu, LookupCpu: Int64;
  BuildAllocations, BuildRequested, BuildLive, BuildPeak, LookupAllocations, LookupFrees: Int64;
  State: UInt32;
  Index: Integer;
  procedure BuildTable;
  var Key: RawUtf8;
  begin
    If Kind = 5 then begin
      Owned := TDictionary<RawUtf8, UInt64>.Create(Count);
      for var I := 0 to High(Keys) do begin
        // Count the actual owned key storage, not references to the fixture.
        SetString(Key, PAnsiChar(Keys[I]), Length(Keys[I]));
        Owned.Add(Key, UInt64(I) * 17 + 3);
      end;
    end else begin
      Table := Implementations[Kind].Create(Count);
      for var I := 0 to High(Keys) do Table.Add(Pointer(Keys[I]), Length(Keys[I]), UInt64(I) * 17 + 3);
    end;
  end;
begin
  Table := nil;
  Owned := nil;
  SetLength(Keys, Count);
  for var I := 0 to High(Keys) do Keys[I] := KeyFor(I, Profile);
  SetLength(Queries, 200000);
  State := 123456789;
  Expected := 0;
  for var I := 0 to High(Queries) do begin
    State := State * 1664525 + 1013904223;
    Index := State mod (Count + Count div 9);
    // Independent storage, surrounded by bytes that are not part of the key.
    Queries[I].Plain := KeyFor(Index, Profile);
    Queries[I].Buffer := '!' + Queries[I].Plain + '!';
    Queries[I].View := TUtf8KeyView.OfBytes(PAnsiChar(Queries[I].Buffer) + 1, Length(Queries[I].Buffer) - 2);
    If Index < Count then Queries[I].Expected := UInt64(Index) * 17 + 3;
    Inc(Expected, Queries[I].Expected);
  end;

  // Warm process-wide comparer initialization before measuring table ownership.
  If Kind = 5 then begin
    Owned := TDictionary<RawUtf8, UInt64>.Create(1);
    Owned.Add('', 1);
    FreeAndNil(Owned);
  end else begin
    Table := Implementations[Kind].Create(1);
    Table.Add(nil, 0, 1);
    FreeAndNil(Table);
  end;
  StartMeter;
  BuildTable;
  BuildAllocations := Allocations;
  BuildRequested := Requested;
  BuildLive := LiveBytes;
  BuildPeak := PeakBytes;
  var BeforeFrees := Frees;
  for var I := 0 to High(Queries) do begin
    var Found: Boolean;
    If Kind = 5 then Found := Owned.TryGetValue(Queries[I].Plain, Value)
    else Found := Table.TryGetValue(Queries[I].View.Text, Queries[I].View.Len, Value);
    Require(Found = (Queries[I].Expected <> 0), 'Lookup presence');
    If Found then Require(Value = Queries[I].Expected, 'Lookup value');
  end;
  LookupAllocations := Allocations - BuildAllocations;
  LookupFrees := Frees - BeforeFrees;
  FreeAndNil(Table);
  FreeAndNil(Owned);
  Metering := False;
  Require(LiveBytes = 0, 'Table allocations not released');
  Require((LookupAllocations = 0) and (LookupFrees = 0), 'Lookup allocated or freed');

  // Timings use the original allocator; metering is not on the measured path.
  SetMemoryManager(OriginalMM);
  CpuStarted := CpuNs;
  Started := TStopwatch.GetTimeStamp;
  BuildTable;
  BuildTicks := TStopwatch.GetTimeStamp - Started;
  BuildCpu := CpuNs - CpuStarted;
  Checksum := 0;
  CpuStarted := CpuNs;
  Started := TStopwatch.GetTimeStamp;
  If Kind = 5 then begin
    for var Pass := 1 to Passes do
      for var I := 0 to High(Queries) do
        If Owned.TryGetValue(Queries[I].Plain, Value) then Inc(Checksum, Value);
  end else begin
    for var Pass := 1 to Passes do
      for var I := 0 to High(Queries) do
        If Table.TryGetValue(Queries[I].View.Text, Queries[I].View.Len, Value) then Inc(Checksum, Value);
  end;
  LookupTicks := TStopwatch.GetTimeStamp - Started;
  LookupCpu := CpuNs - CpuStarted;
  Require(Checksum = Expected * UInt64(Passes), 'Timed checksum');
  Writeln('{"implementation":"', Names[Kind], '","profile":', Profile, ',"entries":', Count,
    ',"queries":', Length(Queries) * Passes, ',"lookup_ns":', LookupTicks * 1000000000 div TStopwatch.Frequency,
    ',"build_ns":', BuildTicks * 1000000000 div TStopwatch.Frequency,
    ',"lookup_cpu_ns":', LookupCpu, ',"build_cpu_ns":', BuildCpu,
    ',"build_allocations":', BuildAllocations, ',"build_requested_bytes":', BuildRequested,
    ',"live_bytes":', BuildLive, ',"peak_live_bytes":', BuildPeak,
    ',"lookup_allocations":', LookupAllocations, ',"lookup_frees":', LookupFrees,
    ',"checksum":', Checksum, '}');
  Table.Free;
  Owned.Free;
  SetMemoryManager(MeterMM);
end;

begin
  GetMemoryManager(OriginalMM);
  MeterMM := OriginalMM;
  MeterMM.GetMem := @MeterGet;
  MeterMM.AllocMem := @MeterAlloc;
  MeterMM.FreeMem := @MeterFree;
  MeterMM.FreeMemSize := @MeterFreeSize;
  MeterMM.ReAllocMem := @MeterRealloc;
  SetMemoryManager(MeterMM);
  If ParamCount = 0 then begin
    for var C in Implementations do begin
      CheckContracts(C);
      CheckGuardPage(C);
    end;
    Writeln('UTF8_LOOKUP_CONTRACTS_PASS');
  end else begin
    Require(ParamCount = 4, 'Usage: utf8_lookup_stand KIND PROFILE COUNT PASSES');
    var Kind := StrToInt(ParamStr(1));
    var Profile := StrToInt(ParamStr(2));
    var Count := StrToInt(ParamStr(3));
    var Passes := StrToInt(ParamStr(4));
    Require((Kind >= 0) and (Kind <= High(Names)) and (Profile >= 0) and (Profile <= 2) and
      (Count >= 100) and (Count <= 1000000) and (Passes > 0) and (Passes <= 100), 'Invalid stand parameters');
    Measure(Kind, Profile, Count, Passes);
  end;
  SetMemoryManager(OriginalMM);
end.
