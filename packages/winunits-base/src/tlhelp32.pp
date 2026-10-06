{******************************************************************************}
{                                                                              }
{ ToolHelp API interface Unit for Object Pascal                                }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: tlhelp32.h, released June 2000. The original Pascal    }
{ code is: TlHelp32.pas, released December 2000. The initial developer of the  }
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

// $Id: TlHelp32.pas,v 1.11 2007/09/05 11:58:52 dezipaitor Exp $
unit TlHelp32;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

// switch back to default (natural alignment), bug 16361
{$ifdef FPC} {$ifdef cpu64}{$packrecords 8} {$endif} {$endif}
interface

uses Windows;

const
  MAX_MODULE_NAME32 = 255;

// Snapshot function

function CreateToolhelp32Snapshot(dwFlags, th32ProcessID: DWORD): HANDLE; stdcall;

//
// The th32ProcessID argument is only used if TH32CS_SNAPHEAPLIST or
// TH32CS_SNAPMODULE is specified. th32ProcessID == 0 means the current
// process.
//
// NOTE that all of the snapshots are global except for the heap and module
//      lists which are process specific. To enumerate the heap or module
//      state for all WIN32 processes call with TH32CS_SNAPALL and the
//      current process. Then for each process in the TH32CS_SNAPPROCESS
//      list that isn't the current process, do a call with just
//      TH32CS_SNAPHEAPLIST and/or TH32CS_SNAPMODULE.
//
// dwFlags
//

const
  TH32CS_SNAPHEAPLIST = $00000001;
  TH32CS_SNAPPROCESS  = $00000002;
  TH32CS_SNAPTHREAD   = $00000004;
  TH32CS_SNAPMODULE   = $00000008;
  TH32CS_SNAPMODULE32 = $00000010;
  TH32CS_SNAPALL      = TH32CS_SNAPHEAPLIST or TH32CS_SNAPPROCESS or
                        TH32CS_SNAPTHREAD or TH32CS_SNAPMODULE;
  TH32CS_INHERIT      = $80000000;

//
// Use CloseHandle to destroy the snapshot
//

// Heap walking

type
  PHEAPLIST32 = ^HEAPLIST32;
  tagHEAPLIST32 = record
    dwSize: SIZE_T;
    th32ProcessID: DWORD;   // owning process
    th32HeapID: ULONG_PTR;  // heap (in owning process's context!)
    dwFlags: DWORD;
  end;
  HEAPLIST32 = tagHEAPLIST32;
  LPHEAPLIST32 = ^HEAPLIST32;
  THeapList32 = HEAPLIST32;

//
// dwFlags
//

const
  HF32_DEFAULT    = 1;  // process's default heap
  HF32_SHARED     = 2;  // is shared heap

function Heap32ListFirst(hSnapshot: HANDLE; var lphl: HEAPLIST32): BOOL; stdcall;
function Heap32ListNext(hSnapshot: HANDLE; var lphl: HEAPLIST32): BOOL; stdcall;

type
  PHEAPENTRY32 = ^HEAPENTRY32;
  tagHEAPENTRY32 = record
    dwSize: SIZE_T;
    hHandle: HANDLE;       // Handle of this heap block
    dwAddress: ULONG_PTR;  // Linear address of start of block
    dwBlockSize: SIZE_T;   // Size of block in bytes
    dwFlags: DWORD;
    dwLockCount: DWORD;
    dwResvd: DWORD;
    th32ProcessID: DWORD;  // owning process
    th32HeapID: ULONG_PTR; // heap block is in
  end;
  HEAPENTRY32 = tagHEAPENTRY32;
  LPHEAPENTRY32 = ^HEAPENTRY32;
  THeapEntry32 = HEAPENTRY32;

//
// dwFlags
//

const
  LF32_FIXED    = $00000001;
  LF32_FREE     = $00000002;
  LF32_MOVEABLE = $00000004;

function Heap32First(var lphe: HEAPENTRY32; th32ProcessID: DWORD;
  th32HeapID: ULONG_PTR): BOOL; stdcall;
function Heap32Next(var lphe: HEAPENTRY32): BOOL; stdcall;

function Toolhelp32ReadProcessMemory(th32ProcessID: DWORD; lpBaseAddress: LPCVOID;
  lpBuffer: LPVOID; cbRead: SIZE_T; lpNumberOfBytesRead: PSIZE_T): BOOL; stdcall;

// Process walking

type
  PPROCESSENTRY32W = ^PROCESSENTRY32W;
  tagPROCESSENTRY32W = record
    dwSize: DWORD;
    cntUsage: DWORD;
    th32ProcessID: DWORD;          // this process
    th32DefaultHeapID: ULONG_PTR;
    th32ModuleID:DWORD;            // associated exe
    cntThreads: DWORD;
    th32ParentProcessID: DWORD;    // this process's parent process
    pcPriClassBase: LONG;          // Base priority of process's threads
    dwFlags: DWORD;
    szExeFile: array [0..MAX_PATH - 1] of WCHAR;   // Path
  end;
  PROCESSENTRY32W = tagPROCESSENTRY32W;
  LPPROCESSENTRY32W = ^PROCESSENTRY32W;
  TProcessEntry32W = PROCESSENTRY32W;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  PROCESSENTRY32 = PROCESSENTRY32W;
  PPROCESSENTRY32 = PPROCESSENTRY32W;
  LPPROCESSENTRY32 = LPPROCESSENTRY32W;
  TProcessEntry32 = TProcessEntry32W;
{$else}
  PPROCESSENTRY32 = ^PROCESSENTRY32;
  tagPROCESSENTRY32 = record
    dwSize: DWORD;
    cntUsage: DWORD;
    th32ProcessID: DWORD;          // this process
    th32DefaultHeapID: ULONG_PTR;
    th32ModuleID: DWORD;           // associated exe
    cntThreads: DWORD;
    th32ParentProcessID: DWORD;    // this process's parent process
    pcPriClassBase: LONG;          // Base priority of process's threads
    dwFlags: DWORD;
    szExeFile: array [0..MAX_PATH - 1] of AnsiChar;    // Path
  end;
  PROCESSENTRY32 = tagPROCESSENTRY32;
  LPPROCESSENTRY32 = ^PROCESSENTRY32;
  TProcessEntry32 = PROCESSENTRY32;
{$endif}

function Process32FirstW(hSnapshot: HANDLE; var lppe: PROCESSENTRY32W): BOOL; stdcall;
function Process32NextW(hSnapshot: HANDLE; var lppe: PROCESSENTRY32W): BOOL; stdcall;

function Process32First(hSnapshot: HANDLE; var lppe: PROCESSENTRY32): BOOL; stdcall;//always ANSI!
function Process32Next(hSnapshot: HANDLE; var lppe: PROCESSENTRY32): BOOL; stdcall; //always ANSI!

// Thread walking

type
  PTHREADENTRY32 = ^THREADENTRY32;
  tagTHREADENTRY32 = record
    dwSize: DWORD;
    cntUsage: DWORD;
    th32ThreadID: DWORD;       // this thread
    th32OwnerProcessID: DWORD; // Process this thread is associated with
    tpBasePri: LONG;
    tpDeltaPri: LONG;
    dwFlags: DWORD;
  end;
  THREADENTRY32 = tagTHREADENTRY32;
  LPTHREADENTRY32 = ^THREADENTRY32;
  TThreadEntry32 = THREADENTRY32;

function Thread32First(hSnapshot: HANDLE; var lpte: THREADENTRY32): BOOL; stdcall;
function Thread32Next(hSnapshot: HANDLE; var lpte: THREADENTRY32): BOOL; stdcall;

// Module walking

type
  PMODULEENTRY32W = ^MODULEENTRY32W;
  tagMODULEENTRY32W = record
    dwSize: DWORD;
    th32ModuleID: DWORD;       // This module
    th32ProcessID: DWORD;      // owning process
    GlblcntUsage: DWORD;       // Global usage count on the module
    ProccntUsage: DWORD;       // Module usage count in th32ProcessID's context
    modBaseAddr: LPBYTE;       // Base address of module in th32ProcessID's context
    modBaseSize: DWORD;        // Size in bytes of module starting at modBaseAddr
    hModule: HMODULE;          // The hModule of this module in th32ProcessID's context
    szModule: array [0..MAX_MODULE_NAME32] of WCHAR;
    szExePath: array [0..MAX_PATH - 1] of WCHAR;
  end;
  MODULEENTRY32W = tagMODULEENTRY32W;
  LPMODULEENTRY32W = ^MODULEENTRY32W;
  TModuleEntry32W = MODULEENTRY32W;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  MODULEENTRY32 = MODULEENTRY32W;
  PMODULEENTRY32 = PMODULEENTRY32W;
  LPMODULEENTRY32 = LPMODULEENTRY32W;
  TModuleEntry32 = TModuleEntry32W;
{$else}
  PMODULEENTRY32 = ^MODULEENTRY32;
  tagMODULEENTRY32 = record
    dwSize: DWORD;
    th32ModuleID: DWORD;       // This module
    th32ProcessID: DWORD;      // owning process
    GlblcntUsage: DWORD;       // Global usage count on the module
    ProccntUsage: DWORD;       // Module usage count in th32ProcessID's context
    modBaseAddr: LPBYTE;       // Base address of module in th32ProcessID's context
    modBaseSize: DWORD;        // Size in bytes of module starting at modBaseAddr
    hModule: HMODULE;          // The hModule of this module in th32ProcessID's context
    szModule: array [0..MAX_MODULE_NAME32] of AnsiChar;
    szExePath: array [0..MAX_PATH - 1] of AnsiChar;
  end;
  MODULEENTRY32 = tagMODULEENTRY32;
  LPMODULEENTRY32 = ^MODULEENTRY32;
  TModuleEntry32 = MODULEENTRY32;
{$endif}

function Module32FirstW(hSnapshot: HANDLE; var lpme: MODULEENTRY32W): BOOL; stdcall;
function Module32NextW(hSnapshot: HANDLE; var lpme: MODULEENTRY32W): BOOL; stdcall;

//
// NOTE CAREFULLY that the modBaseAddr and hModule fields are valid ONLY
// in th32ProcessID's process context.
//
function Module32First(hSnapshot: HANDLE; var lpme: MODULEENTRY32): BOOL; stdcall; //always ANSI!
function Module32Next(hSnapshot: HANDLE; var lpme: MODULEENTRY32): BOOL; stdcall; //always ANSI!

implementation
//uses ...

const
  kernel32 = 'kernel32.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function CreateToolhelp32Snapshot; external kernel32 name 'CreateToolhelp32Snapshot';
function Heap32ListFirst; external kernel32 name 'Heap32ListFirst';
function Heap32ListNext; external kernel32 name 'Heap32ListNext';
function Heap32First; external kernel32 name 'Heap32First';
function Heap32Next; external kernel32 name 'Heap32Next';
function Toolhelp32ReadProcessMemory; external kernel32 name 'Toolhelp32ReadProcessMemory';
function Thread32First; external kernel32 name 'Thread32First';
function Thread32Next; external kernel32 name 'Thread32Next';

function Process32FirstW; external kernel32 name 'Process32FirstW';
function Process32First; external kernel32 name 'Process32First'; //ANSI

function Process32NextW; external kernel32 name 'Process32NextW';
function Process32Next; external kernel32 name 'Process32Next';  //ANSI

function Module32First; external kernel32 name 'Module32First'; //ANSI
function Module32FirstW; external kernel32 name 'Module32FirstW';

function Module32NextW; external kernel32 name 'Module32NextW';
function Module32Next; external kernel32 name 'Module32Next'; //ANSI

end.
