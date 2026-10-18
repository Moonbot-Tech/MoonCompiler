program backtrace_contract;
{$APPTYPE CONSOLE}
uses
{$ifdef unix} cthreads, {$endif}
  System.SysUtils, System.Classes;

type
  TCaptureWorker = class(TThread)
    procedure Execute; override;
  end;

var
  KeepCalls: Integer;

procedure Check(OK: Boolean; const Message: string);
begin
  If not OK then raise Exception.Create(Message);
end;

procedure CaptureLeaf; noinline;
var
  Frames: array[0..7] of CodePointer;
  Routine, Source: ShortString;
  Line: LongInt;
  Count: SizeInt;
begin
  for var Skip := 0 to 2 do begin
    FillChar(Frames, SizeOf(Frames), $55);
    Count := CaptureBacktrace(Skip, 1, @Frames[1]);
    Check(Count = 1, 'one caller requested');
    Check((PtrUInt(Frames[0]) = $5555555555555555) and
      (PtrUInt(Frames[2]) = $5555555555555555), 'buffer guards');
    Check(GetLineInfo(PtrUInt(Frames[1]), Routine, Source, Line), 'caller symbols');
    case Skip of
      0: Check(Pos('CAPTURELEAF', UpperCase(string(Routine))) <> 0, 'skip0 leaf: ' + string(Routine));
      1: Check(Pos('CAPTUREMIDDLE', UpperCase(string(Routine))) <> 0, 'skip1 middle: ' + string(Routine));
      2: Check(Pos('CAPTUREOUTER', UpperCase(string(Routine))) <> 0, 'skip2 outer: ' + string(Routine));
    end;
  end;
  Count := CaptureBacktrace(0, 6, @Frames[1]);
  Check((Count >= 3) and (Count <= 6), 'bounded complete chain');
  Check(PtrUInt(Frames[7]) = $5555555555555555, 'upper guard');
  Check(CaptureBacktrace(0, 0, @Frames[1]) = 0, 'zero capacity');
{$ifdef linux}
  Check(CaptureBacktrace(0, -1, @Frames[1]) = 0, 'negative capacity');
  Check(CaptureBacktrace(0, 4, nil) = 0, 'nil buffer');
  Check(CaptureBacktrace(-1, 4, @Frames[1]) = 0, 'negative skip');
  Check(CaptureBacktrace(High(SizeInt), 4, @Frames[1]) = 0, 'overflow skip');
{$endif}
  Check(CaptureBacktrace(10000, 4, @Frames[1]) = 0, 'skip beyond chain');
end;

procedure CaptureMiddle; noinline;
begin
  CaptureLeaf;
  Inc(KeepCalls);
end;

procedure CaptureOuter; noinline;
begin
  CaptureMiddle;
  Inc(KeepCalls);
end;

procedure TCaptureWorker.Execute;
begin
  CaptureOuter;
end;

begin
  CaptureOuter;
  var Worker := TCaptureWorker.Create(False);
  try
    Check(Worker.WaitFor(5000), 'worker completed');
    If Worker.FatalException <> nil then
      raise Exception.Create('worker: ' + Exception(Worker.FatalException).Message);
  finally
    Worker.Free;
  end;
  Check(KeepCalls = 4, 'call chain not tail-eliminated');
  Writeln('BACKTRACE_CONTRACT_PASS');
end.
