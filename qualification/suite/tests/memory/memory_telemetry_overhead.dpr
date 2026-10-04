program memory_telemetry_overhead;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
  perf_clock,
  SysUtils;

var
  Sink: PtrUInt;

function MeasureAllocFree(Size: PtrUInt; Count: Integer): UInt64;
var
  I: Integer;
  P: pointer;
  Started: TPerfStamp;
  Delta: TPerfDelta;
begin
  Started := BeginPerfStamp;
  for I := 1 to Count do
  begin
    P := _GetMem(Size);
    PByte(P)^ := Byte(I);
    Sink := Sink xor PtrUInt(P);
    _FreeMem(P);
  end;
  Delta := EndPerfStamp(Started);
  Result := Delta.TscTicks;
end;

procedure Run;
var
  Size: PtrUInt;
  Count, I: Integer;
  Cycles: UInt64;
  P: pointer;
begin
  If ParamCount <> 2 then
    raise Exception.Create('Usage: memory_telemetry_overhead SIZE COUNT');
  Size := StrToQWord(ParamStr(1));
  Count := StrToInt(ParamStr(2));
  If (Size = 0) or (Count <= 0) then
    raise Exception.Create('SIZE and COUNT must be positive');
  InitializePerfClock;
  PinBenchmarkThread;
  for I := 1 to 10000 do
  begin
    P := _GetMem(Size);
    _FreeMem(P);
  end;
  Cycles := MeasureAllocFree(Size, Count);
  Writeln('size=', Size, ' count=', Count, ' ticks=', Cycles,
    ' ticks_per_op=', Cycles / Count:0:4, ' sink=', Sink);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln('MEMORY_TELEMETRY_OVERHEAD_FAIL ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
