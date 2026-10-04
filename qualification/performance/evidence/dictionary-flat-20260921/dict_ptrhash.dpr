program dict_ptrhash;
{ lookup cost of TDictionary<Pointer,Integer> over 512 keys at the strides an allocator
  hands out (and real TObject instances): the populations on which the CRC of the key bytes
  collapses into two live buckets out of four. }
{$mode delphi}{$H+}
uses mormot.core.fpcx64mm, SysUtils, Generics.Defaults, Generics.Collections, perf_clock in 'perf_clock.pas', pulse_process_metrics in 'pulse_process_metrics.pas';
{ thread cycles on Windows; on Linux (no per-thread cycle counter here) TSC ticks }
procedure Measure(const Name: string; const Keys: TArray<Pointer>);
var D: TDictionary<Pointer, Integer>; i, n, v, r: Integer; c0, c1, best: UInt64; Started: TPerfStamp;
begin
  D := TDictionary<Pointer, Integer>.Create;
  D.Capacity := 1024;
  for i := 0 to High(Keys) do D.Add(Keys[i], i);
  best := High(UInt64); n := Length(Keys);
  for r := 1 to 7 do begin
    c0 := PulseReadThreadCycles;
    Started := BeginPerfStamp;
    for i := 0 to 1048575 do If D.TryGetValue(Keys[i and (n - 1)], v) then ;
    c1 := PulseReadThreadCycles - c0;
    If c0 = 0 then c1 := EndPerfStamp(Started).TscTicks;
    If c1 < best then best := c1;
  end;
  WriteLn(Name:22, ' lookup cyc/op ', (best / 1048576):6:2);
  D.Free;
end;
var Keys: TArray<Pointer>; i, s: Integer; Objs: TArray<TObject>;
begin
  InitializePerfClock; PinBenchmarkThread;
  SetLength(Keys, 512);
  for s in [8, 16, 24, 32, 48, 64, 96, 128] do begin
    for i := 0 to 511 do Keys[i] := Pointer(NativeUInt($1c8a3f40000) + NativeUInt(s) * NativeUInt(i));
    Measure('stride ' + IntToStr(s), Keys);
  end;
  SetLength(Objs, 512);
  for i := 0 to 511 do begin Objs[i] := TObject.Create; Keys[i] := Objs[i]; end;
  WriteLn('TObject.Create stride: ', NativeUInt(Objs[1]) - NativeUInt(Objs[0]), ' / ', NativeUInt(Objs[2]) - NativeUInt(Objs[1]));
  Measure('real TObjects', Keys);
  for i := 0 to 511 do Keys[i] := Pointer(NativeUInt(i));
  Measure('ints 0..511', Keys);
end.
