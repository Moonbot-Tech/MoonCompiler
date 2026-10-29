program pulse_moonshot_idle;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
{$Q-}{$R-}
uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Classes, SyncObjs, Math, MoonShotFilters, MoonShotOrderState, MoonShotOrderPath,
  {$ifdef MSWINDOWS}Windows{$else}Unix, UnixType{$endif};

{ The quiet BuySet path of the four observed MoonShot strategies. No exchange
  calls, log writes, fake Queue traffic, trade-history scans or live credentials.
  See MOONSHOT_IDLE.md for source anchors, fixture provenance and omissions. }
type
  TCpu = record UserNs, KernelNs: UInt64; end;
  TWorker = class(TThread)
    Id, Received, Issued: Integer;
    Event: TEvent;
    Core: TQuietOrder;
    {$ifdef LINUX}UrgencyLock: TCriticalSection; Waiting: Boolean;{$endif}
    SentNs, Timeouts: UInt64;
    Digest: Int64;
    Latencies: array of UInt64;
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function QuietCheck: Boolean;
    procedure Execute; override;
  end;
  TProducer = class(TThread)
    procedure Execute; override;
  end;
{$ifdef LINUX}
  TRUsage = record UserTime, SystemTime: TTimeVal; Other: array[0..13] of Int64; end;
function GetUsage(Who: Integer; out Usage: TRUsage): Integer; cdecl; external 'c' name 'getrusage';
function LibcClock(Id: Integer; out Stamp: TTimeSpec): Integer; cdecl; external 'c' name 'clock_gettime';
{$else}
function ReadCycles(Process: THandle; out Cycles: UInt64): BOOL; stdcall;
  external 'kernel32.dll' name 'QueryProcessCycleTime';
procedure PreciseUTC(out Value: TFileTime); stdcall;
  external 'kernel32.dll' name 'GetSystemTimePreciseAsFileTime';
{$endif}

{$I pulse_moonshot_fixture.inc}
var
  Workers: array of TWorker;
  Strategies: array[0..3] of TOrderStrategy;
  Markets: array[0..22] of TOrderMarket;
  Gate, Done, Ack: TEvent;
  Ready, Completed: LongInt;
  Rounds, PeriodMs, SignalRounds: Integer;
  Mode: string;
  NoFormat, OnlyWait, Bulk, SkipFilters: Boolean;
  FormatSettingsLocal: TFormatSettings;
  GranularityUS: Cardinal;
  {$ifdef MSWINDOWS}Frequency: Int64;{$endif}

procedure Check(Value: Boolean; const Reason: string);
begin
  If not Value then raise Exception.Create(Reason);
end;

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

function Tick: Int64;
begin
  Result:=Int64(GetTickCount64);
end;

function Cpu: TCpu;
{$ifdef MSWINDOWS}
var C, E, K, U: TFileTime;
begin
  Check(GetProcessTimes(GetCurrentProcess,C,E,K,U),'GetProcessTimes');
  Result.UserNs:=(UInt64(U.dwHighDateTime) shl 32 or U.dwLowDateTime)*100;
  Result.KernelNs:=(UInt64(K.dwHighDateTime) shl 32 or K.dwLowDateTime)*100;
{$else}
var R: TRUsage;
begin
  Check(GetUsage(0,R)=0,'getrusage');
  Result.UserNs:=UInt64(R.UserTime.tv_sec)*1000000000+UInt64(R.UserTime.tv_usec)*1000;
  Result.KernelNs:=UInt64(R.SystemTime.tv_sec)*1000000000+UInt64(R.SystemTime.tv_usec)*1000;
{$endif}
end;

constructor TWorker.Create(AId: Integer);
var Group: Integer;
begin
  inherited Create(True);
  Id:=AId;
  Group:=Id div 23;
  Core:=TQuietOrder.Create(Strategies[Group],Markets[Id mod 23],Id+1);
  Core.NoFormat:=NoFormat;
  Core.SkipFilters:=SkipFilters;
  With Core.Publication do begin
    MContent.HasStrategy:=True;
    MContent.sg:=Strategies[Group];
    MContent.SignalSource:='MoonShot: '+Strategies[Group].GetLogName;
    MContent.comment:='MoonShot: '+Strategies[Group].GetLogName;
    MContent.PriceFound:=True;
    MContent.reason:=2;
    MContent.IsShort:=Strategies[Group].Short;
    MContent.OrderK:=100;
    Status:=OS_BuySet;
    BuyOrder.Quantity:=100/Markets[Id mod 23].pLast;
    BuyOrder.QuantityRemaining:=BuyOrder.Quantity;
    BuyOrder.IsOpened:=True;
    BuyOrder.intID:=Id+1;
    BuyOrder.updCount:=5;
    BuyOrder.CreateTime:=Now;
    BuyOrder.OpenTime:=BuyOrder.CreateTime;
    If Strategies[Group].Short then BuyOrder.ActualPrice:=Markets[Id mod 23].pLast*(1+(StrategyMin[Group]+StrategyDistance[Group])*0.5/100)
    else BuyOrder.ActualPrice:=Markets[Id mod 23].pLast*(1-(StrategyMin[Group]+StrategyDistance[Group])*0.5/100);
    BuyOrder.Price:=BuyOrder.ActualPrice;
    BTCBalance:=100;
    vOrder.OrderSize:=100;
    InitializeCanon;
  end;
  Event:=TEvent.Create(nil,False,False,'');
  {$ifdef LINUX}UrgencyLock:=TCriticalSection.Create;{$endif}
  SetLength(Latencies,SignalRounds);
end;

destructor TWorker.Destroy;
begin
  inherited Destroy;
  {$ifdef LINUX}UrgencyLock.Free;{$endif}
  Event.Free;
  Core.Free;
end;

function TWorker.QuietCheck: Boolean;
begin
  Core.Poll;
  Result:=True;
end;

procedure TWorker.Execute;
var I: Integer; T: Int64; Outcome: TWaitResult;
begin
  try
    Priority:=tpHigher;
    InterlockedIncrement(Ready);
    Gate.WaitFor(INFINITE);
    Core.BeginPhase;
    for I:=1 to Rounds do begin
      If not OnlyWait then Check(QuietCheck,'unexpected trade/cancel branch');
      If Bulk then begin Core.Publish; Continue; end;
      T:=Tick;
      If not OnlyWait then Check(Core.WaitMilliseconds=PeriodMs,'wrong source wait cadence');
      {$ifdef LINUX}
      UrgencyLock.Acquire;
      try Waiting:=True; finally UrgencyLock.Release; end;
      {$endif}
      If (SignalRounds>0) and (Timeouts=UInt64(Rounds-SignalRounds)) then Outcome:=Event.WaitFor(INFINITE)
      else Outcome:=Event.WaitFor(PeriodMs);
      {$ifdef LINUX}
      UrgencyLock.Acquire;
      try Waiting:=False; finally UrgencyLock.Release; end;
      {$endif}
      If Outcome=wrSignaled then begin
        Check(InterlockedCompareExchange(Issued,0,0)=Received+1,'wrong recipient');
        Check(Received<SignalRounds,'duplicate signal');
        Latencies[Received]:=WallNs-SentNs;
        Inc(Received);
        Ack.SetEvent;
      end else begin
        Check(Outcome=wrTimeout,'wait error');
        Inc(Timeouts);
      end;
      Inc(Digest,Ord(Tick>=T));
      If not OnlyWait then Core.Publish;
    end;
  finally
    InterlockedIncrement(Completed);
    Done.SetEvent;
  end;
end;

procedure TProducer.Execute;
var R, I: Integer; Pace: TEvent;
begin
  Pace:=TEvent.Create(nil,False,False,'');
  try
    Gate.WaitFor(INFINITE);
    for R:=1 to SignalRounds do
      for I:=0 to High(Workers) do begin
        Check(Pace.WaitFor(PeriodMs)=wrTimeout,'producer pacing');
        Workers[I].SentNs:=WallNs;
        InterlockedExchange(Workers[I].Issued,R);
        Workers[I].Event.SetEvent;
        Check(Ack.WaitFor(5000)=wrSignaled,'missing recipient acknowledgement');
      end;
  finally
    Pace.Free;
  end;
end;

procedure Sort(var A: array of UInt64; L, R: Integer);
var I, J: Integer; P, V: UInt64;
begin
  I:=L; J:=R; P:=A[(L+R) div 2];
  repeat
    while A[I]<P do Inc(I);
    while A[J]>P do Dec(J);
    If I<=J then begin V:=A[I]; A[I]:=A[J]; A[J]:=V; Inc(I); Dec(J); end;
  until I>J;
  If L<J then Sort(A,L,J);
  If I<R then Sort(A,I,R);
end;

procedure ValidateFixture;
var P: TOrderPublication; S: string; Base: Double; Rejected: Boolean;
begin
  Check(Strategies[0].CheckMarketCond(Markets[0],S,True,True),'baseline filters');
  Strategies[0].IntWhiteLists[Strategies[0].IntWLIndex][1]:=False;
  Check(not Strategies[0].CheckMarketCond(Markets[0],S,True,True),'white-list path was dropped');
  Strategies[0].IntWhiteLists[Strategies[0].IntWLIndex][1]:=True;
  Strategies[0].IntBlackLists[Strategies[0].IntBLIndex][1]:=True;
  Check(not Strategies[0].CheckMarketCond(Markets[0],S,True,True),'black-list path was dropped');
  Strategies[0].IntBlackLists[Strategies[0].IntBLIndex][1]:=False;
  Markets[0].LastMarketOfflineTime:=Now;
  Check(not Strategies[0].CheckMarketCond(Markets[0],S,True,True),'market penalty was dropped');
  Markets[0].LastMarketOfflineTime:=0;
  Base:=Strategies[0].GetMShotPriceDelta(Markets[0]);
  Strategies[0].MShotAddHourlyDelta:=1;
  Check(Abs(Strategies[0].GetMShotPriceDelta(Markets[0])-Base-0.04)<1e-10,'runtime coefficient was folded away');
  Strategies[0].MShotAddHourlyDelta:=0;
  P:=TOrderPublication.Create;
  try
    P.MContent.HasStrategy:=True;
    P.MContent.sg:=Strategies[0];
    P.InitializeCanon;
    P.CheckQuietPublication;
    P.FLastSlowSampleMS:=Tick-OrdersSyncPeriodMS;
    P.CheckQuietPublication;
    Check((P.HotChecks=1) and (P.FullChecks=1),'periodic snapshot was dropped');
    P.BuyOrder.ActualQ:=1;
    Check(P.HotCanonDiff(P.Canon)<>0,'execution comparison was dropped');
    P.BuyOrder.ActualQ:=0;
    P.vOrder.SLLevel:=1;
    Check(P.HotCanonDiff(P.Canon)<>0,'stop comparison was dropped');
    P.vOrder.SLLevel:=0;
    P.SellOrder.tmpBTC:=1;
    Check(P.HotCanonDiff(P.Canon)=0,'slow field appeared in hot path');
    P.FLastSlowSampleMS:=Tick-OrdersSyncPeriodMS;
    Rejected:=False;
    try P.CheckQuietPublication;
    except on E:EUnexpectedOrderPublication do Rejected:=True; end;
    Check(Rejected,'full snapshot missed slow field');
  finally
    P.Free;
  end;
end;

procedure Run;
var I,J,K: Integer; P:TProducer; Before,After:TCpu;
  Start,Elapsed,CyclesBefore,CyclesAfter,Checks,Timeouts,Formats,LocalChecks,States,Filters,FullChecks,Replays:UInt64;
  PhaseStartFileTime: UInt64;
  {$ifdef MSWINDOWS}UtcStamp: TFileTime;{$endif}
  Values:array of UInt64; Bytes,Digest:Int64;
begin
  Check(SizeOf(Char)=2,'the application uses UnicodeString');
  Check(ParamCount=3,'usage: quiet|no-format|wait|response|cpu|cpu-no-format ROUNDS PERIOD_MS');
  Mode:=ParamStr(1); Rounds:=StrToInt(ParamStr(2)); PeriodMs:=StrToInt(ParamStr(3));
  NoFormat:=(Mode='no-format') or (Mode='cpu-no-format'); OnlyWait:=Mode='wait';
  Bulk:=(Mode='cpu') or (Mode='cpu-no-format') or (Mode='cpu-no-filter');
  SkipFilters:=(Mode='no-filter') or (Mode='cpu-no-filter');
  Check(NoFormat or OnlyWait or Bulk or SkipFilters or (Mode='quiet') or (Mode='response'),'mode');
  Check((Rounds>0) and (Rounds<=1000000) and (PeriodMs>=1) and (PeriodMs<=80),'size');
  SignalRounds:=0; If Mode='response' then begin SignalRounds:=2; Check(Rounds>=192,'response rounds'); end;
  FormatSettingsLocal:=TFormatSettings.Create('en-US');
  FormatSettingsLocal.DecimalSeparator:='.';
  {$ifdef MSWINDOWS}
  QueryPerformanceFrequency(Frequency);
  If GetEnvironmentVariable('PULSE_WAKE_CPU')<>'' then
    Check(SetProcessAffinityMask(GetCurrentProcess,NativeUInt(1) shl StrToInt(GetEnvironmentVariable('PULSE_WAKE_CPU'))),'affinity');
  {$endif}
  GranularityUS:=StrToIntDef(GetEnvironmentVariable('PULSE_WAIT_GRANULARITY_US'),0);
  {$if defined(LINUX) and declared(SetWaitGranularityUS)}SetWaitGranularityUS(GranularityUS);
  {$else}Check(GranularityUS=0,'unsupported quantum');{$endif}
  InitQuietFilterEnvironment(Now);
  InitOrderEnvironment;
  for I:=0 to 22 do begin
    Markets[I]:=TOrderMarket.Create;
    Markets[I].InitQuietMarket(I+1,'ALT'+IntToStr(I+1),MarketPrices[I],Now);
    Markets[I].PrevAsk:=MarketPrices[I];
    Markets[I].CurentAsk:=MarketPrices[I];
    Markets[I].CurentBid:=MarketPrices[I];
    Markets[I].Last1hDelta:=0.04;
    Markets[I].Last24hDelta:=0.05;
    Markets[I].ArbRange1m:=0.02;
    Markets[I].Last5sDelta:=0.03;
    Markets[I].PriceBugM:=0.01;
    Markets[I].MinLotSize:=1;
  end;
  for I:=0 to 3 do begin
    Strategies[I]:=TOrderStrategy.Create;
    With Strategies[I] do begin
      InitQuietFilters(23);
      StrategyID:=I+1;
      Active:=True;
      FastShotAlgo:=True;
      Short:=I<>1;
      If Short then begin StrPCopy(@FStategyName[0],'WL3S'); MShotPriceKind:=PK_ASK; end
      else begin StrPCopy(@FStategyName[0],'WL2L'); MShotPriceKind:=PK_BID; end;
      MShotPriceMin:=StrategyMin[I];
      MShotPrice:=StrategyDistance[I];
      MShotAddBTCDelta:=StrategyBtcWeight[I];
      MShotAddPriceBug:=0.1;
      MShotAddArbRange:=0.1;
      MShotAdd5sDelta:=0.1;
      MShotAddDistance:=20;
      MShotRaiseWait:=10;
      AutoCancelBuy:=180;
      HFT:=2000;
    end;
  end;
  ValidateFixture;
  Gate:=TEvent.Create(nil,True,False,''); Done:=TEvent.Create(nil,False,False,''); Ack:=TEvent.Create(nil,False,False,'');
  SetLength(Workers,92);
  for I:=0 to High(Workers) do begin Workers[I]:=TWorker.Create(I); Workers[I].Start; end;
  P:=nil; If SignalRounds>0 then P:=TProducer.Create(False);
  Start:=WallNs;
  while InterlockedCompareExchange(Ready,0,0)<92 do begin Sleep(1); Check(WallNs-Start<10000000000,'startup'); end;
  Before:=Cpu; CyclesBefore:=0; CyclesAfter:=0;
  {$ifdef MSWINDOWS}Check(ReadCycles(GetCurrentProcess,CyclesBefore),'cycles');{$endif}
  PhaseStartFileTime:=0;
  {$ifdef MSWINDOWS}
  PreciseUTC(UtcStamp);
  PhaseStartFileTime:=UInt64(UtcStamp.dwHighDateTime) shl 32 or UtcStamp.dwLowDateTime;
  {$endif}
  Start:=WallNs; Gate.SetEvent;
  while InterlockedCompareExchange(Completed,0,0)<92 do begin
    Done.WaitFor(1000); Check(WallNs-Start<30000000000,'watchdog');
  end;
  Elapsed:=WallNs-Start; After:=Cpu;
  {$ifdef MSWINDOWS}Check(ReadCycles(GetCurrentProcess,CyclesAfter),'cycles');{$endif}
  If P<>nil then begin P.WaitFor; Check(P.FatalException=nil,'producer failure'); P.Free; end;
  Checks:=0; Timeouts:=0; Formats:=0; Bytes:=0; Digest:=0; LocalChecks:=0; States:=0; Filters:=0; FullChecks:=0; Replays:=0; K:=0;
  SetLength(Values,Max(1,92*SignalRounds));
  for I:=0 to High(Workers) do begin
    Workers[I].WaitFor;
    If Workers[I].FatalException<>nil then raise Exception.Create(Exception(Workers[I].FatalException).Message);
    Check(Workers[I].Received=SignalRounds,'lost signal');
    Inc(Checks,Workers[I].Core.Checks); Inc(Timeouts,Workers[I].Timeouts); Inc(Formats,Workers[I].Core.Formats);
    Inc(LocalChecks,Workers[I].Core.LocalOrderChecks); Inc(States,(Workers[I].Core.Publication.HotChecks+Workers[I].Core.Publication.FullChecks));
    Inc(Replays,Workers[I].Core.ReplayCount);
    Inc(Filters,Workers[I].Core.FilterChecks); Inc(FullChecks,Workers[I].Core.Publication.FullChecks);
    Inc(Bytes,Workers[I].Core.StringBytes); Inc(Digest,Workers[I].Digest);
    for J:=0 to SignalRounds-1 do begin Values[K]:=Workers[I].Latencies[J]; Inc(K); end;
    Workers[I].Free;
  end;
  If OnlyWait then Check(Checks=0,'unexpected work') else Check(Checks=UInt64(92)*UInt64(Rounds),'lost work');
  If Bulk then Check(Timeouts=0,'bulk waits') else Check(Timeouts=UInt64(92)*UInt64(Rounds-SignalRounds),'timeout count');
  If NoFormat or OnlyWait then Check(Formats=0,'format control') else Check(Formats=Checks*8,'format count');
  If not OnlyWait then Check((States=Checks) and (LocalChecks=UInt64(92)*UInt64((Rounds+3) div 4)),'state checks');
  If K>0 then Sort(Values,0,K-1) else K:=1;
  WriteLn('PULSE_MOONSHOT model=2 mode=',Mode,' workers=92 rounds=',Rounds,' period_ms=',PeriodMs,' granularity_us=',GranularityUS,
    ' borrowed_content=',{$ifdef MOONSHOT_BORROWED_CONTENT}1{$else}0{$endif},' char_bytes=',SizeOf(Char),' phase_start_filetime=',PhaseStartFileTime,
    ' wall_ns=',Elapsed,' user_ns=',After.UserNs-Before.UserNs,' kernel_ns=',After.KernelNs-Before.KernelNs,
    ' cycles=',CyclesAfter-CyclesBefore,' checks=',Checks,' timeouts=',Timeouts,' signals=',92*SignalRounds,
    ' formats=',Formats,' string_bytes=',Bytes,' digest=',Digest,' local_order_checks=',LocalChecks,' state_checks=',States,' filter_checks=',Filters,' full_checks=',FullChecks,' api_status_replays=',Replays,
    ' log_records=0 exchange_requests=0 history_rows=0 latency_p50_ns=',Values[(K-1)*50 div 100],
    ' latency_p95_ns=',Values[(K-1)*95 div 100],' latency_p99_ns=',Values[(K-1)*99 div 100],
    ' latency_max_ns=',Values[K-1],' verified=1');
  Gate.Free; Done.Free; Ack.Free;
  for I:=0 to 3 do Strategies[I].Free;
  for I:=0 to 22 do Markets[I].Free;
  DoneQuietFilterEnvironment;
end;

begin
  try Run;
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message); Halt(1); end; end;
end.
