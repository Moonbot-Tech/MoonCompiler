{ Win64 uses the OS unwind tables, including optimized/frameless functions.
  No symbol lookup, Pascal allocation or file I/O while another thread is stopped. }
procedure NativeCaptureContext(var Context: TContext); stdcall;
  external 'kernel32.dll' name 'RtlCaptureContext';
function NativeLookupFunction(IP: QWord; out ImageBase: QWord; History: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'RtlLookupFunctionEntry';
function NativeUnwind(Flags: DWORD; ImageBase, IP: QWord; Entry: Pointer; var Context: TContext;
  HandlerData: PPointer; Frame: PQWord; ContextPointers: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'RtlVirtualUnwind';

function NativeThreadId: QWord;
begin
  Result := GetCurrentThreadId;
end;

function NativeProcessId: QWord;
begin
  Result := GetCurrentProcessId;
end;

function ReadOwnMemory(Source, Target: Pointer; Bytes: SizeUInt): SizeInt;
var
  Copied, PageBytes: PtrUInt;
begin
  Copied := 0;
  ReadProcessMemory(GetCurrentProcess, Source, Target, Bytes, @Copied);
  { Unlike process_vm_readv, Windows may reject the entire range when only
    the next page is inaccessible. Retain the readable first-page fragment. }
  PageBytes := 4096 - (PtrUInt(Source) and 4095);
  If (Copied = 0) and (Bytes > PageBytes) then
    ReadProcessMemory(GetCurrentProcess, Source, Target, PageBytes, @Copied);
  Result := Copied;
end;

{$push}{$codealign localmin=16}
procedure CaptureNative(Context: Pointer; out Raw: TRawSnapshot; SignalContext: Boolean;
  WalkStack: Boolean = True; RaiseFrame: PtrUInt = 0);
var
  Local: TContext;
  Entry, HandlerData: Pointer;
  ImageBase, Frame, OldSP: QWord;
  Counter, Frequency: Int64;
begin
  FillChar(Raw, SizeOf(Raw), 0);
  Raw.ThreadId := NativeThreadId;
  QueryPerformanceCounter(Counter);
  QueryPerformanceFrequency(Frequency);
  Raw.MonotonicNS := QWord(Counter div Frequency) * 1000000000 +
    QWord(Counter mod Frequency) * 1000000000 div QWord(Frequency);
  Raw.Hardware := SignalContext;
  If Context = nil then NativeCaptureContext(Local) else Local := PContext(Context)^;
  Move(Local.R8, Raw.Registers[0], 8 * SizeOf(QWord));
  Raw.Registers[8] := Local.Rdi;
  Raw.Registers[9] := Local.Rsi;
  Raw.Registers[10] := Local.Rbp;
  Raw.Registers[11] := Local.Rbx;
  Raw.Registers[12] := Local.Rdx;
  Raw.Registers[13] := Local.Rax;
  Raw.Registers[14] := Local.Rcx;
  Raw.Registers[15] := Local.Rsp;
  Raw.Registers[16] := Local.Rip;
  Raw.Registers[17] := Local.EFlags;
  Raw.MemoryStart := Local.Rsp;
  If RaiseFrame >= StackBytes div 2 then Raw.MemoryStart := RaiseFrame - StackBytes div 2;
  Raw.MemoryCount := ReadOwnMemory(Pointer(Raw.MemoryStart), @Raw.Memory, SizeOf(Raw.Memory));
  If not WalkStack then Exit;
  while (Local.Rip <> 0) and (Raw.Count < MaxFrames) do begin
    Raw.Frames[Raw.Count] := Local.Rip;
    Inc(Raw.Count);
    OldSP := Local.Rsp;
    Entry := NativeLookupFunction(Local.Rip, ImageBase, nil);
    If Entry <> nil then
      NativeUnwind(0, ImageBase, Local.Rip, Entry, Local, @HandlerData, @Frame, nil)
    else begin
      If ReadOwnMemory(Pointer(Local.Rsp), @Local.Rip, SizeOf(Local.Rip)) <> SizeOf(Local.Rip) then begin
        Raw.UnwindStatus := -1;
        Exit;
      end;
      Inc(Local.Rsp, SizeOf(Pointer));
    end;
    If Local.Rsp <= OldSP then begin
      Raw.UnwindStatus := -2;
      Exit;
    end;
  end;
  If Local.Rip <> 0 then Raw.UnwindStatus := 1;
end;

procedure NativeMemoryRegions(var Regions: array of TMemoryRegion);
var
  Info: TMemoryBasicInformation;
  I: Integer;
  Protection: DWORD;
begin
  for I := 0 to High(Regions) do
    If Regions[I].State = rsUnknown then
      If VirtualQuery(Pointer(Regions[I].Address), Info, SizeOf(Info)) = SizeOf(Info) then begin
        case Info.State of
          MEM_FREE: Regions[I].State := rsUnmapped;
          MEM_RESERVE: Regions[I].State := rsReserved;
          MEM_COMMIT: Regions[I].State := rsMapped;
        end;
        Regions[I].Base := PtrUInt(Info.BaseAddress);
        Regions[I].Size := Info.RegionSize;
        { Protect is undefined for free/reserved regions. }
        If Info.State <> MEM_COMMIT then Continue;
        Regions[I].Protection := Info.Protect;
        Protection := Info.Protect and $FF;
        If Protection in [PAGE_READONLY, PAGE_READWRITE, PAGE_WRITECOPY,
          PAGE_EXECUTE_READ, PAGE_EXECUTE_READWRITE, PAGE_EXECUTE_WRITECOPY] then Regions[I].Access := 1;
        If Protection in [PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READWRITE,
          PAGE_EXECUTE_WRITECOPY] then Regions[I].Access := Regions[I].Access or 2;
        If Protection in [PAGE_EXECUTE, PAGE_EXECUTE_READ, PAGE_EXECUTE_READWRITE,
          PAGE_EXECUTE_WRITECOPY] then Regions[I].Access := Regions[I].Access or 4;
        If Info.Protect and PAGE_GUARD <> 0 then Regions[I].Access := Regions[I].Access or 8;
      end;
end;

procedure NativeFaultState(Context: Pointer; var Raw: TRawSnapshot);
var
  Ctx: PContext;
  Entry: PDWord;
  ImageBase: QWord;
begin
  Ctx := PContext(Context);
  If Ctx^.ContextFlags and CONTEXT_FLOATING_POINT = CONTEXT_FLOATING_POINT then begin
    Move(Ctx^.FltSave, Raw.FloatState, SizeOf(Raw.FloatState));
    Raw.FloatValid := True;
  end;
  Entry := NativeLookupFunction(Raw.Registers[16], ImageBase, nil);
  If Entry <> nil then begin
    Raw.FunctionStart := ImageBase + Entry^;
    Raw.FunctionEnd := ImageBase + PDWord(PByte(Entry) + SizeOf(DWord))^;
  end;
end;

function SampleThread(Id: PtrUInt; out Raw: TRawSnapshot): Boolean;
var
  Thread: THandle;
  Context: TContext;
begin
  If Id = NativeThreadId then begin
    CaptureNative(nil, Raw, False);
    Exit(True);
  end;
  Result := False;
  Thread := OpenThread(THREAD_SUSPEND_RESUME or THREAD_GET_CONTEXT, False, Id);
  If Thread = 0 then Exit;
  try
    If SuspendThread(Thread) = DWORD(-1) then Exit;
    try
      FillChar(Context, SizeOf(Context), 0);
      Context.ContextFlags := CONTEXT_FULL;
      If GetThreadContext(Thread, @Context) then begin
        CaptureNative(@Context, Raw, False);
        Raw.ThreadId := Id;
        Result := True;
      end;
    finally
      ResumeThread(Thread);
    end;
  finally
    CloseHandle(Thread);
  end;
end;
{$pop}

procedure EnumerateThreads(Threads: TList);
var
  Snapshot: THandle;
  Entry: THREADENTRY32;
begin
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  If Snapshot = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    FillChar(Entry, SizeOf(Entry), 0);
    Entry.dwSize := SizeOf(Entry);
    If not Thread32First(Snapshot, Entry) then RaiseLastOSError;
    repeat
      If Entry.th32OwnerProcessID = GetCurrentProcessId then
        Threads.Add(Pointer(PtrUInt(Entry.th32ThreadID)));
    until not Thread32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

function CreateReportFile(const Name: string): THandle;
begin
  Result := CreateFileW(PWideChar(UnicodeString(Name)), GENERIC_WRITE, FILE_SHARE_READ,
    nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
end;

procedure NativeClose(Handle: THandle);
begin
  CloseHandle(Handle);
end;

procedure InitializeNative;
begin
end;
