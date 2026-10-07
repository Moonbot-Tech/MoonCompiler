program monitor_wait_contract_semantic;

{$mode delphiunicode}

uses SysUtils;

const
  GuardSize = 64;

var
  Original, Wrapped: TMemoryManager;
  Armed: Boolean;
  Captured: Pointer;
  CapturedSize: PtrUInt;
  GuardByte: Byte;
  Captures, Releases, BrokenGuards: Integer;

function CaptureGetMem(Size: PtrUInt): Pointer;
begin
  if Armed then begin
    Armed := False;
    Result := Original.GetMem(Size + GuardSize);
    Captured := Result;
    CapturedSize := Size;
    Inc(Captures);
    // Valid storage beyond the requested object must not affect its behaviour.
    FillChar((PByte(Result) + Size)^, GuardSize, GuardByte);
  end else
    Result := Original.GetMem(Size);
end;

procedure CheckGuard;
var
  I: Integer;
begin
  for I := 0 to GuardSize - 1 do
    if (PByte(Captured) + CapturedSize + I)^ <> GuardByte then begin
      Inc(BrokenGuards);
      Break;
    end;
  Captured := nil;
  Inc(Releases);
end;

function CaptureFreeMem(P: Pointer): PtrUInt;
begin
  if (P <> nil) and (P = Captured) then
    CheckGuard;
  Result := Original.FreeMem(P);
end;

function CaptureFreeMemSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  if (P <> nil) and (P = Captured) then begin
    CheckGuard;
    // The wrapper enlarged this allocation; do not pass the original size.
    Result := Original.FreeMem(P);
  end else
    Result := Original.FreeMemSize(P, Size);
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  Obj: TObject;
  I: Integer;
  Started, Elapsed: QWord;
  Signalled: Boolean;
begin
  GetMemoryManager(Original);
  Wrapped := Original;
  Wrapped.GetMem := CaptureGetMem;
  Wrapped.FreeMem := CaptureFreeMem;
  Wrapped.FreeMemSize := CaptureFreeMemSize;
  Obj := TObject.Create;
  try
    TMonitor.Enter(Obj);
    TMonitor.Enter(Obj);
    try
      for I := 1 to 3 do begin
        case I of
          1: GuardByte := $FF;
          2: GuardByte := $A5;
          3: GuardByte := 0;
        end;
        // Pulses without waiters must not leak into a future Wait.
        TMonitor.Pulse(Obj);
        TMonitor.PulseAll(Obj);
        Started := GetTickCount64;
        SetMemoryManager(Wrapped);
        Armed := True;
        try
          Signalled := TMonitor.Wait(Obj, 60);
        finally
          Armed := False;
          SetMemoryManager(Original);
        end;
        Elapsed := GetTickCount64 - Started;
        Check(not Signalled, 'Wait without a pulse must time out');
        // Allow clock granularity, but reject an immediate abandoned/error result.
        Check(Elapsed >= 30, 'Wait returned before its timeout');
        Check(Captured = nil, 'Wait leaked its temporary allocation');
        Check(BrokenGuards = 0, 'Wait modified memory beyond its allocation');
        Check(TMonitor.TryEnter(Obj), 'Wait did not restore recursive ownership');
        TMonitor.Exit(Obj);
        Check(not TMonitor.Wait(Obj, 0), 'zero timeout must not consume a stale pulse');
      end;
      {$ifdef UNIX}
      Check(Captures = 3, 'allocation guard did not exercise the portable monitor');
      {$endif}
      Check(Releases = Captures, 'temporary allocation was not released exactly once');
    finally
      TMonitor.Exit(Obj);
      TMonitor.Exit(Obj);
    end;
  finally
    Obj.Free;
  end;
  WriteLn('MONITOR_WAIT_CONTRACT_PASS');
end.
