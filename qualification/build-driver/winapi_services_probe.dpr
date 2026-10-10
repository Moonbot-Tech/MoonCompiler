program winapi_services_probe;

uses Windows;

var
  Info: TMemoryStatusEx;
  Raw: MEMORYSTATUSEX;
  InfoPointer: PMemoryStatusEx;
  Window: HWND;
begin
  If (SizeOf(Info) <> 64) or (SizeOf(Raw) <> 64) then Halt(1);
  If (NativeUInt(@Info.ullTotalPhys) - NativeUInt(@Info) <> 8) or
     (NativeUInt(@Info.ullAvailExtendedVirtual) - NativeUInt(@Info) <> 56) then Halt(2);
  FillChar(Info, SizeOf(Info), 0);
  Info.dwLength := SizeOf(Info);
  If not GlobalMemoryStatusEx(Info) then Halt(3);
  InfoPointer := @Raw;
  FillChar(Raw, SizeOf(Raw), 0);
  Raw.dwLength := SizeOf(Raw);
  If not GlobalMemoryStatusEx(InfoPointer) then Halt(4);
  If (Info.ullTotalPhys = 0) or (Info.ullAvailPhys > Info.ullTotalPhys) or
     (Info.dwMemoryLoad > 100) or (Raw.ullTotalPhys <> Info.ullTotalPhys) then Halt(5);
  SetLastError(0);
  If CancelSynchronousIo(INVALID_HANDLE_VALUE) or (GetLastError <> ERROR_INVALID_HANDLE) then Halt(6);
  SetLastError(0);
  If CancelSynchronousIo(GetCurrentThread) or (GetLastError <> ERROR_NOT_FOUND) then Halt(7);
  Window := CreateWindowExW(0, 'STATIC', 'sdk-test', 0, 0, 0, 0, 0, HWND_MESSAGE, 0, GetModuleHandle(nil), nil);
  If Window = 0 then Halt(8);
  try
    If not AddClipboardFormatListener(Window) then Halt(9);
    If not RemoveClipboardFormatListener(Window) then Halt(10);
    If RemoveClipboardFormatListener(Window) then Halt(11);
  finally
    DestroyWindow(Window);
  end;
  Writeln('WINAPI_SERVICES_OK');
end.
