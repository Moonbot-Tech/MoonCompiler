program getprocaddress_unicode_semantic;
{ %TARGET=win64 }
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses Windows;
var
  H: HMODULE;
  A: AnsiString;
  W: UnicodeString;
  P: Pointer;
begin
  H := GetModuleHandle('kernel32.dll');
  If H = 0 then Halt(11);
  A := 'GetProcessHeap';
  W := UnicodeString(A);
  P := Pointer(GetProcAddress(H, LPCSTR(A)));
  If P = nil then Halt(12);
  If Pointer(GetProcAddress(H, LPCWSTR(W))) <> P then Halt(13);
  If GetProcAddress(H, LPCWSTR('MoonCompilerMissingExport')) <> nil then Halt(14);
  If Pointer(GetProcAddress(H, LPCWSTR(1))) <> Pointer(GetProcAddress(H, LPCSTR(1))) then Halt(15);
  WriteLn('GETPROCADDRESS_UNICODE_SEMANTIC_PASS');
end.
