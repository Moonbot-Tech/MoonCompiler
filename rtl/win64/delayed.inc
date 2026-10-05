{ A private, fixed-size PE section describes each delayed function. No delayed
  DLL appears in the eager import directory. Per-entry ownership serializes
  resolution; published targets are aligned atomic pointers. Explicit unload,
  like FreeLibrary, requires the application to stop calls into that DLL first. }
{$push}{$pointermath on}
type
  PDelayedEntry = ^TDelayedEntry;
  TDelayedEntry = record
    Target, Initial: Pointer;
    Dll: PAnsiChar;
    Import: PtrUInt;             { IMAGE_IMPORT_BY_NAME pointer or high-bit ordinal }
    Handle: THandle;
    Owner: Longint;
    Reserved: Longint;
  end;

function DelayLoadLibrary(Name: PAnsiChar): THandle; stdcall; external 'kernel32' name 'LoadLibraryA';
function DelayGetProcAddress(Module: THandle; Name: PAnsiChar): Pointer; stdcall; external 'kernel32' name 'GetProcAddress';
function DelayFreeLibrary(Module: THandle): LongBool; stdcall; external 'kernel32' name 'FreeLibrary';
function DelayGetModuleHandle(Flags: DWord; Address: Pointer; out Module: THandle): LongBool; stdcall;
  external 'kernel32' name 'GetModuleHandleExA';
function DelayGetError: DWord; stdcall; external 'kernel32' name 'GetLastError';
function DelayThreadId: DWord; stdcall; external 'kernel32' name 'GetCurrentThreadId';
procedure DelaySleep(Milliseconds: DWord); stdcall; external 'kernel32' name 'Sleep';
function DelayNameCompare(A, B: PAnsiChar): Longint; stdcall; external 'kernel32' name 'lstrcmpiA';
procedure DelayRaise(Code, Flags, Count: DWord; Arguments: Pointer); stdcall;
  external 'kernel32' name 'RaiseException';

function DliNotifyHook2: TDelayedLoadHook;
begin
  Result := TDelayedLoadHook(InterlockedCompareExchangePointer(__pfnDliNotifyHook2, nil, nil));
end;

function DliFailureHook2: TDelayedLoadHook;
begin
  Result := TDelayedLoadHook(InterlockedCompareExchangePointer(__pfnDliFailureHook2, nil, nil));
end;

function SetDliNotifyHook2(HookProc: TDelayedLoadHook): TDelayedLoadHook;
var
  Previous: Pointer;
begin
  repeat
    Previous := InterlockedCompareExchangePointer(__pfnDliNotifyHook2, nil, nil);
  until InterlockedCompareExchangePointer(__pfnDliNotifyHook2, Pointer(HookProc), Previous) = Previous;
  Result := TDelayedLoadHook(Previous);
end;

function SetDliFailureHook2(HookProc: TDelayedLoadHook): TDelayedLoadHook;
var
  Previous: Pointer;
begin
  repeat
    Previous := InterlockedCompareExchangePointer(__pfnDliFailureHook2, nil, nil);
  until InterlockedCompareExchangePointer(__pfnDliFailureHook2, Pointer(HookProc), Previous) = Previous;
  Result := TDelayedLoadHook(Previous);
end;

procedure LockDelayed(Entry: PDelayedEntry);
var
  ThreadId, Previous: Longint;
begin
  ThreadId := Longint(DelayThreadId);
  repeat
    Previous := InterlockedCompareExchange(Entry^.Owner, ThreadId, 0);
    If Previous = 0 then
      Exit;
    If Previous = ThreadId then
      DelayRaise($C06D045A, 1, 0, nil); { recursive resolution of the same import }
    DelaySleep(0);
  until False;
end;

function ResolveDelayed(Entry: PDelayedEntry): Pointer;
var
  Info: TDelayLoadInfo;
  Descriptor: TImgDelayDescr;
  Hook: TDelayedLoadHook;
  Argument: Pointer;

  function Notify(Kind: dliNotification; Failure: Boolean = False): Pointer;
  begin
    If Failure then
      Hook := DliFailureHook2
    else
      Hook := DliNotifyHook2;
    If Assigned(Hook) then
      Result := Hook(Kind, @Info)
    else
      Result := nil;
  end;

  procedure Fail(Code: DWord);
  begin
    Argument := @Info;
    DelayRaise($C06D0000 or Code, 1, 1, @Argument);
  end;

begin
  LockDelayed(Entry);
  try
    If Entry^.Target <> Entry^.Initial then
      Exit(Entry^.Target);
    Descriptor := Default(TImgDelayDescr);
    Descriptor.szName := Entry^.Dll;
    Descriptor.hmod := THandle(@Entry^.Handle);
    Descriptor.pIAT := PImageThunkData(@Entry^.Target);
    Descriptor.pINT := PImageThunkData(@Entry^.Import);
    Descriptor.pUnloadIAT := PImageThunkData(@Entry^.Initial);
    Info := Default(TDelayLoadInfo);
    Info.cb := SizeOf(Info);
    Info.pidd := @Descriptor;
    Info.ppfn := @Entry^.Target;
    Info.szDll := Entry^.Dll;
    Info.hmodCur := Entry^.Handle;
    Info.dlp.fImportByName := (Entry^.Import and (PtrUInt(1) shl 63)) = 0;
    If Info.dlp.fImportByName then
      Info.dlp.szProcName := PAnsiChar(Entry^.Import + 2)
    else
      Info.dlp.dwOrdinal := Entry^.Import and $FFFF;
    Result := Notify(dliStartProcessing);
    If Result = nil then begin
      If Entry^.Handle = 0 then begin
        Entry^.Handle := THandle(Notify(dliNotePreLoadLibrary));
        If Entry^.Handle = 0 then
          Entry^.Handle := DelayLoadLibrary(Entry^.Dll);
        If Entry^.Handle = 0 then begin
          Info.dwLastError := DelayGetError;
          Entry^.Handle := THandle(Notify(dliFailLoadLibrary, True));
          If Entry^.Handle = 0 then
            Fail(126);
        end;
      end;
      Info.hmodCur := Entry^.Handle;
      Result := Notify(dliNotePreGetProcAddress);
      If Result = nil then begin
        If Info.dlp.fImportByName then
          Result := DelayGetProcAddress(Entry^.Handle, Info.dlp.szProcName)
        else
          Result := DelayGetProcAddress(Entry^.Handle, PAnsiChar(PtrUInt(Info.dlp.dwOrdinal)));
        If Result = nil then begin
          Info.dwLastError := DelayGetError;
          Result := Notify(dliFailGetProcAddress, True);
          If Result = nil then
            Fail(127);
        end;
      end;
    end;
    Info.pfnCur := Result;
    Notify(dliNoteEndProcessing);
    InterlockedCompareExchangePointer(Entry^.Target, Result, Entry^.Initial);
  finally
    InterlockedExchange(Entry^.Owner, 0);
  end;
end;

procedure DelayedEntries(out Entries: PDelayedEntry; out Count: SizeUInt);
var
  Module: THandle;
  Image, Nt, Section: PByte;
  I, SectionCount: Word;
begin
  Entries := nil;
  Count := 0;
  If not DelayGetModuleHandle(6, @ResolveDelayed, Module) then
    Exit;
  Image := PByte(Module);
  Nt := Image + PDWord(Image + $3C)^;
  SectionCount := PWord(Nt + 6)^;
  Section := Nt + 24 + PWord(Nt + 20)^;
  for I := 1 to SectionCount do begin
    If PUInt64(Section)^ = $79616C6564636D2E then begin { '.mcdelay' }
      Entries := PDelayedEntry(Image + PDWord(Section + 12)^);
      Count := PDWord(Section + 8)^ div SizeOf(TDelayedEntry);
      Exit;
    end;
    Inc(Section, 40);
  end;
end;

procedure LoadAllImportsForDll(szDll: PAnsiChar); stdcall;
var
  Entry: PDelayedEntry;
  Count: SizeUInt;
begin
  DelayedEntries(Entry, Count);
  while Count <> 0 do begin
    If (szDll = nil) or (DelayNameCompare(szDll, Entry^.Dll) = 0) then
      ResolveDelayed(Entry);
    Inc(Entry);
    Dec(Count);
  end;
end;

procedure UnloadDelayLoadedDLL2(szDll: PAnsiChar); stdcall;
var
  Entry: PDelayedEntry;
  Count: SizeUInt;
  Handle: THandle;
begin
  DelayedEntries(Entry, Count);
  while Count <> 0 do begin
    If (szDll = nil) or (DelayNameCompare(szDll, Entry^.Dll) = 0) then begin
      LockDelayed(Entry);
      try
        Handle := Entry^.Handle;
        Entry^.Handle := 0;
        InterlockedCompareExchangePointer(Entry^.Target, Entry^.Initial, Entry^.Target);
        If Handle <> 0 then
          DelayFreeLibrary(Handle);
      finally
        InterlockedExchange(Entry^.Owner, 0);
      end;
    end;
    Inc(Entry);
    Dec(Count);
  end;
end;

{$asmmode att}
procedure DelayLoadEntry; assembler; nostackframe; public name 'FPC_DELAY_LOAD';
asm
  subq $136, %rsp
  .seh_stackalloc 136
  .seh_endprologue
  movq %rcx, 32(%rsp)
  movq %rdx, 40(%rsp)
  movq %r8, 48(%rsp)
  movq %r9, 56(%rsp)
  movdqu %xmm0, 64(%rsp)
  movdqu %xmm1, 80(%rsp)
  movdqu %xmm2, 96(%rsp)
  movdqu %xmm3, 112(%rsp)
  movq %rax, %rcx
  call ResolveDelayed
  nop
  movq 32(%rsp), %rcx
  movq 40(%rsp), %rdx
  movq 48(%rsp), %r8
  movq 56(%rsp), %r9
  movdqu 64(%rsp), %xmm0
  movdqu 80(%rsp), %xmm1
  movdqu 96(%rsp), %xmm2
  movdqu 112(%rsp), %xmm3
  addq $136, %rsp
  jmp *%rax
end;
{$pop}
