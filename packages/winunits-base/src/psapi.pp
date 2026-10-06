{******************************************************************************}
{                                                                              }
{ Process Status API interface Unit for Object Pascal                          }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: psapi.h, released June 2000. The original Pascal       }
{ code is: PsApi.pas, released December 2000. The initial developer of the     }
{ Pascal code is Marcel van Brakel (brakelm att chello dott nl).               }
{                                                                              }
{ Portions created by Marcel van Brakel are Copyright (C) 1999-2001            }
{ Marcel van Brakel. All Rights Reserved.                                      }
{                                                                              }
{ Obtained through: Joint Endeavour of Delphi Innovators (Project JEDI)        }
{                                                                              }
{ You may retrieve the latest version of this file at the Project JEDI         }
{ APILIB home page, located at http://jedi-apilib.sourceforge.net              }
{                                                                              }
{ The contents of this file are used with permission, subject to the Mozilla   }
{ Public License Version 1.1 (the "License"); you may not use this file except }
{ in compliance with the License. You may obtain a copy of the License at      }
{ http://www.mozilla.org/MPL/MPL-1.1.html                                      }
{                                                                              }
{ Software distributed under the License is distributed on an "AS IS" basis,   }
{ WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for }
{ the specific language governing rights and limitations under the License.    }
{                                                                              }
{ Alternatively, the contents of this file may be used under the terms of the  }
{ GNU Lesser General Public License (the  "LGPL License"), in which case the   }
{ provisions of the LGPL License are applicable instead of those above.        }
{ If you wish to allow use of your version of this file only under the terms   }
{ of the LGPL License and not to allow others to use your version of this file }
{ under the MPL, indicate your decision by deleting  the provisions above and  }
{ replace  them with the notice and other provisions required by the LGPL      }
{ License.  If you do not delete the provisions above, a recipient may use     }
{ your version of this file under either the MPL or the LGPL License.          }
{                                                                              }
{ For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html }
{                                                                              }
{******************************************************************************}

// $Id: PsAPI.pas,v 1.12 2007/09/05 11:58:52 dezipaitor Exp $
unit PsAPI;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses Winapi.Support, Windows;

function EnumProcesses(lpidProcess: LPDWORD; cb: DWORD; var cbNeeded: DWORD): BOOL; stdcall;

function EnumProcessModules(hProcess: HANDLE; lphModule: PHMODULE; cb: DWORD;
  var lpcbNeeded: DWORD): BOOL; stdcall;

function GetModuleBaseNameA(hProcess: HANDLE; hModule: HMODULE; lpBaseName: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetModuleBaseNameW(hProcess: HANDLE; hModule: HMODULE; lpBaseName: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetModuleBaseName(hProcess: HANDLE; hModule: HMODULE; lpBaseName: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

function GetModuleFileNameExA(hProcess: HANDLE; hModule: HMODULE; lpFilename: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetModuleFileNameExW(hProcess: HANDLE; hModule: HMODULE; lpFilename: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetModuleFileNameEx(hProcess: HANDLE; hModule: HMODULE; lpFilename: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

type
  LPMODULEINFO = ^MODULEINFO;
  _MODULEINFO = record
    lpBaseOfDll: LPVOID;
    SizeOfImage: DWORD;
    EntryPoint: LPVOID;
  end;
  MODULEINFO = _MODULEINFO;
  TModuleInfo = MODULEINFO;
  PModuleInfo = LPMODULEINFO;

function GetModuleInformation(hProcess: HANDLE; hModule: HMODULE;
  var lpmodinfo: MODULEINFO; cb: DWORD): BOOL; stdcall;

function EmptyWorkingSet(hProcess: HANDLE): BOOL; stdcall;

function QueryWorkingSet(hProcess: HANDLE; pv: PVOID; cb: DWORD): BOOL; stdcall;

function InitializeProcessForWsWatch(hProcess: HANDLE): BOOL; stdcall;

type
  PPSAPI_WS_WATCH_INFORMATION = ^PSAPI_WS_WATCH_INFORMATION;
  _PSAPI_WS_WATCH_INFORMATION = record
    FaultingPc: LPVOID;
    FaultingVa: LPVOID;
  end;
  PSAPI_WS_WATCH_INFORMATION = _PSAPI_WS_WATCH_INFORMATION;
  TPsApiWsWatchInformation = PSAPI_WS_WATCH_INFORMATION;
  PPsApiWsWatchInformation = PPSAPI_WS_WATCH_INFORMATION;

function GetWsChanges(hProcess: HANDLE; var lpWatchInfo: PSAPI_WS_WATCH_INFORMATION;
  cb: DWORD): BOOL; stdcall;

function GetMappedFileNameW(hProcess: HANDLE; lpv: LPVOID; lpFilename: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetMappedFileNameA(hProcess: HANDLE; lpv: LPVOID; lpFilename: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetMappedFileName(hProcess: HANDLE; lpv: LPVOID; lpFilename: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

function EnumDeviceDrivers(lpImageBase: LPLPVOID; cb: DWORD; var lpcbNeeded: DWORD): BOOL; stdcall;

function GetDeviceDriverBaseNameA(ImageBase: LPVOID; lpBaseName: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetDeviceDriverBaseNameW(ImageBase: LPVOID; lpBaseName: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetDeviceDriverBaseName(ImageBase: LPVOID; lpBaseName: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

function GetDeviceDriverFileNameA(ImageBase: LPVOID; lpFilename: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetDeviceDriverFileNameW(ImageBase: LPVOID; lpFilename: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetDeviceDriverFileName(ImageBase: LPVOID; lpFilename: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

// Structure for GetProcessMemoryInfo()

type
  PPROCESS_MEMORY_COUNTERS = ^PROCESS_MEMORY_COUNTERS;
  _PROCESS_MEMORY_COUNTERS = record
    cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: SIZE_T;
    WorkingSetSize: SIZE_T;
    QuotaPeakPagedPoolUsage: SIZE_T;
    QuotaPagedPoolUsage: SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage: SIZE_T;
    PagefileUsage: SIZE_T;
    PeakPagefileUsage: SIZE_T;
  end;
  PROCESS_MEMORY_COUNTERS = _PROCESS_MEMORY_COUNTERS;
  TProcessMemoryCounters = PROCESS_MEMORY_COUNTERS;
  PProcessMemoryCounters = PPROCESS_MEMORY_COUNTERS;

  _PROCESS_MEMORY_COUNTERS_EX = record
    cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: SIZE_T;
    WorkingSetSize: SIZE_T;
    QuotaPeakPagedPoolUsage: SIZE_T;
    QuotaPagedPoolUsage: SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage: SIZE_T;
    PagefileUsage: SIZE_T;
    PeakPagefileUsage: SIZE_T;
    PrivateUsage: SIZE_T;
  end;
  PROCESS_MEMORY_COUNTERS_EX = _PROCESS_MEMORY_COUNTERS_EX;
  PPROCESS_MEMORY_COUNTERS_EX = ^PROCESS_MEMORY_COUNTERS_EX;
  TProcessMemoryCountersEx = PROCESS_MEMORY_COUNTERS_EX;

function GetProcessMemoryInfo(Process: HANDLE;
  ppsmemCounters: PPROCESS_MEMORY_COUNTERS; cb: DWORD): BOOL; stdcall;

type
  _PERFORMANCE_INFORMATION = record
    cb: DWORD;
    CommitTotal: SIZE_T;
    CommitLimit: SIZE_T;
    CommitPeak: SIZE_T;
    PhysicalTotal: SIZE_T;
    PhysicalAvailable: SIZE_T;
    SystemCache: SIZE_T;
    KernelTotal: SIZE_T;
    KernelPaged: SIZE_T;
    KernelNonpaged: SIZE_T;
    PageSize: SIZE_T;
    HandleCount: DWORD;
    ProcessCount: DWORD;
    ThreadCount: DWORD;
  end;
  PERFORMANCE_INFORMATION = _PERFORMANCE_INFORMATION;
  PPERFORMANCE_INFORMATION = ^PERFORMANCE_INFORMATION;
  TPerformanceInformation = PERFORMANCE_INFORMATION;
  PPerformanceInformation = PPERFORMANCE_INFORMATION;

{ MVB:

  Please note that this function, unlike what the Platform SDK documents, is _not_ available for Windows 2000!!!
  It is available starting with Windows XP and Windows.NET Server.
  If needed, you can relatively easily clone the functionality of this function by using the performance monitor
  API (either through the HKEY_PERFORMANCE_DATA registry interface or using the Performance Data Helper API)
}

function GetPerformanceInfo(pPerformanceInformation: PPERFORMANCE_INFORMATION;
  cb: DWORD): BOOL; stdcall;

type
  _ENUM_PAGE_FILE_INFORMATION = record
    cb: DWORD;
    Reserved: DWORD;
    TotalSize: SIZE_T;
    TotalInUse: SIZE_T;
    PeakUsage: SIZE_T;
  end;
  ENUM_PAGE_FILE_INFORMATION = _ENUM_PAGE_FILE_INFORMATION;
  PENUM_PAGE_FILE_INFORMATION = ^ENUM_PAGE_FILE_INFORMATION;
  TEnumPageFileInformation = ENUM_PAGE_FILE_INFORMATION;
  PEnumPageFileInformation = PENUM_PAGE_FILE_INFORMATION;

type
  PENUM_PAGE_FILE_CALLBACKW = function(pContext: LPVOID;
    pPageFileInfo: PENUM_PAGE_FILE_INFORMATION; lpFilename: LPCWSTR): BOOL; stdcall;
  PENUM_PAGE_FILE_CALLBACKA = function(pContext: LPVOID;
    pPageFileInfo: PENUM_PAGE_FILE_INFORMATION; lpFilename: LPCSTR): BOOL; stdcall;
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  PENUM_PAGE_FILE_CALLBACK = PENUM_PAGE_FILE_CALLBACKW;
{$else}
  PENUM_PAGE_FILE_CALLBACK = PENUM_PAGE_FILE_CALLBACKA;
{$endif}

function EnumPageFilesW(pCallBackRoutine: PENUM_PAGE_FILE_CALLBACKW; pContext: LPVOID): BOOL; stdcall;
function EnumPageFilesA(pCallBackRoutine: PENUM_PAGE_FILE_CALLBACKA; pContext: LPVOID): BOOL; stdcall;
function EnumPageFiles(pCallBackRoutine: PENUM_PAGE_FILE_CALLBACK; pContext: LPVOID): BOOL; stdcall;

function GetProcessImageFileNameA(hProcess: HANDLE; lpImageFileName: LPSTR;
  nSize: DWORD): DWORD; stdcall;
function GetProcessImageFileNameW(hProcess: HANDLE; lpImageFileName: LPWSTR;
  nSize: DWORD): DWORD; stdcall;
function GetProcessImageFileName(hProcess: HANDLE; lpImageFileName: LPTSTR;
  nSize: DWORD): DWORD; stdcall;

implementation
//uses ...

const
  PsapiLib = 'psapi.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function EnumProcesses; external PsapiLib name 'EnumProcesses';
function EnumProcessModules; external PsapiLib name 'EnumProcessModules';
function GetModuleBaseNameA; external PsapiLib name 'GetModuleBaseNameA';
function GetModuleBaseNameW; external PsapiLib name 'GetModuleBaseNameW';
function GetModuleBaseName; external PsapiLib name 'GetModuleBaseName' + AWSuffix;
function GetModuleFileNameExA; external PsapiLib name 'GetModuleFileNameExA';
function GetModuleFileNameExW; external PsapiLib name 'GetModuleFileNameExW';
function GetModuleFileNameEx; external PsapiLib name 'GetModuleFileNameEx' + AWSuffix;
function GetModuleInformation; external PsapiLib name 'GetModuleInformation';
function EmptyWorkingSet; external PsapiLib name 'EmptyWorkingSet';
function QueryWorkingSet; external PsapiLib name 'QueryWorkingSet';
function InitializeProcessForWsWatch; external PsapiLib name 'InitializeProcessForWsWatch';
function GetWsChanges; external PsapiLib name 'GetWsChanges';
function GetMappedFileNameW; external PsapiLib name 'GetMappedFileNameW';
function GetMappedFileNameA; external PsapiLib name 'GetMappedFileNameA';
function GetMappedFileName; external PsapiLib name 'GetMappedFileName' + AWSuffix;
function EnumDeviceDrivers; external PsapiLib name 'EnumDeviceDrivers';
function GetDeviceDriverBaseNameA; external PsapiLib name 'GetDeviceDriverBaseNameA';
function GetDeviceDriverBaseNameW; external PsapiLib name 'GetDeviceDriverBaseNameW';
function GetDeviceDriverBaseName; external PsapiLib name 'GetDeviceDriverBaseName' + AWSuffix;
function GetDeviceDriverFileNameA; external PsapiLib name 'GetDeviceDriverFileNameA';
function GetDeviceDriverFileNameW; external PsapiLib name 'GetDeviceDriverFileNameW';
function GetDeviceDriverFileName; external PsapiLib name 'GetDeviceDriverFileName' + AWSuffix;
function GetProcessMemoryInfo; external PsapiLib name 'GetProcessMemoryInfo';
function GetPerformanceInfo; external PsapiLib name 'GetPerformanceInfo';
function EnumPageFilesW; external PsapiLib name 'EnumPageFilesW';
function EnumPageFilesA; external PsapiLib name 'EnumPageFilesA';
function EnumPageFiles; external PsapiLib name 'EnumPageFiles' + AWSuffix;
function GetProcessImageFileNameA; external PsapiLib name 'GetProcessImageFileNameA';
function GetProcessImageFileNameW; external PsapiLib name 'GetProcessImageFileNameW';
function GetProcessImageFileName; external PsapiLib name 'GetProcessImageFileName' + AWSuffix;

end.
