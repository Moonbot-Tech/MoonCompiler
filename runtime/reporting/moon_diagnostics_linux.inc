{ Linux x86-64. libunwind's local init/step APIs are signal-safe. Symbol
  resolution and all managed Pascal data stay outside the signal handler. }
type
  TUnwindCursor = array[0..126] of QWord;
  TUnwindContext = array[0..127] of QWord;
  TUnwindInit = function(Cursor, Context: Pointer; Flags: Integer): Integer; cdecl;
  TUnwindStep = function(Cursor: Pointer): Integer; cdecl;
  TUnwindRegister = function(Cursor: Pointer; Reg: Integer; out Value: QWord): Integer; cdecl;
  TUnwindGetContext = function(Context: Pointer): Integer; cdecl;
  TUnwindProcInfo = record
    StartIP, EndIP, LSDA, Handler, GP, Flags: QWord;
    Format, InfoSize: LongInt;
    Info: Pointer;
    Extra: QWord; { x86-64's unused byte plus native tail padding }
  end;
  TUnwindInfo = function(Cursor: Pointer; out Info: TUnwindProcInfo): Integer; cdecl;
  TNativeTime = record Seconds, Nanoseconds: Int64; end;
  TNativeIOVec = record Data: Pointer; Length: SizeUInt; end;

var
  UnwindLibrary: TLibHandle;
  UnwindInit: TUnwindInit;
  UnwindStep: TUnwindStep;
  UnwindRegister: TUnwindRegister;
  UnwindGetContext: TUnwindGetContext;
  UnwindInfo: TUnwindInfo;
  ProcessId: LongInt;
  SampleSignal: Integer;
  SampleGeneration: Int64;
  { Persistent storage: a timed-out handler must never write into freed memory. }
  Request: record
    State: Int64; { generation * 4 + 1 pending, +2 capturing, +3 complete; 0 idle }
    Raw: TRawSnapshot;
  end;

function NativeSyscall(Number, A1, A2, A3, A4, A5, A6: PtrInt): PtrInt; cdecl;
  external 'c' name 'syscall';
function NativeClock(ClockId: Integer; var Value: TNativeTime): Integer; cdecl;
  external 'c' name 'clock_gettime';

function NativeThreadId: QWord;
begin
  Result := NativeSyscall(186, 0, 0, 0, 0, 0, 0);
end;

function NativeProcessId: QWord;
begin
  Result := ProcessId;
end;

function NativeTimeNS: QWord;
var
  Value: TNativeTime;
begin
  NativeClock(1, Value);
  Result := QWord(Value.Seconds) * 1000000000 + QWord(Value.Nanoseconds);
end;

function ReadOwnMemory(Source, Target: Pointer; Bytes: SizeUInt): SizeInt;
var
  Local, Remote: TNativeIOVec;
begin
  Local.Data := Target;
  Local.Length := Bytes;
  Remote.Data := Source;
  Remote.Length := Bytes;
  Result := NativeSyscall(310, ProcessId, PtrInt(@Local), 1, PtrInt(@Remote), 1, 0);
  If Result < 0 then Result := 0;
end;

{$push}{$codealign localmin=16}
procedure CaptureNative(Context: Pointer; out Raw: TRawSnapshot; SignalContext: Boolean;
  WalkStack: Boolean = True; RaiseFrame: PtrUInt = 0; Origin: PtrUInt = 0);
var
  Local: TUnwindContext;
  Cursor: TUnwindCursor;
  Ctx: PSigContext;
  Address: QWord;
  Status, Steps: Integer;
  Info: TUnwindProcInfo;
  OriginFound: Boolean;
begin
  FillChar(Raw, SizeOf(Raw), 0);
  Raw.ThreadId := NativeThreadId;
  Raw.MonotonicNS := NativeTimeNS;
  Raw.Hardware := SignalContext;
  If Context = nil then begin
    FillChar(Local, SizeOf(Local), 0);
    UnwindGetContext(@Local);
    Context := @Local;
  end;
  Ctx := PSigContext(Context);
  Move(Ctx^.r8, Raw.Registers, SizeOf(Raw.Registers));
  Raw.MemoryStart := Ctx^.rsp;
  { For a Pascal raise, inspect the originating frame, not the collector's
    temporary unwind cursor. Registers still honestly describe capture time. }
  If RaiseFrame >= StackBytes div 2 then Raw.MemoryStart := RaiseFrame - StackBytes div 2;
  Raw.MemoryCount := ReadOwnMemory(Pointer(Raw.MemoryStart), @Raw.Memory, SizeOf(Raw.Memory));
  If not WalkStack then Exit;
  If Ctx^.rip=0 then begin
    Raw.UnwindStatus := -10; { UNW_ENOINFO: no code at the captured PC }
    Exit;
  end;
  Status := UnwindInit(@Cursor, Context, Ord(SignalContext));
  If Status < 0 then begin
    Raw.UnwindStatus := Status;
    Raw.Frames[0] := Ctx^.rip;
    Raw.Count := 1;
    Exit;
  end;
  OriginFound := Origin = 0;
  Steps := 0;
  repeat
    Inc(Steps);
    Status := UnwindRegister(@Cursor, 16, Address);
    If (Status < 0) or (Address = 0) then Break;
    Status := UnwindInfo(@Cursor, Info);
    { libunwind may otherwise fall back to guessing a frame from stack data.
      x86-64 returns a one-byte range when it has no procedure information. }
    If (Status < 0) or (Info.EndIP <= Info.StartIP + 1) then begin
      If (Raw.Count = 0) and OriginFound then begin
        Raw.Frames[0] := Address;
        Raw.Count := 1;
      end;
      If Status = 0 then Status := -10; { UNW_ENOINFO }
      Break;
    end;
    If not OriginFound and (Origin >= Info.StartIP) and (Origin < Info.EndIP) then begin
      { Pascal raise supplies a source label, not necessarily the return PC of
        FPC_RAISEEXCEPTION. Match the real procedure range, not exact PCs. }
      OriginFound := True;
      Address := Origin;
    end;
    If OriginFound then begin
      If Raw.Count = 0 then begin
        Raw.FunctionStart := Info.StartIP;
        Raw.FunctionEnd := Info.EndIP;
      end;
      Raw.Frames[Raw.Count] := Address;
      Inc(Raw.Count);
    end;
    Status := UnwindStep(@Cursor);
  until (Status <= 0) or (Steps = MaxFrames);
  Raw.UnwindStatus := Status;
end;
{$pop}

function ParseMapPrefix(Prefix: PAnsiChar; Count: Integer; out Base, Limit: QWord; out Access: Byte): Boolean;
var
  I: Integer;

  function Hex(out Value: QWord): Boolean;
  var
    Digits, N: Integer;
  begin
    Value := 0;
    Digits := 0;
    while I < Count do begin
      case Prefix[I] of
        '0'..'9': N := Ord(Prefix[I]) - Ord('0');
        'a'..'f': N := Ord(Prefix[I]) - Ord('a') + 10;
        else Break;
      end;
      If Digits = 16 then Exit(False);
      Value := (Value shl 4) or QWord(N);
      Inc(Digits);
      Inc(I);
    end;
    Result := Digits <> 0;
  end;

begin
  Result := False;
  I := 0;
  If not Hex(Base) then Exit;
  If (I >= Count) or (Prefix[I] <> '-') then Exit;
  Inc(I);
  If not Hex(Limit) or (Limit <= Base) then Exit;
  If (I + 6 > Count) or (Prefix[I] <> ' ') then Exit;
  Inc(I);
  If not (Prefix[I] in ['r', '-']) or not (Prefix[I + 1] in ['w', '-']) or
     not (Prefix[I + 2] in ['x', '-']) or not (Prefix[I + 3] in ['p', 's']) or (Prefix[I + 4] <> ' ') then Exit;
  Access := Ord(Prefix[I] = 'r') or (Ord(Prefix[I + 1] = 'w') shl 1) or (Ord(Prefix[I + 2] = 'x') shl 2);
  Result := True;
end;

procedure NativeMemoryRegions(var Regions: array of TMemoryRegion);
var
  Buffer: array[0..4095] of AnsiChar;
  Prefix: array[0..47] of AnsiChar;
  FileName: PAnsiChar;
  Handle, Count, Used, I, J, Reads, Pending: Integer;
  Base, Limit: QWord;
  Access: Byte;
begin
  { One bounded pass for all addresses. Only fixed buffers and OS calls during
    capture; do not allocate strings or cache a map that can become stale. }
  FileName := '/proc/self/maps';
  {$ifdef MOON_DIAGNOSTICS_TEST}
  If DiagnosticTestMapsFile <> nil then FileName := DiagnosticTestMapsFile;
  {$endif}
  Handle := FpOpen(FileName, O_RDONLY or $80000 { O_CLOEXEC });
  If Handle < 0 then Exit;
  Used := 0;
  try
    for Reads := 1 to 256 do begin { at most 1 MiB; unresolved regions stay unavailable }
      Count := FpRead(Handle, Buffer, SizeOf(Buffer));
      If Count < 0 then begin
        If FpGetErrno = ESysEINTR then Continue;
        Exit;
      end;
      If Count = 0 then begin
        If Used <> 0 then Exit; { truncated map is not evidence of absence }
        for J := 0 to High(Regions) do
          If Regions[J].State = rsUnknown then Regions[J].State := rsUnmapped;
        Exit;
      end;
      for I := 0 to Count - 1 do
        If Buffer[I] = #10 then begin
          If not ParseMapPrefix(@Prefix, Used, Base, Limit, Access) then Exit;
          Pending := 0;
          for J := 0 to High(Regions) do
            If Regions[J].State = rsUnknown then begin
              { Kernel VMAs are ordered: crossing an address proves a gap.
                Do not scan the whole process map for a nil/low bad pointer. }
              If Regions[J].Address < Base then Regions[J].State := rsUnmapped
              else If Regions[J].Address < Limit then begin
                Regions[J].Base := Base;
                Regions[J].Size := Limit - Base;
                Regions[J].Access := Access;
                Regions[J].State := rsMapped;
              end else Inc(Pending);
            end;
          If Pending = 0 then Exit;
          Used := 0;
        end else If Used < Length(Prefix) then begin
          Prefix[Used] := Buffer[I];
          Inc(Used);
        end;
    end;
  finally
    FpClose(Handle);
  end;
end;

procedure NativeFaultState(Context: Pointer; var Raw: TRawSnapshot);
var
  Ctx: PSigContext;
begin
  Ctx := PSigContext(Context);
  Raw.TrapNumber := Ctx^.trapno;
  Raw.TrapError := Ctx^.err;
  If Ctx^.trapno = 14 then Raw.FaultAddress := Ctx^.cr2;
  If Ctx^.fpstate <> nil then begin
    Move(Ctx^.fpstate^, Raw.FloatState, SizeOf(Raw.FloatState));
    Raw.FloatValid := True;
  end;
end;

procedure SampleHandler(Signal: LongInt; Info: PSigInfo; Context: PSigContext); cdecl;
var
  Token: Int64;
begin
  If (Info = nil) or (Info^.si_code <> -1) or
     (Info^._sifields._rt._pid <> ProcessId) then Exit;
  Token := PtrInt(Info^._sifields._rt._sigval);
  If (Token <= 0) or ((Token and 3) <> 1) then Exit;
  { Generation and state are claimed atomically. An old queued signal cannot
    take a new request even if it arrives between timeout and the next sample. }
  If InterlockedCompareExchange64(Request.State, Token + 1, Token) <> Token then Exit;
  CaptureNative(Context, Request.Raw, True);
  InterlockedExchange64(Request.State, Token + 2);
end;

procedure EnumerateThreads(Threads: TList);
var
  Search: TSearchRec;
  Id: Int64;
begin
  If FindFirst('/proc/self/task/*', faAnyFile, Search) <> 0 then RaiseLastOSError;
  try
    repeat
      If TryStrToInt64(Search.Name, Id) and (Id > 0) then Threads.Add(Pointer(PtrUInt(Id)));
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

function SampleThread(Id: PtrUInt; out Raw: TRawSnapshot): Boolean;
var
  Info: TSigInfo;
  Deadline: QWord;
  State, Token: Int64;
begin
  If Id = NativeThreadId then begin
    CaptureNative(nil, Raw, False);
    Exit(True);
  end;
  State := InterlockedCompareExchange64(Request.State, 0, 0);
  If (State and 3) = 2 then Exit(False); { A timed-out sample still owns storage. }
  FillChar(Info, SizeOf(Info), 0);
  Info.si_signo := SampleSignal;
  Info.si_code := -1; { SI_QUEUE }
  Info._sifields._rt._pid := ProcessId;
  Inc(SampleGeneration);
  Token := SampleGeneration * 4 + 1;
  Info._sifields._rt._sigval := Pointer(Token);
  InterlockedExchange64(Request.State, Token);
  If NativeSyscall(297, ProcessId, Id, SampleSignal, PtrInt(@Info), 0, 0) <> 0 then begin
    InterlockedCompareExchange64(Request.State, 0, Token);
    Exit(False);
  end;
  Deadline := NativeTimeNS + 250000000;
  repeat
    State := InterlockedCompareExchange64(Request.State, 0, 0);
    If State = Token + 2 then begin
      Raw := Request.Raw;
      InterlockedExchange64(Request.State, 0);
      Exit(True);
    end;
    Sleep(1);
  until NativeTimeNS >= Deadline;
  InterlockedCompareExchange64(Request.State, 0, Token);
  Result := False;
end;

function CreateReportFile(const Name: string): THandle;
var
  Bytes: UTF8String;
begin
  Bytes := UTF8Encode(Name);
  Result := FpOpen(PAnsiChar(Bytes), O_WRONLY or O_CREAT or O_EXCL or $80000 { O_CLOEXEC }, &600);
end;

procedure NativeClose(Handle: THandle);
begin
  FpClose(Handle);
end;

procedure InitializeNative;
var
  Action: SigActionRec;
  PreviousSignal: SigActionRec;
  Mask: TSigSet;
  Warm: TRawSnapshot;
begin
  ProcessId := FpGetPid;
  UnwindLibrary := LoadLibrary('libunwind.so.8');
  If UnwindLibrary = NilHandle then raise Exception.Create('Moon.Diagnostics requires Linux libunwind.so.8');
  try
    UnwindInit := TUnwindInit(GetProcedureAddress(UnwindLibrary, '_ULx86_64_init_local2'));
    UnwindStep := TUnwindStep(GetProcedureAddress(UnwindLibrary, '_ULx86_64_step'));
    UnwindRegister := TUnwindRegister(GetProcedureAddress(UnwindLibrary, '_ULx86_64_get_reg'));
    UnwindGetContext := TUnwindGetContext(GetProcedureAddress(UnwindLibrary, '_Ux86_64_getcontext'));
    UnwindInfo := TUnwindInfo(GetProcedureAddress(UnwindLibrary, '_ULx86_64_get_proc_info'));
    If not Assigned(UnwindInit) or not Assigned(UnwindStep) or
       not Assigned(UnwindRegister) or not Assigned(UnwindGetContext) or not Assigned(UnwindInfo) then
      raise Exception.Create('Incompatible libunwind x86-64 local API');
    CaptureNative(nil, Warm, False); { Load unwind data before any signal capture. }
    FpSigProcMask(SIG_BLOCK, nil, @Mask);
    SampleSignal := 64;
    while SampleSignal >= 34 do begin
      If (FpSigAction(SampleSignal, nil, @PreviousSignal) = 0) and
         (@PreviousSignal.sa_handler = nil) and
         (FpSigIsMember(Mask, SampleSignal) = 0) then Break;
      Dec(SampleSignal);
    end;
    If SampleSignal < 34 then raise Exception.Create('No unused unblocked real-time signal for reports');
    FillChar(Action, SizeOf(Action), 0);
    Action.sa_handler := @SampleHandler;
    Action.sa_flags := SA_SIGINFO or SA_RESTART;
    If FpSigAction(SampleSignal, @Action, nil) <> 0 then RaiseLastOSError;
  except
    UnloadLibrary(UnwindLibrary);
    UnwindLibrary := NilHandle;
    raise;
  end;
  { Process-lifetime registration. A delayed queued signal must not encounter
    SIG_DFL during finalization; a handler may also still be finishing. }
end;
