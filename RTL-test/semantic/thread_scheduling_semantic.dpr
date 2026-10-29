program thread_scheduling_semantic;
{ %TARGET=linux }
{$mode delphi}{$H+}
uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes, SyncObjs
  {$ifdef LINUX}, Linux, BaseUnix{$endif};

procedure Check(OK: Boolean; const What: string);
begin
  If not OK then raise Exception.Create('THREAD_SCHEDULING_FAIL: '+What);
end;

{$ifdef LINUX}
type
  TWorker = class(TThread)
    Ready, Run: TEvent;
    Observed: TSchedAttr;
    ReadOK: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
  end;
  TNativeEntry = function(Arg: Pointer): Pointer; cdecl;

function NativeCreate(var Handle: TThreadID; Attr: Pointer; Entry: TNativeEntry; Arg: Pointer): LongInt;
  cdecl; external 'pthread' name 'pthread_create';
function NativeJoin(Handle: TThreadID; ThreadResult: Pointer): LongInt;
  cdecl; external 'pthread' name 'pthread_join';

constructor TWorker.Create;
begin
  Ready:=TEvent.Create(nil,True,False,'');
  Run:=TEvent.Create(nil,True,False,'');
  inherited Create(True);
end;

destructor TWorker.Destroy;
begin
  Run.SetEvent;
  inherited Destroy;
  Run.Free;
  Ready.Free;
end;

procedure TWorker.Execute;
begin
  Ready.SetEvent;
  If Run.WaitFor(5000)<>wrSignaled then Exit;
  ReadOK:=TryGetCThreadScheduling(GetCurrentThreadID,Observed);
end;

function NativeEntry(Arg: Pointer): Pointer; cdecl;
var A, B: TSchedAttr;
begin
  { First RTL access in a foreign pthread must hook TLS before registry locking. }
  PBoolean(Arg)^:=TryGetCThreadScheduling(GetCurrentThreadID,A) and
    (sched_getattr(0,@B,SizeOf(B),0)=0) and (A.Nice=B.Nice) and
    TrySetCThreadScheduling(GetCurrentThreadID,A);
  Result:=nil;
end;

procedure Failures;
var A, Saved: TSchedAttr;
begin
  Check(not TryGetCThreadScheduling(0,A),'invalid handle accepted');
  Check(fpGetErrno=ESysESRCH,'invalid handle errno');
  Check(TryGetCThreadScheduling(GetCurrentThreadID,A),'read current');
  A.Size:=SizeOf(A)+8;
  Saved:=A;
  Check(not TrySetCThreadScheduling(GetCurrentThreadID,A),'oversize accepted');
  Check(fpGetErrno=ESysE2BIG,'oversize errno');
  Check(CompareMem(@A,@Saved,SizeOf(A)),'setter changed const input');
  A.Size:=1;
  Saved:=A;
  Check(not TrySetCThreadScheduling(GetCurrentThreadID,A),'undersize accepted');
  Check(fpGetErrno=ESysE2BIG,'undersize errno');
  Check(CompareMem(@A,@Saved,SizeOf(A)),'kernel size write escaped const copy');
  Check(TryGetCThreadScheduling(GetCurrentThreadID,A),'error path leaked registry lock');
  Check(sched_getattr(-1,@A,SizeOf(A),0)=-1,'negative native TID accepted');
  Check(fpGetErrno=ESysEINVAL,'raw errno');
end;

procedure Denied;
var A, B: TSchedAttr;
begin
  Check(TryGetCThreadScheduling(GetCurrentThreadID,A),'denied initial read');
  A.Nice:=-20;
  Check(not TrySetCThreadScheduling(GetCurrentThreadID,A),'unprivileged boost accepted');
  Check(fpGetErrno=ESysEPERM,'denied errno');
  Check(TryGetCThreadScheduling(GetCurrentThreadID,B),'read after refusal');
  Check(B.Nice<>-20,'refusal changed priority');
  WriteLn('THREAD_SCHEDULING_DENIED_VERIFIED');
end;

procedure Slice;
var A, B, Restore: TSchedAttr;
begin
  Check(TryGetCThreadScheduling(GetCurrentThreadID,A),'slice initial read');
  Check(A.Policy=SCHED_OTHER,'slice needs ordinary fair policy');
  Restore:=A;
  { This isolated test process starts with the kernel's default slice. A read
    alone cannot recover that mode; it only returns the effective duration. }
  Restore.Runtime:=0;
  A.Runtime:=100000;
  Check(TrySetCThreadScheduling(GetCurrentThreadID,A),'set custom slice');
  try
    Check(TryGetCThreadScheduling(GetCurrentThreadID,B),'slice readback');
    Check((B.Policy=A.Policy) and (B.Nice=A.Nice),'slice changed policy/nice');
    If B.Runtime=100000 then WriteLn('THREAD_SCHEDULING_SLICE_SUPPORTED')
    else WriteLn('THREAD_SCHEDULING_SLICE_UNSUPPORTED');
  finally
    Check(TrySetCThreadScheduling(GetCurrentThreadID,Restore),'restore automatic slice');
  end;
  Check(TryGetCThreadScheduling(GetCurrentThreadID,B),'restored readback');
  Check((B.Policy=Restore.Policy) and (B.Nice=Restore.Nice),'restored wrong profile');
end;

procedure Urgent;
const Priorities: array[0..2] of LongInt = (-20,-5,5);
var Original, Base, Boost, Actual, Reset: TSchedAttr; N: LongInt;
begin
  Check(TryGetCThreadScheduling(GetCurrentThreadID,Original),'urgent initial read');
  Check(Original.Policy=SCHED_OTHER,'urgent test needs ordinary fair policy');
  Reset:=Original;
  Reset.Runtime:=0; // This standalone probe starts in automatic mode.
  Reset.Flags:=Reset.Flags or SCHED_FLAG_UTIL_CLAMP_MIN or SCHED_FLAG_UTIL_CLAMP_MAX;
  try
    for N in Priorities do begin
      Base:=Original;
      Base.Runtime:=0;
      Base.Nice:=N;
      Base.Flags:=SCHED_FLAG_RESET_ON_FORK or SCHED_FLAG_UTIL_CLAMP_MIN or SCHED_FLAG_UTIL_CLAMP_MAX;
      Base.UtilMin:=128;
      Base.UtilMax:=768;
      Check(TrySetCThreadScheduling(GetCurrentThreadID,Base),'privileged baseline');
      Check(TryGetCThreadScheduling(GetCurrentThreadID,Base),'baseline readback');
      Base.Runtime:=0;
      Boost:=Base;
      If Boost.Nice>-10 then Boost.Nice:=-10;
      Boost.Runtime:=100000;
      Check(TrySetCThreadScheduling(GetCurrentThreadID,Boost),'urgent apply');
      Check(TryGetCThreadScheduling(GetCurrentThreadID,Actual),'urgent readback');
      Check((Actual.Nice=Boost.Nice) and (Actual.Runtime=100000),'urgent profile unsupported');
      Check((Actual.Flags and SCHED_FLAG_RESET_ON_FORK<>0) and
        (Actual.UtilMin=128) and (Actual.UtilMax=768),'urgent changed unrelated attributes');
      Check(TrySetCThreadScheduling(GetCurrentThreadID,Base),'urgent restore');
      Check(TryGetCThreadScheduling(GetCurrentThreadID,Actual) and (Actual.Nice=N),'urgent nice not restored');
    end;
  finally
    Check(TrySetCThreadScheduling(GetCurrentThreadID,Reset),'restore standalone probe state');
  end;
  WriteLn('THREAD_SCHEDULING_URGENT_VERIFIED');
end;

var
  A, B: TSchedAttr;
  W: TWorker;
  Handle: TThreadID;
  NativeOK: Boolean;
  I: Integer;
{$endif}
begin
  {$ifdef LINUX}
  If ParamStr(1)='denied' then begin
    Denied;
    Halt;
  end;
  If ParamStr(1)='urgent' then begin
    Urgent;
    Halt;
  end;
  Check(SizeOf(TSchedAttr)=56,'sched_attr ABI size');
  Check((PtrUInt(@A.Runtime)-PtrUInt(@A)=24) and
    (PtrUInt(@A.UtilMin)-PtrUInt(@A)=48),'sched_attr ABI offsets');
  Check(TryGetCThreadScheduling(GetCurrentThreadID,A),'get current handle');
  Check(sched_getattr(0,@B,SizeOf(B),0)=0,'get native current TID');
  Check((A.Policy=B.Policy) and (A.Nice=B.Nice),'handle mapped to wrong native thread');
  Check(TrySetCThreadScheduling(GetCurrentThreadID,A),'reapply current attributes');
  for I:=1 to 8 do begin
    W:=TWorker.Create;
    try
      Handle:=W.ThreadID;
      Check(TryGetCThreadScheduling(Handle,B),'suspended worker registration');
      W.Start;
      Check(W.Ready.WaitFor(5000)=wrSignaled,'worker did not start');
      Check(B.Nice<19,'test requires initial nice below 19');
      Inc(B.Nice);
      Check(TrySetCThreadScheduling(Handle,B),'set foreign live worker');
      W.Run.SetEvent;
      W.WaitFor;
      Check(W.FatalException=nil,'worker exception');
      Check(W.ReadOK and (W.Observed.Nice=B.Nice),'worker did not see its profile');
      Check(TryGetCThreadScheduling(GetCurrentThreadID,B) and (A.Nice=B.Nice),'setter changed sender');
      Check(not TryGetCThreadScheduling(Handle,B),'joined thread still registered');
      Check(fpGetErrno=ESysESRCH,'joined thread errno');
    finally
      W.Free;
    end;
  end;
  NativeOK:=False;
  Check(NativeCreate(Handle,nil,@NativeEntry,@NativeOK)=0,'foreign pthread create');
  Check(NativeJoin(Handle,nil)=0,'foreign pthread join');
  Check(NativeOK,'foreign pthread hook');
  Failures;
  Slice;
  WriteLn('THREAD_SCHEDULING_PASS');
  {$else}
  WriteLn('THREAD_SCHEDULING_NOT_LINUX');
  {$endif}
end.
