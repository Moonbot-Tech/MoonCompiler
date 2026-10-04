program Fragment;
{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  mormot.core.base, mormot.core.data, mormot.core.text, mormot.core.variants, FragmentJsonHelpers,
  Winapi.Windows, System.SysUtils, System.Classes, System.Variants, System.SyncObjs,
  System.Diagnostics, System.Math, BenchSchedule, BenchCompression, MarketBuffers;

const
  FastCS: TDocVariantOptions = [dvoReturnNullForUnknownProperty, dvoValueCopiedByReference,
    dvoNameCaseSensitive, dvoAllowDoubleValue];
  FastMem: TDocVariantOptions = [dvoReturnNullForUnknownProperty, dvoValueCopiedByReference,
    dvoNameCaseSensitive, dvoAllowDoubleValue, dvoInternNames, dvoInternValues];
  Batches = 16;

type
  THeader = packed record
    Magic, EpochCount, Slots, EventCount: Cardinal;
  end;
  TEpoch = packed record
    First, Count: Cardinal;
    LiveCount, LiveBytes: UInt64;
  end;
  TAction = packed record
    OpGroup, Slot, Size, Reserved: Cardinal;
  end;
  TSlot = record
    P: Pointer;
    Size: Cardinal;
  end;
  PSlot = ^TSlot;
  TSample = record
    Epoch, Phase, Pools, Prefetches: Integer;
    LiveSmall, LiveMedium, Free, DeferredFree, SmallPoolUnused,
      EmptySmallPools, Unfed, LargestFree, Reserved, Standby, Large,
      OsHeld, LightSmall, LightOsHeld, LiveCapacity, Unused, LiveBytes,
      LiveCount: UInt64;
    ElapsedMS, CpuMS: Double;
  end;
  TReplayWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Header: THeader;
  Epochs: TArray<TEpoch>;
  Actions: TArray<TAction>;
  Slots: TArray<TSlot>;
  Samples: array[0..511] of TSample;
  SampleCount: Integer;
  Request, Done: TEvent;
  Worker: TReplayWorker;
  FirstAction, LastAction, CurrentEpoch, Batch, BatchLimit: Integer;
  Stopping, Drain: Boolean;
  WorkerFailure: string;
  LiveBytes, LiveCount: UInt64;
  Mode, DataDir, OutputDir, Seed: string;
  FullZip, CompactZip, FuturesZip, TickerZip: RawUtf8;
  Doc: Variant;
  LastResponse: RawUtf8;
  Oracle: UInt64;
  ExpectedSymbols: Integer;
  Clock: TStopwatch;
  CpuStart: UInt64;
  Stride: Int64;
  ParseMS, FreeMS: Double;
  CrossEvery, RestMarkets, QueryCount: Integer;
  FinalBookBytes, FinalBookChecksum: UInt64;

procedure Check(OK: Boolean; const Message: string);
begin
  If not OK then raise Exception.Create(Message);
end;

function ReadBytes(const Path: string): RawUtf8;
begin
  var S := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    If S.Size <> 0 then S.ReadBuffer(Result[1], Length(Result));
  finally
    S.Free;
  end;
end;

function CPUTime: UInt64;
var
  Created, Ended, Kernel, User: TFileTime;
begin
  Check(GetProcessTimes(GetCurrentProcess, Created, Ended, Kernel, User), 'GetProcessTimes');
  Result := (UInt64(Kernel.dwHighDateTime) shl 32) + Kernel.dwLowDateTime +
    (UInt64(User.dwHighDateTime) shl 32) + User.dwLowDateTime;
end;

procedure Capture(Phase: Integer);
var
  S: TSample;
  M: TMMFragmentationStatus;
  L: TMMStatus;
begin
  S := Default(TSample);
  S.Epoch := CurrentEpoch;
  S.Phase := Phase;
  S.ElapsedMS := Clock.Elapsed.TotalMilliseconds;
  S.CpuMS := (CPUTime - CpuStart) / 10000;
  S.LiveBytes := LiveBytes;
  S.LiveCount := LiveCount;
  M := CurrentHeapFragmentationStatus;
  L := CurrentHeapStatus;
  Check(M.Errors = 0, 'MM fragmentation scan');
  Check(M.SmallPoolBytes >= M.LiveSmallBytes, 'Small-pool balance');
  Check(M.MediumReservedBytes >= M.LiveSmallBytes + M.LiveMediumBytes, 'Medium-arena balance');
  S.Pools := M.MediumPools;
  S.Prefetches := M.MediumPrefetches;
  S.LiveSmall := M.LiveSmallBytes;
  S.LiveMedium := M.LiveMediumBytes;
  S.Free := M.FreeMediumBytes;
  S.DeferredFree := M.DeferredFreeBytes;
  S.SmallPoolUnused := M.SmallPoolBytes - M.LiveSmallBytes;
  S.EmptySmallPools := M.EmptySmallPoolBytes;
  S.Unfed := M.UnfedBytes;
  S.LargestFree := M.LargestFreeMediumBlock;
  S.Reserved := M.MediumReservedBytes;
  S.Standby := M.MediumStandbyBytes;
  S.Large := M.LargeReservedBytes;
  S.OsHeld := M.MediumReservedBytes + M.MediumStandbyBytes +
    M.LargeReservedBytes;
  S.LightSmall := L.SmallBlocksSize;
  S.LightOsHeld := L.OsHeldBytes;
  S.LiveCapacity := M.LiveSmallBytes + M.LiveMediumBytes + M.LiveLargeBytes;
  S.Unused := S.Reserved + S.Standby - S.LiveSmall - S.LiveMedium;
  Check(SampleCount < Length(Samples), 'Sample storage full');
  Samples[SampleCount] := S;
  Inc(SampleCount);
end;

procedure VerifySlot(const S: TSlot; Index: Integer);
begin
  Check(S.P <> nil, 'Missing replay allocation');
  Check((PByte(S.P)^ = Byte(Index and 255)) and
    (PByte(NativeUInt(S.P) + S.Size - 1)^ = Byte(Index and 255)), 'Replay payload corrupted');
end;

procedure TReplayWorker.Execute;
begin
  try
    while true do begin
      Check(Request.WaitFor(60000) = wrSignaled, 'Replay request timeout');
      If Stopping then exit;
      If Drain then begin
        for var I := 0 to High(Slots) do If Slots[I].P <> nil then begin
          VerifySlot(Slots[I], I);
          FreeMem(Slots[I].P);
          Slots[I].P := nil;
        end;
        ClearBooks;
        LiveBytes := 0;
        LiveCount := 0;
      end else begin
        for var I := FirstAction to LastAction - 1 do begin
          var A := Actions[I];
          var S: PSlot := @Slots[A.Slot];
          case A.OpGroup and 255 of
            0: begin
              Check(S.P = nil, 'Duplicate replay allocation');
              GetMem(S.P, A.Size);
              Inc(LiveCount);
            end;
            1, 2: begin
              VerifySlot(S^, A.Slot);
              Dec(LiveBytes, S.Size);
              If A.OpGroup and 255 = 1 then begin
                FreeMem(S.P);
                S.P := nil;
                S.Size := 0;
                Dec(LiveCount);
                continue;
              end;
              ReallocMem(S.P, A.Size);
              Check(PByte(S.P)^ = Byte(A.Slot and 255), 'Realloc lost data');
            end;
          else
            raise Exception.Create('Unknown replay action');
          end;
          S.Size := A.Size;
          FillChar(S.P^, A.Size, Byte(A.Slot and 255));
          Inc(LiveBytes, A.Size);
        end;
      end;
      If not Drain and (CurrentEpoch > 0) then PulseBooks;
      Done.SetEvent;
    end;
  except
    on E: Exception do begin
      WorkerFailure := E.ClassName + ': ' + E.Message;
      Done.SetEvent;
    end;
  end;
end;

procedure ApplyRange(First, Last: Integer);
begin
  FirstAction := First;
  LastAction := Last;
  Request.SetEvent;
  Check(Done.WaitFor(60000) = wrSignaled, 'Replay completion timeout');
  Check(WorkerFailure = '', WorkerFailure);
end;

procedure Checkpoint;
begin
  If Batch >= BatchLimit then exit;
  var E := Epochs[CurrentEpoch];
  var First := E.First + UInt64(E.Count) * Cardinal(Batch) div Batches;
  Inc(Batch);
  var Last := E.First + UInt64(E.Count) * Cardinal(Batch) div Batches;
  ApplyRange(First, Last);
end;

function Consume(const V: Variant; out Count: Integer): UInt64;
var
  Root, Items: PDocVariantData;
  Base: string;
begin
  Check(_Safe(V, Root) and Root.GetAsArray('symbols', Items), 'Missing symbols');
  Count := Items^.Count;
  Result := 0;
  for var Item in Items^.Objects do begin
    If Item.SameText('status', 'TRADING') and Item.TryLoadStr('baseAsset', Base) then begin
      for var C in Base do Result := ((Result shl 7) or (Result shr 57)) xor Ord(C);
      If Item.SameText('quoteAsset', 'USDT') then Result := Result xor 1;
      If Item.SameText('quoteAsset', 'BTC') then Result := Result xor 2;
    end;
  end;
end;

procedure ParseSpot(const Compressed: RawUtf8);
begin
  // Exact production Helpers.ZInflate and JSON_OPTIONS_FASTMEM.
  LastResponse := ZInflate(Pointer(Compressed), Length(Compressed), 31);
  Check(LastResponse <> '', 'Inflate failed');
  Check(_Json(LastResponse, Doc, FastMem), 'Spot JSON failed');
  var Count: Integer;
  Check((Consume(Doc, Count) = Oracle) and (Count = ExpectedSymbols), 'Spot consumer result changed');
end;

procedure ClearSpot;
begin
  VarClear(Doc);
  DocVariantType.InternValues.Clean(1);
  // LastResponse is intentionally retained until the next reply, like the engine.
end;

procedure BackgroundBursts;
var
  V: Variant;
  Body: RawUtf8;
  Input, Compressed: TBytes;
begin
  // The retained JSON lifetimes are already replayed from snapshots. These are temporary responses.
  BatchLimit := 14;
  If Mode <> 'serial' then StartCounting(64, Checkpoint);
  try
    Body := ZInflate(Pointer(FuturesZip), Length(FuturesZip), 31);
    Check(_Json(Body, V, FastMem), 'Futures JSON failed');
    VarClear(V);
    DocVariantType.InternValues.Clean(1);
    Body := ZInflate(Pointer(TickerZip), Length(TickerZip), 31);
    for var I := 1 to 1000 do begin
      Check(_Json(Body, V, FastCS), 'Ticker JSON failed');
      VarClear(V);
    end;
  finally
    StopCounting;
  end;
  If Mode <> 'serial' then while Batch < BatchLimit do Checkpoint;
  SetLength(Input, 96);
  FillChar(Input[0], Length(Input), $37);
  BatchLimit := Batches;
  If Mode <> 'serial' then StartCounting(32, Checkpoint);
  try
    for var I := 1 to 100 do Compressed := GZipCompress(Input);
  finally
    StopCounting;
  end;
  If Mode <> 'serial' then while Batch < BatchLimit do Checkpoint;
  Check(ZInflate(Pointer(Compressed), Length(Compressed), 31) = RawUtf8(StringOfChar('7', 96)), 'Ping gzip round trip');
end;

procedure SaveResults;
var
  F: TextFile;
begin
  AssignFile(F, OutputDir + '\samples.csv');
  Rewrite(F);
  try
    Writeln(F, 'epoch,phase,pools,prefetches,live_small,live_medium,medium_free,',
      'deferred_free,small_pool_unused,empty_small_pools,unfed,largest_free,',
      'reserved,standby,large,os_held,light_small,light_os_held,live_capacity,',
      'unused,replay_bytes,replay_count,elapsed_ms,cpu_ms');
    for var I := 0 to SampleCount - 1 do With Samples[I] do
      Writeln(F, Epoch, ',', Phase, ',', Pools, ',', Prefetches, ',', LiveSmall, ',', LiveMedium, ',', Free, ',',
        DeferredFree, ',', SmallPoolUnused, ',', EmptySmallPools, ',', Unfed, ',', LargestFree, ',', Reserved, ',',
        Standby, ',', Large, ',', OsHeld, ',', LightSmall, ',', LightOsHeld, ',', LiveCapacity, ',', Unused, ',',
        LiveBytes, ',', LiveCount, ',', ElapsedMS:0:3, ',', CpuMS:0:3);
  finally
    CloseFile(F);
  end;
  Writeln('BENCH_PASS mode=', Mode, ' seed=', Seed, ' epochs=', CurrentEpoch + 1,
    ' symbols=', ExpectedSymbols, ' signature=', Oracle, ' parse_ms=', ParseMS:0:3, ' free_ms=', FreeMS:0:3,
    ' queries=', QueryCount, ' cadence=', CrossEvery, ' rest_markets=', RestMarkets,
    ' book_bytes=', FinalBookBytes, ' book_checksum=', FinalBookChecksum,
    ' intern_names=', DocVariantType.InternNames.Count, ' intern_values=', DocVariantType.InternValues.Count);
end;

procedure Run;
var
  Stream: TFileStream;
  FullBody: RawUtf8;
  Count: Integer;
  Limit: Integer;
begin
  IsMultiThread := true;
  FormatSettings.DecimalSeparator := '.';
  Mode := ParamStr(1);
  Seed := ParamStr(2);
  Check(ParamCount >= 3, 'Usage: Fragment MODE SEED OUTPUT [EPOCHS=137] [CROSS_EVERY=1] [REST_MARKETS=64]');
  OutputDir := ExpandFileName(ParamStr(3));
  Limit := StrToIntDef(ParamStr(4), MaxInt);
  CrossEvery := StrToIntDef(ParamStr(5), 1);
  RestMarkets := StrToIntDef(ParamStr(6), 64);
  Check((CrossEvery > 0) and (RestMarkets >= 0) and (RestMarkets <= 2048), 'Invalid cadence/books');
  Check((Mode = 'baseline') or (Mode = 'compact') or (Mode = 'serial') or (Mode = 'no-bursts'), 'Unknown mode');
  {$IFDEF DEBUG}
  DataDir := ExtractFilePath(ParamStr(0)) + '..\data';
  {$ELSE}
  DataDir := ExtractFilePath(ParamStr(0)) + 'data';
  {$ENDIF}
  InitBooks(StrToInt(Seed), RestMarkets, DataDir);
  ForceDirectories(OutputDir);
  Stream := TFileStream.Create(DataDir + '\epochs-' + Seed + '.bin', fmOpenRead);
  try
    Stream.ReadBuffer(Header, SizeOf(Header));
    Check((Header.Magic = $31425246) and (Header.EpochCount <= 200), 'Invalid replay header');
    SetLength(Epochs, Header.EpochCount);
    Stream.ReadBuffer(Epochs[0], Length(Epochs) * SizeOf(TEpoch));
  finally
    Stream.Free;
  end;
  Stream := TFileStream.Create(DataDir + '\events-' + Seed + '.bin', fmOpenRead);
  try
    Check(Stream.Size = UInt64(Header.EventCount) * SizeOf(TAction), 'Invalid event file size');
    SetLength(Actions, Header.EventCount);
    Stream.ReadBuffer(Actions[0], Length(Actions) * SizeOf(TAction));
  finally
    Stream.Free;
  end;
  SetLength(Slots, Header.Slots);
  FullZip := ReadBytes(DataDir + '\binance-spot.gz');
  CompactZip := ReadBytes(DataDir + '\binance-spot-compact.gz');
  FuturesZip := ReadBytes(DataDir + '\binance-futures.gz');
  TickerZip := ReadBytes(DataDir + '\binance-single-ticker.gz');
  FullBody := ZInflate(Pointer(FullZip), Length(FullZip), 31);
  Doc := _Json(FullBody, FastMem);
  Oracle := Consume(Doc, ExpectedSymbols);
  ClearSpot;
  FullBody := ZInflate(Pointer(CompactZip), Length(CompactZip), 31);
  Check(_Json(FullBody, Doc, FastMem), 'Compact JSON failed');
  Check((Consume(Doc, Count) = Oracle) and (Count = ExpectedSymbols), 'Compact changed consumer input');
  ClearSpot;
  FullBody := '';
  InstallSchedule;
  try
    StartCounting(MaxInt, nil);
    If Mode = 'compact' then ParseSpot(CompactZip) else ParseSpot(FullZip);
    Stride := Max(Int64(1), StopCounting div (Batches + 1));
    ClearSpot;
    Request := TEvent.Create(nil, false, false, '');
    Done := TEvent.Create(nil, false, false, '');
    Worker := TReplayWorker.Create(true);
    Worker.FreeOnTerminate := false;
    Worker.Start;
    try
      CpuStart := CPUTime;
      Clock := TStopwatch.StartNew;
      Capture(-1);
      ApplyRange(Epochs[0].First, Epochs[0].First + Epochs[0].Count);
      Check((LiveCount = Epochs[0].LiveCount) and (LiveBytes = Epochs[0].LiveBytes), 'Initial replay mismatch');
      Capture(0);
      for var I := 1 to Min(Length(Epochs), Limit) - 1 do begin
        CurrentEpoch := I;
        Batch := 0;
        BatchLimit := Batches;
        If Mode = 'no-bursts' then begin
          while Batch < Batches do Checkpoint;
        end else If (I - 1) mod CrossEvery <> 0 then begin
          BatchLimit := 12;
          while Batch < BatchLimit do Checkpoint;
          BackgroundBursts;
          If Mode = 'serial' then while Batch < Batches do Checkpoint;
        end else begin
          Inc(QueryCount);
          BatchLimit := 12;
          var Timer := TStopwatch.StartNew;
          If (Mode = 'baseline') or (Mode = 'compact') then StartCounting(Stride, Checkpoint);
          try
            If Mode = 'compact' then ParseSpot(CompactZip) else ParseSpot(FullZip);
          finally
            StopCounting;
          end;
          ParseMS := ParseMS + Timer.Elapsed.TotalMilliseconds;
          If Mode <> 'serial' then while Batch < BatchLimit do Checkpoint;
          Capture(1);
          Timer := TStopwatch.StartNew;
          ClearSpot;
          FreeMS := FreeMS + Timer.Elapsed.TotalMilliseconds;
          BackgroundBursts;
          If Mode = 'serial' then while Batch < Batches do Checkpoint;
        end;
        Check((LiveCount = Epochs[I].LiveCount) and (LiveBytes = Epochs[I].LiveBytes), 'Replay differs from source snapshot');
        Capture(2);
      end;
      LastResponse := '';
      FinalBookBytes := BookBytes;
      FinalBookChecksum := BookChecksum;
      Capture(3);
      Drain := true;
      ApplyRange(0, 0);
      Check((LiveCount = 0) and (LiveBytes = 0) and (BookBytes = 0), 'Replay drain failed');
      Capture(4);
    finally
      Stopping := true;
      Request.SetEvent;
      Worker.WaitFor;
      Check(WorkerFailure = '', WorkerFailure);
      Worker.Free;
      Done.Free;
      Request.Free;
    end;
  finally
    RemoveSchedule;
  end;
  SaveResults;
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      Writeln('BENCH_FAIL ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
