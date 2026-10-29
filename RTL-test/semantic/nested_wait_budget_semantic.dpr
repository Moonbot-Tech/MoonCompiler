program nested_wait_budget_semantic;
{ %TARGET=linux }
{$ifdef FPC}{$mode delphi}{$endif}
{$ifdef LINUX}
uses cthreads, Unix, UnixType, SysUtils, Classes, Types;

procedure Check(Value: Boolean; const Reason: string);
begin
  if not Value then raise Exception.Create(Reason);
end;

function Clock(Id: LongInt; Stamp: PTimeSpec): LongInt; cdecl; external 'c' name 'clock_gettime';
function RawNanoSleep(Request, Remaining: PTimeSpec): LongInt; cdecl; external 'c' name 'nanosleep';

function Ns: QWord;
var Stamp: TTimeSpec;
begin
  Check(Clock(1,@Stamp)=0,'clock');
  Result:=QWord(Stamp.tv_sec)*1000000000+QWord(Stamp.tv_nsec);
end;

type
  TNoise = class(TThread)
    Event: TMultiWaitEvent;
    procedure Execute; override;
  end;

procedure TNoise.Execute;
var I: Integer; Request, Remaining: TTimeSpec;
begin
  for I:=1 to 4 do begin
    Request.tv_sec:=0;
    Request.tv_nsec:=10000000;
    Check(RawNanoSleep(@Request,@Remaining)=0,'raw producer sleep');
    Event.ResetEvent;
    Event.SetEvent;
  end;
end;

procedure Run(Granularity: Cardinal);
var Wanted, Unrelated: TMultiWaitEvent; Noise: TNoise; Started, Elapsed: QWord;
begin
  SetWaitGranularityUS(Granularity);
  Wanted:=TMultiWaitEvent.Create;
  Unrelated:=TMultiWaitEvent.Create;
  Noise:=TNoise.Create(True);
  try
    Noise.Event:=Unrelated;
    Started:=Ns;
    Noise.Start;
    { SetEvent on ANY MultiWait event wakes its global waiter list. The
      unrelated input must not become success or reset the outer budget. }
    Check(TMultiWaitEvent.WaitForAny([Wanted],16)=wrTimeout,'unrelated event became input');
    Elapsed:=Ns-Started;
    Check(Elapsed>=15000000,'outer timeout returned early');
    Check(Elapsed<500000000,'outer budget was rounded/reset by nested waits');
    Noise.WaitFor;
    Check(Noise.FatalException=nil,'producer failed');
    Writeln('NESTED_BUDGET granularity_us=',Granularity,' elapsed_ns=',Elapsed,' verified=1');
  finally
    Noise.Free;
    Unrelated.Free;
    Wanted.Free;
  end;
end;

begin
  Run(0);
  Run(1000000);
  SetWaitGranularityUS(0);
  WriteLn('NESTED_BUDGET_PASS');
end.
{$else}
begin
  Writeln('NESTED_BUDGET_NOT_APPLICABLE');
end.
{$endif}
