program TraceBoundaries;
{$mode objfpc}{$H+}
uses cthreads, SysUtils, Classes, lnfodwrf;

procedure Marker; noinline;
begin
  if ParamCount<0 then WriteLn('no');
end;

type TModuleHook=procedure(Addr:Pointer; var BaseAddr:Pointer; var Name:AnsiString);
var OriginalModule:TModuleHook;
  OriginalTrace:TBackTraceStrFunc;
  Entered,ReleaseFirst,SecondStarted:PRTLEvent;
  CallCount:LongInt;
  Mode:AnsiString;

procedure ModuleHook(Addr:Pointer; var BaseAddr:Pointer; var Name:AnsiString);
begin
  Inc(CallCount);
  if (Mode='failure') and (CallCount=1) then raise Exception.Create('injected reader failure');
  if (Mode='recursive') and (CallCount=1) then begin
    WriteLn('RECURSIVE_TRACE=',BackTraceStrFunc(Addr)); Flush(Output);
  end;
  if (Mode='concurrent') and (CallCount=1) then begin
    RTLEventSetEvent(Entered);
    RTLEventWaitFor(ReleaseFirst);
  end;
  OriginalModule(Addr,BaseAddr,Name);
end;

type TTraceThread=class(TThread)
  Index:Integer;
  Trace:ShortString;
  Error:ShortString;
  procedure Execute; override;
end;
procedure TTraceThread.Execute;
begin
  try
    if (Index=1) and (Mode='concurrent') then RTLEventSetEvent(SecondStarted);
    Trace:=DwarfBackTraceStr(CodePointer(PtrUInt(@Marker)+PtrUInt(Index)));
  except
    on E:Exception do Error:=E.ClassName+':'+E.Message;
  end;
end;

var A,B:TTraceThread; F,S:ShortString; L:LongInt; Trace:ShortString;
begin
  Mode:=ParamStr(1);
  OriginalModule:=UnixGetModuleByAddrHook;
  OriginalTrace:=BackTraceStrFunc;
  UnixGetModuleByAddrHook:=@ModuleHook;
  if Mode='close-io' then begin
    WriteLn('INITIAL=',GetLineInfo(PtrUInt(@Marker)+1,F,S,L));
    InOutRes:=2;
    CloseDwarf;
    L:=InOutRes;
    InOutRes:=0;
    WriteLn('IO_PRESERVED=',L=2);
    A:=TTraceThread.Create(True); A.Index:=2; A.Start;
    A.WaitFor;
    WriteLn('WORKER_TRACE=',A.Trace);
    WriteLn('WORKER_ERROR=',A.Error);
    A.Free;
    UnixGetModuleByAddrHook:=OriginalModule;
    Exit;
  end;
  if Mode='concurrent' then begin
    Entered:=RTLEventCreate;
    ReleaseFirst:=RTLEventCreate;
    SecondStarted:=RTLEventCreate;
    A:=TTraceThread.Create(True); A.Index:=0; A.Start;
    RTLEventWaitFor(Entered);
    B:=TTraceThread.Create(True); B.Index:=1; B.Start;
    RTLEventWaitFor(SecondStarted);
    Sleep(100);
    RTLEventSetEvent(ReleaseFirst);
    A.WaitFor; B.WaitFor;
    WriteLn('TRACE_A=',A.Trace); WriteLn('TRACE_B=',B.Trace);
    A.Free; B.Free;
    RTLEventDestroy(Entered); RTLEventDestroy(ReleaseFirst); RTLEventDestroy(SecondStarted);
  end else begin
    try
      Trace:=DwarfBackTraceStr(@Marker);
      WriteLn('TRACE=',Trace);
    except
      on E:Exception do WriteLn('TRACE_ERROR=',E.Message);
    end;
  end;
  WriteLn('HOOK_PRESERVED=',CodePointer(OriginalTrace)=CodePointer(BackTraceStrFunc));
  UnixGetModuleByAddrHook:=OriginalModule;
  WriteLn('RETRY=',GetLineInfo(PtrUInt(@Marker),F,S,L),' ',F,' ',S,':',L);
  CloseDwarf;
end.
