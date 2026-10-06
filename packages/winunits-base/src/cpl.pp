{******************************************************************************}
{                                                                              }
{ Control Panel Applets Interface Unit for Object Pascal                       }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: cpl.h, released June 2000. The original Pascal         }
{ code is: Cpl.pas, released December 2000. The initial developer of the       }
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

// $Id: Cpl.pas,v 1.10 2007/09/06 14:57:11 marquardt Exp $

unit Cpl;
{$mode delphi}{$H+}{$packrecords 1}{$packenum 4}

interface

uses Windows;

//
// General rules for being installed in the Control Panel:
//
//     1) The DLL must export a function named CPlApplet which will handle
//        the messages discussed below.
//     2) If the applet needs to save information in CONTROL.INI minimize
//        clutter by using the application name [MMCPL.appletname].
//     2) If the applet is referenced in CONTROL.INI under [MMCPL] use
//        the following form:
//             ...
//             [MMCPL]
//             uniqueName=c:\mydir\myapplet.dll
//             ...
//
//
// The order applet DLL's are loaded by CONTROL.EXE is not guaranteed.
// Control panels may be sorted for display, etc.
//
//

// #include <pshpack1.h>   // Assume byte packing throughout

//
// CONTROL.EXE will answer this message and launch an applet
//
// WM_CPL_LAUNCH
//
//      wParam      - window handle of calling app
//      lParam      - LPTSTR of name of applet to launch
//
// WM_CPL_LAUNCHED
//
//      wParam      - TRUE/FALSE if applet was launched
//      lParam      - NULL
//
// CONTROL.EXE will post this message to the caller when the applet returns
// (ie., when wParam is a valid window handle)
//
//

const
  WM_CPL_LAUNCH   = WM_USER + 1000;
  WM_CPL_LAUNCHED = WM_USER + 1001;

type
// A function prototype for CPlApplet()
  APPLET_PROC = function(hwndCpl: HWND; msg: UINT;
    lParam1, lParam2: LPARAM): LONG; stdcall;
  TCPLApplet = APPLET_PROC;

// The data structure CPlApplet() must fill in.

  LPCPLINFO = ^CPLINFO;
  tagCPLINFO = record
    idIcon: Integer; // icon resource id, provided by CPlApplet()
    idName: Integer; // name string res. id, provided by CPlApplet()
    idInfo: Integer; // info string res. id, provided by CPlApplet()
    lData: LONG_PTR; // user defined data
  end;
  CPLINFO = tagCPLINFO;

  TCplInfo = CPLINFO;
  PCplInfo = LPCPLINFO;

  LPNEWCPLINFOA = ^NEWCPLINFOA;
  tagNEWCPLINFOA = record
    dwSize: DWORD;                       // similar to the commdlg
    dwFlags: DWORD;
    dwHelpContext: DWORD;                // help context to use
    lData: LONG_PTR;                     // user defined data
    hIcon: HICON; // icon to use, this is owned by CONTROL.EXE (may be deleted)
    szName: array [0..31] of AnsiChar;       // short name
    szInfo: array [0..63] of AnsiChar;       // long name (status line)
    szHelpFile: array [0..127] of AnsiChar;  // path to help file to use
  end;
  NEWCPLINFOA = tagNEWCPLINFOA;
  TNewCplInfoA = NEWCPLINFOA;
  PNewCplInfoA = LPNEWCPLINFOA;

  LPNEWCPLINFOW = ^NEWCPLINFOW;
  tagNEWCPLINFOW = record
    dwSize: DWORD;                       // similar to the commdlg
    dwFlags: DWORD;
    dwHelpContext: DWORD;                // help context to use
    lData: LONG_PTR;                     // user defined data
    hIcon: HICON; // icon to use, this is owned by CONTROL.EXE (may be deleted)
    szName: array [0..31] of WCHAR;      // short name
    szInfo: array [0..63] of WCHAR;      // long name (status line)
    szHelpFile: array [0..127] of WCHAR; // path to help file to use
  end;
  NEWCPLINFOW = tagNEWCPLINFOW;
  TNewCplInfoW = NEWCPLINFOW;

  PNewCplInfoW = LPNEWCPLINFOW;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  NEWCPLINFO = NEWCPLINFOW;
  LPNEWCPLINFO = LPNEWCPLINFOW;
  TNewCplInfo = TNewCplInfoW;
  PNewCplInfo = PNewCplInfoW;
{$else}
  NEWCPLINFO = NEWCPLINFOA;
  LPNEWCPLINFO = LPNEWCPLINFOA;
  TNewCplInfo = TNewCplInfoA;
  PNewCplInfo = PNewCplInfoA;
{$endif}

const
  CPL_DYNAMIC_RES = 0;

// This constant may be used in place of real resource IDs for the idIcon,
// idName or idInfo members of the CPLINFO structure.  Normally, the system
// uses these values to extract copies of the resources and store them in a
// cache.  Once the resource information is in the cache, the system does not
// need to load a CPL unless the user actually tries to use it.
// CPL_DYNAMIC_RES tells the system not to cache the resource, but instead to
// load the CPL every time it needs to display information about an item.  This
// allows a CPL to dynamically decide what information will be displayed, but
// is SIGNIFICANTLY SLOWER than displaying information from a cache.
// Typically, CPL_DYNAMIC_RES is used when a control panel must inspect the
// runtime status of some device in order to provide text or icons to display.

// The messages CPlApplet() must handle:

  CPL_INIT = 1;

//  This message is sent to indicate CPlApplet() was found.
//  lParam1 and lParam2 are not defined.
//  Return TRUE or FALSE indicating whether the control panel should proceed.

  CPL_GETCOUNT = 2;

//  This message is sent to determine the number of applets to be displayed.
//  lParam1 and lParam2 are not defined.
//  Return the number of applets you wish to display in the control
//  panel window.

  CPL_INQUIRE = 3;

//  This message is sent for information about each applet.

//  A CPL SHOULD HANDLE BOTH THE CPL_INQUIRE AND CPL_NEWINQUIRE MESSAGES.
//  The developer must not make any assumptions about the order or dependence
//  of CPL inquiries.

//  lParam1 is the applet number to register, a value from 0 to
//  (CPL_GETCOUNT - 1).  lParam2 is a far ptr to a CPLINFO structure.
//  Fill in CPLINFO's idIcon, idName, idInfo and lData fields with
//  the resource id for an icon to display, name and description string ids,
//  and a long data item associated with applet #lParam1.  This information
//  may be cached by the caller at runtime and/or across sessions.
//  To prevent caching, see CPL_DYNAMIC_RES, above.

  CPL_SELECT = 4;

//  The CPL_SELECT message has been deleted.

  CPL_DBLCLK = 5;

//  This message is sent when the applet's icon has been double-clicked
//  upon.  lParam1 is the applet number which was selected.  lParam2 is the
//  applet's lData value.
//  This message should initiate the applet's dialog box.

  CPL_STOP = 6;

//  This message is sent for each applet when the control panel is exiting.
//  lParam1 is the applet number.  lParam2 is the applet's lData  value.
//  Do applet specific cleaning up here.

  CPL_EXIT = 7;

//  This message is sent just before the control panel calls FreeLibrary.
//  lParam1 and lParam2 are not defined.
//  Do non-applet specific cleaning up here.

  CPL_NEWINQUIRE = 8;

// Same as CPL_INQUIRE execpt lParam2 is a pointer to a NEWCPLINFO struct.

//  A CPL SHOULD HANDLE BOTH THE CPL_INQUIRE AND CPL_NEWINQUIRE MESSAGES.
//  The developer must not make any assumptions about the order or dependence
//  of CPL inquiries.

  CPL_STARTWPARMSA = 9;
  CPL_STARTWPARMSW = 10;

{$if defined(FPC_OS_UNICODE) or defined(MOONCOMPILER_UNICODE_DEFAULT)}
  CPL_STARTWPARMS = CPL_STARTWPARMSW;
{$else}
  CPL_STARTWPARMS = CPL_STARTWPARMSA;
{$endif}

// this message parallels CPL_DBLCLK in that the applet should initiate
// its dialog box.  where it differs is that this invocation is coming
// out of RUNDLL, and there may be some extra directions for execution.
// lParam1: the applet number.
// lParam2: an LPSTR to any extra directions that might exist.
// returns: TRUE if the message was handled; FALSE if not.

// This message is internal to the Control Panel and MAIN applets.
// It is only sent when an applet is invoked from the Command line
// during system installation.

  CPL_SETUP = 200;

implementation
//uses ...

//your implementation here

end.
