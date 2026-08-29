program licm_perf;

{$mode unleashed}
{$Q-}
{$R-}

uses
  SysUtils,
  perf_clock;

function Work(A, B, C, D: Int64; N, Repeats: Integer): UInt64; noinline;
var
  I, R: Integer;
begin
  Result := 0;
  R := 0;
  while R < Repeats do begin
    I := 0;
    while I < N do begin
      Result := Result + UInt64(A * B + C * D + A * D + B * C + (I and 7));
      Inc(I);
    end;
    Inc(R);
  end;
end;

var
  N, Repeats: Integer;
  Digest: UInt64;
  Started: TPerfStamp;
  Delta: TPerfDelta;
begin
  N := 10000;
  Repeats := 2000;
  If ParamCount >= 1 then
    N := StrToInt(ParamStr(1));
  If ParamCount >= 2 then
    Repeats := StrToInt(ParamStr(2));
  InitializePerfClock;
  PinBenchmarkThread;
  Digest := Work(17, 257, 31, 509, 100, 2);
  Started := BeginPerfStamp;
  Digest := Digest xor Work(17, 257, 31, 509, N, Repeats);
  Delta := EndPerfStamp(Started);
  WriteLn('F2-PERF ticks=', Delta.TscTicks, ' iterations=', UInt64(N) *
    UInt64(Repeats), ' digest=', Digest);
end.
