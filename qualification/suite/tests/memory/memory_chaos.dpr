program memory_chaos;

{ Randomized allocator workload: sizes, timings, threads and RTL-managed
  shapes that production FPC programs exercise.

  Usage: memory_chaos <mode> [seed] [seconds] [workers] [ops-per-worker]
    chaos     - randomized multi-threaded workload (default)
    large     - only large raw blocks, realloc and cross-thread release
    finalrtl  - chaos + managed program globals retained until normal exit
    finalexit - chaos + large frees from an ExitProc chain
    all       - chaos plus both valid exit-time shapes }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  cthreads,
  SysUtils,
  Classes;

const
  MaxWorkers = 64;
  SlotsPerWorker = 512;
  QueueSlots = 256;
  PatternPoints = 256;

type
  IGuardProbe = interface
    function IsValid: Boolean;
  end;

  TChaosKind = (
    ckRaw,            // GetMem/FreeMem
    ckRawRealloc,     // ReallocMem chains, grow and shrink
    ckAnsi,           // AnsiString SetLength/concat/unique
    ckWide,           // UnicodeString
    ckDynInt,         // dynamic array of Integer
    ckDynStr,         // dynamic array of managed records
    ckObject,         // TObject/TStringList
    ckIntf,           // refcounted interface
    ckNested,         // array of array
    ckHuge            // > 256KB large blocks, the FreeLargeBlock path
  );

  TSlot = record
    Kind: TChaosKind;
    Raw: PByte;
    RawSize: PtrUInt;
    Pat: Byte;
    A: AnsiString;
    W: UnicodeString;
    DI: array of Integer;
    DS: array of AnsiString;
    Obj: TObject;
    Intf: IGuardProbe;
    NN: array of TBytes;
  end;
  PSlot = ^TSlot;

  TXfer = record
    Lock: TRTLCriticalSection;
    Items: array[0..QueueSlots - 1] of PByte;
    Sizes: array[0..QueueSlots - 1] of PtrUInt;
    Pats: array[0..QueueSlots - 1] of Byte;
    Count: Integer;
  end;
  PXfer = ^TXfer;

var
  Fails: Integer = 0;
  TotalOps: Int64 = 0;
  Xfers: array[0..MaxWorkers - 1] of TXfer;
  WorkerCount: Integer;
  StopAt: UInt64;
  OpsPerWorker: Int64;
  LargeOnly: Boolean;
  LateLarge: array of TBytes;

threadvar
  CurrentWorkerToken: Integer;
  CurrentWorkerOp: Int64;

procedure Bad(const Ctx: string; const Info: string);
begin
  InterlockedIncrement(Fails);
  WriteLn('CHAOS_FAIL worker=', CurrentWorkerToken - 1,
    ' op=', CurrentWorkerOp, ' ', Ctx, ' ', Info);
  Flush(Output);
end;

function Rnd(var S: UInt64): UInt64;
begin
  S := S xor (S shr 12);
  S := S xor (S shl 25);
  S := S xor (S shr 27);
  Result := S * UInt64($2545F4914F6CDD1D);
end;

{ log-uniform size so every class is hit, large blocks often enough to
  exercise mmap/mremap/munmap and the FreeLargeBlock unlink path }
function ChaosSize(var S: UInt64; WantHuge: Boolean): PtrUInt;
var
  R: UInt64;
  Bucket: Integer;
begin
  R := Rnd(S);
  if WantHuge then
    Bucket := 18 + Integer(R mod 5)            // 256KB..8MB
  else
    Bucket := Integer(R mod 24);               // 1B..16MB
  Result := (UInt64(1) shl Bucket) + (Rnd(S) mod (UInt64(1) shl Bucket));
  if Result < 1 then
    Result := 1;
  if Result > 16 * 1024 * 1024 then
    Result := 16 * 1024 * 1024;
end;

function PatternByte(Pat: Byte; Offset: PtrUInt): Byte; inline;
begin
  Result := Pat xor Byte(Offset) xor Byte(Offset shr 8) xor
    Byte(Offset shr 16) xor Byte(Offset shr 24);
end;

procedure FillPat(P: PByte; Size: PtrUInt; Pat: Byte);
var
  I, Offset: PtrUInt;
begin
  if Size = 0 then
    exit;
  if Size <= PatternPoints then
    for I := 0 to Size - 1 do
      P[I] := PatternByte(Pat, I)
  else
    for I := 0 to PatternPoints - 1 do
    begin
      Offset := ((Size - 1) * I) div (PatternPoints - 1);
      P[Offset] := PatternByte(Pat, Offset);
    end;
end;

function CheckPat(P: PByte; Size: PtrUInt; Pat: Byte): Boolean;
var
  I, Offset: PtrUInt;
begin
  Result := True;
  if Size = 0 then
    exit;
  if Size <= PatternPoints then
  begin
    for I := 0 to Size - 1 do
      if P[I] <> PatternByte(Pat, I) then
      begin
        Result := False;
        exit;
      end;
  end
  else
    for I := 0 to PatternPoints - 1 do
    begin
      Offset := ((Size - 1) * I) div (PatternPoints - 1);
      if P[Offset] <> PatternByte(Pat, Offset) then
      begin
        Result := False;
        exit;
      end;
    end;
end;

function CheckPreserved(P: PByte; OldSize, NewSize: PtrUInt;
  Pat: Byte): Boolean;
var
  I, Offset, Preserved: PtrUInt;
begin
  Preserved := OldSize;
  if Preserved > NewSize then
    Preserved := NewSize;
  Result := True;
  if Preserved = 0 then
    exit;
  if OldSize <= PatternPoints then
  begin
    for I := 0 to Preserved - 1 do
      if P[I] <> PatternByte(Pat, I) then
      begin
        Result := False;
        exit;
      end;
  end
  else
    for I := 0 to PatternPoints - 1 do
    begin
      Offset := ((OldSize - 1) * I) div (PatternPoints - 1);
      if (Offset < Preserved) and
         (P[Offset] <> PatternByte(Pat, Offset)) then
      begin
        Result := False;
        exit;
      end;
    end;
end;

type
  TGuard = class(TInterfacedObject, IGuardProbe)
  public
    Payload: TBytes;
    constructor Create(Size: Integer);
    function IsValid: Boolean;
  end;

constructor TGuard.Create(Size: Integer);
begin
  inherited Create;
  SetLength(Payload, Size);
  if Size > 0 then
    Payload[Size - 1] := 42;
end;

type
  TChaosThread = class(TThread)
  private
    FSeed: UInt64;
    FId: Integer;
    FSlots: array[0..SlotsPerWorker - 1] of TSlot;
    procedure DoOp;
    procedure Release(S: PSlot);
    procedure PushRemote(P: PByte; Size: PtrUInt; Pat: Byte);
    procedure DrainRemote;
  public
    Ops: Int64;
    constructor Create(AId: Integer; ASeed: UInt64);
  protected
    procedure Execute; override;
  end;

constructor TChaosThread.Create(AId: Integer; ASeed: UInt64);
begin
  inherited Create(True);
  FId := AId;
  FSeed := ASeed xor (UInt64(AId + 1) * UInt64($9E3779B97F4A7C15));
end;

procedure TChaosThread.PushRemote(P: PByte; Size: PtrUInt; Pat: Byte);
var
  T: Integer;
  Q: PXfer;
begin
  if not CheckPat(P, Size, Pat) then
    Bad('remote-before', IntToStr(Size));
  T := Integer(Rnd(FSeed) mod UInt64(WorkerCount));
  Q := @Xfers[T];
  EnterCriticalSection(Q^.Lock);
  if Q^.Count < QueueSlots then
  begin
    Q^.Items[Q^.Count] := P;
    Q^.Sizes[Q^.Count] := Size;
    Q^.Pats[Q^.Count] := Pat;
    Inc(Q^.Count);
    P := nil;
  end;
  LeaveCriticalSection(Q^.Lock);
  if P <> nil then
    FreeMem(P);                                 // queue full: free locally
end;

procedure TChaosThread.DrainRemote;
var
  Q: PXfer;
  P: PByte;
  Size: PtrUInt;
  Pat: Byte;
  N: Integer;
begin
  Q := @Xfers[FId];
  while True do
  begin
    P := nil;
    Size := 0;
    Pat := 0;
    EnterCriticalSection(Q^.Lock);
    N := Q^.Count;
    if N > 0 then
    begin
      Dec(N);
      P := Q^.Items[N];
      Size := Q^.Sizes[N];
      Pat := Q^.Pats[N];
      Q^.Count := N;
    end;
    LeaveCriticalSection(Q^.Lock);
    if P = nil then
      exit;
    if not CheckPat(P, Size, Pat) then          // content survived transfer
      Bad('remote-content', IntToStr(Size));
    FreeMem(P);                                 // freed by a foreign thread
  end;
end;

procedure TChaosThread.Release(S: PSlot);
begin
  case S^.Kind of
    ckRaw, ckRawRealloc, ckHuge:
      if S^.Raw <> nil then
      begin
        if not CheckPat(S^.Raw, S^.RawSize, S^.Pat) then
          Bad('content', IntToStr(S^.RawSize));
        FreeMem(S^.Raw);
        S^.Raw := nil;
      end;
    ckAnsi:
      begin
        if (S^.A <> '') and
           ((S^.A[1] <> 'x') or (Copy(S^.A, Length(S^.A) - 3, 4) <> 'tail')) then
          Bad('ansi-content', IntToStr(Length(S^.A)));
        S^.A := '';
      end;
    ckWide:
      begin
        if (S^.W <> '') and
           (((Length(S^.W) > 1) and (S^.W[1] <> 'w')) or
            (S^.W[Length(S^.W)] <> 'z')) then
          Bad('wide-content', IntToStr(Length(S^.W)));
        S^.W := '';
      end;
    ckDynInt:
      begin
        if (Length(S^.DI) <> 0) and
           ((S^.DI[0] <> 7) or (S^.DI[High(S^.DI)] <> 9)) then
          Bad('dynint-content', IntToStr(Length(S^.DI)));
        S^.DI := nil;
      end;
    ckDynStr:
      begin
        if (Length(S^.DS) <> 0) and
           (((Length(S^.DS) > 1) and (S^.DS[0] <> '0payload')) or
            (S^.DS[High(S^.DS)] <> 'lastpayload')) then
          Bad('dynstr-content', IntToStr(Length(S^.DS)));
        S^.DS := nil;
      end;
    ckObject:
      begin
        if (S^.Obj <> nil) and (TStringList(S^.Obj).Count = 0) then
          Bad('object-content', 'empty');
        FreeAndNil(S^.Obj);
      end;
    ckIntf:
      begin
        if (S^.Intf <> nil) and not S^.Intf.IsValid then
          Bad('interface-content', 'invalid');
        S^.Intf := nil;
      end;
    ckNested:
      begin
        if (Length(S^.NN) <> 0) and
           ((Length(S^.NN[0]) = 0) or
            ((Length(S^.NN[0]) > 1) and (S^.NN[0][0] <> 0)) or
            (S^.NN[High(S^.NN)][High(S^.NN[High(S^.NN)])] <>
             Byte(High(S^.NN) xor $A5))) then
          Bad('nested-content', IntToStr(Length(S^.NN)));
        S^.NN := nil;
      end;
  end;
end;

function TGuard.IsValid: Boolean;
begin
  Result := (Length(Payload) <> 0) and (Payload[High(Payload)] = 42);
end;

procedure TChaosThread.DoOp;
var
  S: PSlot;
  R: UInt64;
  Size, NewSize, OldSize: PtrUInt;
  OldPat: Byte;
  K, J: Integer;
  NP: PByte;
begin
  R := Rnd(FSeed);
  S := @FSlots[R mod SlotsPerWorker];
  if (S^.Kind in [ckRaw, ckRawRealloc, ckHuge]) and (S^.Raw <> nil) then
  begin
    { live raw block: realloc it, hand it to another thread, or free it }
    case (R shr 40) and 3 of
      0:
        begin
          if not CheckPat(S^.Raw, S^.RawSize, S^.Pat) then
            Bad('realloc-before', IntToStr(S^.RawSize));
          OldSize := S^.RawSize;
          OldPat := S^.Pat;
          NewSize := ChaosSize(FSeed, S^.Kind = ckHuge);
          NP := S^.Raw;
          ReallocMem(NP, NewSize);               // grow/shrink, may mremap
          S^.Raw := NP;
          if not CheckPreserved(S^.Raw, OldSize, NewSize, OldPat) then
            Bad('realloc-preserved', IntToStr(OldSize) + '-' + IntToStr(NewSize));
          S^.RawSize := NewSize;
          S^.Pat := Byte(R shr 8) or 1;
          FillPat(S^.Raw, S^.RawSize, S^.Pat);
        end;
      1:
        begin
          PushRemote(S^.Raw, S^.RawSize, S^.Pat);
          S^.Raw := nil;
        end;
    else
      Release(S);
    end;
    exit;
  end;
  if S^.Kind <> ckRaw then
    Release(S);
  if LargeOnly then
    S^.Kind := ckHuge
  else
    S^.Kind := TChaosKind((R shr 16) mod (Ord(High(TChaosKind)) + 1));
  Size := ChaosSize(FSeed, S^.Kind = ckHuge);
  case S^.Kind of
    ckRaw, ckRawRealloc, ckHuge:
      begin
        GetMem(S^.Raw, Size);
        S^.RawSize := Size;
        S^.Pat := Byte(R shr 24) or 1;
        FillPat(S^.Raw, Size, S^.Pat);
      end;
    ckAnsi:
      begin
        SetLength(S^.A, Size mod (1 shl 22) + 1);
        S^.A[1] := 'x';
        S^.A := S^.A + 'tail';                   // realloc through the RTL
        UniqueString(S^.A);
      end;
    ckWide:
      begin
        SetLength(S^.W, Size mod (1 shl 20) + 1);
        S^.W[1] := 'w';
        S^.W[Length(S^.W)] := 'z';
      end;
    ckDynInt:
      begin
        SetLength(S^.DI, Size mod (1 shl 20) + 1);
        SetLength(S^.DI, Length(S^.DI) * 2 + 1); // dynarray growth
        S^.DI[0] := 7;
        S^.DI[High(S^.DI)] := 9;
      end;
    ckDynStr:
      begin
        SetLength(S^.DS, Size mod 4096 + 1);
        for K := 0 to High(S^.DS) do
          if K and 15 = 0 then
            S^.DS[K] := AnsiString(IntToStr(K)) + 'payload';
        S^.DS[High(S^.DS)] := 'lastpayload';
      end;
    ckObject:
      begin
        S^.Obj := TStringList.Create;
        for K := 0 to Integer(Size mod 512) do
          TStringList(S^.Obj).Add(IntToStr(K));
      end;
    ckIntf:
      S^.Intf := TGuard.Create(Integer(Size mod (1 shl 20)) + 1);
    ckNested:
      begin
        SetLength(S^.NN, Size mod 64 + 1);
        for K := 0 to High(S^.NN) do
        begin
          SetLength(S^.NN[K], (Size mod 8192) + 1);
          for J := 0 to High(S^.NN[K]) do
            if J and 255 = 0 then
              S^.NN[K][J] := Byte(J);
          S^.NN[K][High(S^.NN[K])] := Byte(K xor $A5);
        end;
      end;
  end;
end;

procedure TChaosThread.Execute;
var
  I: Integer;
  R: UInt64;
begin
  CurrentWorkerToken := FId + 1;
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('memory-chaos-worker');
  {$endif}
  try
    while ((OpsPerWorker = 0) and (GetTickCount64 < StopAt)) or
          ((OpsPerWorker <> 0) and (Ops < OpsPerWorker)) do
    begin
      for I := 1 to 64 do
      begin
        if (OpsPerWorker <> 0) and (Ops >= OpsPerWorker) then
          break;
        CurrentWorkerOp := Ops;
        DoOp;
        Inc(Ops);
      end;
      DrainRemote;
      R := Rnd(FSeed);
      case R and 7 of                            // randomized timing
        0: TThread.Yield;
        1: Sleep(0);
        2: Sleep(1);
      end;
    end;
    DrainRemote;
  finally
    for I := 0 to SlotsPerWorker - 1 do
      Release(@FSlots[I]);
    InterlockedExchangeAdd64(TotalOps, Ops);
  end;
end;

procedure DrainAllRemote;
var
  P: PByte;
  Size: PtrUInt;
  Pat: Byte;
  I, N: Integer;
begin
  for I := 0 to WorkerCount - 1 do
  begin
    while Xfers[I].Count <> 0 do
    begin
      N := Xfers[I].Count - 1;
      P := Xfers[I].Items[N];
      Size := Xfers[I].Sizes[N];
      Pat := Xfers[I].Pats[N];
      Xfers[I].Count := N;
      if not CheckPat(P, Size, Pat) then
        Bad('remote-final-content', IntToStr(Size));
      FreeMem(P);
    end;
  end;
end;

{ ---- valid finalization-time allocator traffic ---- }

var
  ExitLarge: array of TBytes;
  OldExit: Pointer;

procedure ChaosExitProc;
var
  I: Integer;
begin
  ExitProc := OldExit;
  for I := 0 to High(ExitLarge) do               // large frees from ExitProc
    ExitLarge[I] := nil;
  ExitLarge := nil;
end;

var
  Mode: string;
  Seed: UInt64;
  Secs, Code, I: Integer;
  WorkerFailure: TObject;
  Ws: array[0..MaxWorkers - 1] of TChaosThread;
begin
  {$ifdef FPCX64MM_DIAGNOSTIC}
  Fpcx64mmDebugSetContext('memory-chaos-main');
  {$endif}
  Mode := 'chaos';
  if ParamCount > 0 then
    Mode := ParamStr(1);
  if (Mode <> 'chaos') and (Mode <> 'large') and (Mode <> 'finalrtl') and
     (Mode <> 'finalexit') and (Mode <> 'all') then
  begin
    WriteLn('invalid mode: ', Mode);
    Halt(2);
  end;
  Seed := 5579800982869324342;
  if ParamCount > 1 then
  begin
    Val(ParamStr(2), Seed, Code);
    if Code <> 0 then
      Halt(2);
  end;
  Secs := 20;
  if ParamCount > 2 then
  begin
    Val(ParamStr(3), Secs, Code);
    if (Code <> 0) or (Secs < 0) then
      Halt(2);
  end;
  WorkerCount := (TThread.ProcessorCount * 3) div 4;
  if ParamCount > 3 then
  begin
    Val(ParamStr(4), WorkerCount, Code);
    if Code <> 0 then
      Halt(2);
  end;
  OpsPerWorker := 0;
  if ParamCount > 4 then
  begin
    Val(ParamStr(5), OpsPerWorker, Code);
    if (Code <> 0) or (OpsPerWorker < 0) then
      Halt(2);
  end;
  if WorkerCount > MaxWorkers then
    WorkerCount := MaxWorkers;
  if WorkerCount < 1 then
    WorkerCount := 1;
  LargeOnly := Mode = 'large';
  FillChar(Ws, SizeOf(Ws), 0);
  WriteLn('CHAOS mode=', Mode, ' seed=', Seed, ' workers=', WorkerCount,
    ' seconds=', Secs, ' ops-per-worker=', OpsPerWorker);
  Flush(Output);

  for I := 0 to WorkerCount - 1 do
  begin
    InitCriticalSection(Xfers[I].Lock);
    Xfers[I].Count := 0;
  end;

  StopAt := GetTickCount64 + UInt64(Secs) * 1000;
  for I := 0 to WorkerCount - 1 do
    Ws[I] := TChaosThread.Create(I, Seed);
  for I := 0 to WorkerCount - 1 do
    Ws[I].Start;
  for I := 0 to WorkerCount - 1 do
    Ws[I].WaitFor;
  for I := 0 to WorkerCount - 1 do
  begin
    WorkerFailure := Ws[I].FatalException;
    if WorkerFailure <> nil then
      if WorkerFailure is Exception then
        Bad('worker-exception', Exception(WorkerFailure).ClassName + ': ' +
          Exception(WorkerFailure).Message)
      else
        Bad('worker-exception', WorkerFailure.ClassName);
  end;
  DrainAllRemote;
  for I := 0 to WorkerCount - 1 do
    Ws[I].Free;
  for I := 0 to WorkerCount - 1 do
    DoneCriticalSection(Xfers[I].Lock);

  if (Mode = 'finalrtl') or (Mode = 'all') then
  begin
    SetLength(LateLarge, 24);                    // large blocks alive at exit
    for I := 0 to High(LateLarge) do
      SetLength(LateLarge[I], 300000 + I * 65536);
  end;
  if (Mode = 'finalexit') or (Mode = 'all') then
  begin
    SetLength(ExitLarge, 16);
    for I := 0 to High(ExitLarge) do
      SetLength(ExitLarge[I], 400000 + I * 65536);
    OldExit := ExitProc;
    ExitProc := @ChaosExitProc;
  end;

  WriteLn('CHAOS_PASS ops=', TotalOps, ' fails=', Fails);
  Flush(Output);
  if Fails > 0 then
    Halt(1);
  { the process now finalizes with large blocks still held by RTL
    managed globals and/or a valid ExitProc chain }
end.
