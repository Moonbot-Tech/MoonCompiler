{ Supplemental scalar SDK types shared by the direct Windows headers. }
unit Winapi.Support;
{$mode delphi}
interface
uses Windows, WinSock2;
type
  ALG_ID = UInt32;
  NTSTATUS = LongInt;
  PHMODULE = ^HMODULE;
  LPLPVOID = ^Pointer;
  PPSID = ^PSID;
  PPACL = ^PACL;
  POBJECT_TYPE_LIST = ^OBJECT_TYPE_LIST;
  in6_addr = TIn6Addr;
  SecHandle = record
    dwLower, dwUpper: NativeUInt;
  end;
  PSecHandle = ^SecHandle;
const
  SEC_E_LOGON_DENIED = HRESULT($8009030C);
  SEC_E_NO_CREDENTIALS = HRESULT($8009030E);
  ERROR_DOWNGRADE_DETECTED = 1265;
  ERROR_AUTHENTICATION_FIREWALL_FAILED = 1935;

function HRESULT_FROM_WIN32(Code: LongInt): HRESULT; inline;
function HRESULT_FROM_NT(Code: NTSTATUS): HRESULT; inline;
implementation
function HRESULT_FROM_WIN32(Code: LongInt): HRESULT;
begin
  if Code <= 0 then
    Result := Code
  else
    Result := HRESULT((UInt32(Code) and $FFFF) or $80070000);
end;

function HRESULT_FROM_NT(Code: NTSTATUS): HRESULT;
begin
  Result := HRESULT(UInt32(Code) or $10000000);
end;
end.
