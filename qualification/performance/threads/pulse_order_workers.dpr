program pulse_order_workers;
{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
{$Q-}{$R-}
uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Classes, SyncObjs,
  {$ifdef MSWINDOWS}Windows{$else}Unix, UnixType{$endif};

{ Fixed useful work and selected-recipient latency in the SAME sparse workload.
  No trading, networking or file logging. A timeout is not an input signal.
  Run each binary serially, on the same reserved CPU(s), using pulse_orders.py. }
type
  TCpu = record UserNs, KernelNs: UInt64; end;
  TWorker = class(TThread)
    Id, Issued, Received: Integer;
    Event: TEvent;
    SentNs, Digest, Timeouts, MinTimeoutNs, Generated, Delivered, Bytes, DeliveredBytes: UInt64;
    Latencies: array of UInt64;
    Log: TStringList;
    Lock: TCriticalSection;
    procedure Deliver;
    procedure Execute; override;
    constructor Create(AId: Integer);
    destructor Destroy; override;
  end;
  TMainWake = class
    Event: TEvent;
    procedure Wake(Sender: TObject);
  end;
  TProducer = class(TThread)
    procedure Execute; override;
  end;
{$ifdef LINUX}
  TRUsage = record
    UserTime, SystemTime: TTimeVal;
    Other: array[0..13] of Int64;
  end;
function GetUsage(Who: Integer; out Usage: TRUsage): Integer; cdecl; external 'c' name 'getrusage';
function LibcClock(Id: Integer; out Stamp: TTimeSpec): Integer; cdecl; external 'c' name 'clock_gettime';
{$else}
function ReadCycles(Process: THandle; out Cycles: UInt64): BOOL; stdcall;
  external 'kernel32.dll' name 'QueryProcessCycleTime';
{$endif}

var
  Workers: array of TWorker;
  Gate, Ack: TEvent;
  MainWake: TMainWake;
  Ready, Completed: LongInt;
  Count, Rounds, PeriodMs, SignalsPerWorker: Integer;
  Mode: string;
  DoWork, SelectedOnly: Boolean;
  TimeoutSlackNs: UInt64;
  GranularityUS: Cardinal;
  EffectiveTimeoutNs: UInt64;
  {$ifdef MSWINDOWS}Frequency: Int64;{$endif}

function WallNs: UInt64;
{$ifdef MSWINDOWS}
var C: Int64;
begin
  QueryPerformanceCounter(C);
  Result:=UInt64(C div Frequency)*1000000000+UInt64(C mod Frequency)*1000000000 div UInt64(Frequency);
{$else}
var T: TTimeSpec;
begin
  If LibcClock(1,T)<>0 then RaiseLastOSError;
  Result:=UInt64(T.tv_sec)*1000000000+UInt64(T.tv_nsec);
{$endif}
end;

function Cpu: TCpu;
{$ifdef MSWINDOWS}
var C, E, K, U: TFileTime;
begin
  If not GetProcessTimes(GetCurrentProcess,C,E,K,U) then RaiseLastOSError;
  Result.UserNs:=(UInt64(U.dwHighDateTime) shl 32 or U.dwLowDateTime)*100;
  Result.KernelNs:=(UInt64(K.dwHighDateTime) shl 32 or K.dwLowDateTime)*100;
{$else}
var R: TRUsage;
begin
  If GetUsage(0,R)<>0 then RaiseLastOSError;
  Result.UserNs:=UInt64(R.UserTime.tv_sec)*1000000000+UInt64(R.UserTime.tv_usec)*1000;
  Result.KernelNs:=UInt64(R.SystemTime.tv_sec)*1000000000+UInt64(R.SystemTime.tv_usec)*1000;
{$endif}
end;

procedure Check(Value: Boolean; const Reason: string);
begin
  If not Value then raise Exception.Create(Reason);
end;

constructor TWorker.Create(AId: Integer);
begin
  inherited Create(True);
  Id:=AId;
  Event:=TEvent.Create(nil,False,False,'');
  Lock:=TCriticalSection.Create;
  Log:=TStringList.Create;
  SetLength(Latencies,SignalsPerWorker);
  MinTimeoutNs:=High(UInt64);
end;

destructor TWorker.Destroy;
begin
  inherited Destroy;
  Event.Free;
  Lock.Free;
  Log.Free;
end;

procedure TWorker.Deliver;
var I: Integer;
begin
  Lock.Acquire;
  try
    Inc(Delivered,Log.Count);
    for I:=0 to Log.Count-1 do Inc(DeliveredBytes,Length(Log[I]));
    Log.Clear;
  finally
    Lock.Release;
  end;
end;

procedure TWorker.Execute;
var I, N: Integer; Began, Ended: UInt64; Outcome: TWaitResult; Text: string;
begin
  try
    InterlockedIncrement(Ready);
    Gate.WaitFor(INFINITE);
    N:=Rounds;
    If SelectedOnly then N:=SignalsPerWorker;
    for I:=1 to N do begin
      Began:=WallNs;
      { A slow sender must not change the work count or outlive its recipient. }
      If SelectedOnly or (Timeouts=UInt64(Rounds-SignalsPerWorker)) then
        Outcome:=Event.WaitFor(INFINITE)
      else
        Outcome:=Event.WaitFor(PeriodMs);
      Ended:=WallNs;
      If Outcome=wrSignaled then begin
        Check(InterlockedCompareExchange(Issued,0,0)=Received+1,'wrong recipient or duplicate signal');
        Check(Received<SignalsPerWorker,'too many signals');
        Latencies[Received]:=Ended-SentNs;
        Inc(Received);
        Ack.SetEvent;
      end else begin
        Check((Outcome=wrTimeout) and not SelectedOnly,'unexpected wait outcome');
        Check(Ended-Began+TimeoutSlackNs>=EffectiveTimeoutNs,'timeout returned early');
        If Ended-Began<MinTimeoutNs then MinTimeoutNs:=Ended-Began;
        Inc(Timeouts);
      end;
      If DoWork then begin
        Digest:=Digest xor UInt64(GetTickCount64);
        Digest:=Digest xor UInt64(TThread.GetTickCount64);
        Digest:=Digest xor UInt64(Trunc(Now*86400000));
        If I mod 8=0 then begin
          Text:='order='+IntToStr(Id)+' step='+IntToStr(I);
          Inc(Generated);
          Inc(Bytes,Length(Text));
          Lock.Acquire;
          try
            Log.Add(Text);
          finally
            Lock.Release;
          end;
          TThread.Queue(nil,Deliver);
        end;
      end;
    end;
    Check(Received=SignalsPerWorker,'worker finished before all input was delivered');
  finally
    InterlockedIncrement(Completed);
    MainWake.Event.SetEvent;
  end;
end;

procedure TMainWake.Wake(Sender: TObject);
begin
  Event.SetEvent;
end;

procedure TProducer.Execute;
var R, I: Integer;
begin
  Gate.WaitFor(INFINITE);
  for R:=1 to SignalsPerWorker do
    for I:=0 to Count-1 do begin
      { No catch-up. A delayed sender changes wall time, never creates a burst.
        Only one recipient is notified; the other 91 retain their timed waits. }
      Sleep(PeriodMs);
      Workers[I].SentNs:=WallNs;
      InterlockedExchange(Workers[I].Issued,R);
      Workers[I].Event.SetEvent;
      If Ack.WaitFor(5000)<>wrSignaled then begin
        If Workers[I].FatalException<>nil then
          raise Exception.Create('recipient '+IntToStr(I)+': '+Exception(Workers[I].FatalException).Message);
        raise Exception.Create('selected recipient '+IntToStr(I)+' did not acknowledge');
      end;
    end;
end;

procedure Sort(var Values: array of UInt64; L, R: Integer);
var I, J: Integer; P, V: UInt64;
begin
  I:=L;
  J:=R;
  P:=Values[(L+R) div 2];
  repeat
    while Values[I]<P do Inc(I);
    while Values[J]>P do Dec(J);
    If I<=J then begin
      V:=Values[I];
      Values[I]:=Values[J];
      Values[J]:=V;
      Inc(I);
      Dec(J);
    end;
  until I>J;
  If L<J then Sort(Values,L,J);
  If I<R then Sort(Values,I,R);
end;

procedure Run;
var P: TProducer; Before, After: TCpu; Start, Elapsed, CyclesBefore, CyclesAfter: UInt64;
  Timeouts, MinTimeoutNs, Logs, Digest: UInt64; I, J, K, Quantum: Integer; Values: array of UInt64;
  QuantumText: string;
  {$ifdef MSWINDOWS}Adjustment, Increment: DWORD; AdjustmentDisabled: BOOL;{$endif}
begin
  Check(ParamCount=5,'usage: orders|wait|selected WORKERS ROUNDS PERIOD_MS SIGNALS_PER_WORKER');
  Mode:=ParamStr(1);
  Count:=StrToInt(ParamStr(2));
  Rounds:=StrToInt(ParamStr(3));
  PeriodMs:=StrToInt(ParamStr(4));
  SignalsPerWorker:=StrToInt(ParamStr(5));
  DoWork:=Mode='orders';
  SelectedOnly:=Mode='selected';
  Check(DoWork or SelectedOnly or (Mode='wait'),'unknown mode');
  Check((Count>0) and (Count<=256) and (Rounds>0) and (Rounds<=10000) and
    (PeriodMs>=2) and (PeriodMs<=1000) and (SignalsPerWorker>0) and (SignalsPerWorker<=100),'invalid size');
  If not SelectedOnly then Check(Rounds>Count*SignalsPerWorker+32,'insufficient timeout rounds for selected input');
  QuantumText:=GetEnvironmentVariable('PULSE_WAIT_GRANULARITY_US');
  Quantum:=0;
  If QuantumText<>'' then Quantum:=StrToIntDef(QuantumText,-1);
  Check((Quantum>=0) and (Quantum<=1000000),'invalid wait granularity');
  GranularityUS:=Quantum;
  EffectiveTimeoutNs:=UInt64(PeriodMs)*1000000;
  If GranularityUS>1 then
    EffectiveTimeoutNs:=((UInt64(PeriodMs)*1000+GranularityUS-1) div GranularityUS)*GranularityUS*1000;
  {$if defined(LINUX) and declared(SetWaitGranularityUS)}
  SetWaitGranularityUS(GranularityUS);
  {$else}
  Check(GranularityUS=0,'wait granularity requires the updated Linux RTL');
  {$endif}
  TimeoutSlackNs:=1000000;
  {$ifdef MSWINDOWS}
  QueryPerformanceFrequency(Frequency);
  { Windows rounds waits to system ticks; do not demand POSIX deadline accuracy. }
  Check(GetSystemTimeAdjustment(Adjustment,Increment,AdjustmentDisabled),'timer resolution');
  TimeoutSlackNs:=UInt64(Increment)*100;
  If GetEnvironmentVariable('PULSE_WAKE_CPU')<>'' then
    Check(SetProcessAffinityMask(GetCurrentProcess,NativeUInt(1) shl StrToInt(GetEnvironmentVariable('PULSE_WAKE_CPU'))),
      'cannot set CPU affinity');
  {$endif}
  Gate:=TEvent.Create(nil,True,False,'');
  Ack:=TEvent.Create(nil,False,False,'');
  MainWake:=TMainWake.Create;
  MainWake.Event:=TEvent.Create(nil,False,False,'');
  WakeMainThread:=MainWake.Wake;
  SetLength(Workers,Count);
  for I:=0 to Count-1 do begin
    Workers[I]:=TWorker.Create(I);
    Workers[I].Start;
  end;
  P:=TProducer.Create(False);
  Start:=WallNs;
  while InterlockedCompareExchange(Ready,0,0)<Count do begin
    Sleep(1);
    Check(WallNs-Start<10000000000,'startup timeout');
  end;
  Sleep(20);
  Before:=Cpu;
  CyclesBefore:=0;
  CyclesAfter:=0;
  {$ifdef MSWINDOWS}Check(ReadCycles(GetCurrentProcess,CyclesBefore),'process cycles');{$endif}
  Start:=WallNs;
  Gate.SetEvent;
  while InterlockedCompareExchange(Completed,0,0)<Count do begin
    CheckSynchronize(0);
    If InterlockedCompareExchange(Completed,0,0)<Count then MainWake.Event.WaitFor(100);
    Check(WallNs-Start<UInt64(Rounds)*EffectiveTimeoutNs*4+10000000000,'workload timeout');
  end;
  CheckSynchronize(0);
  Elapsed:=WallNs-Start;
  After:=Cpu;
  {$ifdef MSWINDOWS}Check(ReadCycles(GetCurrentProcess,CyclesAfter),'process cycles');{$endif}
  P.WaitFor;
  If P.FatalException<>nil then raise Exception.Create('producer: '+Exception(P.FatalException).Message);
  P.Free;
  Timeouts:=0;
  MinTimeoutNs:=High(UInt64);
  Logs:=0;
  Digest:=0;
  SetLength(Values,Count*SignalsPerWorker);
  K:=0;
  for I:=0 to Count-1 do begin
    Workers[I].WaitFor;
    If Workers[I].FatalException<>nil then
      raise Exception.Create('worker '+IntToStr(I)+': '+Exception(Workers[I].FatalException).Message);
    Check(Workers[I].Received=SignalsPerWorker,'lost signal');
    If DoWork then Check(Workers[I].Generated=UInt64(Rounds div 8),'wrong work count');
    Check((Workers[I].Generated=Workers[I].Delivered) and (Workers[I].Bytes=Workers[I].DeliveredBytes),'lost log');
    Inc(Timeouts,Workers[I].Timeouts);
    If Workers[I].MinTimeoutNs<MinTimeoutNs then MinTimeoutNs:=Workers[I].MinTimeoutNs;
    Inc(Logs,Workers[I].Delivered);
    Digest:=Digest xor Workers[I].Digest;
    for J:=0 to SignalsPerWorker-1 do begin
      Values[K]:=Workers[I].Latencies[J];
      Inc(K);
    end;
    Workers[I].Free;
  end;
  If not SelectedOnly then Check(Timeouts=UInt64(Count)*UInt64(Rounds-SignalsPerWorker),'wrong timeout count');
  If Timeouts=0 then MinTimeoutNs:=0;
  Sort(Values,0,High(Values));
  WakeMainThread:=nil;
  MainWake.Event.Free;
  MainWake.Free;
  Gate.Free;
  Ack.Free;
  WriteLn('PULSE_ORDER mode=',Mode,' workers=',Count,' rounds=',Rounds,' period_ms=',PeriodMs,
    ' granularity_us=',GranularityUS,' wall_ns=',Elapsed,' user_ns=',After.UserNs-Before.UserNs,' kernel_ns=',After.KernelNs-Before.KernelNs,
    ' cycles=',CyclesAfter-CyclesBefore,' signals=',K,' timeouts=',Timeouts,
    ' min_timeout_ns=',MinTimeoutNs,' timeout_slack_ns=',TimeoutSlackNs,' logs=',Logs,' digest=',Digest,
    ' latency_p50_ns=',Values[(K-1)*50 div 100],' latency_p95_ns=',Values[(K-1)*95 div 100],
    ' latency_p99_ns=',Values[(K-1)*99 div 100],' latency_max_ns=',Values[K-1],' verified=1');
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
