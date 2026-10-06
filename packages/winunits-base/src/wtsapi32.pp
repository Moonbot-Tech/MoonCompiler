{******************************************************************************}
{                                                                              }
{ Terminal Services API interface Unit for Object Pascal                       }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: wtsapi32.h, released June 2000. The original Pascal    }
{ code is: WtsApi32.pas, released December 2000. The initial developer of the  }
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

// $Id: WTSApi32.pas,v 1.13 2007/09/14 06:48:49 marquardt Exp $

unit WTSApi32;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

uses Windows;

//   Windows Terminal Server public APIs
//
//   Copyright 1995-1999, Citrix Systems Inc.
//   Copyright (c) 1997-1999  Microsoft Corporation

//==============================================================================
// Defines
//==============================================================================

//
//  Specifies the current server
//

const
  WTS_CURRENT_SERVER        = HANDLE(0);
  WTS_CURRENT_SERVER_HANDLE = HANDLE(0);
  WTS_CURRENT_SERVER_NAME   = '';

//
//  Specifies the current session (SessionId)
//

  WTS_CURRENT_SESSION = DWORD(-1);

//
//  Possible pResponse values from WTSSendMessage()
//
  IDTIMEOUT = 32000;
  IDASYNC   = 32001;

//
//  Shutdown flags
//

  WTS_WSD_LOGOFF = $00000001;           // log off all users except
  {$EXTERNALSYM WTS_WSD_LOGOFF}         // current user; deletes
                                        // WinStations (a reboot is
                                        // required to recreate the
                                        // WinStations)
  WTS_WSD_SHUTDOWN = $00000002;         // shutdown system
  WTS_WSD_REBOOT   = $00000004;         // shutdown and reboot
  WTS_WSD_POWEROFF = $00000008;         // shutdown and power off (on
                                        // machines that support power
                                        // off through software)
  WTS_WSD_FASTREBOOT = $00000010;       // reboot without logging users
  {$EXTERNALSYM WTS_WSD_FASTREBOOT}     // off or shutting down

// Added from Server 2008 pre-release SDK
  MAX_ELAPSED_TIME_LENGTH = 15;
  MAX_DATE_TIME_LENGTH = 56;
  WINSTATIONNAME_LENGTH = 32;
  DOMAIN_LENGTH = 17;

//==============================================================================
// WTS_CONNECTSTATE_CLASS - Session connect state
//==============================================================================

type
  _WTS_CONNECTSTATE_CLASS = (
    WTSActive,              // User logged on to WinStation
    WTSConnected,           // WinStation connected to client
    WTSConnectQuery,        // In the process of connecting to client
    WTSShadow,              // Shadowing another WinStation
    WTSDisconnected,        // WinStation logged on without client
    WTSIdle,                // Waiting for client to connect
    WTSListen,              // WinStation is listening for connection
    WTSReset,               // WinStation is being reset
    WTSDown,                // WinStation is down due to error
    WTSInit);               // WinStation in initialization
  WTS_CONNECTSTATE_CLASS = _WTS_CONNECTSTATE_CLASS;
  TWtsConnectStateClass = WTS_CONNECTSTATE_CLASS;

//==============================================================================
// WTS_SERVER_INFO - returned by WTSEnumerateServers (version 1)
//==============================================================================

//
//  WTSEnumerateServers() returns two variables: pServerInfo and Count.
//  The latter is the number of WTS_SERVER_INFO structures contained in
//  the former.  In order to read each server, iterate i from 0 to
//  Count-1 and reference the server name as
//  pServerInfo[i].pServerName; for example:
//
//  for ( i=0; i < Count; i++ ) {
//      _tprintf( TEXT("%s "), pServerInfo[i].pServerName );
//  }
//
//  The memory returned looks like the following.  P is a pServerInfo
//  pointer, and D is the string data for that pServerInfo:
//
//  P1 P2 P3 P4 ... Pn D1 D2 D3 D4 ... Dn
//
//  This makes it easier to iterate the servers, using code similar to
//  the above.
//

type
  PWTS_SERVER_INFOW = ^WTS_SERVER_INFOW;
  _WTS_SERVER_INFOW = record
    pServerName: LPWSTR; // server name
  end;
  WTS_SERVER_INFOW = _WTS_SERVER_INFOW;
  TWtsServerInfoW = WTS_SERVER_INFOW;
  PWtsServerInfoW = PWTS_SERVER_INFOW;

  PWTS_SERVER_INFOA = ^WTS_SERVER_INFOA;
  _WTS_SERVER_INFOA = record
    pServerName: LPSTR; // server name
  end;
  WTS_SERVER_INFOA = _WTS_SERVER_INFOA;
  TWtsServerInfoA = WTS_SERVER_INFOA;
  PWtsServerInfoA = PWTS_SERVER_INFOA;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  WTS_SERVER_INFO = WTS_SERVER_INFOW;
  PWTS_SERVER_INFO = PWTS_SERVER_INFOW;
  TWtsServerInfo = TWtsServerInfoW;
  PWtsServerInfo = PWtsServerInfoW;
{$else}
  WTS_SERVER_INFO = WTS_SERVER_INFOA;
  PWTS_SERVER_INFO = PWTS_SERVER_INFOA;
  TWtsServerInfo = TWtsServerInfoA;
  PWtsServerInfo = PWtsServerInfoA;
{$endif}

//==============================================================================
// WTS_SESSION_INFO - returned by WTSEnumerateSessions (version 1)
//==============================================================================

//
//  WTSEnumerateSessions() returns data in a similar format to the above
//  WTSEnumerateServers().  It returns two variables: pSessionInfo and
//  Count.  The latter is the number of WTS_SESSION_INFO structures
//  contained in the former.  Iteration is similar, except that there
//  are three parts to each entry, so it would look like this:
//
//  for ( i=0; i < Count; i++ ) {
//      _tprintf( TEXT("%-5u  %-20s  %u\n"),
//                pSessionInfo[i].SessionId,
//                pSessionInfo[i].pWinStationName,
//                pSessionInfo[i].State );
//  }
//
//  The memory returned is also segmented as the above, with all the
//  structures allocated at the start and the string data at the end.
//  We'll use S for the SessionId, P for the pWinStationName pointer
//  and D for the string data, and C for the connect State:
//
//  S1 P1 C1 S2 P2 C2 S3 P3 C3 S4 P4 C4 ... Sn Pn Cn D1 D2 D3 D4 ... Dn
//
//  As above, this makes it easier to iterate the sessions.
//

type
  PWTS_SESSION_INFOW = ^WTS_SESSION_INFOW;
  _WTS_SESSION_INFOW = record
    SessionId: DWORD;              // session id
    pWinStationName: LPWSTR;       // name of WinStation this session is connected to
    State: WTS_CONNECTSTATE_CLASS; // connection state (see enum)
  end;
  WTS_SESSION_INFOW = _WTS_SESSION_INFOW;
  TWtsSessionInfoW = WTS_SESSION_INFOW;
  PWtsSessionInfoW = PWTS_SESSION_INFOW;

  PWTS_SESSION_INFOA = ^WTS_SESSION_INFOA;
  _WTS_SESSION_INFOA = record
    SessionId: DWORD;              // session id
    pWinStationName: LPSTR;        // name of WinStation this session is connected to
    State: WTS_CONNECTSTATE_CLASS; // connection state (see enum)
  end;
  WTS_SESSION_INFOA = _WTS_SESSION_INFOA;
  TWtsSessionInfoA = WTS_SESSION_INFOA;
  PWtsSessionInfoA = PWTS_SESSION_INFOA;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  WTS_SESSION_INFO = WTS_SESSION_INFOW;
  PWTS_SESSION_INFO = PWTS_SESSION_INFOW;
  TWtsSessionInfo = TWtsSessionInfoW;
  PWtsSessionInfo = PWtsSessionInfoW;
{$else}
  WTS_SESSION_INFO = WTS_SESSION_INFOA;
  PWTS_SESSION_INFO = PWTS_SESSION_INFOA;
  TWtsSessionInfo = TWtsSessionInfoA;
  PWtsSessionInfo = PWtsSessionInfoA;
{$endif}

//==============================================================================
// WTS_PROCESS_INFO - returned by WTSEnumerateProcesses (version 1)
//==============================================================================

//
//  WTSEnumerateProcesses() also returns data similar to
//  WTSEnumerateServers().  It returns two variables: pProcessInfo and
//  Count.  The latter is the number of WTS_PROCESS_INFO structures
//  contained in the former.  Iteration is similar, except that there
//  are four parts to each entry, so it would look like this:
//
//  for ( i=0; i < Count; i++ ) {
//      GetUserNameFromSid( pProcessInfo[i].pUserSid, UserName,
//                          sizeof(UserName) );
//      _tprintf( TEXT("%-5u  %-20s  %-5u  %s\n"),
//              pProcessInfo[i].SessionId,
//              UserName,
//              pProcessInfo[i].ProcessId,
//              pProcessInfo[i].pProcessName );
//  }
//
//  The memory returned is also segmented as the above, with all the
//  structures allocated at the start and the string data at the end.
//  We'll use S for the SessionId, R for the ProcessId, P for the
//  pProcessName pointer and D for the string data, and U for pUserSid:
//
//  S1 R1 P1 U1 S2 R2 P2 U2 S3 R3 P3 U3 ... Sn Rn Pn Un D1 D2 D3 ... Dn
//
//  As above, this makes it easier to iterate the processes.
//

type
  PWTS_PROCESS_INFOW = ^WTS_PROCESS_INFOW;
  _WTS_PROCESS_INFOW = record
    SessionId: DWORD;     // session id
    ProcessId: DWORD;     // process id
    pProcessName: LPWSTR; // name of process
    pUserSid: PSID;       // user's SID
  end;
  WTS_PROCESS_INFOW = _WTS_PROCESS_INFOW;
  TWtsProcessInfoW = WTS_PROCESS_INFOW;
  PWtsProcessInfoW = PWTS_PROCESS_INFOW;

  PWTS_PROCESS_INFOA = ^WTS_PROCESS_INFOA;
  _WTS_PROCESS_INFOA = record
    SessionId: DWORD;    // session id
    ProcessId: DWORD;    // process id
    pProcessName: LPSTR; // name of process
    pUserSid: PSID;      // user's SID
  end;
  WTS_PROCESS_INFOA = _WTS_PROCESS_INFOA;
  TWtsProcessInfoA = WTS_PROCESS_INFOA;
  PWtsProcessInfoA = PWTS_PROCESS_INFOA;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  WTS_PROCESS_INFO = WTS_PROCESS_INFOW;
  PWTS_PROCESS_INFO = PWTS_PROCESS_INFOW;
  TWtsProcessInfo = TWtsProcessInfoW;
  PWtsProcessInfo = PWtsProcessInfoW;
{$else}
  WTS_PROCESS_INFO = WTS_PROCESS_INFOA;
  PWTS_PROCESS_INFO = PWTS_PROCESS_INFOA;
  TWtsProcessInfo = TWtsProcessInfoA;
  PWtsProcessInfo = PWtsProcessInfoA;
{$endif}

//==============================================================================
// WTS_INFO_CLASS - WTSQuerySessionInformation
// (See additional typedefs for more info on structures)
//==============================================================================

const
  WTS_PROTOCOL_TYPE_CONSOLE = 0; // Console
  WTS_PROTOCOL_TYPE_ICA     = 1; // ICA Protocol
  WTS_PROTOCOL_TYPE_RDP     = 2; // RDP Protocol

type
  _WTS_INFO_CLASS = (
    WTSInitialProgram,
    WTSApplicationName,
    WTSWorkingDirectory,
    WTSOEMId,
    WTSSessionId,
    WTSUserName,
    WTSWinStationName,
    WTSDomainName,
    WTSConnectState,
    WTSClientBuildNumber,
    WTSClientName,
    WTSClientDirectory,
    WTSClientProductId,
    WTSClientHardwareId,
    WTSClientAddress,
    WTSClientDisplay,
    WTSClientProtocolType);
  WTS_INFO_CLASS = _WTS_INFO_CLASS;
  TWtsInfoClass = WTS_INFO_CLASS;

//==============================================================================
// WTSQuerySessionInformation - (WTSClientAddress)
//==============================================================================

type
  PWTS_CLIENT_ADDRESS = ^WTS_CLIENT_ADDRESS;
  _WTS_CLIENT_ADDRESS = record
    AddressFamily: DWORD;           // AF_INET, AF_IPX, AF_NETBIOS, AF_UNSPEC
    Address: array [0..19] of BYTE; // client network address
  end;
  WTS_CLIENT_ADDRESS = _WTS_CLIENT_ADDRESS;
  TWtsClientAddress = WTS_CLIENT_ADDRESS;
  PWtsClientAddress = PWTS_CLIENT_ADDRESS;

//==============================================================================
// WTSQuerySessionInformation - (WTSClientDisplay)
//==============================================================================

type
  PWTS_CLIENT_DISPLAY = ^WTS_CLIENT_DISPLAY;
  _WTS_CLIENT_DISPLAY = record
    HorizontalResolution: DWORD; // horizontal dimensions, in pixels
    VerticalResolution: DWORD;   // vertical dimensions, in pixels
    ColorDepth: DWORD;           // 1=16, 2=256, 4=64K, 8=16M
  end;
  WTS_CLIENT_DISPLAY = _WTS_CLIENT_DISPLAY;
  TWtsClientDisplay = WTS_CLIENT_DISPLAY;
  PWtsClientDisplay = PWTS_CLIENT_DISPLAY;

//==============================================================================
// WTS_CONFIG_CLASS - WTSQueryUserConfig/WTSSetUserConfig
//==============================================================================

type
  _WTS_CONFIG_CLASS = (
    //Initial program settings
    WTSUserConfigInitialProgram,                // string returned/expected
    WTSUserConfigWorkingDirectory,              // string returned/expected
    WTSUserConfigfInheritInitialProgram,        // DWORD returned/expected
    //
    WTSUserConfigfAllowLogonTerminalServer,     //DWORD returned/expected
    //Timeout settings
    WTSUserConfigTimeoutSettingsConnections,    //DWORD returned/expected
    WTSUserConfigTimeoutSettingsDisconnections, //DWORD returned/expected
    WTSUserConfigTimeoutSettingsIdle,           //DWORD returned/expected
    //Client device settings
    WTSUserConfigfDeviceClientDrives,           //DWORD returned/expected
    WTSUserConfigfDeviceClientPrinters,         //DWORD returned/expected
    WTSUserConfigfDeviceClientDefaultPrinter,   //DWORD returned/expected
    //Connection settings
    WTSUserConfigBrokenTimeoutSettings,         //DWORD returned/expected
    WTSUserConfigReconnectSettings,             //DWORD returned/expected
    //Modem settings
    WTSUserConfigModemCallbackSettings,         //DWORD returned/expected
    WTSUserConfigModemCallbackPhoneNumber,      // string returned/expected
    //Shadow settings
    WTSUserConfigShadowingSettings,             //DWORD returned/expected
    //User Profile settings
    WTSUserConfigTerminalServerProfilePath,     // string returned/expected
    //Terminal Server home directory
    WTSUserConfigTerminalServerHomeDir,         // string returned/expected
    WTSUserConfigTerminalServerHomeDirDrive,    // string returned/expected
    WTSUserConfigfTerminalServerRemoteHomeDir); // DWORD 0:LOCAL 1:REMOTE
  WTS_CONFIG_CLASS = _WTS_CONFIG_CLASS;
  TWtsConfigClass = WTS_CONFIG_CLASS;

//==============================================================================
// WTS_EVENT - Event flags for WTSWaitSystemEvent
//==============================================================================

const
  WTS_EVENT_NONE        = $00000000; // return no event
  WTS_EVENT_CREATE      = $00000001; // new WinStation created
  WTS_EVENT_DELETE      = $00000002; // existing WinStation deleted
  WTS_EVENT_RENAME      = $00000004; // existing WinStation renamed
  WTS_EVENT_CONNECT     = $00000008; // WinStation connect to client
  WTS_EVENT_DISCONNECT  = $00000010; // WinStation logged on without client
  WTS_EVENT_LOGON       = $00000020; // user logged on to existing WinStation
  WTS_EVENT_LOGOFF      = $00000040; // user logged off from existing WinStation
  WTS_EVENT_STATECHANGE = $00000080; // WinStation state change
  WTS_EVENT_LICENSE     = $00000100; // license state change
  WTS_EVENT_ALL         = $7fffffff; // wait for all event types
  WTS_EVENT_FLUSH       = DWORD($80000000); // unblock all waiters

//==============================================================================
// WTS_VIRTUAL_CLASS - WTSVirtualChannelQuery
//==============================================================================

type
  _WTS_VIRTUAL_CLASS = (WTSVirtualClientData, WTSVirtualFileHandle);
  WTS_VIRTUAL_CLASS = _WTS_VIRTUAL_CLASS;
  TWtsVirtualClass = WTS_VIRTUAL_CLASS;

//==============================================================================
// Windows Terminal Server public APIs
//==============================================================================

function WTSEnumerateServersA(pDomainName: LPSTR; Reserved, Version: DWORD;
  var ppServerInfo: PWTS_SERVER_INFOA; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateServersW(pDomainName: LPWSTR; Reserved, Version: DWORD;
  var ppServerInfo: PWTS_SERVER_INFOW; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateServers(pDomainName: LPTSTR; Reserved, Version: DWORD;
  var ppServerInfo: PWTS_SERVER_INFO; var pCount: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSOpenServerA(pServerName: LPSTR): HANDLE; stdcall;
function WTSOpenServerW(pServerName: LPWSTR): HANDLE; stdcall;
function WTSOpenServer(pServerName: LPTSTR): HANDLE; stdcall;

//------------------------------------------------------------------------------

procedure WTSCloseServer(hServer: HANDLE); stdcall;

//------------------------------------------------------------------------------

function WTSEnumerateSessionsA(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppSessionInfo: PWTS_SESSION_INFOA; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateSessionsW(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppSessionInfo: PWTS_SESSION_INFOW; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateSessions(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppSessionInfo: PWTS_SESSION_INFO; var pCount: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSEnumerateProcessesA(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppProcessInfo: PWTS_PROCESS_INFOA; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateProcessesW(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppProcessInfo: PWTS_PROCESS_INFOW; var pCount: DWORD): BOOL; stdcall;
function WTSEnumerateProcesses(hServer: HANDLE; Reserved: DWORD; Version: DWORD;
  var ppProcessInfo: PWTS_PROCESS_INFO; var pCount: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSTerminateProcess(hServer: HANDLE; ProcessId, ExitCode: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSQuerySessionInformationA(hServer: HANDLE; SessionId: DWORD;
  WTSInfoClass: WTS_INFO_CLASS; var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;
function WTSQuerySessionInformationW(hServer: HANDLE; SessionId: DWORD;
  WTSInfoClass: WTS_INFO_CLASS; var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;
function WTSQuerySessionInformation(hServer: HANDLE; SessionId: DWORD;
  WTSInfoClass: WTS_INFO_CLASS; var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSQueryUserConfigA(pServerName, pUserName: LPSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;
function WTSQueryUserConfigW(pServerName, pUserName: LPWSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;
function WTSQueryUserConfig(pServerName, pUserName: LPTSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  var ppBuffer: Pointer; var pBytesReturned: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSSetUserConfigA(pServerName, pUserName: LPSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  pBuffer: LPSTR; DataLength: DWORD): BOOL; stdcall;
function WTSSetUserConfigW(pServerName, pUserName: LPWSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  pBuffer: LPWSTR; DataLength: DWORD): BOOL; stdcall;
function WTSSetUserConfig(pServerName, pUserName: LPTSTR; WTSConfigClass: WTS_CONFIG_CLASS;
  pBuffer: LPTSTR; DataLength: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSSendMessageA(hServer: HANDLE; SessionId: DWORD; pTitle: LPSTR;
  TitleLength: DWORD; pMessage: LPSTR; MessageLength: DWORD; Style: DWORD;
  Timeout: DWORD; var pResponse: DWORD; bWait: BOOL): BOOL; stdcall;
function WTSSendMessageW(hServer: HANDLE; SessionId: DWORD; pTitle: LPWSTR;
  TitleLength: DWORD; pMessage: LPWSTR; MessageLength: DWORD; Style: DWORD;
  Timeout: DWORD; var pResponse: DWORD; bWait: BOOL): BOOL; stdcall;
function WTSSendMessage(hServer: HANDLE; SessionId: DWORD; pTitle: LPTSTR;
  TitleLength: DWORD; pMessage: LPTSTR; MessageLength: DWORD; Style: DWORD;
  Timeout: DWORD; var pResponse: DWORD; bWait: BOOL): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSDisconnectSession(hServer: HANDLE; SessionId: DWORD; bWait: BOOL): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSLogoffSession(hServer: HANDLE; SessionId: DWORD; bWait: BOOL): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSShutdownSystem(hServer: HANDLE; ShutdownFlag: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSWaitSystemEvent(hServer: HANDLE; EventMask: DWORD;
  var pEventFlags: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

function WTSVirtualChannelOpen(hServer: HANDLE; SessionId: DWORD;
  pVirtualName: LPSTR): HANDLE; stdcall;

function WTSVirtualChannelClose(hChannelHandle: HANDLE): BOOL; stdcall;

function WTSVirtualChannelRead(hChannelHandle: HANDLE; TimeOut: ULONG;
  Buffer: PAnsiChar; BufferSize: ULONG; var pBytesRead: ULONG): BOOL; stdcall;

function WTSVirtualChannelWrite(hChannelHandle: HANDLE; Buffer: PAnsiChar;
  Length: ULONG; var pBytesWritten: ULONG): BOOL; stdcall;

function WTSVirtualChannelPurgeInput(hChannelHandle: HANDLE): BOOL; stdcall;

function WTSVirtualChannelPurgeOutput(hChannelHandle: HANDLE): BOOL; stdcall;

function WTSVirtualChannelQuery(hChannelHandle: HANDLE; VirtualClass: WTS_VIRTUAL_CLASS;
  ppBuffer: PVOID; var pBytesReturned: DWORD): BOOL; stdcall;

//------------------------------------------------------------------------------

procedure WTSFreeMemory(pMemory: PVOID); stdcall;

// Flags for Console Notification

const
  NOTIFY_FOR_ALL_SESSIONS = 1;
  NOTIFY_FOR_THIS_SESSION = 0;

function WTSRegisterSessionNotification(hWnd: HWND; dwFlags: DWORD): BOOL; stdcall;

function WTSUnRegisterSessionNotification(hWnd: HWND): BOOL; stdcall;

function WTSQueryUserToken(SessionId: ULONG; var phToken: HANDLE): BOOL; stdcall;

implementation
//uses ...

const
  wtsapi = 'wtsapi32.dll';
{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  AWSuffix = 'W';
{$else}
  AWSuffix = 'A';
{$endif}

function WTSEnumerateServersA; external wtsapi name 'WTSEnumerateServersA';
function WTSEnumerateServersW; external wtsapi name 'WTSEnumerateServersW';
function WTSEnumerateServers; external wtsapi name 'WTSEnumerateServers' + AWSuffix;
function WTSOpenServerA; external wtsapi name 'WTSOpenServerA';
function WTSOpenServerW; external wtsapi name 'WTSOpenServerW';
function WTSOpenServer; external wtsapi name 'WTSOpenServer' + AWSuffix;
procedure WTSCloseServer; external wtsapi name 'WTSCloseServer';
function WTSEnumerateSessionsA; external wtsapi name 'WTSEnumerateSessionsA';
function WTSEnumerateSessionsW; external wtsapi name 'WTSEnumerateSessionsW';
function WTSEnumerateSessions; external wtsapi name 'WTSEnumerateSessions' + AWSuffix;
function WTSEnumerateProcessesA; external wtsapi name 'WTSEnumerateProcessesA';
function WTSEnumerateProcessesW; external wtsapi name 'WTSEnumerateProcessesW';
function WTSEnumerateProcesses; external wtsapi name 'WTSEnumerateProcesses' + AWSuffix;
function WTSTerminateProcess; external wtsapi name 'WTSTerminateProcess';
function WTSQuerySessionInformationA; external wtsapi name 'WTSQuerySessionInformationA';
function WTSQuerySessionInformationW; external wtsapi name 'WTSQuerySessionInformationW';
function WTSQuerySessionInformation; external wtsapi name 'WTSQuerySessionInformation' + AWSuffix;
function WTSQueryUserConfigA; external wtsapi name 'WTSQueryUserConfigA';
function WTSQueryUserConfigW; external wtsapi name 'WTSQueryUserConfigW';
function WTSQueryUserConfig; external wtsapi name 'WTSQueryUserConfig' + AWSuffix;
function WTSSetUserConfigA; external wtsapi name 'WTSSetUserConfigA';
function WTSSetUserConfigW; external wtsapi name 'WTSSetUserConfigW';
function WTSSetUserConfig; external wtsapi name 'WTSSetUserConfig' + AWSuffix;
function WTSSendMessageA; external wtsapi name 'WTSSendMessageA';
function WTSSendMessageW; external wtsapi name 'WTSSendMessageW';
function WTSSendMessage; external wtsapi name 'WTSSendMessage' + AWSuffix;
function WTSDisconnectSession; external wtsapi name 'WTSDisconnectSession';
function WTSLogoffSession; external wtsapi name 'WTSLogoffSession';
function WTSShutdownSystem; external wtsapi name 'WTSShutdownSystem';
function WTSWaitSystemEvent; external wtsapi name 'WTSWaitSystemEvent';
function WTSVirtualChannelOpen; external wtsapi name 'WTSVirtualChannelOpen';
function WTSVirtualChannelClose; external wtsapi name 'WTSVirtualChannelClose';
function WTSVirtualChannelRead; external wtsapi name 'WTSVirtualChannelRead';
function WTSVirtualChannelWrite; external wtsapi name 'WTSVirtualChannelWrite';
function WTSVirtualChannelPurgeInput; external wtsapi name 'WTSVirtualChannelPurgeInput';
function WTSVirtualChannelPurgeOutput; external wtsapi name 'WTSVirtualChannelPurgeOutput';
function WTSVirtualChannelQuery; external wtsapi name 'WTSVirtualChannelQuery';
procedure WTSFreeMemory; external wtsapi name 'WTSFreeMemory';
function WTSRegisterSessionNotification; external wtsapi name 'WTSRegisterSessionNotification';
function WTSUnRegisterSessionNotification; external wtsapi name 'WTSUnRegisterSessionNotification';
function WTSQueryUserToken; external wtsapi name 'WTSQueryUserToken';

end.
