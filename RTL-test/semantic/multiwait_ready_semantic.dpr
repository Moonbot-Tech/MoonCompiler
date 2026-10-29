program multiwait_ready_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
uses {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes, Types;
type
  TSetter = class(TThread)
    First, Second: TMultiWaitEvent;
    procedure Execute; override;
  end;
{$ifdef FPC}
var Original, Wrapped: TMemoryManager; Allocations: Integer;
function CountGetMem(Size: PtrUInt): Pointer;
begin
  Inc(Allocations);
  Result:=Original.GetMem(Size);
end;
function CountAllocMem(Size: PtrUInt): Pointer;
begin
  Inc(Allocations);
  Result:=Original.AllocMem(Size);
end;
{$endif}
procedure Check(Value: Boolean; const Text: string);
begin
  If not Value then raise Exception.Create(Text);
end;
procedure TSetter.Execute;
begin
  Sleep(5);
  First.SetEvent;
  If Assigned(Second) then begin
    Sleep(5);
    Second.SetEvent;
  end;
end;
var A, B, Selected: TMultiWaitEvent; I, Index: Integer; W: TSetter; Raised: Boolean;
begin
  A:=TMultiWaitEvent.Create;
  B:=TMultiWaitEvent.Create;
  try
    {$ifdef FPC}
    GetMemoryManager(Original);
    Wrapped:=Original;
    Wrapped.GetMem:=CountGetMem;
    Wrapped.AllocMem:=CountAllocMem;
    Allocations:=0;
    SetMemoryManager(Wrapped);
    try
    {$endif}
      for I:=1 to 1000 do begin
        Check(TMultiWaitEvent.WaitForAny([A,B],Index,0)=wrTimeout,'empty any poll');
        Check(Index=-1,'timeout index');
        A.SetEvent;
        Check(TMultiWaitEvent.WaitForAny([B,A],Selected,100)=wrSignaled,'ready any');
        Check(Selected=A,'selected event');
        Check(TMultiWaitEvent.WaitForAll([A,B],0)=wrTimeout,'incomplete all poll');
        B.SetEvent;
        Check(TMultiWaitEvent.WaitForAll([A,B,A],100)=wrSignaled,'ready all with duplicate');
        A.ResetEvent;
        B.ResetEvent;
      end;
    {$ifdef FPC}
    finally
      SetMemoryManager(Original);
    end;
    {$ifdef WAIT_WORK_PROBE}
    Check(Allocations=0,'ready and poll paths allocated a wait object');
    {$endif}
    {$endif}
    A.SetEvent;
    Raised:=False;
    try
      TMultiWaitEvent.WaitForAny([A,nil],0);
    except
      on E: EArgumentNilException do Raised:=True;
    end;
    Check(Raised,'ready first entry hid nil input');
    A.ResetEvent;
    for I:=1 to 20 do begin
      W:=TSetter.Create(True);
      W.First:=B;
      W.Start;
      Check(TMultiWaitEvent.WaitForAny([A,B],Index,2000)=wrSignaled,'blocked any');
      Check(Index=1,'blocked any index');
      W.WaitFor;
      Check(W.FatalException=nil,'setter failure');
      W.Free;
      B.ResetEvent;
      W:=TSetter.Create(True);
      W.First:=A;
      W.Second:=B;
      W.Start;
      Check(TMultiWaitEvent.WaitForAll([A,B],2000)=wrSignaled,'blocked all');
      W.WaitFor;
      Check(W.FatalException=nil,'setter failure');
      W.Free;
      A.ResetEvent;
      B.ResetEvent;
    end;
  finally
    A.Free;
    B.Free;
  end;
  WriteLn('MULTIWAIT_READY_PASS');
end.
