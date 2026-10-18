program cpu_fixture_contract;

uses System.SysUtils;

type
  cint = Integer;
  TThread = class
  public type
    TSystemTimes = record
      IdleTime, UserTime, KernelTime, NiceTime: QWord;
    end;
  public
    class function GetSystemTimes(out aSystemTimes: TSystemTimes): Boolean; static;
    class function GetCPUUsage(var Previous: TSystemTimes): Integer;
  end;

var
  Fixture: RawByteString;
  OpenFails, ReadFails: Boolean;
  CloseCalls, Checks, Failures: Integer;

function FileOpen(const Name: string; Mode: LongWord): cint;
begin
  If OpenFails then Result := -1 else Result := 7;
end;

function fpRead(Handle: cint; var Buffer; Count: SizeInt): SizeInt;
begin
  If ReadFails then Exit(-1);
  Result := Length(Fixture);
  If Result > Count then Result := Count;
  If Result > 0 then Move(Fixture[1], Buffer, Result);
end;

function fpClose(Handle: cint): cint;
begin
  Inc(CloseCalls);
  Result := 0;
end;

{$I cpu_implementations.inc}

procedure Check(Value: Boolean; const Text: string);
begin
  Inc(Checks);
  If not Value then begin
    Inc(Failures);
    Writeln('FAIL ', Text);
  end;
end;

function Times(User, Nice, Kernel, Idle: QWord): TThread.TSystemTimes;
begin
  Result.UserTime := User;
  Result.NiceTime := Nice;
  Result.KernelTime := Kernel;
  Result.IdleTime := Idle;
end;

function EqualTimes(const A, B: TThread.TSystemTimes): Boolean;
begin
  Result := (A.UserTime = B.UserTime) and (A.NiceTime = B.NiceTime) and
    (A.KernelTime = B.KernelTime) and (A.IdleTime = B.IdleTime);
end;

procedure CheckReading(const Line: RawByteString; Valid: Boolean;
  const Expected: TThread.TSystemTimes; const Name: string);
var
  Actual: TThread.TSystemTimes;
  ClosedBefore: Integer;
begin
  Fixture := Line;
  ClosedBefore := CloseCalls;
  Check(TThread.GetSystemTimes(Actual) = Valid, Name + ' validity');
  If Valid then Check(EqualTimes(Actual, Expected), Name + ' complete accounting');
  Check(CloseCalls = ClosedBefore + 1, Name + ' closes descriptor');
end;

procedure Readings;
var
  Z: TThread.TSystemTimes;
begin
  Z := Default(TThread.TSystemTimes);
  CheckReading('cpu  11 13 17 19 23 29 31 37 41 43'#10, True, Times(11, 13, 156, 42), 'all eight plus guest');
  CheckReading('cpu  11 13 17 19 23 29 31 37'#10, True, Times(11, 13, 156, 42), 'eight newline');
  CheckReading('cpu  11'#9'13'#9'17'#9'19'#9'23'#9'29'#9'31'#9'37 ', True, Times(11, 13, 156, 42), 'tabs and complete last delimiter');
  CheckReading('cpu 0 0 0 0 0 0 0 0'#10, True, Z, 'all zero');
  CheckReading('cpu 11 0 0 0 0 0 0 0 999999 999999'#10, True, Times(11, 0, 0, 0), 'guest not counted twice');
  CheckReading('cpu 0 13 0 0 0 0 0 0'#10, True, Times(0, 13, 0, 0), 'nice stays separate');
  CheckReading('cpu 0 0 0 0 0 29 0 0'#10, True, Times(0, 0, 29, 0), 'irq contributes busy');
  CheckReading('cpu 0 0 0 0 0 0 31 0'#10, True, Times(0, 0, 31, 0), 'softirq contributes busy');
  CheckReading('cpu 0 0 0 0 0 0 0 37'#10, True, Times(0, 0, 37, 0), 'steal contributes busy');
  CheckReading('cpu 0 0 0 0 23 0 0 0'#10, True, Times(0, 0, 23, 23), 'iowait contributes idle and kernel');
  CheckReading('', False, Z, 'empty read');
  CheckReading('cp', False, Z, 'truncated prefix');
  CheckReading('cpu0 1 2 3 4 5 6 7 8'#10, False, Z, 'per CPU line rejected');
  CheckReading('cpu 1 2 3 4'#10, False, Z, 'old four field partial sample');
  CheckReading('cpu 1 2 3 4 5 6 7'#10, False, Z, 'missing steal');
  CheckReading('cpu 1 2 3 4 5 6 7 8', False, Z, 'read boundary may truncate eighth value');
  CheckReading('cpu 1 2 3 4 5 x 7 8'#10, False, Z, 'invalid counter');
end;

procedure Usage;
var
  Previous, Actual: TThread.TSystemTimes;
  Saved: TThread.TSystemTimes;
begin
  Fixture := 'cpu 100 20 30 400 50 6 7 8 90 10'#10;
  Actual := Times(100, 20, 501, 450);
  Previous := Times(80, 10, 431, 400);
  Check(TThread.GetCPUUsage(Previous) = 50, 'ordinary interval percentage');
  Check(EqualTimes(Previous, Actual), 'ordinary interval updates Previous');
  Check(TThread.GetCPUUsage(Previous) = 0, 'unchanged interval');
  for var Field := 0 to 3 do begin
    Previous := Actual;
    case Field of
      0: Inc(Previous.UserTime);
      1: Inc(Previous.KernelTime);
      2: Inc(Previous.NiceTime);
      3: Inc(Previous.IdleTime);
    end;
    Check(TThread.GetCPUUsage(Previous) = 0, 'rollback ' + IntToStr(Field) + ' returns zero');
    Check(EqualTimes(Previous, Actual), 'rollback ' + IntToStr(Field) + ' resets baseline');
  end;
  { Isolate delta safety from the reader's accounting: use its own actual sample. }
  Check(TThread.GetSystemTimes(Actual), 'rollback control obtains the actual reader sample');
  Previous := Actual;
  Inc(Previous.UserTime);
  Dec(Previous.KernelTime, 20);
  Check(TThread.GetCPUUsage(Previous) = 0, 'user rollback must not wrap to 100 percent');
  Previous := Actual;
  Inc(Previous.KernelTime);
  Dec(Previous.UserTime, 20);
  Check(TThread.GetCPUUsage(Previous) = 0, 'kernel rollback must not wrap to 100 percent');
  Previous := Actual;
  Inc(Previous.NiceTime);
  Dec(Previous.UserTime, 20);
  Check(TThread.GetCPUUsage(Previous) = 0, 'nice rollback must not wrap to 100 percent');
  Previous := Times(100, 20, 451, 400);
  Check(TThread.GetCPUUsage(Previous) = 0, 'pure idle interval');
  Previous := Times(80, 10, 431, 450);
  Check(TThread.GetCPUUsage(Previous) = 100, 'pure busy interval');
  Previous := Times(0, 0, 0, 0);
  Saved := Previous;
  OpenFails := True;
  Check(TThread.GetCPUUsage(Previous) = 0, 'open failure returns zero');
  Check(EqualTimes(Previous, Saved), 'open failure retains baseline');
  OpenFails := False;
  ReadFails := True;
  Check(TThread.GetCPUUsage(Previous) = 0, 'read failure returns zero');
  Check(EqualTimes(Previous, Saved), 'read failure retains baseline');
  ReadFails := False;
  Fixture := 'cpu 1 2 3 4'#10;
  Check(TThread.GetCPUUsage(Previous) = 0, 'short sample returns zero');
  Check(EqualTimes(Previous, Saved), 'short sample retains baseline');
end;

begin
  Readings;
  Usage;
  Writeln('CPU_FIXTURE_CONTRACT checks=', Checks, ' failures=', Failures);
  If Failures <> 0 then Halt(1);
end.
