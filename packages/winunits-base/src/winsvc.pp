{******************************************************************************}
{                                                                              }
{ Services API interface Unit for Object Pascal                                }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: winsvc.h, released June 2000. The original Pascal      }
{ code is: WinSvc.pas, released December 2000. The initial developer of the    }
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

// $Id: WinSvc.pas,v 1.12 2007/09/05 11:58:54 dezipaitor Exp $
unit WinSvc;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses Windows;

//
// Service database names
//

const
  SERVICES_ACTIVE_DATABASEW = 'ServicesActive';
  SERVICES_FAILED_DATABASEW = 'ServicesFailed';

  SERVICES_ACTIVE_DATABASEA = 'ServicesActive';
  SERVICES_FAILED_DATABASEA = 'ServicesFailed';

//
// Character to designate that a name is a group
//

  SC_GROUP_IDENTIFIERW = '+';
  SC_GROUP_IDENTIFIERA = '+';

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  SERVICES_ACTIVE_DATABASE = SERVICES_ACTIVE_DATABASEW;
  SERVICES_FAILED_DATABASE = SERVICES_FAILED_DATABASEW;
{$else}
  SERVICES_ACTIVE_DATABASE = SERVICES_ACTIVE_DATABASEA;
  SERVICES_FAILED_DATABASE = SERVICES_FAILED_DATABASEA;
{$endif}

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  SC_GROUP_IDENTIFIER = SC_GROUP_IDENTIFIERW;
{$else}
  SC_GROUP_IDENTIFIER = SC_GROUP_IDENTIFIERA;
{$endif}

//
// Value to indicate no change to an optional parameter
//

  SERVICE_NO_CHANGE = $ffffffff;

//
// Service State -- for Enum Requests (Bit Mask)
//

  SERVICE_ACTIVE    = $00000001;
  SERVICE_INACTIVE  = $00000002;
  SERVICE_STATE_ALL = SERVICE_ACTIVE or SERVICE_INACTIVE;

//
// Controls
//

  SERVICE_CONTROL_STOP                  = $00000001;
  SERVICE_CONTROL_PAUSE                 = $00000002;
  SERVICE_CONTROL_CONTINUE              = $00000003;
  SERVICE_CONTROL_INTERROGATE           = $00000004;
  SERVICE_CONTROL_SHUTDOWN              = $00000005;
  SERVICE_CONTROL_PARAMCHANGE           = $00000006;
  SERVICE_CONTROL_NETBINDADD            = $00000007;
  SERVICE_CONTROL_NETBINDREMOVE         = $00000008;
  SERVICE_CONTROL_NETBINDENABLE         = $00000009;
  SERVICE_CONTROL_NETBINDDISABLE        = $0000000A;
  SERVICE_CONTROL_DEVICEEVENT           = $0000000B;
  SERVICE_CONTROL_HARDWAREPROFILECHANGE = $0000000C;
  SERVICE_CONTROL_POWEREVENT            = $0000000D;
  SERVICE_CONTROL_SESSIONCHANGE         = $0000000E;
  SERVICE_CONTROL_TIMECHANGE            = $00000010;
  SERVICE_CONTROL_TRIGGEREVENT          = $00000020;
  SERVICE_CONTROL_USERMODEREBOOT        = $00000040;

//
// Service State -- for CurrentState
//

  SERVICE_STOPPED          = $00000001;
  SERVICE_START_PENDING    = $00000002;
  SERVICE_STOP_PENDING     = $00000003;
  SERVICE_RUNNING          = $00000004;
  SERVICE_CONTINUE_PENDING = $00000005;
  SERVICE_PAUSE_PENDING    = $00000006;
  SERVICE_PAUSED           = $00000007;

//
// Controls Accepted  (Bit Mask)
//

  SERVICE_ACCEPT_STOP                  = $00000001;
  SERVICE_ACCEPT_PAUSE_CONTINUE        = $00000002;
  SERVICE_ACCEPT_SHUTDOWN              = $00000004;
  SERVICE_ACCEPT_PARAMCHANGE           = $00000008;
  SERVICE_ACCEPT_NETBINDCHANGE         = $00000010;
  SERVICE_ACCEPT_HARDWAREPROFILECHANGE = $00000020;
  SERVICE_ACCEPT_POWEREVENT            = $00000040;
  SERVICE_ACCEPT_SESSIONCHANGE         = $00000080;
  SERVICE_ACCEPT_TIMECHANGE            = $00000200;
  SERVICE_ACCEPT_TRIGGEREVENT          = $00000400;
  SERVICE_ACCEPT_USERMODEREBOOT        = $00000800;

//
// Service Control Manager object specific access types
//

  SC_MANAGER_CONNECT            = $0001;
  SC_MANAGER_CREATE_SERVICE     = $0002;
  SC_MANAGER_ENUMERATE_SERVICE  = $0004;
  SC_MANAGER_LOCK               = $0008;
  SC_MANAGER_QUERY_LOCK_STATUS  = $0010;
  SC_MANAGER_MODIFY_BOOT_CONFIG = $0020;

  SC_MANAGER_ALL_ACCESS         = STANDARD_RIGHTS_REQUIRED or
                                  SC_MANAGER_CONNECT or
                                  SC_MANAGER_CREATE_SERVICE or
                                  SC_MANAGER_ENUMERATE_SERVICE or
                                  SC_MANAGER_LOCK or
                                  SC_MANAGER_QUERY_LOCK_STATUS or
                                  SC_MANAGER_MODIFY_BOOT_CONFIG;

//
// Service object specific access type
//

  SERVICE_QUERY_CONFIG         = $0001;
  SERVICE_CHANGE_CONFIG        = $0002;
  SERVICE_QUERY_STATUS         = $0004;
  SERVICE_ENUMERATE_DEPENDENTS = $0008;
  SERVICE_START                = $0010;
  SERVICE_STOP                 = $0020;
  SERVICE_PAUSE_CONTINUE       = $0040;
  SERVICE_INTERROGATE          = $0080;
  SERVICE_USER_DEFINED_CONTROL = $0100;

  SERVICE_ALL_ACCESS           = STANDARD_RIGHTS_REQUIRED or
                                 SERVICE_QUERY_CONFIG or
                                 SERVICE_CHANGE_CONFIG or
                                 SERVICE_QUERY_STATUS or
                                 SERVICE_ENUMERATE_DEPENDENTS or
                                 SERVICE_START or
                                 SERVICE_STOP or
                                 SERVICE_PAUSE_CONTINUE or
                                 SERVICE_INTERROGATE or
                                 SERVICE_USER_DEFINED_CONTROL;

//
// Service flags for QueryServiceStatusEx
//

  SERVICE_RUNS_IN_SYSTEM_PROCESS = $00000001;

//
// Info levels for ChangeServiceConfig2 and QueryServiceConfig2
//

  SERVICE_CONFIG_DESCRIPTION     = 1;
  SERVICE_CONFIG_FAILURE_ACTIONS = 2;

//
// Service description string
//

type
  LPSERVICE_DESCRIPTIONA = ^SERVICE_DESCRIPTIONA;
  _SERVICE_DESCRIPTIONA = record
    lpDescription: LPSTR;
  end;
  SERVICE_DESCRIPTIONA = _SERVICE_DESCRIPTIONA;
  TServiceDescriptionA = SERVICE_DESCRIPTIONA;
  PServiceDescriptionA = LPSERVICE_DESCRIPTIONA;

//
// Service description string
//

  LPSERVICE_DESCRIPTIONW = ^SERVICE_DESCRIPTIONW;
  _SERVICE_DESCRIPTIONW = record
    lpDescription: LPWSTR;
  end;
  SERVICE_DESCRIPTIONW = _SERVICE_DESCRIPTIONW;
  TServiceDescriptionW = SERVICE_DESCRIPTIONW;
  PServiceDescriptionW = LPSERVICE_DESCRIPTIONW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  SERVICE_DESCRIPTION = SERVICE_DESCRIPTIONW;
  LPSERVICE_DESCRIPTION = LPSERVICE_DESCRIPTIONW;
  TServiceDescription = TServiceDescriptionW;
  PServiceDescription = PServiceDescriptionW;
{$else}
  SERVICE_DESCRIPTION = SERVICE_DESCRIPTIONA;
  LPSERVICE_DESCRIPTION = LPSERVICE_DESCRIPTIONA;
  TServiceDescription = TServiceDescriptionA;
  PServiceDescription = PServiceDescriptionA;
{$endif}

//
// Actions to take on service failure
//

  _SC_ACTION_TYPE = (SC_ACTION_NONE, SC_ACTION_RESTART, SC_ACTION_REBOOT,
    SC_ACTION_RUN_COMMAND);
  SC_ACTION_TYPE = _SC_ACTION_TYPE;
  TScActionType = _SC_ACTION_TYPE;

  LPSC_ACTION = ^SC_ACTION;
  _SC_ACTION = record
    Type_: SC_ACTION_TYPE;
    Delay: DWORD;
  end;
  SC_ACTION = _SC_ACTION;
  TScAction = SC_ACTION;
  PScAction = LPSC_ACTION;

  LPSERVICE_FAILURE_ACTIONSA = ^SERVICE_FAILURE_ACTIONSA;
  _SERVICE_FAILURE_ACTIONSA = record
    dwResetPeriod: DWORD;
    lpRebootMsg: LPSTR;
    lpCommand: LPSTR;
    cActions: DWORD;
    lpsaActions: LPSC_ACTION;
  end;
  SERVICE_FAILURE_ACTIONSA = _SERVICE_FAILURE_ACTIONSA;
  TServiceFailureActionsA = SERVICE_FAILURE_ACTIONSA;
  PServiceFailureActionsA = LPSERVICE_FAILURE_ACTIONSA;

  LPSERVICE_FAILURE_ACTIONSW = ^SERVICE_FAILURE_ACTIONSW;
  _SERVICE_FAILURE_ACTIONSW = record
    dwResetPeriod: DWORD;
    lpRebootMsg: LPWSTR;
    lpCommand: LPWSTR;
    cActions: DWORD;
    lpsaActions: LPSC_ACTION;
  end;
  SERVICE_FAILURE_ACTIONSW = _SERVICE_FAILURE_ACTIONSW;
  TServiceFailureActionsW = SERVICE_FAILURE_ACTIONSW;
  PServiceFailureActionsW = LPSERVICE_FAILURE_ACTIONSW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  SERVICE_FAILURE_ACTIONS = SERVICE_FAILURE_ACTIONSW;
  LPSERVICE_FAILURE_ACTIONS = LPSERVICE_FAILURE_ACTIONSW;
  TServiceFailureActions = TServiceFailureActionsW;
  PServiceFailureActions = PServiceFailureActionsW;
{$else}
  SERVICE_FAILURE_ACTIONS = SERVICE_FAILURE_ACTIONSA;
  LPSERVICE_FAILURE_ACTIONS = LPSERVICE_FAILURE_ACTIONSA;
  TServiceFailureActions = TServiceFailureActionsA;
  PServiceFailureActions = PServiceFailureActionsA;
{$endif}

//
// Handle Types
//

  SC_HANDLE = HANDLE;
  LPSC_HANDLE = ^SC_HANDLE;

  SERVICE_STATUS_HANDLE = HANDLE;

//
// Info levels for QueryServiceStatusEx
//

  _SC_STATUS_TYPE = (SC_STATUS_PROCESS_INFO);
  SC_STATUS_TYPE = _SC_STATUS_TYPE;

//
// Info levels for EnumServicesStatusEx
//

  _SC_ENUM_TYPE = (SC_ENUM_PROCESS_INFO);
  SC_ENUM_TYPE = _SC_ENUM_TYPE;

//
// Service Status Structures
//

  LPSERVICE_STATUS = ^SERVICE_STATUS;
  _SERVICE_STATUS = record
    dwServiceType: DWORD;
    dwCurrentState: DWORD;
    dwControlsAccepted: DWORD;
    dwWin32ExitCode: DWORD;
    dwServiceSpecificExitCode: DWORD;
    dwCheckPoint: DWORD;
    dwWaitHint: DWORD;
  end;
  SERVICE_STATUS = _SERVICE_STATUS;
  TServiceStatus = SERVICE_STATUS;
  PServiceStatus = LPSERVICE_STATUS;

  LPSERVICE_STATUS_PROCESS = ^SERVICE_STATUS_PROCESS;
  _SERVICE_STATUS_PROCESS = record
    dwServiceType: DWORD;
    dwCurrentState: DWORD;
    dwControlsAccepted: DWORD;
    dwWin32ExitCode: DWORD;
    dwServiceSpecificExitCode: DWORD;
    dwCheckPoint: DWORD;
    dwWaitHint: DWORD;
    dwProcessId: DWORD;
    dwServiceFlags: DWORD;
  end;
  SERVICE_STATUS_PROCESS = _SERVICE_STATUS_PROCESS;
  TServiceStatusProcess = SERVICE_STATUS_PROCESS;
  PServiceStatusProcess = LPSERVICE_STATUS_PROCESS;

//
// Service Status Enumeration Structure
//

  LPENUM_SERVICE_STATUSA = ^ENUM_SERVICE_STATUSA;
  _ENUM_SERVICE_STATUSA = record
    lpServiceName: LPSTR;
    lpDisplayName: LPSTR;
    ServiceStatus: SERVICE_STATUS;
  end;
  ENUM_SERVICE_STATUSA = _ENUM_SERVICE_STATUSA;
  TEnumServiceStatusA = ENUM_SERVICE_STATUSA;
  PEnumServiceStatusA = LPENUM_SERVICE_STATUSA;

  LPENUM_SERVICE_STATUSW = ^ENUM_SERVICE_STATUSW;
  _ENUM_SERVICE_STATUSW = record
    lpServiceName: LPWSTR;
    lpDisplayName: LPWSTR;
    ServiceStatus: SERVICE_STATUS;
  end;
  ENUM_SERVICE_STATUSW = _ENUM_SERVICE_STATUSW;
  TEnumServiceStatusW = ENUM_SERVICE_STATUSW;
  PEnumServiceStatusW = LPENUM_SERVICE_STATUSW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ENUM_SERVICE_STATUS = ENUM_SERVICE_STATUSW;
  LPENUM_SERVICE_STATUS = LPENUM_SERVICE_STATUSW;
  TEnumServiceStatus = TEnumServiceStatusW;
  PEnumServiceStatus = PEnumServiceStatusW;
{$else}
  ENUM_SERVICE_STATUS = ENUM_SERVICE_STATUSA;
  LPENUM_SERVICE_STATUS = LPENUM_SERVICE_STATUSA;
  TEnumServiceStatus = TEnumServiceStatusA;
  PEnumServiceStatus = PEnumServiceStatusA;
{$endif}

  LPENUM_SERVICE_STATUS_PROCESSA = ^ENUM_SERVICE_STATUS_PROCESSA;
  _ENUM_SERVICE_STATUS_PROCESSA = record
    lpServiceName: LPSTR;
    lpDisplayName: LPSTR;
    ServiceStatusProcess: SERVICE_STATUS_PROCESS;
  end;
  ENUM_SERVICE_STATUS_PROCESSA = _ENUM_SERVICE_STATUS_PROCESSA;
  TEnumServiceStatusProcessA = ENUM_SERVICE_STATUS_PROCESSA;
  PEnumServiceStatusProcessA = LPENUM_SERVICE_STATUS_PROCESSA;

  LPENUM_SERVICE_STATUS_PROCESSW = ^ENUM_SERVICE_STATUS_PROCESSW;
  _ENUM_SERVICE_STATUS_PROCESSW = record
    lpServiceName: LPWSTR;
    lpDisplayName: LPWSTR;
    ServiceStatusProcess: SERVICE_STATUS_PROCESS;
  end;
  ENUM_SERVICE_STATUS_PROCESSW = _ENUM_SERVICE_STATUS_PROCESSW;
  TEnumServiceStatusProcessW = ENUM_SERVICE_STATUS_PROCESSW;
  PEnumServiceStatusProcessW = LPENUM_SERVICE_STATUS_PROCESSW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  ENUM_SERVICE_STATUS_PROCESS = ENUM_SERVICE_STATUS_PROCESSW;
  LPENUM_SERVICE_STATUS_PROCESS = LPENUM_SERVICE_STATUS_PROCESSW;
  TEnumServiceStatusProcess = TEnumServiceStatusProcessW;
  PEnumServiceStatusProcess = PEnumServiceStatusProcessW;
{$else}
  ENUM_SERVICE_STATUS_PROCESS = ENUM_SERVICE_STATUS_PROCESSA;
  LPENUM_SERVICE_STATUS_PROCESS = LPENUM_SERVICE_STATUS_PROCESSA;
  TEnumServiceStatusProcess = TEnumServiceStatusProcessA;
  PEnumServiceStatusProcess = PEnumServiceStatusProcessA;
{$endif}

//
// Structures for the Lock API functions
//

  SC_LOCK = LPVOID;

  LPQUERY_SERVICE_LOCK_STATUSA = ^QUERY_SERVICE_LOCK_STATUSA;
  _QUERY_SERVICE_LOCK_STATUSA = record
    fIsLocked: DWORD;
    lpLockOwner: LPSTR;
    dwLockDuration: DWORD;
  end;
  QUERY_SERVICE_LOCK_STATUSA = _QUERY_SERVICE_LOCK_STATUSA;
  TQueryServiceLockStatusA = QUERY_SERVICE_LOCK_STATUSA;
  PQueryServiceLockStatusA = LPQUERY_SERVICE_LOCK_STATUSA;

  LPQUERY_SERVICE_LOCK_STATUSW = ^QUERY_SERVICE_LOCK_STATUSW;
  _QUERY_SERVICE_LOCK_STATUSW = record
    fIsLocked: DWORD;
    lpLockOwner: LPWSTR;
    dwLockDuration: DWORD;
  end;
  QUERY_SERVICE_LOCK_STATUSW = _QUERY_SERVICE_LOCK_STATUSW;
  TQueryServiceLockStatusW = QUERY_SERVICE_LOCK_STATUSW;
  PQueryServiceLockStatusW = LPQUERY_SERVICE_LOCK_STATUSW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  QUERY_SERVICE_LOCK_STATUS = QUERY_SERVICE_LOCK_STATUSW;
  LPQUERY_SERVICE_LOCK_STATUS = LPQUERY_SERVICE_LOCK_STATUSW;
  TQueryServiceLockStatus = TQueryServiceLockStatusW;
  PQueryServiceLockStatus = PQueryServiceLockStatusW;
{$else}
  QUERY_SERVICE_LOCK_STATUS = QUERY_SERVICE_LOCK_STATUSA;
  LPQUERY_SERVICE_LOCK_STATUS = LPQUERY_SERVICE_LOCK_STATUSA;
  TQueryServiceLockStatus = TQueryServiceLockStatusA;
  PQueryServiceLockStatus = PQueryServiceLockStatusA;
{$endif}

//
// Query Service Configuration Structure
//

  LPQUERY_SERVICE_CONFIGA = ^QUERY_SERVICE_CONFIGA;
  _QUERY_SERVICE_CONFIGA = record
    dwServiceType: DWORD;
    dwStartType: DWORD;
    dwErrorControl: DWORD;
    lpBinaryPathName: LPSTR;
    lpLoadOrderGroup: LPSTR;
    dwTagId: DWORD;
    lpDependencies: LPSTR;
    lpServiceStartName: LPSTR;
    lpDisplayName: LPSTR;
  end;
  QUERY_SERVICE_CONFIGA = _QUERY_SERVICE_CONFIGA;
  TQueryServiceConfigA = QUERY_SERVICE_CONFIGA;
  PQueryServiceConfigA = LPQUERY_SERVICE_CONFIGA;

  LPQUERY_SERVICE_CONFIGW = ^QUERY_SERVICE_CONFIGW;
  _QUERY_SERVICE_CONFIGW = record
    dwServiceType: DWORD;
    dwStartType: DWORD;
    dwErrorControl: DWORD;
    lpBinaryPathName: LPWSTR;
    lpLoadOrderGroup: LPWSTR;
    dwTagId: DWORD;
    lpDependencies: LPWSTR;
    lpServiceStartName: LPWSTR;
    lpDisplayName: LPWSTR;
  end;
  QUERY_SERVICE_CONFIGW = _QUERY_SERVICE_CONFIGW;
  TQueryServiceConfigW = QUERY_SERVICE_CONFIGW;
  PQueryServiceConfigW = LPQUERY_SERVICE_CONFIGW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  QUERY_SERVICE_CONFIG = QUERY_SERVICE_CONFIGW;
  LPQUERY_SERVICE_CONFIG = LPQUERY_SERVICE_CONFIGW;
  TQueryServiceConfig = TQueryServiceConfigW;
  PQueryServiceConfig = PQueryServiceConfigW;
{$else}
  QUERY_SERVICE_CONFIG = QUERY_SERVICE_CONFIGA;
  LPQUERY_SERVICE_CONFIG = LPQUERY_SERVICE_CONFIGA;
  TQueryServiceConfig = TQueryServiceConfigA;
  PQueryServiceConfig = PQueryServiceConfigA;
{$endif}

//
// Function Prototype for the Service Main Function
//

type
  LPSERVICE_MAIN_FUNCTIONW = procedure(dwNumServicesArgs: DWORD;
    lpServiceArgVectors: PPWideChar); stdcall;
  LPSERVICE_MAIN_FUNCTIONA = procedure(dwNumServicesArgs: DWORD;
    lpServiceArgVectors: PPAnsiChar); stdcall;

  TServiceMainFunctionA = LPSERVICE_MAIN_FUNCTIONA;
  TServiceMainFunctionW = LPSERVICE_MAIN_FUNCTIONW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  LPSERVICE_MAIN_FUNCTION = LPSERVICE_MAIN_FUNCTIONW;
  TServiceMainFunction = LPSERVICE_MAIN_FUNCTIONW;
{$else}
  LPSERVICE_MAIN_FUNCTION = LPSERVICE_MAIN_FUNCTIONA;
  TServiceMainFunction = LPSERVICE_MAIN_FUNCTIONA;
{$endif}

//
// Service Start Table
//

  LPSERVICE_TABLE_ENTRYA = ^SERVICE_TABLE_ENTRYA;
  _SERVICE_TABLE_ENTRYA = record
    lpServiceName: LPSTR;
    lpServiceProc: LPSERVICE_MAIN_FUNCTIONA;
  end;
  SERVICE_TABLE_ENTRYA = _SERVICE_TABLE_ENTRYA;
  TServiceTableEntryA = SERVICE_TABLE_ENTRYA;
  PServiceTableEntryA = LPSERVICE_TABLE_ENTRYA;

  LPSERVICE_TABLE_ENTRYW = ^SERVICE_TABLE_ENTRYW;
  _SERVICE_TABLE_ENTRYW = record
    lpServiceName: LPWSTR;
    lpServiceProc: LPSERVICE_MAIN_FUNCTIONW;
  end;
  SERVICE_TABLE_ENTRYW = _SERVICE_TABLE_ENTRYW;
  TServiceTableEntryW = SERVICE_TABLE_ENTRYW;
  PServiceTableEntryW = LPSERVICE_TABLE_ENTRYW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  SERVICE_TABLE_ENTRY = SERVICE_TABLE_ENTRYW;
  LPSERVICE_TABLE_ENTRY = LPSERVICE_TABLE_ENTRYW;
  TServiceTableEntry = TServiceTableEntryW;
  PServiceTableEntry = PServiceTableEntryW;
{$else}
  SERVICE_TABLE_ENTRY = SERVICE_TABLE_ENTRYA;
  LPSERVICE_TABLE_ENTRY = LPSERVICE_TABLE_ENTRYA;
  TServiceTableEntry = TServiceTableEntryA;
  PServiceTableEntry = PServiceTableEntryA;
{$endif}

//
// Prototype for the Service Control Handler Function
//

  LPHANDLER_FUNCTION = procedure(dwControl: DWORD); stdcall;
  THandlerFunction = LPHANDLER_FUNCTION;

  LPHANDLER_FUNCTION_EX = function(dwControl, dwEventType: DWORD;
    lpEventData, lpContext: LPVOID): DWORD; stdcall;
  THandlerFunctionEx = LPHANDLER_FUNCTION_EX;

///////////////////////////////////////////////////////////////////////////
// API Function Prototypes
///////////////////////////////////////////////////////////////////////////

function ChangeServiceConfigA(hService: SC_HANDLE; dwServiceType, dwStartType,
  dwErrorControl: DWORD; lpBinaryPathName, lpLoadOrderGroup: LPCSTR;
  lpdwTagId: LPDWORD; lpDependencies, lpServiceStartName, lpPassword,
  lpDisplayName: LPCSTR): BOOL; stdcall;
function ChangeServiceConfigW(hService: SC_HANDLE; dwServiceType, dwStartType,
  dwErrorControl: DWORD; lpBinaryPathName, lpLoadOrderGroup: LPCWSTR;
  lpdwTagId: LPDWORD; lpDependencies, lpServiceStartName, lpPassword,
  lpDisplayName: LPCWSTR): BOOL; stdcall;
function ChangeServiceConfig(hService: SC_HANDLE; dwServiceType, dwStartType,
  dwErrorControl: DWORD; lpBinaryPathName, lpLoadOrderGroup: LPCTSTR;
  lpdwTagId: LPDWORD; lpDependencies, lpServiceStartName, lpPassword,
  lpDisplayName: LPCTSTR): BOOL; stdcall;

function ChangeServiceConfig2A(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpInfo: LPVOID): BOOL; stdcall;
function ChangeServiceConfig2W(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpInfo: LPVOID): BOOL; stdcall;
function ChangeServiceConfig2(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpInfo: LPVOID): BOOL; stdcall;

function CloseServiceHandle(hSCObject: SC_HANDLE): BOOL; stdcall;

function ControlService(hService: SC_HANDLE; dwControl: DWORD;
  var lpServiceStatus: SERVICE_STATUS): BOOL; stdcall;

function CreateServiceA(hSCManager: SC_HANDLE; lpServiceName, lpDisplayName: LPCSTR;
  dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: DWORD;
  lpBinaryPathName, lpLoadOrderGroup: LPCSTR; lpdwTagId: LPDWORD;
  lpDependencies, lpServiceStartName, lpPassword: LPCSTR): SC_HANDLE; stdcall;
function CreateServiceW(hSCManager: SC_HANDLE; lpServiceName, lpDisplayName: LPCWSTR;
  dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: DWORD;
  lpBinaryPathName, lpLoadOrderGroup: LPCWSTR; lpdwTagId: LPDWORD;
  lpDependencies, lpServiceStartName, lpPassword: LPCWSTR): SC_HANDLE; stdcall;
function CreateService(hSCManager: SC_HANDLE; lpServiceName, lpDisplayName: LPCTSTR;
  dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: DWORD;
  lpBinaryPathName, lpLoadOrderGroup: LPCTSTR; lpdwTagId: LPDWORD;
  lpDependencies, lpServiceStartName, lpPassword: LPCTSTR): SC_HANDLE; stdcall;

function DeleteService(hService: SC_HANDLE): BOOL; stdcall;

function EnumDependentServicesA(hService: SC_HANDLE; dwServiceState: DWORD;
  lpServices: LPENUM_SERVICE_STATUSA; cbBufSize: DWORD; var pcbBytesNeeded,
  lpServicesReturned: DWORD): BOOL; stdcall;
function EnumDependentServicesW(hService: SC_HANDLE; dwServiceState: DWORD;
  lpServices: LPENUM_SERVICE_STATUSW; cbBufSize: DWORD; var pcbBytesNeeded,
  lpServicesReturned: DWORD): BOOL; stdcall;
function EnumDependentServices(hService: SC_HANDLE; dwServiceState: DWORD;
  lpServices: LPENUM_SERVICE_STATUS; cbBufSize: DWORD; var pcbBytesNeeded,
  lpServicesReturned: DWORD): BOOL; stdcall;

function EnumServicesStatusA(hSCManager: SC_HANDLE; dwServiceType: DWORD;
  dwServiceState: DWORD; lpServices: LPENUM_SERVICE_STATUSA; cbBufSize: DWORD;
  var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD): BOOL; stdcall;
function EnumServicesStatusW(hSCManager: SC_HANDLE; dwServiceType: DWORD;
  dwServiceState: DWORD; lpServices: LPENUM_SERVICE_STATUSW; cbBufSize: DWORD;
  var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD): BOOL; stdcall;
function EnumServicesStatus(hSCManager: SC_HANDLE; dwServiceType: DWORD;
  dwServiceState: DWORD; lpServices: LPENUM_SERVICE_STATUS; cbBufSize: DWORD;
  var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD): BOOL; stdcall;

function EnumServicesStatusExA(hSCManager: SC_HANDLE; InfoLevel: SC_ENUM_TYPE;
  dwServiceType: DWORD; dwServiceState: DWORD; lpServices: LPBYTE;
  cbBufSize: DWORD; var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD;
  pszGroupName: LPCSTR): BOOL; stdcall;
function EnumServicesStatusExW(hSCManager: SC_HANDLE; InfoLevel: SC_ENUM_TYPE;
  dwServiceType: DWORD; dwServiceState: DWORD; lpServices: LPBYTE;
  cbBufSize: DWORD; var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD;
  pszGroupName: LPCWSTR): BOOL; stdcall;
function EnumServicesStatusEx(hSCManager: SC_HANDLE; InfoLevel: SC_ENUM_TYPE;
  dwServiceType: DWORD; dwServiceState: DWORD; lpServices: LPBYTE;
  cbBufSize: DWORD; var pcbBytesNeeded, lpServicesReturned, lpResumeHandle: DWORD;
  pszGroupName: LPCTSTR): BOOL; stdcall;

function GetServiceKeyNameA(hSCManager: SC_HANDLE; lpDisplayName: LPCSTR;
  lpServiceName: LPSTR; var lpcchBuffer: DWORD): BOOL; stdcall;
function GetServiceKeyNameW(hSCManager: SC_HANDLE; lpDisplayName: LPCWSTR;
  lpServiceName: LPWSTR; var lpcchBuffer: DWORD): BOOL; stdcall;
function GetServiceKeyName(hSCManager: SC_HANDLE; lpDisplayName: LPCTSTR;
  lpServiceName: LPTSTR; var lpcchBuffer: DWORD): BOOL; stdcall;

function GetServiceDisplayNameA(hSCManager: SC_HANDLE; lpServiceName: LPCSTR;
  lpDisplayName: LPSTR; var lpcchBuffer: DWORD): BOOL; stdcall;
function GetServiceDisplayNameW(hSCManager: SC_HANDLE; lpServiceName: LPCWSTR;
  lpDisplayName: LPWSTR; var lpcchBuffer: DWORD): BOOL; stdcall;
function GetServiceDisplayName(hSCManager: SC_HANDLE; lpServiceName: LPCTSTR;
  lpDisplayName: LPTSTR; var lpcchBuffer: DWORD): BOOL; stdcall;

function LockServiceDatabase(hSCManager: SC_HANDLE): SC_LOCK; stdcall;

function NotifyBootConfigStatus(BootAcceptable: BOOL): BOOL; stdcall;

function OpenSCManagerA(lpMachineName: LPCSTR; lpDatabaseName: LPCSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;
function OpenSCManagerW(lpMachineName: LPCWSTR; lpDatabaseName: LPCWSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;
function OpenSCManager(lpMachineName: LPCTSTR; lpDatabaseName: LPCTSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;

function OpenServiceA(hSCManager: SC_HANDLE; lpServiceName: LPCSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;
function OpenServiceW(hSCManager: SC_HANDLE; lpServiceName: LPCWSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;
function OpenService(hSCManager: SC_HANDLE; lpServiceName: LPCTSTR;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall;

function QueryServiceConfigA(hService: SC_HANDLE;
  lpServiceConfig: LPQUERY_SERVICE_CONFIGA; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceConfigW(hService: SC_HANDLE;
  lpServiceConfig: LPQUERY_SERVICE_CONFIGW; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceConfig(hService: SC_HANDLE;
  lpServiceConfig: LPQUERY_SERVICE_CONFIG; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;

function QueryServiceConfig2A(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpBuffer: LPBYTE; cbBufSize: DWORD; var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceConfig2W(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpBuffer: LPBYTE; cbBufSize: DWORD; var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceConfig2(hService: SC_HANDLE; dwInfoLevel: DWORD;
  lpBuffer: LPBYTE; cbBufSize: DWORD; var pcbBytesNeeded: DWORD): BOOL; stdcall;

function QueryServiceLockStatusA(hSCManager: SC_HANDLE;
  lpLockStatus: LPQUERY_SERVICE_LOCK_STATUSA; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceLockStatusW(hSCManager: SC_HANDLE;
  lpLockStatus: LPQUERY_SERVICE_LOCK_STATUSW; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;
function QueryServiceLockStatus(hSCManager: SC_HANDLE;
  lpLockStatus: LPQUERY_SERVICE_LOCK_STATUS; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;

function QueryServiceObjectSecurity(hService: SC_HANDLE;
  dwSecurityInformation: SECURITY_INFORMATION;
  var lpSecurityDescriptor: SECURITY_DESCRIPTOR; cbBufSize: DWORD;
  var pcbBytesNeeded: DWORD): BOOL; stdcall;

function QueryServiceStatus(hService: SC_HANDLE;
  var lpServiceStatus: SERVICE_STATUS): BOOL; stdcall;

function QueryServiceStatusEx(hService: SC_HANDLE; InfoLevel: SC_STATUS_TYPE;
  lpBuffer: LPBYTE; cbBufSize: DWORD; var pcbBytesNeeded: DWORD): BOOL; stdcall;

function RegisterServiceCtrlHandlerA(lpServiceName: LPCSTR;
  lpHandlerProc: LPHANDLER_FUNCTION): SERVICE_STATUS_HANDLE; stdcall;
function RegisterServiceCtrlHandlerW(lpServiceName: LPCWSTR;
  lpHandlerProc: LPHANDLER_FUNCTION): SERVICE_STATUS_HANDLE; stdcall;
function RegisterServiceCtrlHandler(lpServiceName: LPCTSTR;
  lpHandlerProc: LPHANDLER_FUNCTION): SERVICE_STATUS_HANDLE; stdcall;

function RegisterServiceCtrlHandlerExA(lpServiceName: LPCSTR;
  lpHandlerProc: LPHANDLER_FUNCTION_EX; lpContext: LPVOID): SERVICE_STATUS_HANDLE; stdcall;
function RegisterServiceCtrlHandlerExW(lpServiceName: LPCWSTR;
  lpHandlerProc: LPHANDLER_FUNCTION_EX; lpContext: LPVOID): SERVICE_STATUS_HANDLE; stdcall;
function RegisterServiceCtrlHandlerEx(lpServiceName: LPCTSTR;
  lpHandlerProc: LPHANDLER_FUNCTION_EX; lpContext: LPVOID): SERVICE_STATUS_HANDLE; stdcall;

// 9/4/2002 Changed last parameter from const to pointer - reported by James Ots.

function SetServiceObjectSecurity(hService: SC_HANDLE;
  dwSecurityInformation: SECURITY_INFORMATION;
  lpSecurityDescriptor: PSECURITY_DESCRIPTOR): BOOL; stdcall;

function SetServiceStatus(hServiceStatus: SERVICE_STATUS_HANDLE;
  const lpServiceStatus: SERVICE_STATUS): BOOL; stdcall;

function StartServiceCtrlDispatcherA(lpServiceStartTable: LPSERVICE_TABLE_ENTRYA): BOOL; stdcall;
function StartServiceCtrlDispatcherW(lpServiceStartTable: LPSERVICE_TABLE_ENTRYW): BOOL; stdcall;
function StartServiceCtrlDispatcher(lpServiceStartTable: LPSERVICE_TABLE_ENTRY): BOOL; stdcall;

function StartServiceA(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PPAnsiChar): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceA';
function StartServiceA(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  var lpServiceArgVectors: LPCSTR): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceA';
function StartServiceW(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PPWideChar): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceW';
function StartServiceW(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  var lpServiceArgVectors: LPCWSTR): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceW';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PPWideChar): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceW';
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  var lpServiceArgVectors: LPCWSTR): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceW';
{$else}
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PPAnsiChar): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceA';
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  var lpServiceArgVectors: LPCSTR): BOOL; stdcall; overload; external 'advapi32.dll' name 'StartServiceA';
{$endif}

function UnlockServiceDatabase(ScLock: SC_LOCK): BOOL; stdcall;

implementation
//uses ...

const
  advapi32 = 'advapi32.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function ChangeServiceConfigA; external advapi32 name 'ChangeServiceConfigA';
function ChangeServiceConfigW; external advapi32 name 'ChangeServiceConfigW';
function ChangeServiceConfig; external advapi32 name 'ChangeServiceConfig' + AWSuffix;
function ChangeServiceConfig2A; external advapi32 name 'ChangeServiceConfig2A';
function ChangeServiceConfig2W; external advapi32 name 'ChangeServiceConfig2W';
function ChangeServiceConfig2; external advapi32 name 'ChangeServiceConfig2' + AWSuffix;
function CloseServiceHandle; external advapi32 name 'CloseServiceHandle';
function ControlService; external advapi32 name 'ControlService';
function CreateServiceA; external advapi32 name 'CreateServiceA';
function CreateServiceW; external advapi32 name 'CreateServiceW';
function CreateService; external advapi32 name 'CreateService' + AWSuffix;
function DeleteService; external advapi32 name 'DeleteService';
function EnumDependentServicesA; external advapi32 name 'EnumDependentServicesA';
function EnumDependentServicesW; external advapi32 name 'EnumDependentServicesW';
function EnumDependentServices; external advapi32 name 'EnumDependentServices' + AWSuffix;
function EnumServicesStatusA; external advapi32 name 'EnumServicesStatusA';
function EnumServicesStatusW; external advapi32 name 'EnumServicesStatusW';
function EnumServicesStatus; external advapi32 name 'EnumServicesStatus' + AWSuffix;
function EnumServicesStatusExA; external advapi32 name 'EnumServicesStatusExA';
function EnumServicesStatusExW; external advapi32 name 'EnumServicesStatusExW';
function EnumServicesStatusEx; external advapi32 name 'EnumServicesStatusEx' + AWSuffix;
function GetServiceKeyNameA; external advapi32 name 'GetServiceKeyNameA';
function GetServiceKeyNameW; external advapi32 name 'GetServiceKeyNameW';
function GetServiceKeyName; external advapi32 name 'GetServiceKeyName' + AWSuffix;
function GetServiceDisplayNameA; external advapi32 name 'GetServiceDisplayNameA';
function GetServiceDisplayNameW; external advapi32 name 'GetServiceDisplayNameW';
function GetServiceDisplayName; external advapi32 name 'GetServiceDisplayName' + AWSuffix;
function LockServiceDatabase; external advapi32 name 'LockServiceDatabase';
function NotifyBootConfigStatus; external advapi32 name 'NotifyBootConfigStatus';
function OpenSCManagerA; external advapi32 name 'OpenSCManagerA';
function OpenSCManagerW; external advapi32 name 'OpenSCManagerW';
function OpenSCManager; external advapi32 name 'OpenSCManager' + AWSuffix;
function OpenServiceA; external advapi32 name 'OpenServiceA';
function OpenServiceW; external advapi32 name 'OpenServiceW';
function OpenService; external advapi32 name 'OpenService' + AWSuffix;
function QueryServiceConfigA; external advapi32 name 'QueryServiceConfigA';
function QueryServiceConfigW; external advapi32 name 'QueryServiceConfigW';
function QueryServiceConfig; external advapi32 name 'QueryServiceConfig' + AWSuffix;
function QueryServiceConfig2A; external advapi32 name 'QueryServiceConfig2A';
function QueryServiceConfig2W; external advapi32 name 'QueryServiceConfig2W';
function QueryServiceConfig2; external advapi32 name 'QueryServiceConfig2' + AWSuffix;
function QueryServiceLockStatusA; external advapi32 name 'QueryServiceLockStatusA';
function QueryServiceLockStatusW; external advapi32 name 'QueryServiceLockStatusW';
function QueryServiceLockStatus; external advapi32 name 'QueryServiceLockStatus' + AWSuffix;
function QueryServiceObjectSecurity; external advapi32 name 'QueryServiceObjectSecurity';
function QueryServiceStatus; external advapi32 name 'QueryServiceStatus';
function QueryServiceStatusEx; external advapi32 name 'QueryServiceStatusEx';
function RegisterServiceCtrlHandlerA; external advapi32 name 'RegisterServiceCtrlHandlerA';
function RegisterServiceCtrlHandlerW; external advapi32 name 'RegisterServiceCtrlHandlerW';
function RegisterServiceCtrlHandler; external advapi32 name 'RegisterServiceCtrlHandler' + AWSuffix;
function RegisterServiceCtrlHandlerExA; external advapi32 name 'RegisterServiceCtrlHandlerExA';
function RegisterServiceCtrlHandlerExW; external advapi32 name 'RegisterServiceCtrlHandlerExW';
function RegisterServiceCtrlHandlerEx; external advapi32 name 'RegisterServiceCtrlHandlerEx' + AWSuffix;
function SetServiceObjectSecurity; external advapi32 name 'SetServiceObjectSecurity';
function SetServiceStatus; external advapi32 name 'SetServiceStatus';
function StartServiceCtrlDispatcherA; external advapi32 name 'StartServiceCtrlDispatcherA';
function StartServiceCtrlDispatcherW; external advapi32 name 'StartServiceCtrlDispatcherW';
function StartServiceCtrlDispatcher; external advapi32 name 'StartServiceCtrlDispatcher' + AWSuffix;
function UnlockServiceDatabase; external advapi32 name 'UnlockServiceDatabase';

end.
