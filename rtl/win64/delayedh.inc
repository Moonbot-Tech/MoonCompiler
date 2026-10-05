{ Public delay-load contracts; implemented independently of Delphi. }
type
  PImageThunkData = ^TImageThunkData;
  TImageThunkData = record
    case Byte of
      0: (ForwarderString: NativeUInt);
      1: (_Function: NativeUInt);
      2: (Ordinal: NativeUInt);
      3: (AddressOfData: NativeUInt);
  end;
  ImgDelayDescr = record
    grAttrs: LongWord;
    szName: PAnsiChar;
    hmod: THandle;
    pIAT, pINT, pBoundIAT, pUnloadIAT: PImageThunkData;
    dwTimeStamp: LongWord;
  end;
  TImgDelayDescr = ImgDelayDescr;
  PImgDelayDescr = ^TImgDelayDescr;
  dliNotification = (dliStartProcessing, dliNoteStartProcessing = dliStartProcessing,
    dliNotePreLoadLibrary, dliNotePreGetProcAddress, dliFailLoadLibrary,
    dliFailGetProcAddress, dliNoteEndProcessing);
  DelayLoadProc = record
    fImportByName: LongBool;
    case Byte of
      0: (szProcName: PAnsiChar);
      1: (dwOrdinal: LongWord);
  end;
  TDelayLoadProc = DelayLoadProc;
  PDelayLoadProc = ^TDelayLoadProc;
  DelayLoadInfo = record
    cb: LongWord;
    pidd: PImgDelayDescr;
    ppfn: Pointer;
    szDll: PAnsiChar;
    dlp: TDelayLoadProc;
    hmodCur: THandle;
    pfnCur: Pointer;
    dwLastError: LongWord;
  end;
  TDelayLoadInfo = DelayLoadInfo;
  PDelayLoadInfo = ^TDelayLoadInfo;
  PfnDliHook = function(Notification: dliNotification; Info: PDelayLoadInfo): Pointer; stdcall;
  TDelayedLoadHook = PfnDliHook;
var
  __pfnDliNotifyHook2: Pointer;
  __pfnDliFailureHook2: Pointer;
function SetDliNotifyHook2(HookProc: TDelayedLoadHook): TDelayedLoadHook;
function DliNotifyHook2: TDelayedLoadHook;
function SetDliFailureHook2(HookProc: TDelayedLoadHook): TDelayedLoadHook;
function DliFailureHook2: TDelayedLoadHook;
procedure UnloadDelayLoadedDLL2(szDll: PAnsiChar); stdcall;
procedure LoadAllImportsForDll(szDll: PAnsiChar); stdcall;
