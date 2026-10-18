{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1999-2000 by Michael Van Canneyt and Florian Klaempfl

    Classes unit for linux

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$h+}
{$modeswitch advancedrecords}
{$if FPC_FULLVERSION>=30301}
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
{$define Win16Res}

{$IFNDEF FPC_DOTTEDUNITS}
unit Classes;
{$ENDIF FPC_DOTTEDUNITS}
{$INLINE ON}

interface

{$ifdef NO_FPC_USE_INTRINSICS}
  {$undef FPC_USE_INTRINSICS}
{$endif}
{$IFDEF FPC_DOTTEDUNITS}
uses
  System.SysUtils,
  System.Types,
  System.TypInfo,
{$ifdef FPC_TESTGENERICS}
  System.FGL,
{$endif}
  System.RtlConsts,
{$ifdef FPC_USE_INTRINSICS}
  System.Intrinsics,
{$endif}
  System.SortBase;
{$ELSE FPC_DOTTEDUNITS}
uses
  sysutils,
  types,
  typinfo,
{$ifdef FPC_TESTGENERICS}
  fgl,
{$endif}
  rtlconsts,
{$ifdef FPC_USE_INTRINSICS}
  intrinsics,
{$endif}
  sortbase;
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

{$i classesh.inc}

implementation

{$IFDEF FPC_DOTTEDUNITS}
uses
  UnixApi.Base,UnixApi.Unix
  ;
{$ELSE FPC_DOTTEDUNITS}
uses
  BaseUnix,unix
  ;
{$ENDIF FPC_DOTTEDUNITS}

{$IFDEF LINUX}
{$DEFINE HAS_TTHREAD_GETSYSTEMTIMES}
class function TThread.GetSystemTimes(out aSystemTimes : TSystemTimes) : Boolean;
var
  Times: TSystemTimes;

  procedure StoreTime(aField : integer; aTime : QWord);
  begin
    case aField of
      1: Times.UserTime:=aTime;
      2: Times.NiceTime:=aTime;
      3,6,7,8: Inc(Times.KernelTime,aTime);
      4,5: begin
           Inc(Times.IdleTime,aTime);
           Inc(Times.KernelTime,aTime);
           end;
    end;
  end;


const
  StatFile = '/proc/stat';
  CPULine = 'cpu';
  BufSize = 1024;

var
  { /proc/stat is bytes; Char is a WideChar in the Unicode RTL }
  Buf: array[0..BufSize-1] of AnsiChar;
  fd: cint;
  BytesRead, Pos, Len: SizeInt;
  V: QWord;
  lField: Integer;
  lDigits: Boolean;
  Ch: AnsiChar;



begin
  Result := False;
  aSystemTimes := Default(TSystemTimes);
  Times := Default(TSystemTimes);
  fd:=FileOpen(StatFile,fmOpenRead or fmShareDenyNone);
  if fd<0 then
    Exit;
  try
    BytesRead:=fpRead(fd,Buf,BufSize);
    if BytesRead<=0 then
      Exit;
    Len:=BytesRead;
    { Find the first line starting with 'cpu ' (the aggregate line). }
    Pos:=0;
    if (Len<4) or (Buf[0]<>'c') or (Buf[1]<>'p') or (Buf[2]<>'u') or (Buf[3]<>' ') then
      Exit;
    Pos:=4;
    // user nice system idle iowait irq softirq steal; guest is already in user/nice
    lField:=1;
    V:=0;
    lDigits:=False;
    while Pos<Len do
      begin
      Ch:=Buf[Pos];
      if Ch=#10 then
        Break;
      if (Ch>='0') and (Ch<='9') then
        begin
        lDigits:=True;
        V:=V*10+(Ord(Ch)-Ord('0'));
        end
      else begin
        If not (Ch in [#9,' ']) then
          Exit;
        If lDigits then begin
          StoreTime(lField,V);
          Inc(lField);
          V:=0;
          lDigits:=False;
          If lField > 8 then
            Break;
        end;
      end;
      Inc(Pos);
    end;
    { A number ending at the read boundary may be truncated. A newline ends a complete field. }
    If lDigits and (lField<=8) and (Pos<Len) then
      begin
      StoreTime(lField,V);
      Inc(lField);
      end;
    Result:=lField>8;
    If Result then
      aSystemTimes:=Times;
  finally
    fpClose(fd);
  end;
end;
{$ENDIF}


{ OS - independent class implementations are in /inc directory. }
{$i classes.inc}


initialization
  CommonInit;
finalization
  CommonCleanup;

  if ThreadsInited then
     DoneThreads;
end.
