program monotonic_tick_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$endif}
uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Classes, SyncObjs, System.Diagnostics
  {$ifndef FPC}, Windows{$endif}
  {$ifdef LINUX}, UnixType, Unix, Linux{$endif};

{$ifdef LINUX}
function ReferenceClock(Id: LongInt; out Stamp: TTimeSpec): LongInt;
  cdecl; external 'c' name 'clock_gettime';
{$endif}

type
  TReader = class(TThread)
    procedure Execute; override;
  end;

procedure CheckReads;
var I: Integer; Before, Current, After, Previous: UInt64;
{$ifdef LINUX}Stamp: TTimeSpec;{$endif}
begin
  Previous := 0;
  for I := 1 to 10000 do begin
    {$ifdef LINUX}
    If ReferenceClock(1, Stamp) <> 0 then raise Exception.Create('reference clock failed');
    Before := UInt64(Stamp.tv_sec) * 1000 + UInt64(Stamp.tv_nsec) div 1000000;
    {$else}
    Before := {$ifdef FPC}SysUtils.{$else}Windows.{$endif}GetTickCount64;
    {$endif}
    Current := TThread.GetTickCount64;
    {$ifdef LINUX}
    If ReferenceClock(1, Stamp) <> 0 then raise Exception.Create('reference clock failed');
    After := UInt64(Stamp.tv_sec) * 1000 + UInt64(Stamp.tv_nsec) div 1000000;
    {$else}
    After := {$ifdef FPC}SysUtils.{$else}Windows.{$endif}GetTickCount64;
    {$endif}
    If (Current < Before) or (Current > After) or (Current < Previous) then
      raise Exception.Create('tick clock violated monotonic bracket');
    Previous := Current;
  end;
end;

procedure TReader.Execute;
begin
  CheckReads;
end;

var Workers: array[0..7] of TReader; I: Integer; Before, After: UInt64; Event: TEvent;
{$ifdef LINUX}RawStamp: TTimeSpec; RawTime: TTimeVal; CalendarMs: Int64;{$endif}
begin
  If ParamStr(1) = 'fixed' then begin
    If SysUtils.GetTickCount64 <> UInt64(6000000123) then Halt(2);
    If TThread.GetTickCount64 <> UInt64(6000000123) then Halt(3);
    If TStopwatch.GetTimeStamp <> Int64(60000001234567) then Halt(5);
    WriteLn('MONOTONIC_TICK_FIXED_PASS');
    Halt(0);
  end;
  If ParamStr(1) = 'fallback' then begin
    { Test interposer rejects libc's monotonic clock; the existing realtime
      fallback must remain initialized and in epoch milliseconds. }
    Before := UInt64(Trunc((Now - EncodeDate(1970, 1, 1)) * 86400000));
    After := SysUtils.GetTickCount64;
    If (After < Before - 1000) or (After > Before + 1000) then Halt(4);
    {$ifdef LINUX}
    Linux.clock_gettime(1,@RawStamp);
    Before:=UInt64(RawStamp.tv_sec)*10000000+UInt64(RawStamp.tv_nsec) div 100;
    After:=UInt64(TStopwatch.GetTimeStamp);
    If (After<Before) or (After-Before>10000000) then Halt(6);
    {$endif}
    WriteLn('MONOTONIC_TICK_FALLBACK_PASS');
    Halt(0);
  end;
  {$ifdef LINUX}
  If ParamStr(1)='calendar-fixed' then begin
    CalendarMs:=Round((Now-EncodeDate(1970,1,1))*86400000);
    If Abs(CalendarMs-Int64(1700000123456))>1 then Halt(7);
    WriteLn('CALENDAR_FIXED_PASS');
    Halt(0);
  end;
  If ParamStr(1)='calendar-fallback' then begin
    fpGetTimeOfDay(@RawTime,nil);
    CalendarMs:=Round((Now-EncodeDate(1970,1,1))*86400000);
    If Abs(CalendarMs-(RawTime.tv_sec*1000+RawTime.tv_usec div 1000))>1000 then Halt(8);
    WriteLn('CALENDAR_FALLBACK_PASS');
    Halt(0);
  end;
  {$endif}
  CheckReads;
  for I := Low(Workers) to High(Workers) do Workers[I] := TReader.Create(False);
  for I := Low(Workers) to High(Workers) do begin
    Workers[I].WaitFor;
    If Assigned(Workers[I].FatalException) then raise Exception.Create('concurrent clock failed');
    Workers[I].Free;
  end;
  Before := SysUtils.GetTickCount64;
  Sleep(30);
  After := SysUtils.GetTickCount64;
  If (After < Before + 20) or (After > Before + 2000) then raise Exception.Create('tick does not advance');
  Event := TEvent.Create(nil, False, False, '');
  try
    Before := SysUtils.GetTickCount64;
    If Event.WaitFor(30) <> wrTimeout then raise Exception.Create('event timeout lost');
    After := SysUtils.GetTickCount64;
    If (After < Before + 20) or (After > Before + 2000) then raise Exception.Create('event deadline changed');
    Event.SetEvent;
    If Event.WaitFor(100) <> wrSignaled then raise Exception.Create('event signal lost');
    If Event.WaitFor(0) <> wrTimeout then raise Exception.Create('auto-reset lost');
  finally
    Event.Free;
  end;
  WriteLn('MONOTONIC_TICK_PASS');
end.
