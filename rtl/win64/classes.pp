{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1998-2006 by Michael Van Canneyt and Florian Klaempfl

    Classes unit for winx64

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$H+}
{$modeswitch advancedrecords}
{$IF FPC_FULLVERSION>=30301}
{$modeswitch FUNCTIONREFERENCES}
{$define FPC_HAS_REFERENCE_PROCEDURE}
{$ifndef CPULLVM}
{$if DEFINED(CPUARM) or DEFINED(CPUAARCH64)}
   {$define FPC_USE_INTRINSICS}
{$endif}
{$if defined(CPUPOWERPC) or defined(CPUPOWERPC64)}
   {$define FPC_USE_INTRINSICS}
{$endif}
{$if defined(CPURISCV32) or defined(CPURISCV64)}
   {$define FPC_USE_INTRINSICS}
{$endif}
{$endif}
{$endif}

{ determine the type of the resource/form file }
{ $define Win16Res}

{$IFNDEF FPC_DOTTEDUNITS}
unit Classes;
{$ENDIF FPC_DOTTEDUNITS}

interface

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.RtlConsts,
  System.SysUtils,
  System.Types,
  System.SortBase,
{$ifdef FPC_TESTGENERICS}
  System.FGL,
{$endif}
  System.TypInfo,
{$ifdef FPC_USE_INTRINSICS}
  System.Intrinsics,
{$endif}
  WinApi.Windows;
{$ELSE FPC_DOTTEDUNITS}
uses
  rtlconsts,
  sysutils,
  types,
  sortbase,
{$ifdef FPC_TESTGENERICS}
  fgl,
{$endif}
  typinfo,
{$ifdef FPC_USE_INTRINSICS}
  intrinsics,
{$endif}
  windows;
{$ENDIF FPC_DOTTEDUNITS}

{ Also set FPC_USE_INTRINSICS for i386 and x86_64,
  but only after _USES clause as there
  is not intinsics unit for those CPUs }
{$IF FPC_FULLVERSION>=30301}
{$ifndef CPULLVM}
{$if defined(CPUI386) or defined(CPUX86_64)}
   {$define FPC_USE_INTRINSICS}
{$endif}
{$endif}
{$endif}

type
  TWndMethod = procedure(var msg : TMessage) of object;

function MakeObjectInstance(Method: TWndMethod): Pointer;
procedure FreeObjectInstance(ObjectInstance: Pointer);

function AllocateHWnd(Method: TWndMethod): HWND;
procedure DeallocateHWnd(Wnd: HWND);

{$i classesh.inc}

implementation

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.SysConst;
{$ELSE FPC_DOTTEDUNITS}
uses
  sysconst;
{$ENDIF FPC_DOTTEDUNITS}

{$DEFINE HAS_TTHREAD_GETSYSTEMTIMES}
function WinGetSystemTimes(IdleTime, KernelTime, UserTime: PQWord): LongBool; stdcall;
  external 'kernel32' name 'GetSystemTimes';

class function TThread.GetSystemTimes(out aSystemTimes : TSystemTimes) : Boolean;
begin
  { FILETIME counts of all processors; the kernel time includes the idle time }
  aSystemTimes:=Default(TSystemTimes);
  Result:=WinGetSystemTimes(@aSystemTimes.IdleTime,@aSystemTimes.KernelTime,@aSystemTimes.UserTime);
end;

{ OS - independent class implementations are in /inc directory. }
{$i classes.inc}

type
  PWndMethod = ^TWndMethod;
  PObjectWindowThunk = ^TObjectWindowThunk;
  TObjectWindowThunk = record
    Code: array[0..21] of Byte;
    Method: TWndMethod;
  end;

function DispatchObjectMessage(Method: PWndMethod; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Message: TMessage;
begin
  Message:=Default(TMessage);
  Message.Msg:=Msg;
  Message.WParam:=WParam;
  Message.LParam:=LParam;
  Method^(Message);
  Result:=Message.Result;
end;

function MakeObjectInstance(Method: TWndMethod): Pointer;
var
  Thunk: PObjectWindowThunk;
  Address: Pointer;
  OldProtect: DWORD;
begin
  if not Assigned(Method) then
    raise EArgumentNilException.Create('Window method must be assigned');
  Thunk:=VirtualAlloc(nil,SizeOf(TObjectWindowThunk),MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE);
  if Thunk=nil then
    RaiseLastOSError;
  try
    Thunk^.Method:=Method;
    { Win64 passes HWND, message, wParam, lParam in RCX, RDX, R8, R9.
      A TWndMethod has no HWND argument. Replace only RCX by the method
      descriptor and tail-jump to a normally compiled, unwindable function. }
    Thunk^.Code[0]:=$48;
    Thunk^.Code[1]:=$B9; { mov rcx, imm64 }
    Address:=@Thunk^.Method;
    Move(Address,Thunk^.Code[2],SizeOf(Address));
    Thunk^.Code[10]:=$48;
    Thunk^.Code[11]:=$B8; { mov rax, imm64 }
    Address:=@DispatchObjectMessage;
    Move(Address,Thunk^.Code[12],SizeOf(Address));
    Thunk^.Code[20]:=$FF;
    Thunk^.Code[21]:=$E0; { jmp rax -- no stack frame or return address added }
    if not VirtualProtect(Thunk,SizeOf(TObjectWindowThunk),PAGE_EXECUTE_READ,OldProtect) then
      RaiseLastOSError;
    if not FlushInstructionCache(GetCurrentProcess,Thunk,SizeOf(Thunk^.Code)) then
      RaiseLastOSError;
    Result:=Thunk;
  except
    VirtualFree(Thunk,0,MEM_RELEASE);
    raise;
  end;
end;

procedure FreeObjectInstance(ObjectInstance: Pointer);
begin
  if (ObjectInstance<>nil) and not VirtualFree(ObjectInstance,0,MEM_RELEASE) then
    RaiseLastOSError;
end;

function AllocateHWnd(Method: TWndMethod): HWND;
const
  WindowClassName = WideString('MoonCompiler.Classes.HiddenWindow');
var
  WindowClass: WNDCLASSW;
  Instance: Pointer;
  Error: DWORD;
begin
  Instance:=MakeObjectInstance(Method);
  try
    WindowClass:=Default(WNDCLASSW);
    WindowClass.hInstance:=HInstance;
    WindowClass.lpfnWndProc:=@DefWindowProcW;
    WindowClass.cbWndExtra:=SizeOf(Pointer);
    WindowClass.lpszClassName:=PWideChar(WindowClassName);
    if (RegisterClassW(WindowClass)=0) and (GetLastError<>ERROR_CLASS_ALREADY_EXISTS) then
      RaiseLastOSError;
    Result:=CreateWindowExW(WS_EX_TOOLWINDOW,WindowClass.lpszClassName,'',WS_POPUP,
      0,0,0,0,0,0,HInstance,nil);
    if Result=0 then
      RaiseLastOSError;
    SetWindowLongPtrW(Result,0,LONG_PTR(Instance));
    SetLastError(0);
    if (SetWindowLongPtrW(Result,GWLP_WNDPROC,LONG_PTR(Instance))=0) and (GetLastError<>0) then
      begin
        Error:=GetLastError;
        DestroyWindow(Result);
        RaiseLastOSError(Error);
      end;
  except
    FreeObjectInstance(Instance);
    raise;
  end;
end;

procedure DeallocateHWnd(Wnd: HWND);
var
  Instance: Pointer;
begin
  if Wnd=0 then
    Exit;
  Instance:=Pointer(GetWindowLongPtrW(Wnd,0));
  if not DestroyWindow(Wnd) then
    RaiseLastOSError;
  FreeObjectInstance(Instance);
end;


initialization
  CommonInit;

finalization
  CommonCleanup;
end.
