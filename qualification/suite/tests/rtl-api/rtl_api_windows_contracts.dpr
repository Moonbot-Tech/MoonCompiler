program rtl_api_windows_contracts;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$CODEPAGE UTF8}{$ENDIF}
uses System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows, Winapi.PsAPI,
  Winapi.TlHelp32, Winapi.WinSvc, Winapi.WinSock2, Winapi.WinCred, Winapi.AccCtrl, Winapi.IpTypes, Winapi.IpRtrMib,
  Winapi.IpExport, Winapi.WTSApi32, Winapi.UserEnv, Winapi.Qos, Winapi.Cpl, Winapi.AclAPI;
procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;
procedure CheckCredentialPointers;
var
  Info: CERT_CREDENTIAL_INFO;
  TextA: PAnsiChar;
  TextW: PWideChar;
  Output: Pointer;
  Kind: CRED_MARSHAL_TYPE;
begin
  { Serialize a fabricated certificate hash. Never access the credential store. }
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Info.rgbHashOfCert[0] := 73;
  TextA := nil;
  Check(CredMarshalCredentialA(CertCredential, @Info, TextA), 'ANSI credential marshal output');
  try
    Output := nil;
    Check(CredUnmarshalCredentialA(TextA, @Kind, Output), 'ANSI credential unmarshal output');
    try
      Check((Kind = CertCredential) and CompareMem(@Info, Output, SizeOf(Info)), 'ANSI credential round trip');
    finally
      CredFree(Output);
    end;
  finally
    CredFree(TextA);
  end;
  TextW := nil;
  Check(CredMarshalCredentialW(CertCredential, @Info, TextW), 'wide credential marshal output');
  try
    Output := nil;
    Check(CredUnmarshalCredentialW(TextW, @Kind, Output), 'wide credential unmarshal output');
    try
      Check((Kind = CertCredential) and CompareMem(@Info, Output, SizeOf(Info)), 'wide credential round trip');
    finally
      CredFree(Output);
    end;
  finally
    CredFree(TextW);
  end;
end;
procedure CheckDiskOverloads;
type
  TSignedWideQuery = function(Path: PWideChar; A,B,C: PLargeInteger): BOOL; stdcall;
  TUnsignedWideQuery = function(Path: PWideChar; A,B,C: PULargeInteger): BOOL; stdcall;
  TSignedAnsiQuery = function(Path: PAnsiChar; A,B,C: PLargeInteger): BOOL; stdcall;
  TUnsignedAnsiQuery = function(Path: PAnsiChar; A,B,C: PULargeInteger): BOOL; stdcall;
var
  SignedWideQuery: TSignedWideQuery;
  UnsignedWideQuery: TUnsignedWideQuery;
  SignedAnsiQuery: TSignedAnsiQuery;
  UnsignedAnsiQuery: TUnsignedAnsiQuery;
  SignedFree, SignedTotal, SignedAll: Int64;
  FreeBytes, TotalBytes, AllBytes: TULargeInteger;
  SignedPointer: PLargeInteger;
  UnsignedPointer: PULargeInteger;
  Path: string;
  PathA: AnsiString;
begin
  Path:=GetEnvironmentVariable('TEMP');
  PathA:=AnsiString(Path);
  SignedPointer:=@SignedFree;
  UnsignedPointer:=@FreeBytes;
  Check(GetDiskFreeSpaceEx(PChar(Path),FreeBytes,TotalBytes,@AllBytes),'unsigned generic var disk space');
  Check((FreeBytes>0) and (TotalBytes>=AllBytes) and (AllBytes>=FreeBytes),'unsigned disk values');
  Check(GetDiskFreeSpaceExW(PWideChar(Path),FreeBytes,TotalBytes,nil),'unsigned wide var with nil');
  Check(GetDiskFreeSpaceExA(PAnsiChar(PathA),FreeBytes,TotalBytes,@AllBytes),'unsigned ANSI var disk space');
  Check(GetDiskFreeSpaceEx(PChar(Path),SignedFree,SignedTotal,@SignedAll),'signed generic var disk space');
  Check(GetDiskFreeSpaceExW(PWideChar(Path),SignedFree,SignedTotal,nil),'signed wide var with nil');
  Check(GetDiskFreeSpaceExA(PAnsiChar(PathA),SignedFree,SignedTotal,@SignedAll),'signed ANSI var disk space');
  Check((SignedFree>0) and (SignedTotal=Int64(TotalBytes)),'same disk through signed and unsigned ABI');
  Check(GetDiskFreeSpaceEx(PChar(Path),SignedPointer,nil,nil),'typed signed pointer');
  Check(GetDiskFreeSpaceExW(PWideChar(Path),UnsignedPointer,nil,nil),'typed unsigned pointer');
  Check(GetDiskFreeSpaceExA(PAnsiChar(PathA),nil,@TotalBytes,nil),'optional pointer outputs');
  Check(GetDiskFreeSpaceEx(PChar(Path),nil,nil,nil),'all disk outputs optional');
  SignedWideQuery:=GetDiskFreeSpaceEx;
  UnsignedWideQuery:=GetDiskFreeSpaceEx;
  Check(SignedWideQuery(PWideChar(Path),SignedPointer,nil,nil),'signed generic function pointer');
  Check(UnsignedWideQuery(PWideChar(Path),UnsignedPointer,nil,nil),'unsigned generic function pointer');
  SignedWideQuery:=GetDiskFreeSpaceExW;
  UnsignedWideQuery:=GetDiskFreeSpaceExW;
  Check(SignedWideQuery(PWideChar(Path),SignedPointer,nil,nil),'signed wide function pointer');
  Check(UnsignedWideQuery(PWideChar(Path),UnsignedPointer,nil,nil),'unsigned wide function pointer');
  SignedAnsiQuery:=GetDiskFreeSpaceExA;
  UnsignedAnsiQuery:=GetDiskFreeSpaceExA;
  Check(SignedAnsiQuery(PAnsiChar(PathA),SignedPointer,nil,nil),'signed ANSI function pointer');
  Check(UnsignedAnsiQuery(PAnsiChar(PathA),UnsignedPointer,nil,nil),'unsigned ANSI function pointer');
end;

procedure CheckNativeOutputWidths;
var
  Source, Dest: Integer;
  Guard: record Count: SIZE_T; Canary: UInt64; end;
  Descriptor: SECURITY_DESCRIPTOR;
  AccessList, AuditList: PEXPLICIT_ACCESS_W;
  AccessCount, AuditCount: ULONG;
  Args: array[0..1] of PWideChar;
begin
  Source := 73;
  Dest := 0;
  Guard.Count := 0;
  Guard.Canary := $1122334455667788;
  Check(Toolhelp32ReadProcessMemory(GetCurrentProcessId, @Source, @Dest, SizeOf(Source), @Guard.Count),
    'read own process memory');
  Check((Dest = Source) and (Guard.Count = SizeOf(Source)) and (Guard.Canary = $1122334455667788),
    'native-sized byte count preserves adjacent memory');
  Check(InitializeSecurityDescriptor(@Descriptor, SECURITY_DESCRIPTOR_REVISION), 'initialize private descriptor');
  AccessList := nil;
  AuditList := nil;
  Check(LookupSecurityDescriptorPartsW(nil, nil, @AccessCount, AccessList, @AuditCount, AuditList,
    Descriptor) = ERROR_SUCCESS, 'ACL output pointer depth');
  try
    Check((AccessCount = 0) and (AuditCount = 0), 'private descriptor has no entries');
  finally
    LocalFree(HLOCAL(AccessList));
    LocalFree(HLOCAL(AuditList));
  end;
  Args[0] := 'first';
  Args[1] := 'second';
  { Invalid handle exercises both signatures without starting a real service. }
  Check(not StartServiceW(0, Length(Args), @Args[0]), 'service pointer-array form');
  Check(not StartServiceW(0, Length(Args), Args[0]), 'service var-array form');
end;
var
  Folder, FileName, DllPath: string;
  Handle, Snapshot, Manager: THandle;
  Counters: TProcessMemoryCounters;
  Entry: TThreadEntry32;
  FindData: TWin32FindData;
  FreeBytes, TotalBytes, TotalFree: Int64;
  Bytes, Unused: DWORD;
  Buffer: array[0..32767] of Char;
  Event: WSAEVENT;
  Network: TWSAData;
  SocketHandle: TSocket;
  Events: TWSANetworkEvents;
  OldFilter: TFNTopLevelExceptionFilter; Credential: CREDENTIALW; Adapter: IP_ADAPTER_INFO;
  CharTypes: array[0..2] of Word;
  RegistryKey: HKEY;
  RegistryPath: string;
begin
  CheckDiskOverloads;
  CheckCredentialPointers;
  CheckNativeOutputWidths;
  Check(GetStringTypeW(CT_CTYPE1, PWideChar('aЖ9'), 3, CharTypes[0]), 'wide character classification');
  Check(((CharTypes[0] and C1_ALPHA) <> 0) and ((CharTypes[1] and C1_ALPHA) <> 0) and
    ((CharTypes[2] and C1_DIGIT) <> 0), 'classification writes one word per UTF-16 unit');
  RegistryPath := 'Software\Moon-RTL-тест-' + IntToStr(GetCurrentProcessId);
  Check(RegCreateKeyEx(HKEY_CURRENT_USER, PChar(RegistryPath), 0, nil, 0, KEY_READ, nil,
    RegistryKey, nil) = ERROR_SUCCESS, 'generic Unicode registry create var form');
  RegCloseKey(RegistryKey);
  try
    Check(RegOpenKeyExW(HKEY_CURRENT_USER, PWideChar(RegistryPath), 0, KEY_READ, @RegistryKey) = ERROR_SUCCESS,
      'registry key keeps its Unicode name');
    RegCloseKey(RegistryKey);
  finally
    RegDeleteKeyW(HKEY_CURRENT_USER, PWideChar(RegistryPath));
  end;
  { Values independently checked with platform_abi_oracle.c and Win64 SDK headers. }
  Check((SizeOf(TProcessMemoryCounters) = 72) and (SizeOf(TThreadEntry32) = 28), 'process and thread ABI');
  Check((SizeOf(CREDENTIALW) = 80) and (NativeUInt(@Credential.CredentialBlob) - NativeUInt(@Credential) = 40),
    'credential ABI');
  Check((SizeOf(SERVICE_STATUS) = 28) and (SizeOf(SERVICE_STATUS_PROCESS) = 36), 'service ABI');
  Check((SizeOf(TRUSTEE_W) = 32) and (SizeOf(EXPLICIT_ACCESS_W) = 48), 'ACL ABI');
  Check((SizeOf(IP_ADAPTER_INFO) = 704) and (SizeOf(IP_ADDR_STRING) = 48) and
    (NativeUInt(@Adapter.LeaseObtained) - NativeUInt(@Adapter) = 688), 'adapter ABI');
  Check((SizeOf(MIB_IPADDRTABLE) = 28) and (SizeOf(MIB_IFROW) = 860), 'IP routing ABI');
  Check((SizeOf(WTS_SESSION_INFOW) = 24) and (SizeOf(PROFILEINFOW) = 56), 'session and profile ABI');
  Check((SizeOf(Winapi.WinSock2.QOS) = 80) and (SizeOf(CPLINFO) = 20), 'QoS and control-panel ABI');
  Check((SizeOf(IP_OPTION_INFORMATION) = 16) and (SizeOf(ICMP_ECHO_REPLY) = 40), 'ICMP ABI');
  Folder := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'Moon-RTL-тест-' + IntToStr(GetCurrentProcessId);
  Check(CreateDirectory(PChar(Folder), nil), 'Unicode directory');
  FileName := Folder + '\данные.txt';
  try
    Handle := CreateFile(PChar(FileName), GENERIC_WRITE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    Check(Handle <> INVALID_HANDLE_VALUE, 'Unicode CreateFile');
    Check(CloseHandle(Handle), 'close file');
    Handle := FindFirstFile(PChar(Folder + '\*'), FindData);
    Check(Handle <> INVALID_HANDLE_VALUE, 'Unicode FindFirstFile');
    Winapi.Windows.FindClose(Handle);
    Check(GetDiskFreeSpaceEx(PChar(Folder), FreeBytes, TotalBytes, @TotalFree), 'Unicode disk space var form');
    Check((FreeBytes > 0) and (TotalBytes >= FreeBytes), 'disk space values');
    Check(GetDiskFreeSpaceEx(PChar(Folder), @FreeBytes, @TotalBytes, @TotalFree), 'Unicode disk space pointer form');
    Check(SetDllDirectory(PChar(Folder)), 'Unicode SetDllDirectory');
    try
      Bytes := GetDllDirectory(Length(Buffer), @Buffer[0]);
      Check((Bytes = DWORD(Length(Folder))) and (string(PChar(@Buffer[0])) = Folder), 'Unicode DLL directory');
    finally
      Check(SetDllDirectory(nil), 'restore DLL search');
    end;
    Bytes := GetSystemDirectory(@Buffer[0], Length(Buffer));
    Check((Bytes > 0) and (Bytes < Length(Buffer)), 'system directory');
    DllPath := string(PChar(@Buffer[0])) + '\kernel32.dll';
    Check(GetFileVersionInfoSize(PChar(DllPath), Unused) > 0, 'version resource var form');
    {$IFDEF FPC}
    Check(GetFileVersionInfoSize(PChar(DllPath), @Unused) > 0, 'version resource pointer form');
    {$ENDIF}
  finally
    DeleteFile(PChar(FileName));
    RemoveDirectory(PChar(Folder));
  end;
  FillChar(Counters, SizeOf(Counters), 0);
  Counters.cb := SizeOf(Counters);
  Check(GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)), 'process memory pointer');
  Check(Counters.WorkingSetSize > 0, 'working set');
  Check(EnumProcesses(@Buffer[0], SizeOf(Buffer), Bytes) and (Bytes >= 4), 'process enumeration');
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  Check(Snapshot <> INVALID_HANDLE_VALUE, 'thread snapshot');
  try
    Entry.dwSize := SizeOf(Entry);
    Check(Thread32First(Snapshot, Entry), 'first thread');
  finally
    CloseHandle(Snapshot);
  end;
  Manager := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  Check(Manager <> 0, 'service manager');
  CloseServiceHandle(Manager);
  Check(WSAStartup($0202, Network) = 0, 'Winsock startup');
  try
    Event := WSACreateEvent;
    Check(Event <> WSA_INVALID_EVENT, 'Winsock event');
    SocketHandle:=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
    Check(SocketHandle<>INVALID_SOCKET,'create event socket');
    try
      Check(WSAEventSelect(SocketHandle,Event,FD_READ or FD_CLOSE)=0,'subscribe socket events');
      FillChar(Events,SizeOf(Events),$FF);
      Check(WSAEnumNetworkEvents(SocketHandle,Event,Events)=0,'socket events var record');
      Check(Events.lNetworkEvents=0,'no events on unconnected socket');
      FillChar(Events,SizeOf(Events),$FF);
      Check(WSAEnumNetworkEvents(SocketHandle,Event,@Events)=0,'socket events pointer');
      Check(Events.lNetworkEvents=0,'pointer event record written');
    finally
      closesocket(SocketHandle);
      Check(WSACloseEvent(Event), 'Winsock event close');
    end;
  finally
    WSACleanup;
  end;
  OldFilter := SetUnhandledExceptionFilter(nil);
  SetUnhandledExceptionFilter(OldFilter);
  Writeln('RTL_API_WINDOWS_CONTRACTS_OK');
end.
