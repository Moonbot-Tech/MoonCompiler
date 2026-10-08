program windows_boundaries_semantic;
{$APPTYPE CONSOLE}
{$mode delphiunicode}
{ %TARGET=win64 }
uses SysUtils, Classes, DateUtils, SyncObjs, System.IOUtils, Windows, Registry;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
function HandleCount(Process: THandle; var Count: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'GetProcessHandleCount';

procedure CheckText;
var
  Name, Value, Expected, S: string;
  I: Integer;
  Found: Boolean;
  WindowsPath: array[0..MAX_PATH] of WideChar;
  TZ: TTimeZoneInformation;
begin
  SetMultiByteConversionCodePage(1251);
  Name:='MOON_RTL240_'+IntToStr(GetCurrentProcessId);
  Value:=UnicodeChar($03BB)+UnicodeChar($4E2D);
  Check(SetEnvironmentVariableW(PWideChar(Name),PWideChar(Value)),'set own environment');
  try
    Check(GetEnvironmentVariable(Name)=Value,'environment lookup');
    Expected:=Name+'='+Value;
    Found:=False;
    for I:=1 to GetEnvironmentVariableCount do
    begin
      S:=GetEnvironmentString(I);
      if Pos(Name+'=',S)=1 then
      begin
        Found:=True;
        Check(S=Expected,'environment enumeration preserves Unicode');
      end;
    end;
    Check(Found,'environment entry enumerated');
  finally SetEnvironmentVariableW(PWideChar(Name),nil); end;
  Check(GetWindowsDirectoryW(WindowsPath,Length(WindowsPath))>0,'Windows directory native');
  Check(ExcludeTrailingPathDelimiter(SysConfigDir)=string(PWideChar(@WindowsPath[0])),'SysConfigDir Unicode storage');
  FillChar(TZ,SizeOf(TZ),0);
  Check(GetTimeZoneInformation(TZ)<>DWORD($FFFFFFFF),'timezone native');
  Check(TTimeZone.Local.ID=string(PWideChar(@TZ.StandardName[0])),'complete timezone ID');
end;

procedure CheckNames;
var Name: string; First, Second: TEvent; Handle: THandle;
begin
  Name:='Local\MOON_RTL240_'+IntToStr(GetCurrentProcessId)+'_';
  First:=TEvent.Create(nil,True,False,Name+UnicodeChar($03BB));
  Second:=TEvent.Create(nil,True,False,Name+UnicodeChar($03BC));
  try
    First.SetEvent;
    Check(Second.WaitFor(0)=wrTimeout,'Unicode events must not alias');
    Handle:=OpenEventW(SYNCHRONIZE,False,PWideChar(Name+UnicodeChar($03BB)));
    Check(Handle<>0,'event exact Unicode name');
    try Check(WaitForSingleObject(Handle,0)=WAIT_OBJECT_0,'native event identity');
    finally CloseHandle(Handle); end;
  finally
    Second.Free;
    First.Free;
  end;
end;

procedure CheckSharing;
var Path: string; First, Second: TFileStream; Share: TFileShare; Access: TFileAccess; Opened: Boolean;
begin
  Path:=TPath.GetTempFileName;
  try
    for Share:=TFileShare.fsNone to TFileShare.fsReadWrite do
    begin
      First:=TFile.Open(Path,TFileMode.fmOpen,TFileAccess.faRead,Share);
      try
        for Access:=TFileAccess.faRead to TFileAccess.faReadWrite do
        begin
          Opened:=False;
          try
            Second:=TFile.Open(Path,TFileMode.fmOpen,Access,TFileShare.fsReadWrite);
            Second.Free;
            Opened:=True;
          except on E: EFOpenError do ; end;
          Check(Opened=((Share=TFileShare.fsReadWrite) or
            ((Share=TFileShare.fsRead) and (Access=TFileAccess.faRead)) or
            ((Share=TFileShare.fsWrite) and (Access=TFileAccess.faWrite))),'file share/access matrix');
        end;
      finally First.Free; end;
    end;
  finally SysUtils.DeleteFile(Path); end;
end;

procedure CheckRegistry;
var Reg: TRegistry; I: Integer; Before, After: DWORD; Lazy: Boolean;
begin
  Reg:=TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:=HKEY_CURRENT_USER;
    for Lazy:=False to True do
    begin
      Reg.LazyWrite:=Lazy;
      Check(Reg.OpenKeyReadOnly('Software'),'registry warmup');
      Reg.CloseKey;
      Check(HandleCount(GetCurrentProcess,Before),'count handles before');
      for I:=1 to 24 do
      begin
        Check(Reg.OpenKeyReadOnly('Software'),'registry reopen');
        Reg.CloseKey;
      end;
      Check(HandleCount(GetCurrentProcess,After),'count handles after');
      Check(After<=Before+2,'registry close leaked handles');
    end;
  finally Reg.Free; end;
end;

type
  TAbandon = class(TThread)
    Mutex: TMutex;
    procedure Execute; override;
  end;
procedure TAbandon.Execute;
begin
  Check(Mutex.WaitFor(5000)=wrSignaled,'owner acquires mutex');
end;

procedure CheckAbandoned;
var Mutex: TMutex; Other: TEvent; Owner: TAbandon; Selected: THandleObject; Kind: Integer;
begin
  for Kind:=0 to 1 do
  begin
    Mutex:=TMutex.Create(nil,False,'');
    Other:=TEvent.Create(nil,True,False,'');
    Owner:=TAbandon.Create(True);
    try
      Owner.Mutex:=Mutex;
      Owner.Start;
      Owner.WaitFor;
      Check(Owner.FatalException=nil,'owner thread completed');
      if Kind=0 then
        Check(Mutex.WaitFor(0)=wrAbandoned,'single abandoned result')
      else
      begin
        Selected:=nil;
        Check(THandleObject.WaitForMultiple([Other,Mutex],0,False,Selected)=wrAbandoned,'multiple abandoned result');
        Check(Selected=Mutex,'abandoned index translated');
      end;
      Mutex.Release;
    finally
      Owner.Free;
      Other.Free;
      Mutex.Free;
    end;
  end;
end;

var CapturedCOM: Boolean;
function CaptureWait(Timeout: Cardinal; State: PEventState; UseCOM: Boolean=False): LongInt;
begin
  CapturedCOM:=UseCOM;
  Result:=Ord(wrTimeout);
end;
procedure CheckCOM;
var Saved, Hooked: TThreadManager; Event: TEvent; UseCOM: Boolean;
begin
  GetThreadManager(Saved);
  Hooked:=Saved;
  Hooked.BasicEventWaitFor:=@CaptureWait;
  SetThreadManager(Hooked);
  try
    for UseCOM:=False to True do
    begin
      Event:=TEvent.Create(nil,True,False,'',UseCOM);
      try
        CapturedCOM:=not UseCOM;
        Check(Event.WaitFor(0)=wrTimeout,'wait handler result');
        Check(CapturedCOM=UseCOM,'COM wait option reached backend');
      finally Event.Free; end;
    end;
  finally SetThreadManager(Saved); end;
end;

begin
  CheckText;
  CheckNames;
  CheckSharing;
  CheckRegistry;
  CheckAbandoned;
  CheckCOM;
  WriteLn('WINDOWS_BOUNDARIES_PASS');
end.
