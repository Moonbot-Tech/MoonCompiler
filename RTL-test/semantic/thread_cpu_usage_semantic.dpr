program thread_cpu_usage_semantic;

{$mode delphi}{$H+}

{ TThread.GetSystemTimes and TThread.GetCPUUsage read the machine as in
  Delphi 12.2: the times of all processors, the kernel time including the idle
  time, and the busy share of an interval in percent.  The thread pool monitor
  grows the pool past its maximum only while that share is below 80%.  The
  times used to be unavailable on both targets (always 0%): Win64 had no
  reader, and the Linux reader took /proc/stat into a buffer of Char, a
  WideChar in the Unicode RTL, so it never found the counters (read as bytes
  it would have stopped before the idle field).  The percentage was truncated
  to 0 or 100. }

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes;

{$ifdef MSWINDOWS}
function OsSystemTimes(IdleTime, KernelTime, UserTime: PQWord): LongBool; stdcall;
  external 'kernel32' name 'GetSystemTimes';
{$endif MSWINDOWS}

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('THREAD_CPU_USAGE_FAIL: '+AMessage);
end;

{ The counters as the operating system reports them. }
function OsTimes(out Times: TThread.TSystemTimes): Boolean;
{$ifdef MSWINDOWS}
begin
  Times:=Default(TThread.TSystemTimes);
  Result:=OsSystemTimes(@Times.IdleTime,@Times.KernelTime,@Times.UserTime);
end;
{$else}
var
  Handle: THandle;
  Buffer: array[0..1023] of AnsiChar;
  Values: array[1..4] of QWord;
  Count, I, Field: Integer;
  Digits: Boolean;
begin
  Result:=False;
  Times:=Default(TThread.TSystemTimes);
  Handle:=FileOpen('/proc/stat',fmOpenRead or fmShareDenyNone);
  if Handle=THandle(-1) then
    Exit;
  try
    Count:=FileRead(Handle,Buffer,SizeOf(Buffer));
  finally
    FileClose(Handle);
  end;
  { the first line: "cpu  user nice system idle iowait ..." }
  if (Count<5) or (Buffer[0]<>'c') or (Buffer[1]<>'p') or (Buffer[2]<>'u') or (Buffer[3]<>' ') then
    Exit;
  FillChar(Values,SizeOf(Values),0);
  Field:=1;
  Digits:=False;
  for I:=4 to Count-1 do
    begin
    if Buffer[I] in ['0'..'9'] then
      begin
      Values[Field]:=Values[Field]*10+Ord(Buffer[I])-Ord('0');
      Digits:=True;
      end
    else if Digits then
      begin
      Inc(Field);
      Digits:=False;
      if Field>4 then
        Break;
      end;
    if Buffer[I]=#10 then
      Break;
    end;
  if Field<=4 then
    Exit;
  { user nice system idle: the kernel time includes the idle time }
  Times.UserTime:=Values[1];
  Times.NiceTime:=Values[2];
  Times.IdleTime:=Values[4];
  Times.KernelTime:=Values[3]+Values[4];
  Result:=True;
end;
{$endif}

function NotAfter(const A, B: TThread.TSystemTimes): Boolean;
begin
  Result:=(A.IdleTime<=B.IdleTime) and (A.KernelTime<=B.KernelTime) and
          (A.UserTime<=B.UserTime) and (A.NiceTime<=B.NiceTime);
end;

function Busy(const Previous, Current: TThread.TSystemTimes): Integer;
var
  Load, Idle: QWord;
begin
  Load:=(Current.UserTime-Previous.UserTime)+(Current.KernelTime-Previous.KernelTime)+
        (Current.NiceTime-Previous.NiceTime);
  Idle:=Current.IdleTime-Previous.IdleTime;
  Result:=0;
  if Load>Idle then
    Result:=(Load-Idle)*100 div Load;
end;

procedure CheckSystemTimes;
var
  Before, Times, After: TThread.TSystemTimes;
begin
  Check(OsTimes(Before),'the operating system counters are unavailable');
  Check(TThread.GetSystemTimes(Times),'GetSystemTimes returned False');
  Check(OsTimes(After),'the operating system counters are unavailable');
  { counters only grow: the RTL reading lies between the two direct ones }
  Check(NotAfter(Before,Times) and NotAfter(Times,After),
    Format('GetSystemTimes idle %u kernel %u user %u nice %u is not the system reading '+
      '(idle %u..%u, kernel %u..%u, user %u..%u, nice %u..%u)',
      [Times.IdleTime,Times.KernelTime,Times.UserTime,Times.NiceTime,
       Before.IdleTime,After.IdleTime,Before.KernelTime,After.KernelTime,
       Before.UserTime,After.UserTime,Before.NiceTime,After.NiceTime]));
  Check(Times.IdleTime>0,'no idle time');
  Check(Times.KernelTime>=Times.IdleTime,'the kernel time does not include the idle time');
end;

procedure CheckUsageOfInterval;
var
  Start, Previous, Current, After: TThread.TSystemTimes;
  Usage, Low, High, Swap: Integer;
begin
  { An interval with a known share: the previous sample is a quarter of the
    counters back, part of that span idle.  Real time moves the counters by a
    few ticks during the call; the expectation brackets it. }
  Check(TThread.GetSystemTimes(Start),'GetSystemTimes returned False');
  Previous:=Start;
  Dec(Previous.UserTime,Start.UserTime div 4);
  Dec(Previous.NiceTime,Start.NiceTime div 4);
  Dec(Previous.KernelTime,Start.KernelTime div 4);
  if Start.IdleTime<Start.KernelTime div 4 then
    Dec(Previous.IdleTime,Start.IdleTime div 3)
  else
    Dec(Previous.IdleTime,(Start.KernelTime div 4) div 3);
  Current:=Previous;
  Usage:=TThread.GetCPUUsage(Current);
  Check(TThread.GetSystemTimes(After),'GetSystemTimes returned False');
  Check(NotAfter(Start,Current) and NotAfter(Current,After),'GetCPUUsage did not store the current times');
  Low:=Busy(Previous,Start);
  High:=Busy(Previous,After);
  if Low>High then
    begin
    Swap:=Low;
    Low:=High;
    High:=Swap;
    end;
  Check((Low>0) and (High<100),Format('interval share %d..%d%% is not partial',[Low,High]));
  Check((Usage>=Low-1) and (Usage<=High+1),
    Format('GetCPUUsage %d%% for an interval of %d..%d%%',[Usage,Low,High]));
end;

procedure CheckRange;
var
  Previous: TThread.TSystemTimes;
  I, Usage: Integer;
begin
  Check(TThread.GetSystemTimes(Previous),'GetSystemTimes returned False');
  for I:=1 to 3 do
    begin
    TThread.Sleep(50);
    Usage:=TThread.GetCPUUsage(Previous);
    Check((Usage>=0) and (Usage<=100),'GetCPUUsage '+IntToStr(Usage)+'% out of range');
    end;
end;

begin
  CheckSystemTimes;
  CheckUsageOfInterval;
  CheckRange;
  WriteLn('THREAD_CPU_USAGE_PASS');
end.
