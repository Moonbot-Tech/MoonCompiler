{
    This file is part of the Free Pascal run time library.
    This unit contains the record definition for the Win64 API
    Copyright (c) 1999-2006 by Florian KLaempfl,
    member of the Free Pascal development team.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit windows;
{$ENDIF FPC_DOTTEDUNITS}

{$PACKSET 1}

{$ifndef NO_SMART_LINK}
{$smartlink on}
{$endif}

{ stuff like array of const is used }
{$mode objfpc}
{$modeswitch ADVANCEDRECORDS}
{$modeswitch class}
{$inline on}
{$calling stdcall}

{$ifdef FPC_OS_UNICODE}
  {$define UNICODE}
{$endif}

interface

{$define read_interface}
{$undef read_implementation}

{$i base.inc}
{$i errors.inc}
{$i defines.inc}
{$i struct.inc}
{$i messages.inc}
{$i ascfun.inc}
{$i unifun.inc}
{$ifdef UNICODE}
{$i unidef.inc}
{$else not UNICODE}
{$i ascdef.inc}
{$endif UNICODE}
{$i func.inc}
{$i redef.inc}

{ SDK declarations used by ordinary service and diagnostics code. }
type
  TTopLevelExceptionFilter = function(Info: PEXCEPTION_POINTERS): LONG; stdcall;
  LPTOP_LEVEL_EXCEPTION_FILTER = TTopLevelExceptionFilter;
  TFNTopLevelExceptionFilter = TFarProc;
function SetUnhandledExceptionFilter(Filter: TFNTopLevelExceptionFilter): TFNTopLevelExceptionFilter;
  external 'kernel32' name 'SetUnhandledExceptionFilter';
function SetDllDirectoryA(Path: LPCSTR): BOOL; external 'kernel32' name 'SetDllDirectoryA';
function SetDllDirectoryW(Path: LPCWSTR): BOOL; external 'kernel32' name 'SetDllDirectoryW';
function GetDllDirectoryA(Length: DWORD; Buffer: LPSTR): DWORD; external 'kernel32' name 'GetDllDirectoryA';
function GetDllDirectoryW(Length: DWORD; Buffer: LPWSTR): DWORD; external 'kernel32' name 'GetDllDirectoryW';
{$ifdef UNICODE}
function SetDllDirectory(Path: LPCWSTR): BOOL; external 'kernel32' name 'SetDllDirectoryW';
function GetDllDirectory(Length: DWORD; Buffer: LPWSTR): DWORD; external 'kernel32' name 'GetDllDirectoryW';
{$else}
function SetDllDirectory(Path: LPCSTR): BOOL; external 'kernel32' name 'SetDllDirectoryA';
function GetDllDirectory(Length: DWORD; Buffer: LPSTR): DWORD; external 'kernel32' name 'GetDllDirectoryA';
{$endif}

implementation

{$undef read_interface}
{$define read_implementation}

{$i base.inc}
{$i errors.inc}
{$i defines.inc}
{$i struct.inc}
{$i messages.inc}
{$i ascfun.inc}
{$i unifun.inc}
{$ifdef UNICODE}
{$i unidef.inc}
{$else not UNICODE}
{$i ascdef.inc}
{$endif UNICODE}
{$i func.inc}
{$i redef.inc}

end.
